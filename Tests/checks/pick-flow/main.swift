// PickFlow（iOSClient/PickFlow.swift，本 fork）单独检查。
//   swiftc -O iOSClient/PickFlow.swift Tests/checks/pick-flow/main.swift -o .build/checks/pick-flow/check && .build/checks/pick-flow/check
import Foundation

typealias Flow = PickFlow<Int>
var passes = 0, fails = 0
func check(_ name: String, _ ok: Bool) {
    if ok { passes += 1; print("通过 \(name)") }
    else { fails += 1; print("FAIL \(name)") }
}
func near(_ a: TimeInterval?, _ b: TimeInterval) -> Bool { a.map { abs($0 - b) < 1e-9 } ?? false }
let all: (Int) -> Bool = { _ in true }
// 源：0 是桌面，1…9 是窗口，-1 是什么都不串流。
let A = 1, B = 2, C = 3, D = 4

check("等 Mac 结果最长 8 秒", Flow.answerWait == 8)
check("等画面最长 9 秒", Flow.pictureWait == 9)

// 一次选择，列表先到、关键帧后到。
do {
    var f = Flow()
    check("第一次选择马上发", f.pick(B, active: A, now: 10))
    check("发了就在路上", f.flight == Flow.Flight(source: B, from: A, sentAt: 10) && f.queued == nil)
    check("要的是它，已发出", f.wanted == Flow.Wanted(source: B, pickedAt: 10, sentAt: 10))
    check("期限是发出后 8 秒", near(f.deadline, 18))
    let stale = f.listed(active: A, exists: all, now: 10.1)
    check("Mac 还在串流原来的源：这份列表是之前的，继续等", stale.send == nil && stale.done == nil && f.flight != nil && f.wanted != nil)
    let listed = f.listed(active: B, exists: all, now: 10.4)
    check("Mac 说在串流它了：不在路上了，画面还没到", listed.send == nil && listed.done == nil && f.flight == nil
          && f.wanted?.confirmedAt == 10.4)
    check("期限改成发出后 9 秒（等画面）", near(f.deadline, 19))
    check("例行列表不影响等画面", f.listed(active: B, exists: all, now: 10.45).done == nil && f.wanted != nil)
    let done = f.keyframe(receivedAt: 10.5)
    check("关键帧到：画面到了", done == Flow.Done(source: B, total: 0.5, queued: 0, listAfterSend: 10.4 - 10, keyframeAfterSend: 0.5))
    check("到了就什么都不等", f.wanted == nil && f.flight == nil && f.deadline == nil)
    check("再来关键帧不重复报", f.keyframe(receivedAt: 10.6) == nil)
}

// 关键帧先到、列表后到。
do {
    var f = Flow()
    _ = f.pick(B, active: A, now: 0)
    check("发出之前收到的关键帧不算", f.keyframe(receivedAt: -0.001) == nil && f.wanted?.keyframeAt == nil)
    check("关键帧先到：还要等 Mac 的列表", f.keyframe(receivedAt: 0.30) == nil && f.wanted?.keyframeAt == 0.30)
    check("第二个关键帧不改第一个的时刻", f.keyframe(receivedAt: 0.35) == nil && f.wanted?.keyframeAt == 0.30)
    let listed = f.listed(active: B, exists: all, now: 0.32)
    check("列表到：画面到了，耗时算到两者中较晚的", listed.done == Flow.Done(source: B, total: 0.32, queued: 0, listAfterSend: 0.32, keyframeAfterSend: 0.30))
}

// 连续选择：只留最新的一个排队，上一次有结果后才发。
do {
    var f = Flow()
    _ = f.pick(B, active: A, now: 0)
    check("路上有一次：第二次不发", !f.pick(C, active: A, now: 0.1))
    check("排着 C，要的是 C，还没发出", f.queued == C && f.wanted == Flow.Wanted(source: C, pickedAt: 0.1))
    check("第三次也不发，顶掉第二次", !f.pick(D, active: A, now: 0.2) && f.queued == D && f.wanted?.source == D)
    check("路上的还是 B", f.flight?.source == B)
    check("B 的关键帧不算 D 的（D 还没发出）", f.keyframe(receivedAt: 0.38) == nil && f.wanted?.keyframeAt == nil)
    let listed = f.listed(active: B, exists: all, now: 0.4)
    check("B 有结果了：发 D", listed.send == D && listed.done == nil)
    check("D 在路上，从 B 出发", f.flight == Flow.Flight(source: D, from: B, sentAt: 0.4) && f.queued == nil)
    check("D 记为此刻发出", f.wanted == Flow.Wanted(source: D, pickedAt: 0.2, sentAt: 0.4))
    check("B 晚到的关键帧记下了，但 Mac 还没说在串流 D", f.keyframe(receivedAt: 0.42) == nil && f.wanted?.keyframeAt == 0.42)
    let end = f.listed(active: D, exists: all, now: 0.9)
    check("D 的列表到：完成，排队等了 0.2 秒", end.done == Flow.Done(source: D, total: 0.9 - 0.2, queued: 0.4 - 0.2,
                                                           listAfterSend: 0.9 - 0.4, keyframeAfterSend: 0.42 - 0.4))
}

