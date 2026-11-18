import Foundation

/// 本 fork：这台设备上的"选择"（点 Dock 图标、缩略图、桌面按钮，三指左右滑）在路上时的规则。纯逻辑，
/// `Tests/checks/pick-flow` 单独检查；StreamClient 在主线程上执行它。
///
/// 为什么要有：Mac 正切到另一个源时收到的新选择会被直接丢掉（StreamCoordinator.handlePick），连续点或连续滑
/// 时只有第一下生效，Dock 的高亮随后弹回去。所以设备同一时刻只让一次选择在路上（`flight`）：它有了结果
/// （窗口列表说 Mac 在串流它了，或者串流的换成了别的）之前，新的选择只记最新的一个（`queued`），等结果到了再发。
///
/// 另外记着这个人最后要的是什么（`wanted`），直到它的画面到：Mac 说在串流它了，并且发出之后收到过关键帧。
/// 画面上的占位（PickShade）和切换耗时的记录（`Done`）都从这里来。
struct PickFlow<Source: Equatable> {
    /// 一次选择发出后等 Mac 结果的最长时间。日志里 Mac 端一次切换最长 3.2 秒；选择到的时候 Mac 正在重启当前源
    /// （改了视口、设置）的话，它先做完重启再做这次选择，两段加起来要等得起，否则排队的会发早、被 Mac 丢掉。
    static var answerWait: TimeInterval { 8 }
    /// 发出后等新画面的最长时间；过了就不再占着画面。
    static var pictureWait: TimeInterval { 9 }

    /// 已经发给 Mac、还没有结果的那一次：发的时候 Mac 在串流 `from`。
    struct Flight: Equatable {
        let source: Source
        let from: Source
        let sentAt: TimeInterval
    }

    /// 这个人最后要的源：什么时候选的，什么时候发出的（排着队时还没有），Mac 什么时候说在串流它了，
    /// 发出之后第一个关键帧什么时候到的。后两个都有了，画面就到了。
    struct Wanted: Equatable {
        let source: Source
        let pickedAt: TimeInterval
        var sentAt: TimeInterval?
        var confirmedAt: TimeInterval?
        var keyframeAt: TimeInterval?
    }

    /// 一次切换完成：从选到画面一共多久，其中排队等了多久，Mac 的列表和关键帧各在发出后多久到。
    struct Done: Equatable {
        let source: Source
        let total: TimeInterval
        let queued: TimeInterval
        let listAfterSend: TimeInterval
        let keyframeAfterSend: TimeInterval
    }

    private(set) var flight: Flight?
    private(set) var queued: Source?
    private(set) var wanted: Wanted?
    /// 最近一个关键帧收到的时刻：要的那一次还排着队时到的关键帧，等它改回"已发出"时还要算数。
    private var lastKeyframeAt: TimeInterval?

    /// 这个人选了 `source`，Mac 此刻在串流 `active`。true：现在就发给 Mac；false：有一次还在路上，这次排着。
    /// 重选正在串流的源照旧直接发（Mac 会重启它，期间到的选择它自己会排队），不跟踪。
    mutating func pick(_ source: Source, active: Source, now: TimeInterval) -> Bool {
        if let flight {
            if flight.source == source {
                // 又选回了路上的那一个：不用再发，排队的作废。
                queued = nil
                if wanted?.source != source {
                    wanted = Wanted(source: source, pickedAt: now, sentAt: flight.sentAt, keyframeAt: keyframe(since: flight.sentAt))
                }
            } else {
                queued = source
                wanted = Wanted(source: source, pickedAt: now)
            }
            return false
        }
        queued = nil
        if source == active {
            wanted = nil
            return true
        }
        flight = Flight(source: source, from: active, sentAt: now)
        wanted = Wanted(source: source, pickedAt: now, sentAt: now)
        return true
    }

