// ViewportOwner（Sources/SillHost/ViewportOwner.swift，本 fork）单独检查。
//   swiftc -O Sources/SillHost/ViewportOwner.swift Tests/checks/viewport-owner/main.swift -o .build/checks/viewport-owner/check && .build/checks/viewport-owner/check
import Foundation

typealias Owner = ViewportOwner<String, Int>
var passes = 0, fails = 0
func check(_ name: String, _ ok: Bool) {
    if ok { passes += 1; print("通过 \(name)") }
    else { fails += 1; print("FAIL \(name)") }
}
// 设备用名字，视口用一个数代表（手机 1824×752 记 100，平板 1408×922 记 200）。
let phone = "iPhone", pad = "iPad", third = "iPad mini"

// 只有一台设备：和上游一样，发什么就是什么。
do {
    var o = Owner()
    check("还没有设备：没有视口", o.chosen == nil && o.owner == nil)
    check("第一台发来视口：选中它，变了", o.received(100, from: phone) && o.chosen == 100 && o.owner == phone)
    check("原样重发：没变", !o.received(100, from: phone) && o.chosen == 100)
    check("它改了视口（收起顶栏、转屏）：跟着变", o.received(110, from: phone) && o.chosen == 110)
    check("它自己操作：没变", !o.used(by: phone) && o.chosen == 110)
    check("它走了：没有视口了，变了", o.left(phone) && o.chosen == nil && o.owner == nil)
}

// 两台设备：别的设备发来视口只记下；有人操作的那台成为主人。
do {
    var o = Owner()
    _ = o.received(100, from: phone)
    check("第二台发来视口：只记下，窗口不动", !o.received(200, from: pad) && o.chosen == 100 && o.owner == phone)
    check("第二台重发（每次换源它都会重发）：还是不动", !o.received(200, from: pad) && o.chosen == 100)
    check("第二台改了自己的视口：还是不动", !o.received(210, from: pad) && o.chosen == 100)
    check("主人重发、改视口照常生效", !o.received(100, from: phone) && o.received(120, from: phone) && o.chosen == 120)
    check("有人在第二台上操作：窗口改按它的，变了", o.used(by: pad) && o.chosen == 210 && o.owner == pad)
    check("接着操作：不再变", !o.used(by: pad) && o.chosen == 210)
    check("这时手机重发视口：只记下", !o.received(120, from: phone) && o.chosen == 210)
    check("回到手机上操作：改回手机的", o.used(by: phone) && o.chosen == 120 && o.owner == phone)
}

// 两台的视口正好一样：换主人，但选中的没变（不用改窗口）。
do {
    var o = Owner()
    _ = o.received(100, from: phone)
    _ = o.received(100, from: pad)
    check("视口一样时换主人不算变", !o.used(by: pad) && o.owner == pad && o.chosen == 100)
}

// 还没发过视口的设备上有人操作：主人不变；等它发来视口，再操作才换。
do {
    var o = Owner()
    _ = o.received(100, from: phone)
    check("没发过视口的设备操作：不换", !o.used(by: pad) && o.owner == phone && o.chosen == 100)
    check("它发来视口：只记下（主人还在）", !o.received(200, from: pad) && o.chosen == 100)
    check("它再操作：换成它", o.used(by: pad) && o.chosen == 200)
}

// 没有主人时第一个发视口的就是主人，哪怕别的设备先操作过。
do {
    var o = Owner()
    _ = o.used(by: pad)
    check("先操作、没视口：没有主人", o.owner == nil && o.chosen == nil)
    check("手机先发视口：手机是主人", o.received(100, from: phone) && o.owner == phone)
}

// 主人走了：换成剩下的里面最近用过的；没用过的按给的顺序；别的设备走了不影响。
do {
    var o = Owner()
    _ = o.received(100, from: phone)
    _ = o.received(200, from: pad)
    _ = o.received(300, from: third)
    _ = o.used(by: third)
    _ = o.used(by: pad)
    _ = o.used(by: phone)
    check("三台都用过，现在是手机", o.owner == phone && o.chosen == 100)
    check("不是主人的走了：不变", !o.left(third) && o.chosen == 100 && o.owner == phone)
    check("主人走了：换成最近用过的平板", o.left(phone) && o.owner == pad && o.chosen == 200)
    check("最后一台也走了", o.left(pad) && o.chosen == nil && o.owner == nil)

    var p = Owner()
    _ = p.received(100, from: phone)
    _ = p.received(200, from: pad)
    _ = p.received(300, from: third)
    _ = p.used(by: pad)
    _ = p.used(by: third)
    _ = p.used(by: phone)
    check("最近用过的是第三台，不看给的顺序", p.left(phone, order: [pad, third]) && p.owner == third && p.chosen == 300)

    var q = Owner()
    _ = q.received(100, from: phone)
    _ = q.received(200, from: pad)
    _ = q.received(300, from: third)
    check("都没用过：按给的顺序里第一个发过视口的", q.left(phone, order: [phone, third, pad]) && q.owner == third && q.chosen == 300)

    var r = Owner()
    _ = r.received(100, from: phone)
    _ = r.used(by: pad)                      // 用过，但没发过视口
    _ = r.received(300, from: third)
    check("最近用过的那台没有视口：跳过它", r.left(phone, order: [pad, third]) && r.owner == third && r.chosen == 300)

    var s = Owner()
    _ = s.received(100, from: phone)
    _ = s.received(200, from: pad)
    _ = s.used(by: pad)
    _ = s.left(pad)
    check("走掉的设备不留在最近用过的名单里", s.owner == phone)
    _ = s.received(300, from: third)
    _ = s.used(by: third)
    check("之后主人再走，不会回到已经走掉的那台", s.left(third) && s.owner == phone && s.chosen == 100)

    // 走掉的设备又连上来（连接的标识可能被复用）：之前用过不算数。
    var t = Owner()
    _ = t.received(100, from: phone)
    _ = t.received(200, from: pad)
    _ = t.used(by: pad)
    _ = t.left(pad)
    _ = t.received(200, from: pad)
    _ = t.received(300, from: third)
    _ = t.used(by: third)
    check("重新连上的设备不算最近用过", t.left(third, order: [phone, pad]) && t.owner == phone && t.chosen == 100)

    // 主人不是最近用过的那台（它没操作过，别的设备操作时还没有视口）：别的设备走了，主人不动。
    var u = Owner()
    _ = u.received(100, from: phone)
    _ = u.used(by: pad)
    _ = u.received(200, from: pad)
    _ = u.received(300, from: third)
    check("不是主人的走了：主人不动，哪怕有别的设备更近用过", !u.left(third) && u.owner == phone && u.chosen == 100)
}

