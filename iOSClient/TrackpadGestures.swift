import Foundation
import CoreGraphics

/// Three- and four-finger strokes on the device's glass, for the Mac (docs/trackpad-gestures-plan.md
/// §6.1): which stroke is a gesture, and which gesture it is. Both glass surfaces feed one of these
/// with every direct touch (StrokeObserver, InputOverlay.swift): the portrait trackpad and the stream.
///
/// A stroke runs from its first touch down to its last touch up. It goes *silent* once three fingers
/// are down, before any finger has moved `chordTravel` from where it landed and while no button the
/// surface pressed is held (the trackpad's press-and-hold drag), however slowly they came down and
/// whatever else rests on the glass. From then until the next stroke's first touch the surfaces send
/// nothing for it, no pointer motion, click, button or scroll (a tap's action runs after its touch
/// has ended, so silence outlasts the last lift). A two-finger scroll that a third finger joins after
/// moving is never silent and goes on as it always did; a stroke that never has three fingers down is
/// never silent, so one- and two-finger strokes are exactly what they were.
///
/// A silent stroke is *armed*, one that can become a gesture, when the three fingers that landed last
/// came down within `chordWindow` of each other, before any finger moved `chordTravel`, with no button
/// held, no touch of the stroke cancelled and at most four fingers down. So a thumb resting on the
/// glass before neither keeps three fingers from arming nor becomes one of them; three fingers placed
/// slowly are silent and decide nothing.
///
/// The decision comes at the first lift of one of those three (another finger lifting only leaves the
/// stroke), from their centroid's net travel since arming, and their spread. A swipe when the centroid
/// travelled `swipeDistance` (or `flickDistance` while moving at `flickSpeed` over the last
/// `flickWindow`), one axis beats the other by `axisRatio`, and the fingers moved together: each of
/// the three at least `swipeShare` of the centroid's way along the swipe, and no other finger that
/// moved (`chordTravel` or more) that share or more against it. In a pinch or a spread some digit
/// moves against the others, however far the centroid goes (a thumb-led pinch drags it along with
/// the thumb). Else a pinch or a spread when the mean distance from the centroid changed by
/// `pinchRatio`, of the three and every other finger that moved (a thumb pinching with three
/// fingers); else nothing. At most one decision per stroke; `fingers` counts the three and the other
/// fingers that moved, 4 at most. A fifth finger down leaves the stroke silent and deciding nothing;
/// touches the system cancels decide nothing. So a swipe taken back before the lift does nothing, as
/// on a Mac, and a four-finger stroke that iPadOS takes for itself (its touches cancelled) never
/// reaches the Mac.
///
/// 本 fork：三指左右滑在切应用可用时不等抬手：三指同向横移 `pageStart` 就进入翻页拖动（`drag`），之后每次移动报告
/// 水平位移，抬手给 `.pageEnded`（位移与速度，翻不翻由 `pageCommit` 定），被取消或落下第四指给 `.pageCancelled`。
///
/// Pure: Foundation and CoreGraphics only, checked on its own with swiftc (Tests/checks/gestures).
/// Deterministic: the same touches give the same outputs. Main thread, as the touches come.
struct TrackpadGestures {
    /// The gestures, named as kind 28 names them (TrackpadGesture). Natural direction: fingers
    /// moving left are `swipeLeft`, which brings the Space on the right.
    enum Gesture: String, Equatable, CaseIterable {
        case swipeUp, swipeDown, swipeLeft, swipeRight, pinch, spread

        /// The way a swipe's fingers move, as a unit vector in the surface's points (y grows down);
        /// nil for a pinch or a spread.
        var direction: CGVector? {
            switch self {
            case .swipeUp: return CGVector(dx: 0, dy: -1)
            case .swipeDown: return CGVector(dx: 0, dy: 1)
            case .swipeLeft: return CGVector(dx: -1, dy: 0)
            case .swipeRight: return CGVector(dx: 1, dy: 0)
            case .pinch, .spread: return nil
            }
        }
    }

    enum Output: Equatable {
        case none
        /// The stroke just went silent: close what it had opened (a scroll).
        case silenced
        /// The decision, at the first lift of a finger that armed the stroke.
        case gesture(Gesture, fingers: Int)
        /// 本 fork：翻页拖动中，质心相对武装时刻的水平位移（`drag`）。
        case paging(dx: CGFloat)
        /// 本 fork：翻页拖动结束（武装的三指之一抬起）：最后的水平位移和抬手前的水平速度（pt/s，带符号）。
        case pageEnded(dx: CGFloat, velocity: CGFloat)
        /// 本 fork：翻页拖动被系统取消，或出现第四根手指：弹回。
        case pageCancelled
    }