    /// Mac 的窗口列表到了：它在串流 `active`；`exists` 说一个源还在不在（窗口可能已经关了）；`hasPicture` 说一个源
    /// 有没有画面可等（"什么都不串流"没有，Mac 说到了就算到了）。
    /// `send`：现在该发的下一次选择（排队的那个）；`done`：这个人要的画面到了。
    mutating func listed(active: Source, exists: (Source) -> Bool, hasPicture: (Source) -> Bool = { _ in true },
                         now: TimeInterval) -> (send: Source?, done: Done?) {
        // 要的窗口已经不在了：不再等它。
        if let w = wanted, !exists(w.source) {
            wanted = nil
            if queued == w.source { queued = nil }
        }
        guard let f = flight else {
            // 没有在路上的：要的源被别处换掉了（Mac 上，或另一台设备），不再等它的画面。
            if let w = wanted, w.source != active { wanted = nil }
            return (nil, nil)
        }
        // 还是发之前的那个源：这份列表是 Mac 处理这次选择之前的（每两秒的例行列表），继续等。
        if active == f.from { return (nil, nil) }
        flight = nil
        if let next = queued {
            queued = nil
            if next != active {       // 它还在：不在的话上面已经连同 wanted 一起放下了
                flight = Flight(source: next, from: active, sentAt: now)
                if wanted?.source == next { wanted?.sentAt = now }
                return (next, nil)
            }
            // 排着的正是 Mac 现在串流的：当作上一次发出时就要了它。
            if wanted?.source == next, next == active {
                let seen = keyframe(since: f.sentAt)
                wanted?.sentAt = f.sentAt
                wanted?.keyframeAt = seen
            }
        }
        guard var w = wanted, w.source == active else {
            wanted = nil            // 这次选择没成（窗口没了、Mac 锁着、被别的选择顶掉）
            return (nil, nil)
        }
        w.confirmedAt = now
        if !hasPicture(w.source), w.keyframeAt == nil { w.keyframeAt = now }
        wanted = w
        return (nil, finish())
    }

    /// 收到一个关键帧（`receivedAt`：网络队列上收到它的时刻）。要的那一次发出之后的第一个才算；
    /// Mac 也说在串流它了，画面就到了。
    mutating func keyframe(receivedAt: TimeInterval) -> Done? {
        lastKeyframeAt = receivedAt
        guard var w = wanted, let sentAt = w.sentAt, receivedAt >= sentAt, w.keyframeAt == nil else { return nil }
        w.keyframeAt = receivedAt
        wanted = w
        return finish()
    }

    /// 到点了（`deadline`）：路上那次等过了 `answerWait` 就不等了，排队的接着发；没有排队的，或者画面等过了
    /// `pictureWait`，就放下这次选择（`gaveUp`）。
    mutating func expire(active: Source, now: TimeInterval) -> (send: Source?, gaveUp: Bool) {
        if let f = flight {
            guard now - f.sentAt >= Self.answerWait else { return (nil, false) }
            flight = nil
            if let next = queued {
                queued = nil
                if next != active {
                    flight = Flight(source: next, from: active, sentAt: now)
                    if wanted?.source == next { wanted?.sentAt = now }
                    return (next, false)
                }
            }
            wanted = nil
            return (nil, true)
        }
        if let w = wanted, let sentAt = w.sentAt, now - sentAt >= Self.pictureWait {
            wanted = nil
            return (nil, true)
        }
        return (nil, false)
    }

    /// 下一次该调 `expire` 的时刻；没有在等的就是 nil。
    var deadline: TimeInterval? {
        if let f = flight { return f.sentAt + Self.answerWait }
        if let sentAt = wanted?.sentAt { return sentAt + Self.pictureWait }
        return nil
    }

    /// 会话结束：什么都不等了。
    mutating func reset() {
        flight = nil
        queued = nil
        wanted = nil
        lastKeyframeAt = nil
    }

    /// `sentAt` 之后已经收到过的关键帧的时刻。
    private func keyframe(since sentAt: TimeInterval) -> TimeInterval? {
        lastKeyframeAt.flatMap { $0 >= sentAt ? $0 : nil }
    }

    /// Mac 说在串流它了、发出之后的关键帧也到了：画面到了，记下耗时。
    private mutating func finish() -> Done? {
        guard let w = wanted, let sentAt = w.sentAt, let confirmedAt = w.confirmedAt, let keyframeAt = w.keyframeAt else { return nil }
        wanted = nil
        return Done(source: w.source, total: max(confirmedAt, keyframeAt) - w.pickedAt, queued: max(0, sentAt - w.pickedAt),
                    listAfterSend: confirmedAt - sentAt, keyframeAfterSend: keyframeAt - sentAt)
    }
}