// 重置。
do {
    var o = Owner()
    _ = o.received(100, from: phone)
    _ = o.received(200, from: pad)
    _ = o.used(by: pad)
    o.reset()
    check("重置后什么都没有", o.chosen == nil && o.owner == nil)
    check("重置后第一台重新成为主人", o.received(100, from: phone) && o.owner == phone)
    _ = o.received(300, from: third)
    check("重置前的视口不留着", o.left(phone, order: [pad, third]) && o.owner == third && o.chosen == 300)

    var v = Owner()
    _ = v.received(100, from: phone)
    _ = v.received(200, from: pad)
    _ = v.used(by: pad)
    v.reset()
    _ = v.received(100, from: phone)
    _ = v.received(300, from: third)
    _ = v.received(200, from: pad)
    check("重置前用过的不算数", v.left(phone, order: [third, pad]) && v.owner == third && v.chosen == 300)
}

// 随机会话：两三台设备，每次"换源"后每台都把自己的视口重发一遍（真设备就是这样）。窗口尺寸（选中的视口）
// 只允许在三种时刻变：有人换了一台设备操作、主人改了自己的视口、主人走了。对照：上游的"谁最后发就按谁的"。
struct Rng { var s: UInt64; mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s >> 33 }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) } }
var strayChanges = 0, lastSenderChanges = 0, wrongOwner = 0, sessions = 0
for seed in 1...2000 {
    var rng = Rng(s: UInt64(seed))
    let devices = [phone, pad, third].prefix(2 + rng.int(2))
    var own: [String: Int] = [:]
    for (i, d) in devices.enumerated() { own[d] = 100 * (i + 1) }
    var o = Owner()
    var upstream: Int? = nil                 // 上游：最后收到的视口
    for d in devices { _ = o.received(own[d]!, from: d); upstream = own[d] }
    var inUse: String? = nil                 // 最近有人操作的设备
    sessions += 1
    for _ in 0..<60 {
        switch rng.int(4) {
        case 0:                              // 换源：每台设备重发视口，顺序随机
            var order = Array(devices)
            for i in stride(from: order.count - 1, to: 0, by: -1) { order.swapAt(i, rng.int(i + 1)) }
            for d in order {
                let before = o.chosen
                _ = o.received(own[d]!, from: d)
                if o.chosen != before { strayChanges += 1 }
                if upstream != own[d] { lastSenderChanges += 1 }
                upstream = own[d]
            }
        case 1:                              // 有人在某台设备上操作
            let d = devices[rng.int(devices.count)]
            _ = o.used(by: d)
            inUse = d
        case 2:                              // 某台设备改了自己的视口（收起顶栏）
            let d = devices[rng.int(devices.count)]
            own[d]! += 1
            let before = o.chosen
            _ = o.received(own[d]!, from: d)
            if o.chosen != before, o.owner != d { strayChanges += 1 }
            upstream = own[d]
        default: break
        }
        if let inUse, o.owner != inUse || o.chosen != own[inUse] { wrongOwner += 1 }
    }
}
print("随机 \(sessions) 场：重发视口引起的窗口变化 \(strayChanges) 次（上游的规则 \(lastSenderChanges) 次），主人不是正在用的那台 \(wrongOwner) 次")
check("随机 2,000 场：别的设备重发或改视口从不改窗口", strayChanges == 0)
check("随机 2,000 场：窗口总是按最近有人操作的那台", wrongOwner == 0)
check("随机 2,000 场：上游的规则在同样的会话里来回改窗口（原问题）", lastSenderChanges > 5000)

print("\(passes) 项通过，\(fails) 项失败")
exit(fails == 0 ? 0 : 1)