// 又选回路上的那一个；选回出发的那一个。
do {
    var f = Flow()
    _ = f.pick(B, active: A, now: 0)
    _ = f.pick(C, active: A, now: 0.1)
    check("B 的关键帧在 C 排队时到", f.keyframe(receivedAt: 0.3) == nil)
    check("又选回 B：不发，排队作废", !f.pick(B, active: A, now: 0.35) && f.queued == nil)
    check("要的是 B，按路上那次的发出时刻算，之前到的关键帧算数", f.wanted == Flow.Wanted(source: B, pickedAt: 0.35, sentAt: 0, keyframeAt: 0.3))
    check("再点一次 B：什么都不变", !f.pick(B, active: A, now: 0.36) && f.wanted?.pickedAt == 0.35)
    let listed = f.listed(active: B, exists: all, now: 0.4)
    check("B 的列表到：不发别的，画面到了", listed.send == nil && listed.done?.source == B && near(listed.done?.total, 0.05))

    var g = Flow()
    _ = g.pick(B, active: A, now: 0)
    check("选回出发的 A：排着", !g.pick(A, active: A, now: 0.1) && g.queued == A)
    check("B 有结果后发 A", g.listed(active: B, exists: all, now: 0.5).send == A && g.flight == Flow.Flight(source: A, from: B, sentAt: 0.5))
}

// 发出之前到的关键帧，选回路上的那一个时也不算。
do {
    var f = Flow()
    check("没有在等的时候到的关键帧", f.keyframe(receivedAt: 0.5) == nil)
    _ = f.pick(B, active: A, now: 1)
    _ = f.pick(C, active: A, now: 1.1)
    _ = f.pick(B, active: A, now: 1.2)
    check("选回 B：发出之前的关键帧不算", f.wanted == Flow.Wanted(source: B, pickedAt: 1.2, sentAt: 1))
}

// 重选正在串流的源：直接发，不跟踪。
do {
    var f = Flow()
    check("重选当前源：发", f.pick(A, active: A, now: 0))
    check("不在路上，也不等画面", f.flight == nil && f.wanted == nil && f.deadline == nil)
    check("之后的选择照常", f.pick(B, active: A, now: 1) && f.flight?.source == B)
}

// 这次选择没成，或者被别处换掉。
do {
    var f = Flow()
    _ = f.pick(B, active: A, now: 0)
    let failed = f.listed(active: -1, exists: all, now: 0.5)
    check("Mac 什么都不串流了：这次没成，不再等", failed.send == nil && failed.done == nil && f.flight == nil && f.wanted == nil)

    var g = Flow()
    _ = g.pick(B, active: A, now: 0)
    _ = g.pick(C, active: A, now: 0.1)
    check("没成但有排队的：接着发", g.listed(active: -1, exists: all, now: 0.5).send == C && g.flight == Flow.Flight(source: C, from: -1, sentAt: 0.5))

    var h = Flow()
    _ = h.pick(B, active: A, now: 0)
    _ = h.pick(C, active: A, now: 0.1)
    check("B 的关键帧", h.keyframe(receivedAt: 0.2) == nil)
    let elsewhere = h.listed(active: C, exists: all, now: 0.5)
    check("Mac 已经在串流排着的 C：不用发", elsewhere.send == nil && h.flight == nil && h.queued == nil)
    check("C 当作上一次发出时就要了，之后的关键帧算数：完成", elsewhere.done == Flow.Done(source: C, total: 0.4, queued: 0, listAfterSend: 0.5, keyframeAfterSend: 0.2))

    var k = Flow()
    _ = k.pick(B, active: A, now: 0)
    _ = k.listed(active: B, exists: all, now: 0.4)
    check("等画面时 Mac 换成了别的源：不等了", k.listed(active: D, exists: all, now: 0.6).done == nil && k.wanted == nil)
}

