// StageHome（Sources/SillHost/StageHome.swift，本 fork）单独检查。
//   swiftc -O Sources/SillHost/StageHome.swift Tests/checks/stage-home/main.swift -o .build/checks/stage-home/check && .build/checks/stage-home/check
import CoreGraphics
import Foundation

typealias H = StageHome
var passes = 0, fails = 0
func check(_ name: String, _ ok: Bool) {
    if ok { passes += 1; print("通过 \(name)") }
    else { fails += 1; print("FAIL \(name)") }
}
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }

check("误差 2 pt", H.tolerance == 2)
check("回读五次，时刻递增，最后一次不超过 3 秒", H.looks == [0.15, 0.4, 0.9, 1.6, 2.5] && H.looks == H.looks.sorted() && H.looks.last! <= 3)

// 日志里的数字：Tabbit 原位 (776,31,2395×997)，舞台上 1824×752，送回后停在 (776,276,1824×752)。
let tabbitHome = rect(776, 31, 2395, 997), tabbitStaged = CGSize(width: 1824, height: 752)
check("Tabbit 在原位", H.verdict(now: tabbitHome, home: tabbitHome, staged: tabbitStaged) == .home)
check("Tabbit 又变回舞台上的大小（左下角不动，位置偏了）", H.verdict(now: rect(776, 276, 1824, 752), home: tabbitHome, staged: tabbitStaged) == .wearsStage)
check("舞台上的大小、位置在原位：也是变回去了", H.verdict(now: rect(776, 31, 1824, 752), home: tabbitHome, staged: tabbitStaged) == .wearsStage)
// Chrome 原位 (1109,308,1520×720)，舞台上 1552×840，送回后 (1109,188,1552×840)。
let chromeHome = rect(1109, 308, 1520, 720), chromeStaged = CGSize(width: 1552, height: 840)
check("Chrome 又变回舞台上的大小", H.verdict(now: rect(1109, 188, 1552, 840), home: chromeHome, staged: chromeStaged) == .wearsStage)
check("Chrome 在原位", H.verdict(now: chromeHome, home: chromeHome, staged: chromeStaged) == .home)

// 误差的边。
check("原位差 2 pt 以内算在原位", H.verdict(now: rect(778, 29, 2397, 995), home: tabbitHome, staged: tabbitStaged) == .home)
check("大小差 3 pt 不算原位的大小", H.verdict(now: rect(776, 31, 2398, 997), home: tabbitHome, staged: tabbitStaged) == .elsewhere
      && H.verdict(now: rect(776, 31, 2395, 1000), home: tabbitHome, staged: tabbitStaged) == .elsewhere)
check("原来的大小但挪了 3 pt：人动过", H.verdict(now: rect(779, 31, 2395, 997), home: tabbitHome, staged: tabbitStaged) == .elsewhere
      && H.verdict(now: rect(776, 34, 2395, 997), home: tabbitHome, staged: tabbitStaged) == .elsewhere)
check("舞台大小差 2 pt 以内算舞台上的大小", H.verdict(now: rect(0, 0, 1826, 750), home: tabbitHome, staged: tabbitStaged) == .wearsStage)
check("舞台大小差 3 pt：别的大小，人动过", H.verdict(now: rect(776, 276, 1827, 752), home: tabbitHome, staged: tabbitStaged) == .elsewhere
      && H.verdict(now: rect(776, 276, 1824, 755), home: tabbitHome, staged: tabbitStaged) == .elsewhere)
check("别的大小：人动过", H.verdict(now: rect(100, 100, 1200, 800), home: tabbitHome, staged: tabbitStaged) == .elsewhere)
check("只有宽是舞台的：不算", H.verdict(now: rect(776, 276, 1824, 900), home: tabbitHome, staged: tabbitStaged) == .elsewhere)
check("只有高是舞台的：不算", H.verdict(now: rect(776, 276, 1700, 752), home: tabbitHome, staged: tabbitStaged) == .elsewhere)
// 原位的大小本来就等于舞台上的大小：看位置。
let sameSize = rect(300, 200, 1824, 752)
check("原位和舞台一样大：在原位", H.verdict(now: sameSize, home: sameSize, staged: tabbitStaged) == .home)
check("原位和舞台一样大、位置不对：人动过，不重写", H.verdict(now: rect(300, 400, 1824, 752), home: sameSize, staged: tabbitStaged) == .elsewhere)

