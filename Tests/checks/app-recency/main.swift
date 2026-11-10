// 应用栏的稳定分组、最近使用、当前应用置顶、完整窗口轮换及按 Mac 隔离的持久化。
import Foundation

typealias R = AppRecency
var passes = 0
var failures = 0
func check(_ name: String, _ valid: Bool) {
    if valid { passes += 1; print("ok   \(name)") }
    else { failures += 1; print("FAIL \(name)") }
}
let windows: [R.Window] = [
    .init(id: 11, bundleID: "a", appName: "Alpha"),
    .init(id: 21, bundleID: "b", appName: "Beta"),
    .init(id: 12, bundleID: "a", appName: "Alpha"),
    .init(id: 31, bundleID: "c", appName: "Gamma"),
    .init(id: 13, bundleID: "a", appName: "Alpha"),
    .init(id: 41, bundleID: "d", appName: "Delta")
]
func groups(_ record: R.Record = R.Record(), active: UInt32? = nil, list: [R.Window] = windows) -> [R.Group] {
    R.groups(windows: list, active: active, record: record)
}
func group(_ id: String, record: R.Record = R.Record(), active: UInt32? = nil) -> R.Group {
    groups(record, active: active).first { $0.id == id }!
}

check("没有窗口时没有应用", groups(list: []).isEmpty)
let initial = groups()
check("从未使用的应用按 Mac 首次报告顺序", initial.map(\.id) == ["a", "b", "c", "d"])
check("一个应用只显示一组", initial.count == 4)
check("分组保留应用名和 bundle ID", initial[0].appName == "Alpha" && initial[0].bundleID == "a")
check("同应用窗口保持 Mac 顺序", initial[0].windowIDs == [11, 12, 13])
check("未使用应用默认选择第一个窗口", initial[0].targetID == 11)
let used = R.Record(apps: ["b": 10, "c": 30], windows: [12: 10, 13: 20])
check("已用应用时间降序且未用应用在后", groups(used).map(\.id) == ["c", "b", "a", "d"])
check("当前应用置顶优先于时间", groups(used, active: 11).map(\.id) == ["a", "c", "b", "d"])
check("当前应用是分组里任意窗口", groups(used, active: 12).first?.id == "a")
check("已关闭的 active 不影响应用顺序", groups(used, active: 99).map(\.id) == ["c", "b", "a", "d"])
check("相同使用时间按 Mac 顺序", groups(.init(apps: ["b": 10, "c": 10])).map(\.id) == ["b", "c", "a", "d"])
check("零和负时间仍算使用过", groups(.init(apps: ["c": -1, "d": 0])).map(\.id) == ["d", "c", "a", "b"])
check("切到非当前应用的最近窗口", group("a", record: used, active: 21).targetID == 13)
check("窗口时间相同按 Mac 顺序", group("a", record: .init(windows: [12: 10, 13: 10])).targetID == 12)
check("当前应用选择其他窗口里最久未用的", group("a", record: used, active: 11).targetID == 12)
check("当前应用优先选择从未用过的窗口", group("a", record: used, active: 13).targetID == 11)
check("当前应用窗口时间相同按 Mac 顺序", group("a", record: .init(windows: [12: 10, 13: 10]), active: 11).targetID == 12)
check("其他窗口都未使用时按 Mac 顺序选择", group("a", active: 12).targetID == 11)
check("单窗口应用点按保持当前窗口", group("b", active: 21).targetID == 21)
var history = R.Record()
R.recordUse(window: windows[2], record: &history, at: 50)
check("一次使用同时记录应用和窗口", history.apps == ["a": 50] && history.windows == [12: 50])
R.recordUse(window: windows[2], record: &history, at: 80)
check("再次使用更新时间", history.apps["a"] == 80 && history.windows[12] == 80)
R.recordUse(window: windows[1], record: &history, at: 90)
check("使用其他应用保留原记录", history.apps == ["a": 80, "b": 90] && history.windows[12] == 80)
let finiteHistory = history
for invalid in [Double.nan, .infinity, -.infinity] { R.recordUse(window: windows[0], record: &history, at: invalid) }
check("非有限时间不破坏记录", history == finiteHistory)
var cursor: UInt32 = 11
var cycle: [UInt32] = []
var cycleHistory = R.Record()
for time in 1...6 {
    R.recordUse(window: windows.first { $0.id == cursor }!, record: &cycleHistory, at: Double(time))
    cursor = group("a", record: cycleHistory, active: cursor).targetID
    cycle.append(cursor)
}
check("更新使用记录后仍完整轮换三个窗口", cycle == [12, 13, 11, 12, 13, 11])
var frontToBack = windows
var dynamicHistory = R.Record()
var dynamicCycle: [UInt32] = []
cursor = 11
for time in 1...9 {
    let current = frontToBack.first { $0.id == cursor }!
    R.recordUse(window: current, record: &dynamicHistory, at: Double(time))
    frontToBack.removeAll { $0.id == cursor }
    frontToBack.insert(current, at: 0)
    let currentGroup = groups(dynamicHistory, active: cursor, list: frontToBack).first { $0.id == "a" }!
    cursor = currentGroup.targetID
    dynamicCycle.append(cursor)
}
check("Mac 每次把当前窗口移到最前后仍遍历三个窗口", dynamicCycle == [12, 13, 11, 12, 13, 11, 12, 13, 11])
let closed = windows.filter { $0.id != 13 && $0.id != 31 }
check("窗口关闭后从组里移除", groups(used, list: closed).first { $0.id == "a" }?.windowIDs == [11, 12])
check("关闭窗口的历史不会成为切换目标", groups(used, list: closed).first { $0.id == "a" }?.targetID == 12)
check("全部窗口关闭的应用移除", !groups(used, list: closed).contains { $0.id == "c" })
let unknown: [R.Window] = [.init(id: 1, bundleID: "", appName: "One"), .init(id: 2, bundleID: "", appName: "Two"), .init(id: 3, bundleID: "", appName: "One")]
check("没有 bundle ID 时按应用名分组", groups(list: unknown).map(\.windowIDs) == [[1, 3], [2]])
var unnamedHistory = R.Record()
R.recordUse(window: unknown[1], record: &unnamedHistory, at: 1)
check("没有 bundle ID 的应用也能记录并排序", groups(unnamedHistory, list: unknown).first?.appName == "Two")

