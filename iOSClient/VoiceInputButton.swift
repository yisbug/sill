import SwiftUI
import UIKit
import StreamProtocol

// 语音悬浮球（docs/voice-and-immersive-plan.md 第 2.4 节）：点按开始录音，再点提交；Mac 交给它的 meeppo-voice 识别，
// 把文字当作这台设备打的字输入正在串流的应用（kind 100–102，Voice.swift）。规则在 VoiceInputPolicy，录音在 VoiceRecorder。
//
// - 只在会话中、Mac 的窗口列表说 `voice` 为 1、本机的开关（Settings › 本机 › 语音输入）开着时显示；设置面板、抽屉、
//   导览卡片、配对覆盖层盖在串流上时藏起（录音中则丢弃）。
// - 放在串流画面之内（不盖顶栏和键盘行），松手贴最近的左右边缘，高度按方向记忆；避开剪贴板芯片。
// - 硬件键盘：⌃⌥R 开始或提交，录音中与发送中 Esc 取消（EscapeKey：不发给 Mac）。
// - VoiceOver：一个按钮元素 "Voice input"，录音中 Magic Tap 提交。
// - DEBUG：`-SillVoiceClip <path>` 点按时不录音，直接发送这个文件；`-SillVoiceState recording|sending|done|failed`
//   让模拟截图显示某个状态（与 `-SillVoice on` 一起，MockCatalog）。

/// 一个会话的语音输入：状态机的执行者。主线程。
@MainActor
final class VoiceInputController: ObservableObject {
    @Published private(set) var phase: VoiceInputPolicy.Phase = .idle
    /// 录音中最近的音量（0…1），画波形用，最新的在最后。
    @Published private(set) var levels: [Double] = Array(repeating: 0, count: VoiceInputController.bars)
    /// 定时刷新的现在（systemUptime），时长与到时判断用。
    @Published private(set) var now = ProcessInfo.processInfo.systemUptime

    static let bars = 16

    private weak var client: StreamClient?
    private let recorder = VoiceRecorder()
    private var nextClip: UInt32 = 1
    private var timer: Timer?
    /// 开始录音前 Mac 的声音是否本来就静音：结束后照原样恢复。
    private var soundWasMuted: Bool?