extension PickFlow.Done {
    /// 调试控制台的一行（毫秒取整）："switch: 512 ms to the picture (queued 0 ms; after it was sent, the Mac's list 498 ms, the keyframe 512 ms)"。
    var line: String {
        func ms(_ seconds: TimeInterval) -> Int { Int((seconds * 1000).rounded()) }
        return "switch: \(ms(total)) ms to the picture (queued \(ms(queued)) ms; after it was sent, the Mac's list \(ms(listAfterSend)) ms, the keyframe \(ms(keyframeAfterSend)) ms)"
    }
}

#if canImport(UIKit)
import SwiftUI
import StreamProtocol

#if DEBUG
/// `-SillPickScript '<t> <source>; …'`（调试用）：没有手指的模拟器里替这个人做选择，走 `StreamClient.select`，
/// 和点 Dock 图标、桌面按钮一样。`t` 是会话第一份窗口列表之后的秒数；源是 `desktop`、`none` 或 `window:ID`。
/// 只对回环地址上、窗口列表不带版本号的主机（合成测试主机）生效，规则借用 InputScript 的（不需要 `-SillLive`）。
/// 控制台："pick script: …"，以及 PickFlow 自己的 "switch: …"。
enum PickScript {
    private static var started = false

    static func sessionListed(_ client: StreamClient) {
        guard !started, let text = UserDefaults.standard.string(forKey: "SillPickScript") else { return }
        started = true
        if let why = InputScript.refusal(endpoint: client.connection?.endpoint, hostVersion: client.hostVersion) {
            print("pick script: refused: \(why)")
            return
        }
        for part in text.split(separator: ";") {
            let words = part.split(separator: " ")
            guard words.count == 2, let at = Double(words[0]) else { print("pick script: cannot read \(part)"); continue }
            let source: StreamSource
            switch words[1] {
            case "desktop": source = .desktop
            case "none": source = .none
            default:
                guard words[1].hasPrefix("window:"), let id = UInt32(words[1].dropFirst(7)) else {
                    print("pick script: cannot read \(part)")
                    continue
                }
                source = .window(id)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak client] in
                guard let client else { return }
                print(String(format: "pick script: t=%.2f ", at) + "\(source) (the Mac streams \(client.active))")
                client.select(source)
            }
        }
    }
}
#endif

/// 本 fork：选了另一个源、它的画面还没到的这段时间，盖在画面上的占位：目标窗口的缩略图（Mac 每两秒更新一次，
/// 设备上本来就有）和一个转圈；选的是桌面（没有缩略图）时只压暗旧画面。画面一到就撤（StreamClient.pickPending）。
/// 只是看的：不接触摸，VoiceOver 不读。
struct PickShade: View {
    @ObservedObject var client: StreamClient

    #if DEBUG
    /// `-SillPickShade desktop|<窗口 ID>`（调试用）：一直显示占位，给排版 mock 拍照用。
    private static let debugPending: StreamSource? = UserDefaults.standard.string(forKey: "SillPickShade").map {
        UInt32($0).map(StreamSource.window) ?? .desktop
    }
    private var pending: StreamSource? { client.pickPending ?? Self.debugPending }
    #else
    private var pending: StreamSource? { client.pickPending }
    #endif

