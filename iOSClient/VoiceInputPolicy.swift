import Foundation
import CoreGraphics
import StreamProtocol

/// 语音悬浮球的纯规则（docs/voice-and-immersive-plan.md 第 2.4 节；VoiceInputButton 与 VoiceRecorder 负责执行）：
/// - 状态机：空闲 → 录音中 → 发送中 → 完成（文字预览 2 秒）或失败（说明 4 秒）→ 空闲；点按开始与提交，Esc 取消。
/// - 位置：松手贴最近的左右边缘，高度按方向（横、竖）各记一份，存成 "trailing:0.750"。
/// - 避让：球放在串流画面之内（不盖顶栏与键盘行），再避开画面上的提示（剪贴板芯片等）。
/// - 何时显示、文字、时长与音量。
/// 只用 Foundation、CoreGraphics 与 StreamProtocol 的 Voice.swift，`Tests/checks/voice` 单独编译检查。
enum VoiceInputPolicy {
    // MARK: 状态机

    enum Phase: Equatable {
        case idle
        /// 正在录 `clip`，从 `since`（systemUptime）起。
        case recording(clip: UInt32, since: Double)
        /// `clip` 已发出，等 Mac 的结果。
        case sending(clip: UInt32, since: Double)
        /// 文字打进去了：在球旁显示预览，到 `until` 为止。
        case done(text: String, until: Double)
        /// 失败：显示说明，到 `until` 为止。
        case failed(message: String, until: Double)
    }

    enum Event: Equatable {
        /// 点按球（或 VoiceOver 的激活、硬件键盘的 ⌃⌥R、录音中的 Magic Tap）。
        case tap(now: Double)
        /// Esc：录音中丢弃，发送中取消。
        case cancel
        /// Mac 回了一个片段的结果（或设备自己判定的失败，比如超过 4 MiB）。
        case result(VoiceResult, now: Double)
        /// 麦克风权限被拒。
        case permissionDenied(now: Double)
        /// 录音没能开始或没能结束。
        case recorderFailed(now: Double)
        /// 定时检查：预览与说明到时回空闲；发送超时算失败；录音到最长时自动提交。
        case tick(now: Double)
        /// 球被藏起（设置面板、导览、配对覆盖层、会话结束）：录音中则丢弃。
        case hidden
    }

    enum Effect: Equatable {
        case startRecording(clip: UInt32)
        case stopAndSend(clip: UInt32)
        case discardRecording
        case sendCancel(clip: UInt32)
        /// 给 VoiceOver 念的一句。
        case announce(String)
    }

    /// 文字预览显示多久。
    static let previewSeconds = 2.0
    /// 失败说明显示多久。
    static let failureSeconds = 4.0
    /// 发出后等 Mac 多久（它自己等 meeppo-voice 90 秒）。
    static let sendTimeout = 100.0
    /// 一次最多录多久，到时自动提交（单声道 16 kHz、32 kbps 约 2.4 MB，在 4 MiB 之内）。
    static let maxRecordingSeconds = 600.0

    /// 一个事件之后的状态与要做的事。`nextClip`：开始录音时用的片段号。
    static func next(_ phase: Phase, _ event: Event, nextClip: UInt32) -> (Phase, [Effect]) {
        switch (phase, event) {
        case (.idle, .tap(let now)), (.done, .tap(let now)), (.failed, .tap(let now)):
            return (.recording(clip: nextClip, since: now), [.startRecording(clip: nextClip)])
        case (.recording(let clip, _), .tap(let now)):
            return (.sending(clip: clip, since: now), [.stopAndSend(clip: clip)])
        case (.sending, .tap):
            return (phase, [])
        case (.recording, .cancel), (.recording, .hidden):
            return (.idle, [.discardRecording])
        case (.sending(let clip, _), .cancel):
            return (.idle, [.sendCancel(clip: clip)])
        case (.done, .cancel), (.failed, .cancel):
            return (.idle, [])
        case (.sending(let clip, _), .result(let r, let now)) where r.clip == clip:
            if r.ok {
                let text = r.text ?? ""
                return (.done(text: text, until: now + previewSeconds), [.announce(typedAnnouncement(text))])
            }
            let words = message(for: r)
            return (.failed(message: words, until: now + failureSeconds), [.announce(words)])
        case (.recording, .permissionDenied(let now)), (.idle, .permissionDenied(let now)):
            let words = permissionMessage
            return (.failed(message: words, until: now + failureSeconds), [.announce(words)])
        case (.recording, .recorderFailed(let now)), (.sending, .recorderFailed(let now)):
            let words = recorderMessage
            return (.failed(message: words, until: now + failureSeconds), [.announce(words)])
        case (.done(_, let until), .tick(let now)) where now >= until,
             (.failed(_, let until), .tick(let now)) where now >= until:
            return (.idle, [])
        case (.sending(_, let since), .tick(let now)) where now - since >= sendTimeout:
            let words = noAnswerMessage
            return (.failed(message: words, until: now + failureSeconds), [.announce(words)])
        case (.recording(let clip, let since), .tick(let now)) where now - since >= maxRecordingSeconds:
            return (.sending(clip: clip, since: now), [.stopAndSend(clip: clip)])
        default:
            return (phase, [])
        }
    }