// 没有画面可等的源（什么都不串流）：Mac 说到了就算到了。
do {
    var f = Flow()
    _ = f.pick(-1, active: A, now: 0)
    let listed = f.listed(active: -1, exists: all, hasPicture: { $0 != -1 }, now: 0.3)
    check("选了什么都不串流：列表到就完成，不等关键帧", listed.done == Flow.Done(source: -1, total: 0.3, queued: 0, listAfterSend: 0.3, keyframeAfterSend: 0.3)
          && f.wanted == nil)
    var g = Flow()
    _ = g.pick(B, active: A, now: 0)
    check("有画面的源照旧等关键帧", g.listed(active: B, exists: all, hasPicture: { $0 != -1 }, now: 0.3).done == nil && g.wanted != nil)
}

// 窗口关了。
do {
    var f = Flow()
    _ = f.pick(B, active: A, now: 0)
    _ = f.pick(C, active: A, now: 0.1)
    let gone = f.listed(active: B, exists: { $0 != C }, now: 0.5)
    check("排着的窗口已经不在：不发，也不等它", gone.send == nil && f.queued == nil && f.flight == nil && f.wanted == nil)

    var g = Flow()
    _ = g.pick(B, active: A, now: 0)
    _ = g.listed(active: A, exists: { $0 != B }, now: 0.2)
    check("要的窗口不在了：不占画面，路上那次等 Mac 的结果", g.wanted == nil && g.flight?.source == B)
}

// 到点。
do {
    var f = Flow()
    _ = f.pick(B, active: A, now: 0)
    check("没到 8 秒不动", f.expire(active: A, now: 7.999) == (nil, false) && f.flight != nil)
    let gave = f.expire(active: A, now: 8)
    check("8 秒没结果：放下", gave.send == nil && gave.gaveUp && f.flight == nil && f.wanted == nil && f.deadline == nil)

    var g = Flow()
    _ = g.pick(B, active: A, now: 0)
    _ = g.pick(C, active: A, now: 1)
    let next = g.expire(active: A, now: 8)
    check("8 秒没结果但有排队的：接着发", next.send == C && !next.gaveUp && g.flight == Flow.Flight(source: C, from: A, sentAt: 8)
          && g.wanted?.sentAt == 8 && g.queued == nil)

    var h = Flow()
    _ = h.pick(B, active: A, now: 0)
    _ = h.pick(A, active: A, now: 1)
    let same = h.expire(active: A, now: 8)
    check("排着的就是现在串流的：不发，放下", same.send == nil && same.gaveUp && h.flight == nil && h.wanted == nil && h.queued == nil)

    var k = Flow()
    _ = k.pick(B, active: A, now: 0)
    _ = k.listed(active: B, exists: all, now: 0.4)
    check("等画面没到 9 秒不动", k.expire(active: B, now: 8.999) == (nil, false) && k.wanted != nil)
    check("9 秒没画面：放下", k.expire(active: B, now: 9) == (nil, true) && k.wanted == nil)
    check("什么都不等时到点无事", k.expire(active: B, now: 100) == (nil, false))
}

// 排队的在等时没有期限以外的东西；重置。
do {
    var f = Flow()
    _ = f.pick(B, active: A, now: 2)
    _ = f.pick(C, active: A, now: 3)
    check("排队时期限仍是路上那次的", near(f.deadline, 10))
    _ = f.keyframe(receivedAt: 50)
    f.reset()
    check("重置后什么都没有", f.flight == nil && f.queued == nil && f.wanted == nil && f.deadline == nil)
    _ = f.pick(B, active: A, now: 4)
    _ = f.pick(C, active: A, now: 4.1)
    _ = f.pick(B, active: A, now: 4.2)
    check("重置前的关键帧不带过来", f.wanted?.keyframeAt == nil)
}

check("控制台的一行", Flow.Done(source: B, total: 0.5124, queued: 0.1, listAfterSend: 0.3986, keyframeAfterSend: 0.4124).line
      == "switch: 512 ms to the picture (queued 100 ms; after it was sent, the Mac's list 399 ms, the keyframe 412 ms)")