let suite = "Sill.appRecency.check." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
check("存储键保持新前缀和 Mac 名", R.key(for: "Office Mac") == "Sill.appRecency.Office Mac")
check("未存储时为空", R.load(from: defaults, mac: "one") == R.Record())
R.save(used, to: defaults, mac: "one")
check("应用和窗口时间持久化读写往返", R.load(from: defaults, mac: "one") == used)
check("可被新的 UserDefaults 实例读取", R.load(from: UserDefaults(suiteName: suite)!, mac: "one") == used)
check("另一台 Mac 的记录隔离", R.load(from: defaults, mac: "two") == R.Record())
R.save(history, to: defaults, mac: "two")
check("两台 Mac 分别保存后互不覆盖", R.load(from: defaults, mac: "one") == used && R.load(from: defaults, mac: "two") == history)
R.save(R.Record(), to: defaults, mac: "one")
check("保存空记录覆盖旧记录", R.load(from: defaults, mac: "one") == R.Record())
defaults.set("bad", forKey: R.key(for: "bad"))
check("损坏存储回退为空", R.load(from: defaults, mac: "bad") == R.Record())
defaults.set(["apps": ["valid": 10.0, "nan": Double.nan], "windows": ["12": 20.0, "-1": 40.0, "oops": 1.0, "13": Double.infinity]], forKey: R.key(for: "partial"))
check("读取时保留有效项并丢弃无效项", R.load(from: defaults, mac: "partial") == R.Record(apps: ["valid": 10], windows: [12: 20]))
R.save(.init(apps: ["a": 2, "bad": .nan], windows: [UInt32.max: 4, 12: .infinity]), to: defaults, mac: "edge")
check("保存清理非有限时间且支持最大窗口 ID", R.load(from: defaults, mac: "edge") == R.Record(apps: ["a": 2], windows: [UInt32.max: 4]))
let encoded = try JSONEncoder().encode(used)
check("Record 的 Codable 往返", try JSONDecoder().decode(R.Record.self, from: encoded) == used)

print("\(passes) 项通过，\(failures) 项失败")
exit(failures == 0 ? 0 : 1)