    // The tunables, in the surface's points and seconds (Noah's P1 and P3 tune them on glass).
    /// The three fingers that arm a stroke land within this of each other…
    var chordWindow: TimeInterval = 0.15
    /// …before any finger has moved this far from where it landed (which also keeps a stroke from
    /// going silent). A finger other than the three that moved this far took part in the gesture.
    var chordTravel: CGFloat = 24
    /// The fingers' centroid, net travel, for a swipe…
    var swipeDistance: CGFloat = 40
    /// …or this much while moving at `flickSpeed` or faster over the last `flickWindow`.
    var flickDistance: CGFloat = 20
    var flickSpeed: CGFloat = 500
    var flickWindow: TimeInterval = 0.05
    /// The swipe's axis beats the other by this.
    var axisRatio: CGFloat = 1.3
    /// A swipe's fingers move together: each of the three this share of the centroid's travel along
    /// the swipe or more, and no other finger that moved this share of it or more the other way.
    var swipeShare: CGFloat = 0.5
    /// The fingers' mean distance from their centroid changed by this fraction: a pinch or a spread.
    var pinchRatio: CGFloat = 0.25
    /// 本 fork：三指只在屏上、同向横移这么远（且横向占优 `axisRatio`），这一笔就进入翻页拖动（`drag`）。
    var pageStart: CGFloat = 12

    /// From three fingers down (see above) until the next stroke's first touch: the surfaces send
    /// nothing.
    private(set) var silent = false
    /// The stroke armed: it decides at the first lift of one of its three fingers (for the checks).
    var armed: Bool { !armedBy.isEmpty }

    // MARK: The stroke

    private struct Finger {
        let landed: CGPoint
        let landedAt: TimeInterval
        var now: CGPoint
    }
    /// The fingers down now, by the caller's id.
    private var fingersDown: [Int: Finger] = [:]
    /// Some finger moved `chordTravel` from where it landed before the stroke armed.
    private var travelled = false
    /// The system cancelled a touch of this stroke before it armed: it never arms.
    private var cancelledEarly = false
    /// The three fingers that armed the stroke, and where each was at that moment.
    private var armedBy: [Int] = []
    private var armedAt: [Int: CGPoint] = [:]
    /// Every other finger of an armed stroke: where it was at arming (or landed, after), and where it
    /// is now or lifted. The ones that moved `chordTravel` took part.
    private var others: [Int: (start: CGPoint, now: CGPoint)] = [:]
    /// The stroke has decided, or can decide nothing more (a fifth finger, a cancel).
    private var done = false
    /// The armed fingers' centroid over time, from arming, for the flick.
    private var track: [(time: TimeInterval, at: CGPoint)] = []
    /// 本 fork：这一笔已进入翻页拖动：之后每次移动都报告水平位移，不再产生 `.gesture`。
    private(set) var paging = false

    /// A finger lands. `holding`: a button the surface pressed is held (the trackpad's drag).
    /// Returns `.silenced` once, when this finger makes the stroke silent.
    mutating func down(_ id: Int, at point: CGPoint, time: TimeInterval, holding: Bool) -> Output {
        if fingersDown.isEmpty {
            // A new stroke: silence, and everything else of the last one, ends here.
            silent = false
            travelled = false
            cancelledEarly = false
            armedBy = []
            armedAt = [:]
            others = [:]
            done = false
            track = []
            paging = false
        }
        fingersDown[id] = Finger(landed: point, landedAt: time, now: point)
        if fingersDown.count >= 5 { done = true }        // a fifth finger: deciding nothing
        if armed {
            others[id] = (point, point)
            // 本 fork：翻页中又落下一根手指：弹回，这一笔不再判定。
            if paging, !done {
                done = true
                return .pageCancelled
            }
            return .none
        }
        guard fingersDown.count >= 3, !travelled, !holding else { return .none }
        var output = Output.none
        if !silent {
            silent = true
            output = .silenced
        }
        // Armed by the three that landed last, when they came down within the window.
        let byLanding = fingersDown.sorted { a, b in
            a.value.landedAt != b.value.landedAt ? a.value.landedAt < b.value.landedAt : a.key < b.key
        }
        let three = byLanding.suffix(3)
        if !done, !cancelledEarly, let first = three.first, time - first.value.landedAt <= chordWindow {
            armedBy = three.map(\.key).sorted()
            for id in armedBy { armedAt[id] = fingersDown[id]!.now }
            for (id, finger) in fingersDown where armedAt[id] == nil { others[id] = (finger.now, finger.now) }
            track = [(time, centroid(armedAt))]
        }
        return output
    }