// 随机会话：一个和真 Mac 一样会丢选择的模型（正切到另一个源时到的选择丢掉；重启当前源时到的排队，最新的赢）。
struct Rng { var s: UInt64; mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s >> 33 }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) } }
enum Event { case userPick(Int), hostPick(Int), hostEnds, list(Int), keyframe, poll, expire }
func session(seed: UInt64, useFlow: Bool) -> (finalOK: Bool, drops: Int, idle: Bool, oneFlight: Bool, picks: Int) {
    var rng = Rng(s: seed)
    var events: [(t: Int, n: Int, e: Event)] = []     // 毫秒；n 保序
    var counter = 0
    func push(_ t: Int, _ e: Event) { counter += 1; events.append((t, counter, e)) }
    var t = 100
    let picks = 2 + rng.int(8)
    var lastPick = 0
    for _ in 0..<picks {
        t += [20, 80, 200, 500, 1500, 4000][rng.int(6)] + rng.int(50)
        lastPick = rng.int(5)
        push(t, .userPick(lastPick))
    }
    let quietUntil = t + 40_000
    var p = 0
    while p < quietUntil { push(p, .poll); p += 2000 }
    var hostActive = 0, hostTarget: Int? = nil, hostQueued: Int? = nil, drops = 0
    var deviceActive = 0
    var flow = Flow()
    var oneFlight = true
    func send(_ source: Int, at now: Int) { push(now + 3 + rng.int(5), .hostPick(source)) }
    func afterFlow(_ now: Int) {
        if let d = flow.deadline { push(max(now, Int((d * 1000).rounded(.up))) + 1, .expire) }
    }
    while !events.isEmpty {
        let i = events.indices.min { (events[$0].t, events[$0].n) < (events[$1].t, events[$1].n) }!
        let (now, _, event) = events.remove(at: i)
        let seconds = Double(now) / 1000
        switch event {
        case .userPick(let source):
            if useFlow {
                if flow.pick(source, active: deviceActive, now: seconds) { send(source, at: now) }
                afterFlow(now)
            } else { send(source, at: now) }
        case .hostPick(let source):
            if let target = hostTarget {
                if target == hostActive, source != target { hostQueued = source } else { drops += target == source ? 0 : 1 }
            } else {
                hostTarget = source
                push(now + 100 + rng.int(2900), .hostEnds)
            }
        case .hostEnds:
            hostActive = hostTarget!
            hostTarget = nil
            let lag = 3 + rng.int(5)
            push(now + lag, .list(hostActive))
            push(max(now - 10, now + lag - 12 + rng.int(40)), .keyframe)
            if let q = hostQueued { hostQueued = nil; if q != hostActive { hostTarget = q; push(now + 100 + rng.int(2900), .hostEnds) } }
        case .list(let active):
            deviceActive = active
            if useFlow {
                let r = flow.listed(active: active, exists: all, now: seconds)
                if let next = r.send { send(next, at: now) }
                afterFlow(now)
            }
        case .keyframe:
            if useFlow { _ = flow.keyframe(receivedAt: seconds); afterFlow(now) }
        case .poll:
            push(now + 3 + rng.int(5), .list(hostActive))
        case .expire:
            if useFlow {
                let r = flow.expire(active: deviceActive, now: seconds)
                if let next = r.send { send(next, at: now) }
                afterFlow(now)
            }
        }
        if flow.flight != nil, flow.queued != nil, flow.wanted?.source != flow.queued { oneFlight = false }
        if events.count > 5000 { break }
        // 期限事件只会越排越少：没有在等的就不再排。
        if case .expire = event, flow.deadline == nil { events.removeAll { if case .expire = $0.e { return true }; return false } }
    }
    return (hostActive == lastPick, drops, flow.flight == nil && flow.queued == nil && flow.wanted == nil, oneFlight, picks)
}
var withFlow = (wrong: 0, drops: 0, busy: 0, broken: 0), direct = (wrong: 0, drops: 0)
for seed in 1...3000 {
    let a = session(seed: UInt64(seed), useFlow: true)
    if !a.finalOK { withFlow.wrong += 1 }
    withFlow.drops += a.drops
    if !a.idle { withFlow.busy += 1 }
    if !a.oneFlight { withFlow.broken += 1 }
    let b = session(seed: UInt64(seed), useFlow: false)
    if !b.finalOK { direct.wrong += 1 }
    direct.drops += b.drops
}
print("随机 3,000 场：经 PickFlow 最后串流的不是最后选的 \(withFlow.wrong) 场、Mac 丢掉 \(withFlow.drops) 次；直接发 \(direct.wrong) 场、丢 \(direct.drops) 次")
check("随机 3,000 场：经 PickFlow，Mac 最后串流的就是最后选的", withFlow.wrong == 0)
check("随机 3,000 场：经 PickFlow，Mac 一次选择都不丢", withFlow.drops == 0)
check("随机 3,000 场：安静下来后什么都不等", withFlow.busy == 0)
check("随机 3,000 场：排着队时要的就是排着的那个", withFlow.broken == 0)
check("随机 3,000 场：不经 PickFlow 直接发会丢选择、停在错的源上（原问题）", direct.wrong > 300 && direct.drops > 300)