    /// DEBUG：点按时直接发送这个文件，不录音（模拟器测试）。
    private var debugClip: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "SillVoiceClip")
        #else
        return nil
        #endif
    }

    func attach(_ client: StreamClient) {
        self.client = client
        client.onVoiceResult = { [weak self] result in
            self?.handle(.result(result, now: ProcessInfo.processInfo.systemUptime))
        }
        #if DEBUG
        // 模拟截图：某个状态，不会自己结束。
        let t = ProcessInfo.processInfo.systemUptime
        switch UserDefaults.standard.string(forKey: "SillVoiceState") {
        case "recording"?:
            phase = .recording(clip: 1, since: t - 7)
            levels = (0..<Self.bars).map { i in 0.25 + 0.6 * abs(sin(Double(i) * 0.7)) }
        case "sending"?: phase = .sending(clip: 1, since: t)
        case "done"?: phase = .done(text: "你好，世界。这是一段语音输入的预览。", until: .infinity)
        case "failed"?: phase = .failed(message: VoiceInputPolicy.message(for: VoiceResult(clip: 1, ok: false, reason: "noService")), until: .infinity)
        default: break
        }
        // `-SillVoiceTapAt <s>[,<s>…]`：这几秒时点按一次球（模拟器里没有手指；配 `-SillVoiceClip` 发文件）。
        // `-SillVoiceEscAt <s>`：这一秒按一次 Esc。
        for (key, act) in [("SillVoiceTapAt", { [weak self] in self?.tap() }), ("SillVoiceEscAt", { [weak self] in self?.cancel() })] as [(String, () -> Void)] {
            for part in (UserDefaults.standard.string(forKey: key) ?? "").split(separator: ",") {
                guard let s = Double(part.trimmingCharacters(in: .whitespaces)) else { continue }
                DispatchQueue.main.asyncAfter(deadline: .now() + s) {
                    print("voice: \(key) \(s)")
                    act()
                }
            }
        }
        #endif
    }

    /// 点按球、⌃⌥R、VoiceOver 的激活。
    func tap() { handle(.tap(now: ProcessInfo.processInfo.systemUptime)) }

    /// Esc。
    func cancel() { handle(.cancel) }

    /// 球被藏起（盖住了，或会话结束）。
    func hidden() { handle(.hidden) }

    /// 会话结束：录音丢掉，还在识别的取消，计时停下。
    func detach() {
        if case .sending = phase { handle(.cancel) } else { handle(.hidden) }
        stopTimer()
        client?.onVoiceResult = nil
    }

    private func handle(_ event: VoiceInputPolicy.Event) {
        let (after, effects) = VoiceInputPolicy.next(phase, event, nextClip: nextClip)
        #if DEBUG
        if after != phase { print("voice: \(phase) → \(after)") }
        #endif
        phase = after
        for effect in effects { perform(effect) }
        updateTimer()
    }

    private func perform(_ effect: VoiceInputPolicy.Effect) {
        switch effect {
        case .startRecording(let clip):
            nextClip = VoiceInputPolicy.clip(after: clip)
            startRecording(clip)
        case .stopAndSend(let clip):
            stopAndSend(clip)
        case .discardRecording:
            if debugClip == nil { recorder.discard() }
            restoreSound()
        case .sendCancel(let clip):
            client?.send(.voiceCancel, payload: Wire.encode(VoiceCancel(clip: clip)))
            #if DEBUG
            print("voice: cancelled clip \(clip)")
            #endif
        case .announce(let words):
            UIAccessibility.post(notification: .announcement, argument: words)
        }
    }

    private func startRecording(_ clip: UInt32) {
        guard debugClip == nil else { return }
        // Mac 的声音先停，免得录进去；结束后照原样恢复。
        if let client {
            soundWasMuted = client.soundMuted
            client.sound.setMuted(true)
        }
        Task { @MainActor in
            let allowed = await VoiceRecorder.permission()
            // 等权限的时候用户可能已经取消了。
            guard case .recording(let current, _) = phase, current == clip else { return }
            guard allowed else {
                restoreSound()
                handle(.permissionDenied(now: ProcessInfo.processInfo.systemUptime))
                return
            }
            do {
                try recorder.start()
            } catch {
                print("voice: the recording couldn’t start: \(error)")
                restoreSound()
                handle(.recorderFailed(now: ProcessInfo.processInfo.systemUptime))
            }
        }
    }

    private func stopAndSend(_ clip: UInt32) {
        let audio: Data?
        if let path = debugClip {
            audio = FileManager.default.contents(atPath: path)
            #if DEBUG
            print("voice: sending \(path) (\(audio?.count ?? 0) bytes) as clip \(clip), not a recording (-SillVoiceClip)")
            #endif
        } else {
            audio = recorder.finish()
            restoreSound()
        }
        guard let audio, !audio.isEmpty else {
            handle(.recorderFailed(now: ProcessInfo.processInfo.systemUptime))
            return
        }
        guard VoiceInputPolicy.sendable(bytes: audio.count) else {
            handle(.result(VoiceInputPolicy.tooLarge(clip: clip), now: ProcessInfo.processInfo.systemUptime))
            return
        }
        // 文字由 Mac 直接打入：输入视图先送出还在组合的、忘掉已打的上下文（#138，StreamScreen 的 onCaretMayMove）。
        client?.onCaretMayMove?()
        client?.send(.voiceClip, payload: VoiceClip.encode(clip: clip, format: VoiceClip.formatM4A, audio: audio))
    }

    private func restoreSound() {
        guard let client, let was = soundWasMuted else { return }
        soundWasMuted = nil
        client.sound.setMuted(was || client.soundMuted)
    }

    // MARK: 计时

    private func updateTimer() {
        if case .idle = phase { stopTimer(); return }
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        now = ProcessInfo.processInfo.systemUptime
        if case .recording = phase {
            let level = debugClip == nil ? recorder.level() : Double.random(in: 0.2...0.8)
            levels = Array((levels + [level]).suffix(Self.bars))
        }
        handle(.tick(now: now))
    }
}

/// 悬浮球所在的一层：放在串流屏幕的 ZStack 里，在布局之上、导览与配对覆盖层之下（StreamScreen）。
/// `area`：串流画面在屏幕空间里的矩形，球只在这里面；`avoiding`：画面上要避开的提示。
struct VoiceInputLayer: View {
    @ObservedObject var client: StreamClient
    let area: CGRect
    let avoiding: [CGRect]
    let landscape: Bool
    /// 设置面板、抽屉、导览卡片、配对覆盖层盖在串流上。
    let covered: Bool