    var body: some View {
        ZStack {
            if let pending {
                if case .window(let id) = pending, let image = client.thumbnails[id] {
                    Color.black
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFit()
                    Color.black.opacity(0.25)
                } else {
                    Color.black.opacity(0.45)
                }
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        .animation(.easeOut(duration: 0.12), value: client.pickPending)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: 本 fork：三指翻页拖动的画面

/// 本 fork：三指翻页拖动的界面状态：画面的横向偏移，两边要进来的窗口，是否在拖动或动画中。偏移每帧都变（触摸 120 Hz），
/// 所以单独一个对象，只有 `PagerStage` 看它；StreamClient 的 @Published 不变，串流画面以外的界面不跟着重算。
/// StreamClient 持有一个（`pager`），并在这里登记，让触摸面按窗口找到它（PageReceivers）。主线程。
final class PagerModel: ObservableObject {
    /// 两边要进来的窗口：`left` 是手指往右滑时从左边进来的（Dock 里的上一个），`right` 是往左滑时从右边进来的。
    struct Targets: Equatable {
        var left: UInt32?
        var right: UInt32?
    }
    /// 串流画面横向挪了多少（pt）：往右为正。
    @Published private(set) var offset: CGFloat = 0
    @Published private(set) var targets = Targets()
    /// 在拖动或动画中：这时才画两边要进来的页。
    @Published private(set) var active = false
    /// 已经决定翻过去、正滑到位：这段时间占位（PickShade）不叠在移出去的旧画面上，滑完在原位出现。
    @Published private(set) var committing = false
    /// 画面区域的宽度（ZoomedStreamView 量出来告诉这里）。
    @Published private(set) var width: CGFloat = 0
    /// 每次开始、提交、弹回、复位都加一，过期的动画完成回调不再做事。
    private var generation = 0
    private weak var client: StreamClient?

    /// 登记过的（每个会话一个），按窗口找。
    private static let all = NSHashTable<PagerModel>.weakObjects()

    init(client: StreamClient) {
        self.client = client
        Self.all.add(self)
        PageReceivers.lookup = PagerModel.receiver(in:)
    }

    /// 这个窗口里的会话：它的画面（displayView）就在这个窗口里。
    static func receiver(in window: UIWindow?) -> PageReceiver? {
        guard let window else { return nil }
        return all.allObjects.lazy.compactMap(\.client).first { $0.displayView.window === window }
    }

    func setWidth(_ new: CGFloat) {
        if new != width { width = new }
    }

    /// 拖动开始：记下两边的目标。
    func began(left: UInt32?, right: UInt32?) {
        generation += 1
        withTransaction(Self.still) {
            targets = Targets(left: left, right: right)
            committing = false
            active = true
        }
    }

    /// 拖动中：跟手，不带动画。
    func drag(to x: CGFloat) {
        withTransaction(Self.still) { offset = x }
    }

    /// 松手翻过去：`toward` 是 1（往右）或 -1；画面滑到 ±width，滑完无动画地归零，由占位接上。
    func commit(toward: CGFloat, animated: Bool) {
        generation += 1
        let mine = generation
        committing = true
        guard animated, width > 0 else { finish(); return }
        withAnimation(.easeOut(duration: 0.22)) {
            offset = toward * width
        } completion: { [weak self] in
            guard let self, self.generation == mine else { return }
            self.finish()
        }
    }

    /// 不翻、到头了、被取消：弹回 0。
    func bounce() {
        generation += 1
        let mine = generation
        committing = false
        guard offset != 0 else { finish(); return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85), completionCriteria: .removed) {
            offset = 0
        } completion: { [weak self] in
            guard let self, self.generation == mine else { return }
            self.finish()
        }
    }

    /// 会话结束：什么都不留。
    func reset() {
        generation += 1
        finish()
    }

    private func finish() {
        withTransaction(Self.still) {
            offset = 0
            active = false
            committing = false
            targets = Targets()
        }
    }

    private static var still: Transaction {
        var t = Transaction()
        t.disablesAnimations = true
        return t
    }
}

extension StreamClient: PageReceiver {}

/// 本 fork：串流画面（`content`，已经按缩放变换过）跟着翻页的偏移横向平移，旁边紧挨着带出要进来的那一页；
/// 占位（PickShade）随画面移动，翻过去的那一小段动画里不显示，滑完在原位出现。只看 PagerModel，所以每帧只重算这里。
/// 只是看的：不接触摸，VoiceOver 不读。
struct PagerStage<Content: View>: View {
    @ObservedObject var pager: PagerModel
    let client: StreamClient
    let content: Content

    var body: some View {
        ZStack {
            content
                .overlay {
                    if !pager.committing { PickShade(client: client) }
                }
                .offset(x: pager.offset)
            if pager.active {
                // 手指往右（offset > 0）时从左边进来，往左时从右边；那边没有目标就什么都不带出来。
                PageIncoming(image: image(pager.targets.left), present: pager.targets.left != nil)
                    .offset(x: pager.offset - pager.width)
                PageIncoming(image: image(pager.targets.right), present: pager.targets.right != nil)
                    .offset(x: pager.offset + pager.width)
            }
        }
        .allowsHitTesting(false)
    }

    private func image(_ id: UInt32?) -> UIImage? {
        id.flatMap { client.thumbnails[$0] }
    }
}

/// 本 fork：翻页时要进来的那一页，与占位（PickShade）的窗口样式一致：黑底、目标窗口缩略图 `scaledToFit`、0.25 的压暗，
/// 不带转圈；没有缩略图只是黑底；那边没有目标（`present` 为 false）什么都不画。
private struct PageIncoming: View {
    let image: UIImage?
    let present: Bool

    var body: some View {
        ZStack {
            if present {
                Color.black
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFit()
                    Color.black.opacity(0.25)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