// 相同的判断。
check("大小相同的边", H.same(CGSize(width: 10, height: 10), CGSize(width: 12, height: 8)) && !H.same(CGSize(width: 10, height: 10), CGSize(width: 12.5, height: 10))
      && !H.same(CGSize(width: 10, height: 10), CGSize(width: 10, height: 7.5)))
check("位置相同的边", H.same(CGPoint(x: 5, y: 5), CGPoint(x: 3, y: 7)) && !H.same(CGPoint(x: 5, y: 5), CGPoint(x: 7.5, y: 5))
      && !H.same(CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 2.5)))

// 提前结束。
check("一次在原位不够", !H.settled(homesInARow: 1, look: 4))
check("连续两次但还太早（第二次回读）不够", !H.settled(homesInARow: 2, look: 1))
check("连续两次、第三次回读起：结束", H.settled(homesInARow: 2, look: 2) && H.settled(homesInARow: 3, look: 4))
check("没有在原位过", !H.settled(homesInARow: 0, look: 4))

// 再次上舞台时的原位。
let memory = H.Memory(home: tabbitHome, staged: tabbitStaged)
check("没有上次：就是现在的框", H.home(found: rect(1, 2, 300, 400), remembered: nil) == rect(1, 2, 300, 400))
check("还带着舞台上的大小：用上次的原位", H.home(found: rect(776, 276, 1824, 752), remembered: memory) == tabbitHome)
check("带着舞台上的大小、在别处：也用上次的原位", H.home(found: rect(50, 60, 1825, 751), remembered: memory) == tabbitHome)
check("已经是原位：就是它", H.home(found: tabbitHome, remembered: memory) == tabbitHome)
check("人改成了别的大小：用现在的框", H.home(found: rect(700, 100, 1600, 900), remembered: memory) == rect(700, 100, 1600, 900))
check("人挪了位置、大小是原来的：用现在的框", H.home(found: rect(900, 31, 2395, 997), remembered: memory) == rect(900, 31, 2395, 997))
check("舞台大小差 3 pt：用现在的框", H.home(found: rect(776, 276, 1827, 752), remembered: memory) == rect(776, 276, 1827, 752))
let sameMemory = H.Memory(home: sameSize, staged: tabbitStaged)
check("上次的原位本来就是舞台那么大：用现在的框（人可能挪过）", H.home(found: rect(10, 20, 1824, 752), remembered: sameMemory) == rect(10, 20, 1824, 752))

// 一段完整的过程：送回后应用把大小改回去，回读发现、重写，直到稳定在原位。
do {
    // 应用在第 0.2 秒把大小改回舞台的；之后每次重写在 0.1 秒后生效。
    var frame = tabbitHome
    var revertAt: TimeInterval? = 0.2, rewriteLandsAt: TimeInterval? = nil
    var homes = 0, asked = 0, ended: Int? = nil
    for (i, at) in H.looks.enumerated() {
        if let r = revertAt, at >= r { frame = rect(776, 276, 1824, 752); revertAt = nil }
        if let l = rewriteLandsAt, at >= l { frame = tabbitHome; rewriteLandsAt = nil }
        switch H.verdict(now: frame, home: tabbitHome, staged: tabbitStaged) {
        case .home: homes += 1; if H.settled(homesInARow: homes, look: i) { ended = i }
        case .wearsStage: homes = 0; asked += 1; rewriteLandsAt = at + 0.1
        case .elsewhere: ended = -1
        }
        if ended != nil { break }
    }
    check("改回去一次：重写一次，之后连续两次在原位就结束", asked == 1 && ended == 3 && frame == tabbitHome)
}
do {
    // 一直在原位：不重写，第三次回读结束。
    var homes = 0, ended: Int? = nil
    for i in H.looks.indices {
        if H.verdict(now: tabbitHome, home: tabbitHome, staged: tabbitStaged) == .home { homes += 1 }
        if H.settled(homesInARow: homes, look: i) { ended = i; break }
    }
    check("一直在原位：第三次回读结束", ended == 2)
}

print("\(passes) 项通过，\(fails) 项失败")
exit(fails == 0 ? 0 : 1)