    @StateObject private var voice = VoiceInputController()
    @AppStorage(VoiceInputPolicy.switchKey) private var switchOn = true
    @AppStorage(VoiceInputPolicy.spotKey(landscape: true)) private var landscapeSpot = ""
    @AppStorage(VoiceInputPolicy.spotKey(landscape: false)) private var portraitSpot = ""
    /// 拖动中的球心（屏幕空间）。
    @State private var dragging: CGPoint? = nil

    private var shown: Bool { VoiceInputPolicy.shows(hostVoice: client.hostVoice, switchOn: switchOn, covered: covered) }

    private var spot: VoiceInputPolicy.Spot {
        VoiceInputPolicy.decode(landscape ? landscapeSpot : portraitSpot) ?? VoiceInputPolicy.defaultSpot
    }

    var body: some View {
        ZStack {
            if shown {
                let center = dragging ?? VoiceInputPolicy.center(for: spot, in: area, avoiding: avoiding)
                VoiceBubble(voice: voice, side: spot.side)
                    .position(x: center.x + bubbleOffset(side: spot.side), y: center.y)
                    .allowsHitTesting(false)
                ball
                    .position(center)
                if VoiceInputPolicy.takesEscape(voice.phase) {
                    EscapeKey(action: { voice.cancel() }).frame(width: 0, height: 0)
                }
                VoiceShortcutKey(action: { voice.tap() }).frame(width: 0, height: 0)
            }
        }
        .onAppear { voice.attach(client) }
        .onDisappear { voice.detach() }
        .onChange(of: shown) { _, now in if !now { voice.hidden() } }
        .animation(.spring(duration: 0.3, bounce: 0.2), value: spot)
    }

    /// 画面上要避开的：剪贴板芯片所在的角（`chip`，它在时；芯片最宽 320 pt、高约 64 pt，靠右），链路提示所在的
    /// 顶边一条（`linkLine`）。
    static func avoiding(panel: CGRect, chip: ClipboardPolicy.Corner?, linkLine: Bool) -> [CGRect] {
        var out: [CGRect] = []
        if let chip {
            let width = min(panel.width, 320), height: CGFloat = 64
            let y = chip == .topTrailing ? panel.minY : panel.maxY - height
            out.append(CGRect(x: panel.maxX - width, y: y, width: width, height: height))
        }
        if linkLine { out.append(CGRect(x: panel.minX, y: panel.minY, width: panel.width, height: 36)) }
        return out
    }

    /// 气泡在球的里侧（贴右边时在左边）。
    private func bubbleOffset(side: VoiceInputPolicy.Side) -> CGFloat {
        let shift = VoiceInputPolicy.diameter / 2 + 8 + VoiceBubble.width / 2
        return side == .trailing ? -shift : shift
    }

    private var ball: some View {
        let d = VoiceInputPolicy.diameter
        return VoiceBall(phase: voice.phase)
            .frame(width: d, height: d)
            .contentShape(Circle())
            .onTapGesture { voice.tap() }
            .gesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .named(TourSpace.name))
                    .onChanged { dragging = $0.location }
                    .onEnded { value in
                        let snapped = VoiceInputPolicy.snap(value.location, in: area)
                        if landscape { landscapeSpot = VoiceInputPolicy.encode(snapped) } else { portraitSpot = VoiceInputPolicy.encode(snapped) }
                        withAnimation(.spring(duration: 0.3, bounce: 0.2)) { dragging = nil }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(VoiceInputPolicy.accessibilityLabel)
            .accessibilityValue(VoiceInputPolicy.accessibilityValue(voice.phase, now: voice.now))
            .accessibilityHint(VoiceInputPolicy.accessibilityHint(voice.phase))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { voice.tap() }
            .accessibilityAction(.magicTap) {
                if case .recording = voice.phase { voice.tap() }
            }
    }
}

/// 球本身：空闲时话筒，录音中红色的停止，发送中转圈，完成打勾，失败感叹号。
private struct VoiceBall: View {
    let phase: VoiceInputPolicy.Phase

    var body: some View {
        ZStack {
            Circle().fill(fill)
            Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            content
        }
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }

