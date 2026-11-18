import Foundation

/// 流量统计（本 fork）：这台设备和 Mac 之间收发的数据量，按小时、按天、累计记下来，存在本机（`key`），不发给 Mac。
///
/// - 计的是 Sill 自己的数据：收到的每条消息（画面、声音、窗口列表…）与发出的每条消息（输入、心跳…）的字节数，
///   不含 TLS、TCP/IP 的包头，所以比系统「蜂窝网络」里给 Sill 记的略少（通常几个百分点）。
/// - 小时与天按设备当前的日历和时区切分（`Calendar.current`），小时留最近 8 天，天留最近 400 天；累计从开始统计起。
/// - 只用 Foundation，`Tests/checks/traffic-stats` 单独编译检查。
struct TrafficStats: Codable, Equatable {
    static let key = "Sill.trafficStats"
    /// 小时桶保留多久（秒）：近 7 天按小时看要用到 7 × 24 个，多留一天给跨日。
    static let keepHours: TimeInterval = 8 * 24 * 3600
    /// 天桶保留多少天。
    static let keepDays = 400

    struct Usage: Codable, Equatable {
        var received: Int64 = 0
        var sent: Int64 = 0
        var total: Int64 { received + sent }

        static func + (a: Usage, b: Usage) -> Usage { Usage(received: a.received + b.received, sent: a.sent + b.sent) }
    }

    /// 一个时间段（某小时、某天）和它的用量。
    struct Bucket: Equatable {
        let start: Date
        let usage: Usage
    }

    /// 键是这一小时（这一天）开始的时刻，自 1970 起的整秒。
    var hours: [Int64: Usage] = [:]
    var days: [Int64: Usage] = [:]
    var total = Usage()
    /// 开始统计的时刻（第一次记下数据，或清零时）。
    var since: Date?

    /// 记下一笔：`received`、`sent` 是字节数（负数当 0），记到 `date` 所在的小时和天，并去掉过期的桶。
    mutating func add(received: Int, sent: Int, at date: Date, calendar: Calendar) {
        let usage = Usage(received: Int64(max(0, received)), sent: Int64(max(0, sent)))
        guard usage.total > 0 else { return }
        if since == nil { since = date }
        let hour = Self.stamp(Self.hourStart(date, calendar))
        let day = Self.stamp(calendar.startOfDay(for: date))
        hours[hour, default: Usage()] = hours[hour, default: Usage()] + usage
        days[day, default: Usage()] = days[day, default: Usage()] + usage
        total = total + usage
        prune(now: date, calendar: calendar)
    }

    /// 去掉 `keepHours` 以前的小时桶和 `keepDays` 天以前的天桶；累计不动。
    mutating func prune(now: Date, calendar: Calendar) {
        let oldestHour = Self.stamp(Self.hourStart(now, calendar)) - Int64(Self.keepHours)
        hours = hours.filter { $0.key > oldestHour }
        let today = calendar.startOfDay(for: now)
        if let oldest = calendar.date(byAdding: .day, value: -(Self.keepDays - 1), to: today) {
            let cut = Self.stamp(oldest)
            days = days.filter { $0.key >= cut }
        }
    }

    /// 最近 `count` 个小时，含当前这一小时，从早到晚；没有数据的小时为 0。
    func lastHours(_ count: Int, now: Date, calendar: Calendar) -> [Bucket] {
        guard count > 0 else { return [] }
        let current = Self.hourStart(now, calendar)
        return (0..<count).reversed().compactMap { back in
            guard let start = calendar.date(byAdding: .hour, value: -back, to: current) else { return nil }
            return Bucket(start: start, usage: hours[Self.stamp(start)] ?? Usage())
        }
    }

    /// 最近 `count` 天，含今天，从早到晚；没有数据的天为 0。
    func lastDays(_ count: Int, now: Date, calendar: Calendar) -> [Bucket] {
        guard count > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { back in
            guard let start = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            return Bucket(start: start, usage: days[Self.stamp(start)] ?? Usage())
        }
    }

    /// 近 7 天（含今天）的合计。
    func lastSevenDays(now: Date, calendar: Calendar) -> Usage {
        lastDays(7, now: now, calendar: calendar).reduce(Usage()) { $0 + $1.usage }
    }

    /// 今天的合计。
    func today(now: Date, calendar: Calendar) -> Usage {
        days[Self.stamp(calendar.startOfDay(for: now))] ?? Usage()
    }

    static func hourStart(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.dateInterval(of: .hour, for: date)?.start ?? date
    }

    static func stamp(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970.rounded(.down)) }

    // MARK: 存取

    /// 读回存的 JSON；读不出来是空的。
    static func decode(_ data: Data?) -> TrafficStats {
        guard let data, let stats = try? JSONDecoder().decode(TrafficStats.self, from: data) else { return TrafficStats() }
        return stats
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }
}