    /// A finger moves.
    mutating func moved(_ id: Int, to point: CGPoint, time: TimeInterval) {
        guard var finger = fingersDown[id] else { return }
        finger.now = point
        fingersDown[id] = finger
        if !armed {
            if distance(point, finger.landed) >= chordTravel { travelled = true }
            return
        }
        if others[id] != nil { others[id]!.now = point }
        if !done, armedBy.contains(id) { track.append((time, centroid(nowOfArmed()))) }
    }

    /// A finger lifts. The first lift of one of the three that armed the stroke decides: `.gesture` at
    /// most once a stroke. Any other finger lifting only leaves the stroke (where it lifted counts, if
    /// it moved).
    mutating func up(_ id: Int, at point: CGPoint, time: TimeInterval) -> Output {
        guard var finger = fingersDown[id] else { return .none }
        finger.now = point
        fingersDown[id] = finger
        if others[id] != nil { others[id]!.now = point }
        var output = Output.none
        if armed, !done, armedBy.contains(id) {
            done = true
            if paging {
                // 本 fork：翻页的笔不判定手势，只交出位移与抬手前的水平速度。
                let end = centroid(nowOfArmed())
                output = .pageEnded(dx: end.x - centroid(armedAt).x, velocity: horizontalVelocity(to: end, at: time))
            } else if let (gesture, fingers) = decide(liftAt: time) {
                output = .gesture(gesture, fingers: fingers)
            }
        }
        fingersDown[id] = nil
        return output
    }

    /// A touch that is not a finger (a Pencil, the iPad's own trackpad or mouse) lands. It is never
    /// part of a stroke, but with no finger down it starts something new: the last stroke's silence
    /// ends, so a Pencil on the portrait trackpad right after a gesture is not ignored.
    mutating func otherTouch() {
        if fingersDown.isEmpty { silent = false }
    }

    /// The system took a touch (an iPadOS gesture, an alert): nothing is decided for this stroke,
    /// and one that has not armed never will; a silent one stays silent.
    /// 本 fork：翻页拖动中被取消时返回 `.pageCancelled`（弹回），其余 `.none`。
    @discardableResult
    mutating func cancelled(_ id: Int) -> Output {
        guard fingersDown[id] != nil else { return .none }
        fingersDown[id] = nil
        guard armed else {
            cancelledEarly = true
            return .none
        }
        let wasPaging = paging && !done
        done = true
        return wasPaging ? .pageCancelled : .none
    }

    // MARK: The decision

    private func nowOfArmed() -> [Int: CGPoint] {
        var out: [Int: CGPoint] = [:]
        for id in armedBy { out[id] = fingersDown[id]?.now ?? armedAt[id] }
        return out
    }

    /// The gesture and its fingers, or nil for none.
    private func decide(liftAt time: TimeInterval) -> (Gesture, Int)? {
        let now = nowOfArmed()
        let start = centroid(armedAt), end = centroid(now)
        let dx = end.x - start.x, dy = end.y - start.y
        let travel = hypot(dx, dy)
        // The other fingers that took part: a thumb pinching, a fourth finger swiping along. One that
        // stayed where it was (a thumb resting) or barely moved did not.
        let movers = others.filter { distance($0.value.start, $0.value.now) >= chordTravel }
        let fingers = min(3 + movers.count, 4)
        if travel >= swipeDistance || (travel >= flickDistance && speed(to: end, at: time) >= flickSpeed) {
            if let found = swipeOf(dx: dx, dy: dy, now: now, movers: movers) { return (found, fingers) }
        }
        // A pinch or a spread: the three and the others that moved, each from where it was at arming
        // (or landed, after) to where it is now or lifted.
        var before = armedAt, after = now
        for (id, other) in movers { before[id] = other.start; after[id] = other.now }
        let r0 = spread(before, around: centroid(before)), r1 = spread(after, around: centroid(after))
        guard r0 > 0 else { return nil }
        let change = r1 / r0
        if change <= 1 - pinchRatio { return (.pinch, fingers) }
        if change >= 1 + pinchRatio { return (.spread, fingers) }
        return nil
    }