    private var fill: Color {
        switch phase {
        case .recording: return Color.red
        case .failed: return Color.orange
        default: return Color(white: 0.16).opacity(0.92)
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .idle:
            Image(systemName: "mic.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
        case .recording:
            RoundedRectangle(cornerRadius: 4).fill(.white).frame(width: 18, height: 18)
        case .sending:
            ProgressView().tint(.white).controlSize(.regular)
        case .done:
            Image(systemName: "checkmark").font(.system(size: 22, weight: .bold)).foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
        }
    }
}

/// 球旁的气泡：录音中的波形与时长，发送中的说明，完成的文字预览，失败的说明。空闲时没有。
private struct VoiceBubble: View {
    @ObservedObject var voice: VoiceInputController
    let side: VoiceInputPolicy.Side
    static let width: CGFloat = 240

    var body: some View {
        Group {
            switch voice.phase {
            case .idle:
                EmptyView()
            case .recording(_, let since):
                HStack(spacing: 8) {
                    HStack(alignment: .center, spacing: 2) {
                        ForEach(Array(voice.levels.enumerated()), id: \.offset) { _, level in
                            Capsule().fill(Color.white).frame(width: 3, height: 4 + 20 * level)
                        }
                    }
                    .frame(height: 24)
                    Text(VoiceInputPolicy.elapsedText(voice.now - since))
                        .font(.system(.callout, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                }
                .bubble(alignment: side)
            case .sending:
                Text("Recognizing…")
                    .font(.callout)
                    .foregroundStyle(.white)
                    .bubble(alignment: side)
            case .done(let text, _):
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .bubble(alignment: side)
            case .failed(let message, _):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .lineLimit(4)
                    .bubble(alignment: side, warning: true)
            }
        }
        .frame(width: Self.width, alignment: side == .trailing ? .trailing : .leading)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.2), value: kind)
    }

    /// 气泡的种类变了才动画（时长与音量每 0.05 秒变一次，不动画）。
    private var kind: Int {
        switch voice.phase {
        case .idle: return 0
        case .recording: return 1
        case .sending: return 2
        case .done: return 3
        case .failed: return 4
        }
    }
}

private extension View {
    func bubble(alignment side: VoiceInputPolicy.Side, warning: Bool = false) -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(warning ? Color.orange.opacity(0.92) : Color(white: 0.12).opacity(0.92))
            )
            .multilineTextAlignment(side == .trailing ? .trailing : .leading)
            .accessibilityHidden(true)          // 球的值已经说了
    }
}

/// ⌃⌥R：开始或提交语音输入，从硬件键盘（与 meeppo-voice 的快捷键一致）。同 EscapeKey 的做法：一个零大小的视图进窗口
/// 时把键命令加到它的视图控制器上，`wantsPriorityOverSystemBehavior`，不在快捷键列表里显示标题之外的东西。
struct VoiceShortcutKey: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> Anchor { Anchor() }
    func updateUIView(_ anchor: Anchor, context: Context) { anchor.action = action }
    static func dismantleUIView(_ anchor: Anchor, coordinator: ()) { anchor.detach() }

    final class Anchor: UIView {
        var action: (() -> Void)?
        fileprivate static var live: [Anchor] = []
        private weak var host: UIViewController?
        private let command: UIKeyCommand = {
            let command = UIKeyCommand(title: String(localized: "Voice Input", comment: "硬件键盘快捷键列表：语音输入"),
                                       action: #selector(UIViewController.sillVoiceShortcut(_:)),
                                       input: "r", modifierFlags: [.control, .alternate])
            command.wantsPriorityOverSystemBehavior = true
            return command
        }()

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { detach() } else { attach() }
        }

        private func attach() {
            guard host == nil else { return }
            var responder: UIResponder? = next
            while let r = responder, !(r is UIViewController) { responder = r.next }
            guard let controller = responder as? UIViewController else { return }
            host = controller
            controller.addKeyCommand(command)
            Self.live.append(self)
        }

        func detach() {
            host?.removeKeyCommand(command)
            host = nil
            Self.live.removeAll { $0 === self }
        }

        /// 只在按键的那个窗口里的球应答（每个 Sill 窗口各有自己的会话）。
        fileprivate static func fire(in window: UIWindow?) {
            guard let window, let anchor = live.last(where: { $0.window === window }) else { return }
            #if DEBUG
            print("voice: ⌃⌥R")
            #endif
            anchor.action?()
        }
    }
}

extension UIViewController {
    @objc fileprivate func sillVoiceShortcut(_ sender: UIKeyCommand) {
        VoiceShortcutKey.Anchor.fire(in: viewIfLoaded?.window)
    }
}
