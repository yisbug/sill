import Foundation
import StreamProtocol

/// 语音输入在 Mac 端的纯规则（docs/voice-and-immersive-plan.md 第 2.5 节；VoiceBridge 负责执行）：
/// - 发现：meeppo-voice 写在数据目录下的 `local-api.json`（`{"version":1,"port":…,"token":"…","pid":…,
///   "startedAt":"…"}`），校验 version 为 1、端口在 1…65535、令牌非空、pid 还活着。
/// - 片段：kind 100 的载荷，超过 4 MiB 的回 `tooLarge`。
/// - 结果：`/api/process` 的回答取 `polishedText`，空则 `recognizedText`；非 200 或读不懂回 `serviceError`，
///   说明用服务返回的 `error` 字段。
/// - 预览截到 200 个字符；日志一行，不写识别出的文字。
/// 只用 Foundation 和 StreamProtocol，`Tests/checks/voice` 单独编译检查。
enum VoicePolicy {
    // MARK: 发现

    /// 发现文件的名字，在数据目录下。
    static let discoveryFileName = "local-api.json"
    /// 数据目录的默认值（相对用户主目录），meeppo-voice（typefreedemo）的约定。
    static let defaultDataDirectory = "Library/Application Support/TypefreeDemo"

    /// 一个可用的 meeppo-voice：只在 127.0.0.1 的这个端口上，带这个令牌。
    struct Service: Equatable {
        var port: Int
        var token: String
        var pid: Int32
    }

    /// 发现文件为什么不能用（日志里的说法，供排障）。
    enum Unusable: Error, Equatable {
        case missing
        case unreadable
        case wrongVersion(Int?)
        case badPort
        case noToken
        case badPid
        case notRunning(Int32)

        var words: String {
            switch self {
            case .missing: return "no \(VoicePolicy.discoveryFileName)"
            case .unreadable: return "\(VoicePolicy.discoveryFileName) is not the expected JSON"
            case .wrongVersion(let v): return "\(VoicePolicy.discoveryFileName) has version \(v.map(String.init) ?? "none"), not 1"
            case .badPort: return "\(VoicePolicy.discoveryFileName) names no port in 1…65535"
            case .noToken: return "\(VoicePolicy.discoveryFileName) has no token"
            case .badPid: return "\(VoicePolicy.discoveryFileName) names no process"
            case .notRunning(let pid): return "process \(pid) in \(VoicePolicy.discoveryFileName) is not running"
            }
        }
    }

    /// 数据目录：测试钩子（只在测试主机上生效，由调用方判断）优先，然后是配置（Sill.app 的 UserDefaults
    /// `voiceDataDirectory`，CLI 的 `--voice-dir`），最后是默认值。空字符串当作没给。`~` 开头的展开为主目录。
    static func dataDirectory(home: String, configured: String?, testOverride: String?) -> String {
        func usable(_ s: String?) -> String? {
            guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            if s == "~" { return home }
            if s.hasPrefix("~/") { return (home as NSString).appendingPathComponent(String(s.dropFirst(2))) }
            return s
        }
        return usable(testOverride) ?? usable(configured) ?? (home as NSString).appendingPathComponent(defaultDataDirectory)
    }

    /// 发现文件的内容（nil：文件不存在）判成一个可用的服务，或不能用的原因。`isAlive` 判断 pid 是否还活着
    /// （VoiceBridge 用 `kill(pid, 0)`）。
    static func discover(_ data: Data?, isAlive: (Int32) -> Bool) -> Result<Service, Unusable> {
        guard let data else { return .failure(.missing) }
        guard let object = try? JSONSerialization.jsonObject(with: data), let json = object as? [String: Any] else {
            return .failure(.unreadable)
        }
        let version = integer(json["version"])
        guard version == 1 else { return .failure(.wrongVersion(version)) }
        guard let port = integer(json["port"]), (1...65535).contains(port) else { return .failure(.badPort) }
        guard let token = json["token"] as? String, !token.isEmpty else { return .failure(.noToken) }
        guard let pid = integer(json["pid"]), pid > 0, pid <= Int(Int32.max) else { return .failure(.badPid) }
        guard isAlive(Int32(pid)) else { return .failure(.notRunning(Int32(pid))) }
        return .success(Service(port: port, token: token, pid: Int32(pid)))
    }

    /// JSON 里的整数：整数值的数字才算（布尔值和带小数的数字都不算）。
    private static func integer(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        guard d.isFinite, d == d.rounded(), abs(d) < 1e15 else { return nil }
        return Int(d)
    }

    // MARK: 片段

    /// 主机为 kind 100 读的最大载荷：4 MiB 的音频加片段头，再留一倍，超出这些的才断开连接（同其他种类的
    /// 1 MiB 上限）；读进来超过 4 MiB 的回 `tooLarge`。
    static let maxReadPayload = 2 * VoiceClip.maxAudioBytes + VoiceClip.headerLength