// LastWatched：每台 Mac 上最后看的源，和新连接上该不该选回它。
typealias LW = LastWatched
do {
    let chrome = LW.Window(id: 70, bundleID: "com.google.Chrome", appName: "Google Chrome")
    let list: [(id: UInt32, bundleID: String, appName: String)] = [
        (10, "com.apple.finder", "Finder"), (70, "com.google.Chrome", "Google Chrome"), (71, "com.google.Chrome", "Google Chrome"),
        (90, "", "Loose"), (91, "", "Other"),
    ]
    check("没有上次：照旧要桌面", LW.resume(nil, windows: list) == nil)
    check("上次看的是桌面：照旧要桌面", LW.resume(.desktop, windows: list) == nil)
    check("上次的窗口还在：选回它", LW.resume(.window(chrome), windows: list) == 70)
    check("它不在了，那个应用还有窗口：选那个应用在列表里的第一个", LW.resume(.window(LW.Window(id: 999, bundleID: "com.google.Chrome", appName: "Google Chrome")), windows: list) == 70
          && LW.resume(.window(LW.Window(id: 71, bundleID: "com.google.Chrome", appName: "Google Chrome")), windows: list.filter { $0.id != 71 }) == 70)
    check("第二个窗口还在：选的是它自己，不是应用的第一个", LW.resume(.window(LW.Window(id: 71, bundleID: "com.google.Chrome", appName: "Google Chrome")), windows: list) == 71)
    check("编号被别的应用的窗口占了（Mac 重启过）：不选它，按应用找", LW.resume(.window(LW.Window(id: 10, bundleID: "com.google.Chrome", appName: "Google Chrome")), windows: list) == 70)
    check("应用也不在了：照旧要桌面", LW.resume(.window(LW.Window(id: 5, bundleID: "com.example.gone", appName: "Gone")), windows: list) == nil
          && LW.resume(.window(chrome), windows: []) == nil)
    check("没有包名的应用按名字认", LW.resume(.window(LW.Window(id: 500, bundleID: "", appName: "Other")), windows: list) == 91
          && LW.resume(.window(LW.Window(id: 90, bundleID: "", appName: "Loose")), windows: list) == 90)
    check("没有包名时不会认成有包名的同名应用", LW.resume(.window(LW.Window(id: 500, bundleID: "", appName: "Finder")), windows: list) == nil)
    check("有包名时不看名字", LW.resume(.window(LW.Window(id: 500, bundleID: "com.apple.finder", appName: "访达")), windows: list) == 10)

    check("存盘的键", LW.key == "Sill.lastWatched" && LW.cap == 16)
    var all = LW.remember([:], mac: "Studio", source: .window(chrome))
    check("记下一台", all == ["Studio": .window(chrome)])
    all = LW.remember(all, mac: "Mini", source: .desktop)
    all = LW.remember(all, mac: "Studio", source: .desktop)
    check("各记各的，新的盖旧的", all == ["Studio": .desktop, "Mini": .desktop])
    check("没有名字的 Mac 不记", LW.remember(all, mac: "", source: .window(chrome)) == all)
    check("存了读回来一样", LW.decode(LW.encode(LW.remember(all, mac: "Air", source: .window(chrome)))) == ["Studio": .desktop, "Mini": .desktop, "Air": .window(chrome)])
    check("没存过、坏数据读成空", LW.decode(nil).isEmpty && LW.decode(Data([1, 2, 3])).isEmpty)
    var many: [String: LW.Source] = [:]
    for i in 0..<20 { many = LW.remember(many, mac: String(format: "Mac %02d", i), source: .desktop) }
    check("最多 16 台，最新记的那台一定在", many.count == 16 && many["Mac 19"] != nil && many["Mac 00"] == nil)
    check("只有一台超出也不丢它自己", LW.remember(many, mac: "Mac 00", source: .desktop)["Mac 00"] != nil)
}

print("\(passes) 项通过，\(fails) 项失败")
exit(fails == 0 ? 0 : 1)