    /// 本 fork：质心位移 (dx, dy) 是否成立一次滑动（轴向占优、三指同向、其他动过的手指没有逆着滑），成立则给出方向。
    /// 抬手时的 `decide` 用它；同向的那一半（`together`）翻页拖动（`drag`）也用。
    private func swipeOf(dx: CGFloat, dy: CGFloat, now: [Int: CGPoint],
                       movers: [Int: (start: CGPoint, now: CGPoint)]) -> Gesture? {
        let major = max(abs(dx), abs(dy)), minor = min(abs(dx), abs(dy))
        if major >= axisRatio * minor {
            let swipe: Gesture = abs(dx) > abs(dy) ? (dx < 0 ? .swipeLeft : .swipeRight) : (dy < 0 ? .swipeUp : .swipeDown)
            if together(along: swipe, dx: dx, dy: dy, now: now, movers: movers) { return swipe }
        }
        return nil
    }

    /// 本 fork：三指沿 `swipe` 的方向同向（每指至少 `swipeShare` 的质心位移），其他动过的手指没有逆着它走那么远。
    private func together(along swipe: Gesture, dx: CGFloat, dy: CGFloat, now: [Int: CGPoint],
                          movers: [Int: (start: CGPoint, now: CGPoint)]) -> Bool {
        let axis = swipe.direction!
        let along = dx * axis.dx + dy * axis.dy
        func share(_ from: CGPoint, _ to: CGPoint) -> CGFloat { (to.x - from.x) * axis.dx + (to.y - from.y) * axis.dy }
        let together = armedBy.allSatisfy { share(armedAt[$0]!, now[$0]!) >= swipeShare * along }
            && movers.values.allSatisfy { share($0.start, $0.now) > -swipeShare * along }
        return together
    }

    // MARK: 三指翻页拖动（本 fork）

    /// 本 fork：一次触摸事件里的移动都记完之后调用；`enabled`：翻页此刻可用（三指左右滑会切应用的时候）。
    /// 进入翻页（返回第一个 `.paging`）要：已武装、未判定，屏上正好是武装的三指（没有过别的手指），质心横移
    /// `pageStart` 以上且横向占优 `axisRatio`，三指同向，`enabled`。进入后锁定：之后每次都报告质心相对武装时刻的
    /// 水平位移，不再看轴向；抬手给 `.pageEnded`，不产生 `.gesture`。没进入的笔一切照旧，抬手时由 `decide` 判定。
    mutating func drag(time: TimeInterval, enabled: Bool) -> Output {
        guard armed, !done else { return .none }
        let now = nowOfArmed()
        let start = centroid(armedAt), end = centroid(now)
        let dx = end.x - start.x, dy = end.y - start.y
        if paging { return .paging(dx: dx) }
        // 屏上正好是武装的三指：`others` 为空就是（武装的三指之一抬起或被取消，这一笔已判定，上面就返回了），
        // 所以不必再数 `fingersDown`。
        guard enabled, others.isEmpty,
              abs(dx) >= pageStart, abs(dx) >= axisRatio * abs(dy),
              together(along: dx < 0 ? .swipeLeft : .swipeRight, dx: dx, dy: dy, now: now, movers: [:]) else { return .none }
        paging = true
        return .paging(dx: dx)
    }

    /// 本 fork：抬手前的水平速度（pt/s，带符号）：与 flick 的 `speed` 同一个起点（`flickWindow` 之前最后的位置），
    /// 只取水平分量。
    private func horizontalVelocity(to end: CGPoint, at time: TimeInterval) -> CGFloat {
        guard let first = track.first else { return 0 }
        var from = first
        for sample in track where sample.time <= time - flickWindow { from = sample }
        let dt = time - from.time
        guard dt > 0 else { return 0 }
        return (end.x - from.at.x) / CGFloat(dt)
    }

    /// 本 fork：松手时位移过了这么远就翻：min(120, 画面宽度 × 0.22)。
    static func pageCommitDistance(width: CGFloat) -> CGFloat {
        min(120, width * 0.22)
    }

    /// 本 fork：抬手时的速度朝位移的反方向到了这么快（pt/s），就不翻，弹回。慢于它的反向速度当作抬手时的抖动，不算。
    static let pageBackSpeed: CGFloat = 100

    /// 本 fork：松手时翻不翻：位移过了 `pageCommitDistance(width)`，或者以 `flickSpeed` 以上的速度朝位移的方向甩，就翻；
    /// 速度以 `pageBackSpeed` 以上朝位移的反方向时不翻；零位移不翻。返回 .swipeRight（手指往右）或 .swipeLeft，nil 是弹回。
    static func pageCommit(dx: CGFloat, velocity: CGFloat, width: CGFloat) -> Gesture? {
        guard dx != 0 else { return nil }
        let toward = dx > 0 ? velocity : -velocity          // 速度在位移方向上的分量
        guard toward > -pageBackSpeed else { return nil }
        guard abs(dx) >= pageCommitDistance(width: width) || toward >= TrackpadGestures().flickSpeed else { return nil }
        return dx > 0 ? .swipeRight : .swipeLeft
    }