    /// 一个 kind 100 载荷的判断。
    enum Clip: Equatable {
        /// 可以发给 meeppo-voice。
        case audio(clip: UInt32, audio: Data)
        /// 回失败（片段号可知）。
        case refuse(clip: UInt32, reason: VoiceReason, message: String)
        /// 连片段号都读不出：丢弃，什么都不回。
        case malformed
    }

    static func clip(_ payload: Data, locale: Locale = DeviceLanguage.hostLocale) -> Clip {
        guard let (clip, format, audio) = VoiceClip.parse(payload) else { return .malformed }
        guard audio.count <= VoiceClip.maxAudioBytes else {
            return .refuse(clip: clip, reason: .tooLarge, message: message(.tooLarge, locale: locale))
        }
        guard format == VoiceClip.formatM4A else {
            return .refuse(clip: clip, reason: .serviceError,
                           message: String(localized: "This Mac doesn’t know that audio format. Update Sill on it.", bundle: DeviceLanguage.bundle(for: locale), locale: locale, comment: "语音输入结果：Mac 不认识设备发来的音频格式"))
        }
        guard !audio.isEmpty else {
            return .refuse(clip: clip, reason: .serviceError,
                           message: String(localized: "The recording was empty.", bundle: DeviceLanguage.bundle(for: locale), locale: locale, comment: "语音输入结果：录音为空"))
        }
        return .audio(clip: clip, audio: audio)
    }

    // MARK: 请求

    /// 等 meeppo-voice 回答的最长时间。
    static let timeout: TimeInterval = 90
    /// 请求头里令牌的名字。
    static let tokenHeader = "X-Typefree-Token"
    /// 请求体的类型：m4a 容器（meeppo-voice 用 ffmpeg 转码，原样收）。
    static let contentType = "audio/mp4"

    /// 识别接口的地址：只在本机回环上。
    static func processURL(port: Int) -> URL? {
        guard (1...65535).contains(port) else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/api/process")
    }

    // MARK: 结果

    /// meeppo-voice 的一个回答的含义。
    enum Answer: Equatable {
        case text(String)
        case failed(VoiceReason, message: String)
    }