    /// 录音中或发送中：Esc 归悬浮球（EscapeKey），不发给 Mac。
    static func takesEscape(_ phase: Phase) -> Bool {
        switch phase {
        case .recording, .sending: return true
        default: return false
        }
    }

    // MARK: 何时显示

    /// 这台设备的开关：Settings › 本机 › 语音输入，默认开。只存在设备上，不发给 Mac。
    static let switchKey = "Sill.voiceInput"

    /// 存的值读成开关：没存过为开；数字和布尔值按真假；启动参数给的字符串 "0"/"1"、"NO"/"YES" 也认。
    static func switchOn(stored: Any?) -> Bool {
        switch stored {
        case nil: return true
        case let n as NSNumber: return n.boolValue
        case let s as String: return !["0", "no", "false", "off"].contains(s.trimmingCharacters(in: .whitespaces).lowercased())
        default: return true
        }
    }

    /// 悬浮球显示：会话中、Mac 的窗口列表说 `voice` 为 1 或以上、开关开着，且没有东西盖在串流上（设置面板、
    /// 抽屉、导览卡片、配对覆盖层）。
    static func shows(hostVoice: Int?, switchOn: Bool, covered: Bool) -> Bool {
        (hostVoice ?? 0) >= VoiceSupport.generation && switchOn && !covered
    }

    /// 片段能发：不超过 4 MiB（超过的不发，直接显示 tooLarge）。
    static func sendable(bytes: Int) -> Bool { bytes > 0 && bytes <= VoiceClip.maxAudioBytes }

    /// 片段号：从 1 起，到顶回到 1（0 不用）。
    static func clip(after clip: UInt32) -> UInt32 { clip == UInt32.max ? 1 : clip + 1 }

    // MARK: 位置

    enum Side: String, Equatable { case leading, trailing }

    /// 球停在哪：左右哪一边，以及在能放的高度里的比例（0 最上，1 最下）。
    struct Spot: Equatable {
        var side: Side
        var y: Double
    }

    /// 没记过时的位置：右边，靠下四分之一。
    static let defaultSpot = Spot(side: .trailing, y: 0.75)
    /// 球的直径。
    static let diameter: CGFloat = 56
    /// 球与画面边缘的距离。
    static let margin: CGFloat = 12
    /// 与要避开的区域之间至少留的空。
    static let clearance: CGFloat = 8

    /// 位置按方向分开记。
    static func spotKey(landscape: Bool) -> String { landscape ? "Sill.voiceBall.landscape" : "Sill.voiceBall.portrait" }

    static func encode(_ spot: Spot) -> String {
        "\(spot.side.rawValue):" + String(format: "%.3f", min(max(spot.y, 0), 1))
    }

    /// 读回存的位置；读不懂时为 nil（用默认位置）。
    static func decode(_ text: String?) -> Spot? {
        guard let text else { return nil }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let side = Side(rawValue: String(parts[0])), let y = Double(parts[1]), y.isFinite else { return nil }
        return Spot(side: side, y: min(max(y, 0), 1))
    }

    /// 球心能在的竖直范围（在 `area` 之内，离边 `margin`）；区域太矮时只有中线。
    private static func verticalRange(in area: CGRect) -> ClosedRange<CGFloat> {
        let r = diameter / 2
        let low = area.minY + margin + r, high = area.maxY - margin - r
        return low <= high ? low...high : area.midY...area.midY
    }

    /// 松手处贴最近的左右边缘：哪一边看球心在区域中线的哪一侧，高度换成比例。
    static func snap(_ center: CGPoint, in area: CGRect) -> Spot {
        let side: Side = center.x < area.midX ? .leading : .trailing
        let range = verticalRange(in: area)
        let span = range.upperBound - range.lowerBound
        let y = span > 0 ? Double((min(max(center.y, range.lowerBound), range.upperBound) - range.lowerBound) / span) : 0.5
        return Spot(side: side, y: y)
    }