    /// 本 fork：画面实际挪多少：那个方向有可切的应用时就是 dx（夹在 ±width 内）；没有时带阻尼，dx × 0.25，最多 ±60。
    static func pageOffset(dx: CGFloat, width: CGFloat, hasTarget: Bool) -> CGFloat {
        if hasTarget { return min(max(dx, -width), width) }
        return min(max(dx * 0.25, -60), 60)
    }

    /// The centroid's speed over the last `flickWindow` before `time`: from the last place it was at
    /// or before that moment (where it was at arming when the stroke armed later), to `end`.
    private func speed(to end: CGPoint, at time: TimeInterval) -> CGFloat {
        guard let first = track.first else { return 0 }
        var from = first
        for sample in track where sample.time <= time - flickWindow { from = sample }
        let dt = time - from.time
        guard dt > 0 else { return 0 }
        return distance(end, from.at) / CGFloat(dt)
    }

    private func centroid(_ points: [Int: CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        var x: CGFloat = 0, y: CGFloat = 0
        for id in points.keys.sorted() { x += points[id]!.x; y += points[id]!.y }
        return CGPoint(x: x / CGFloat(points.count), y: y / CGFloat(points.count))
    }

    /// The mean distance of `points` from `center`.
    private func spread(_ points: [Int: CGPoint], around center: CGPoint) -> CGFloat {
        guard !points.isEmpty else { return 0 }
        var total: CGFloat = 0
        for id in points.keys.sorted() { total += distance(points[id]!, center) }
        return total / CGFloat(points.count)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    // MARK: Sending

    /// What becomes of a decided gesture (StreamClient.sendGesture): it goes to the Mac only while
    /// this device's switch is on, a session is up, and the Mac's window list said it takes at least
    /// `generation` (`WindowList.gestures`; nil from a Mac before them, which gets none). While a
    /// window streams the Desktop is picked first, as its button does: none of the views a gesture
    /// opens is in a window's picture.
    static func sending(switchOn: Bool, connected: Bool, hostGestures: Int?, generation: Int,
                        windowStreams: Bool) -> (send: Bool, desktopFirst: Bool) {
        guard switchOn, connected, let takes = hostGestures, takes >= generation else { return (false, false) }
        return (true, windowStreams)
    }

    // MARK: 三指左右滑切换应用（本 fork）

    /// 三指左右滑不发给 Mac（不再切换 Mac 的桌面空间），而是在顶栏 Dock 里换到相邻的应用（图标模式按应用，
    /// 缩略图模式按窗口）；串流桌面时也一样，从桌面切进 Dock 的第一个或最后一个。只认三指的左右滑；四指与其他方向照旧。
    static func switchesApp(_ gesture: Gesture, fingers: Int, switchOn: Bool, connected: Bool) -> Bool {
        switchOn && connected && fingers == 3 && (gesture == .swipeLeft || gesture == .swipeRight)
    }

    /// 连续切换时沿用的顺序：上一次切换后这么久之内再滑，用当时的顺序（图标按最近使用排序，切换后会把新应用排到
    /// 最前；沿用旧顺序，连续往一个方向滑才能一路往后走）。
    static let appSwitchKeepsOrder = 1.5

    /// 切换的目标：在 `order`（Dock 从左到右）里，`current` 往左滑是下一个（Dock 里右边那个，画面往左走、它从右边进来）、
    /// 往右滑是上一个，到头不绕回（用户 2026-11-18：方向调反，和拖动画面的方向一致）；
    /// `current` 不在列表里（刚关掉、或在串流桌面）时往左是第一个、往右是最后一个。没有别的可切就是 nil。
    static func appSwitchTarget(order: [UInt32], current: UInt32?, gesture: Gesture) -> UInt32? {
        guard !order.isEmpty, gesture == .swipeLeft || gesture == .swipeRight else { return nil }
        let forward = gesture == .swipeLeft
        guard let current, let i = order.firstIndex(of: current) else {
            return forward ? order.first : order.last
        }
        let j = forward ? i + 1 : i - 1
        return order.indices.contains(j) ? order[j] : nil
    }
}
