// TrafficStats（iOSClient，本 fork）：流量统计的记账规则。与 iOSClient/TrafficStats.swift 一起编译（run.sh）。
import Foundation

var passes = 0, fails = 0
func check(_ what: String, _ ok: Bool) {
    if ok { passes += 1; print("ok   \(what)") } else { fails += 1; print("FAIL \(what)") }
}
typealias T = TrafficStats

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Asia/Taipei")!
func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

check("存储键", T.key == "Sill.trafficStats")
check("小时保留 8 天、天保留 400 天", T.keepHours == 8 * 24 * 3600 && T.keepDays == 400)

var s = T()
check("空的：累计 0，没有开始时刻", s.total == T.Usage() && s.since == nil)
s.add(received: 1000, sent: 10, at: at(2026, 11, 18, 9, 15), calendar: cal)
s.add(received: 500, sent: 5, at: at(2026, 11, 18, 9, 59), calendar: cal)
s.add(received: 200, sent: 2, at: at(2026, 11, 18, 10, 0), calendar: cal)
check("累计收发分开相加", s.total == T.Usage(received: 1700, sent: 17) && s.total.total == 1717)
check("开始时刻是第一笔", s.since == at(2026, 11, 18, 9, 15))
check("同一小时合并，9 点一桶", s.hours[T.stamp(at(2026, 11, 18, 9))] == T.Usage(received: 1500, sent: 15))
check("整点进下一小时", s.hours[T.stamp(at(2026, 11, 18, 10))] == T.Usage(received: 200, sent: 2))
check("同一天合并", s.days[T.stamp(at(2026, 11, 18, 0))] == T.Usage(received: 1700, sent: 17))
check("今天", s.today(now: at(2026, 11, 18, 23, 59), calendar: cal).total == 1717)

// 跨日：按台北时间的午夜分天。
s.add(received: 7, sent: 0, at: at(2026, 11, 19, 0, 0), calendar: cal)
check("午夜进下一天", s.days[T.stamp(at(2026, 11, 19, 0))] == T.Usage(received: 7, sent: 0))
check("前一天不变", s.days[T.stamp(at(2026, 11, 18, 0))]?.total == 1717)

// 0 与负数不记，也不设开始时刻。
var z = T()
z.add(received: 0, sent: 0, at: at(2026, 1, 1, 1), calendar: cal)
z.add(received: -5, sent: -1, at: at(2026, 1, 1, 1), calendar: cal)
check("0 和负数不记", z == T())
z.add(received: -5, sent: 3, at: at(2026, 1, 1, 1), calendar: cal)
check("负的一边当 0", z.total == T.Usage(received: 0, sent: 3))
var z2 = T()
z2.add(received: 4, sent: -9, at: at(2026, 1, 1, 1), calendar: cal)
check("发出的负数当 0", z2.total == T.Usage(received: 4, sent: 0))

// 近 N 小时 / N 天：补零、从早到晚、含当前。
let hours = s.lastHours(24, now: at(2026, 11, 19, 0, 30), calendar: cal)
check("近 24 小时 24 个", hours.count == 24)
check("最后一个是当前小时", hours.last?.start == at(2026, 11, 19, 0))
check("第一个是 23 小时前", hours.first?.start == at(2026, 11, 18, 1))
check("从早到晚", zip(hours, hours.dropFirst()).allSatisfy { $0.start < $1.start })
check("有数据的小时取到，其余为 0", hours.first { $0.start == at(2026, 11, 18, 9) }?.usage.total == 1515
      && hours.first { $0.start == at(2026, 11, 18, 3) }?.usage == T.Usage())
let days = s.lastDays(7, now: at(2026, 11, 19, 12), calendar: cal)
check("近 7 天 7 个，最后是今天", days.count == 7 && days.last?.start == at(2026, 11, 19, 0) && days.first?.start == at(2026, 11, 13, 0))
check("近 7 天合计", s.lastSevenDays(now: at(2026, 11, 19, 12), calendar: cal).total == 1724)
check("8 天后近 7 天不含 18 日", s.lastSevenDays(now: at(2026, 11, 25, 12), calendar: cal).total == 7
      && s.lastSevenDays(now: at(2026, 11, 26, 12), calendar: cal).total == 0)
check("0 个就是空", s.lastHours(0, now: Date(), calendar: cal).isEmpty && s.lastDays(-3, now: Date(), calendar: cal).isEmpty)

// 清理：小时留 8 天，天留 400 天，累计不动。
var p = T()
p.add(received: 1, sent: 0, at: at(2026, 1, 1, 0), calendar: cal)
p.add(received: 1, sent: 0, at: at(2026, 1, 9, 0), calendar: cal)
check("8 天前的小时桶清掉，正好 8 天内的留下", p.hours[T.stamp(at(2026, 1, 1, 0))] == nil && p.hours.count == 1)
p.add(received: 1, sent: 0, at: at(2026, 1, 8, 23), calendar: cal)
check("不到 8 天的小时还在", p.hours[T.stamp(at(2026, 1, 8, 23))] != nil)
check("天桶还在", p.days[T.stamp(at(2026, 1, 1, 0))] != nil)
var q = T()
q.add(received: 1, sent: 0, at: at(2025, 1, 1, 12), calendar: cal)
q.add(received: 1, sent: 0, at: at(2026, 2, 4, 12), calendar: cal)   // 399 天后
check("399 天前的天桶留下", q.days[T.stamp(at(2025, 1, 1, 0))] != nil)
q.add(received: 1, sent: 0, at: at(2026, 2, 5, 12), calendar: cal)   // 400 天后
check("400 天前的天桶清掉", q.days[T.stamp(at(2025, 1, 1, 0))] == nil && q.days.count == 2)
check("清理不动累计", q.total.received == 3)

// 存取。
let back = T.decode(s.encoded())
check("编码再解码不变", back == s)
check("读不出来是空的", T.decode(nil) == T() && T.decode(Data("x".utf8)) == T())

// 随机：累计等于所有小时之和（不过期时），也等于所有天之和。
var gen = SystemRandomNumberGenerator()
var r = T(); var sum: Int64 = 0
let base = at(2026, 6, 1, 0)
for _ in 0..<5_000 {
    let d = base.addingTimeInterval(Double.random(in: 0..<(6 * 24 * 3600), using: &gen))
    let rx = Int.random(in: 0...100_000, using: &gen), tx = Int.random(in: 0...1_000, using: &gen)
    r.add(received: rx, sent: tx, at: d, calendar: cal); sum += Int64(rx + tx)
}
check("随机 5,000 笔：累计、小时和、天和相等", r.total.total == sum
      && r.hours.values.reduce(0) { $0 + $1.total } == sum && r.days.values.reduce(0) { $0 + $1.total } == sum)

print("\(passes + fails) checks, \(fails) failed")
exit(fails == 0 ? 0 : 1)