    /// 球心：贴 `spot.side` 那一边，高度按比例；与 `avoiding` 里任何一块（放大 `clearance`）相交时，
    /// 上下挪到最近的不相交处（都挪不开时留在原处）。
    static func center(for spot: Spot, in area: CGRect, avoiding: [CGRect] = []) -> CGPoint {
        let r = diameter / 2
        let x: CGFloat = spot.side == .leading ? area.minX + margin + r : area.maxX - margin - r
        let range = verticalRange(in: area)
        let y = range.lowerBound + CGFloat(min(max(spot.y, 0), 1)) * (range.upperBound - range.lowerBound)
        let blocks = avoiding.map { $0.insetBy(dx: -clearance, dy: -clearance) }
        func free(_ y: CGFloat) -> Bool {
            let ball = CGRect(x: x - r, y: y - r, width: diameter, height: diameter)
            return !blocks.contains { $0.intersects(ball) }
        }
        if free(y) { return CGPoint(x: x, y: y) }
        // 候选：每块的上方与下方紧贴处，取在范围内、不相交、离原处最近的。
        var candidates: [CGFloat] = []
        for b in blocks {
            candidates.append(b.minY - r - 0.5)
            candidates.append(b.maxY + r + 0.5)
        }
        let best = candidates
            .filter { range.contains($0) && free($0) }
            .min { abs($0 - y) < abs($1 - y) }
        return CGPoint(x: x, y: best ?? y)
    }

    // MARK: 文字

    /// 录音时长 "0:07"、"12:03"：分与秒。
    static func elapsedText(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.isFinite ? seconds : 0))
        return Duration.seconds(s).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1)))
    }

    /// AVAudioRecorder 的平均功率（dBFS，-160…0）换成 0…1 的音量：-50 dB 以下为 0。
    static func level(power: Float) -> Double {
        guard power.isFinite else { return 0 }
        return Double(min(max((power + 50) / 50, 0), 1))
    }

    /// 失败的说明：认识的原因用这台设备的语言，不认识的显示 Mac 给的说明。
    static func message(for result: VoiceResult) -> String {
        switch result.reason.flatMap(VoiceReason.init(rawValue:)) {
        case .noService?:
            return String(localized: "meeppo-voice isn’t running on the Mac. Open it there, then try again.", comment: "语音悬浮球：Mac 上没有找到识别服务")
        case .timeout?:
            return String(localized: "meeppo-voice didn’t answer in time.", comment: "语音悬浮球：识别超时")
        case .serviceError?:
            return result.message ?? String(localized: "meeppo-voice couldn’t recognize the recording.", comment: "语音悬浮球：识别失败")
        case .locked?:
            return String(localized: "The Mac is locked, so the text wasn’t typed.", comment: "语音悬浮球：Mac 已锁屏")
        case .nothingStreams?:
            return String(localized: "Nothing is streaming, so the text had nowhere to go.", comment: "语音悬浮球：没有正在串流的内容")
        case .tooLarge?:
            return String(localized: "The recording is too long to send.", comment: "语音悬浮球：录音超过大小上限")
        case .busy?:
            return String(localized: "The last recording is still being recognized.", comment: "语音悬浮球：上一段还在识别")
        case nil:
            return result.message ?? String(localized: "Voice input didn’t work.", comment: "语音悬浮球：未知原因的失败")
        }
    }

    /// 设备自己判定超过 4 MiB 时的结果（与 Mac 回的同形）。
    static func tooLarge(clip: UInt32) -> VoiceResult {
        VoiceResult(clip: clip, ok: false, reason: VoiceReason.tooLarge.rawValue)
    }

    static var permissionMessage: String {
        String(localized: "Sill can’t use the microphone. Allow it in Settings › Privacy & Security › Microphone.", comment: "语音悬浮球：麦克风权限被拒")
    }

    static var recorderMessage: String {
        String(localized: "The recording couldn’t start.", comment: "语音悬浮球：录音无法开始")
    }

    static var noAnswerMessage: String {
        String(localized: "The Mac didn’t answer.", comment: "语音悬浮球：Mac 没有回答")
    }

    static func typedAnnouncement(_ text: String) -> String {
        String(localized: "Typed: \(text)", comment: "语音悬浮球：文字已输入的 VoiceOver 通知，插值为文字预览")
    }

    /// VoiceOver 的标签（单一按钮元素）。
    static var accessibilityLabel: String { String(localized: "Voice input", comment: "语音悬浮球：无障碍标签") }

    /// VoiceOver 的值：现在在做什么。
    static func accessibilityValue(_ phase: Phase, now: Double) -> String {
        switch phase {
        case .idle: return ""
        case .recording(_, let since):
            return String(localized: "Recording, \(elapsedText(now - since))", comment: "语音悬浮球：录音中的无障碍值，插值为时长")
        case .sending: return String(localized: "Recognizing", comment: "语音悬浮球：识别中的无障碍值")
        case .done(let text, _): return text
        case .failed(let message, _): return message
        }
    }

    /// VoiceOver 的提示：双击做什么。
    static func accessibilityHint(_ phase: Phase) -> String {
        switch phase {
        case .recording:
            return String(localized: "Double-tap to send what you said. A two-finger double-tap sends it too.", comment: "语音悬浮球：录音中的无障碍提示")
        case .sending:
            return ""
        default:
            return String(localized: "Double-tap to start recording.", comment: "语音悬浮球：空闲时的无障碍提示")
        }
    }
}