    /// HTTP 状态码与响应体判成文字或失败：200 时取 `polishedText`，去掉首尾空白后为空则取 `recognizedText`，
    /// 两者都空回 `serviceError`（没识别出文字）；非 200 或读不懂回 `serviceError`，说明优先用响应里的 `error`。
    static func answer(status: Int, body: Data, locale: Locale = DeviceLanguage.hostLocale) -> Answer {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        guard status == 200 else {
            let error = (json?["error"] as? String).map { SafeText.label($0, limit: 200) } ?? ""
            let text = error.isEmpty
                ? String(localized: "meeppo-voice answered with an error (HTTP \(status)).", bundle: DeviceLanguage.bundle(for: locale), locale: locale, comment: "语音输入结果：识别服务返回错误，插值为 HTTP 状态码")
                : String(localized: "meeppo-voice: \(error)", bundle: DeviceLanguage.bundle(for: locale), locale: locale, comment: "语音输入结果：识别服务返回的错误说明，插值为服务给出的原文")
            return .failed(.serviceError, message: text)
        }
        guard let json else {
            return .failed(.serviceError, message: String(localized: "meeppo-voice’s answer couldn’t be read.", bundle: DeviceLanguage.bundle(for: locale), locale: locale, comment: "语音输入结果：识别服务的回答无法解析"))
        }
        for key in ["polishedText", "recognizedText"] {
            if let text = json[key] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .text(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return .failed(.serviceError, message: String(localized: "Nothing was recognized. Try speaking again.", bundle: DeviceLanguage.bundle(for: locale), locale: locale, comment: "语音输入结果：没有识别出文字"))
    }

    /// 请求没拿到回答时（URLError 的代码）的原因：超时回 `timeout`，连不上（服务刚退出）回 `noService`，
    /// 其余回 `serviceError`。取消不在这里：取消的片段什么都不回。
    static func failure(urlErrorCode code: Int) -> VoiceReason {
        switch code {
        case NSURLErrorTimedOut: return .timeout
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorNetworkConnectionLost,
             NSURLErrorNotConnectedToInternet:
            return .noService
        default: return .serviceError
        }
    }

    /// 文字打进去的结果（StreamCoordinator 走 kind 8 文字的同一入口）。
    enum Landing: Equatable {
        case typed
        case locked
        case nothingStreams
    }

    /// 成功的结果：文字的预览。
    static func typed(clip: UInt32, text: String) -> VoiceResult {
        VoiceResult(clip: clip, ok: true, text: preview(text))
    }

    /// 文字识别出来了但没能打进去，或者别的失败。
    static func failed(clip: UInt32, _ reason: VoiceReason, message: String? = nil, locale: Locale = DeviceLanguage.hostLocale) -> VoiceResult {
        VoiceResult(clip: clip, ok: false, reason: reason.rawValue, message: message ?? self.message(reason, locale: locale))
    }

    /// 落点对应的结果。
    static func result(clip: UInt32, text: String, landing: Landing, locale: Locale = DeviceLanguage.hostLocale) -> VoiceResult {
        switch landing {
        case .typed: return typed(clip: clip, text: text)
        case .locked: return failed(clip: clip, .locked, locale: locale)
        case .nothingStreams: return failed(clip: clip, .nothingStreams, locale: locale)
        }
    }

    // MARK: 多行文字：粘贴，不逐字打

    /// 识别出的文字含换行时不逐字打而是粘贴：逐字打会把换行打成回车键（InputInjector.type），聊天类输入框
    /// 里回车就是发送，第一行一到就发出去，后面几行落到空输入框或别处，整段没能完整录入。粘贴的换行只是
    /// 文字里的换行，哪个应用都不当作发送（终端的括号粘贴也不执行）。单行照旧逐字打。与 meeppo-voice
    /// 自己回填的做法一致：存下剪贴板、写入文字、⌘V、稍后恢复（HostClipboard.stageVoicePaste）。
    static func pastes(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.newlines.contains($0) }
    }

    /// 粘贴：⌘V，和设备的"立即粘贴"一样按键盘的按法，⌘ 自己的键在 V 的外面（KeyStrokes 据此定每个事件的标志，
    /// V 抬起后 HID 状态表里不留 ⌘）。V 是 HID 用法 0x19（ClipboardPolicy.pasteKey），⌘ 是 0xE3，标志 1 << 20。
    static let pasteKeys: [InputEvent] = [
        .key(hidUsage: commandKey, down: true, modifiers: commandFlag),
        .key(hidUsage: ClipboardPolicy.pasteKey, down: true, modifiers: commandFlag),
        .key(hidUsage: ClipboardPolicy.pasteKey, down: false, modifiers: commandFlag),
        .key(hidUsage: commandKey, down: false, modifiers: 0),
    ]
    private static let commandKey: UInt16 = 0xE3
    private static let commandFlag: UInt64 = 1 << 20

    /// 粘贴后多久把剪贴板恢复成原来的内容：⌘V 可能要等应用到前台（协调器最多扣住输入 0.6 s），应用读剪贴板
    /// 也要一点时间，所以留足 1.5 s。期间有人复制了别的东西就不恢复（HostClipboard）。
    static let clipboardRestoreDelay: TimeInterval = 1.5

    /// 预览：最多 200 个字符（Character），超出时截断并以省略号结尾（省略号算在 200 之内）。
    static func preview(_ text: String) -> String {
        let limit = VoiceResult.maxPreviewCharacters
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "…"
    }

    /// 每个原因的默认说明（按连接设备的语言）。
    static func message(_ reason: VoiceReason, locale: Locale = DeviceLanguage.hostLocale) -> String {
        switch reason {
        case .noService:
            return String(localized: "meeppo-voice isn’t running on this Mac. Open it, then try again.", bundle: DeviceLanguage.bundle(for: locale), locale: locale, comment: "语音输入结果：没有找到识别服务")
        case .timeout:
            return String(localized: "meeppo-voice didn’t answer in time.", bundle: DeviceLanguage.bundle(for: locale), locale: locale, comment: "语音输入结果：识别超时")
        case .serviceError:
            return String(localized: "meeppo-voice couldn’t recognize the recording.", bundle: DeviceLanguage.bundle(for: locale), locale: locale, comment: "语音输入结果：识别服务出错")
        case .locked:
            return String(localized: "The Mac is locked, so the text wasn’t typed.", bundle: DeviceLanguage.bundle(for: locale), locale: locale, comment: "语音输入结果：Mac 已锁屏")
        case .nothingStreams:
            return String(localized: "Nothing is streaming, so the text had nowhere to go.", bundle: DeviceLanguage.bundle(for: locale), locale: locale, comment: "语音输入结果：没有正在串流的内容")
        case .tooLarge:
            return String(localized: "The recording is too long to send.", bundle: DeviceLanguage.bundle(for: locale), locale: locale, comment: "语音输入结果：录音超过大小上限")
        case .busy:
            return String(localized: "The last recording is still being recognized.", bundle: DeviceLanguage.bundle(for: locale), locale: locale, comment: "语音输入结果：上一段还在识别")
        }
    }

    // MARK: 日志

    /// 每个片段一行：片段号、设备、字节数、耗时、结果字数、原因。不写识别出的文字。
    static func logLine(clip: UInt32, device: String, bytes: Int, seconds: Double?, characters: Int?, reason: String?) -> String {
        var parts = ["\(bytes) bytes"]
        if let seconds { parts.append(String(format: "%.2f s", seconds)) }
        if let characters { parts.append("\(characters) characters") }
        parts.append(reason ?? "ok")
        return "Voice clip \(clip) from \(device): " + parts.joined(separator: ", ")
    }
}
