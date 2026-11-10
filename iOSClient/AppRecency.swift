import Foundation

/// 横屏应用栏的分组、最近使用排序和切换目标；不依赖 UI 或串流协议。
enum AppRecency {
    struct Window: Equatable {
        let id: UInt32
        let bundleID: String
        let appName: String

        /// 无 bundle ID 的应用按名字分组，避免所有未知应用合成一组。
        var appID: String { bundleID.isEmpty ? "name:" + appName : bundleID }
    }

    struct Record: Codable, Equatable {
        var apps: [String: Double] = [:]
        var windows: [UInt32: Double] = [:]
    }

    struct Group: Identifiable, Equatable {
        let id: String
        let bundleID: String
        let appName: String
        /// 窗口列表保持 Mac 的报告顺序；切换目标单独按使用时间决定。
        let windowIDs: [UInt32]
        let targetID: UInt32
    }

    static func groups(windows: [Window], active: UInt32?, record: Record) -> [Group] {
        var appOrder: [String] = []
        var grouped: [String: [Window]] = [:]
        for window in windows {
            if grouped[window.appID] == nil { appOrder.append(window.appID) }
            grouped[window.appID, default: []].append(window)
        }
        let activeApp = windows.first { $0.id == active }?.appID
        let ranked = appOrder.enumerated().sorted { left, right in
            if left.element == activeApp { return right.element != activeApp }
            if right.element == activeApp { return false }
            let lhs = record.apps[left.element] ?? -.infinity
            let rhs = record.apps[right.element] ?? -.infinity
            return lhs == rhs ? left.offset < right.offset : lhs > rhs
        }
        return ranked.compactMap { entry in
            guard let members = grouped[entry.element], let first = members.first else { return nil }
            let ids = members.map(\.id)
            let target: UInt32
            if let active, ids.contains(active) {
                // Mac 会把新激活的窗口移到列表最前，不能按该列表的相邻位置轮换。
                // 排除当前窗口后先选从未使用的，再选最久未用的，才能遍历所有窗口。
                target = members.filter { $0.id != active }.enumerated().sorted { left, right in
                    let lhs = record.windows[left.element.id] ?? -.infinity
                    let rhs = record.windows[right.element.id] ?? -.infinity
                    return lhs == rhs ? left.offset < right.offset : lhs < rhs
                }.first?.element.id ?? active
            } else {
                target = members.enumerated().sorted { left, right in
                    let lhs = record.windows[left.element.id] ?? -.infinity
                    let rhs = record.windows[right.element.id] ?? -.infinity
                    return lhs == rhs ? left.offset < right.offset : lhs > rhs
                }.first!.element.id
            }
            return Group(id: entry.element, bundleID: first.bundleID, appName: first.appName,
                         windowIDs: ids, targetID: target)
        }
    }

    /// 点按、抽屉选源和 Mac 发来的 active 更新共用这一条记录路径。
    static func recordUse(window: Window, record: inout Record, at time: Double) {
        guard time.isFinite else { return }
        record.apps[window.appID] = time
        record.windows[window.id] = time
    }

    static func key(for mac: String) -> String { "Sill.appRecency." + mac }

    /// UserDefaults 原生字典避免编码异常；无效或旧格式记录视为从未使用。
    static func load(from defaults: UserDefaults, mac: String) -> Record {
        guard let stored = defaults.dictionary(forKey: key(for: mac)) else { return Record() }
        let apps = (stored["apps"] as? [String: Double] ?? [:]).filter { $0.value.isFinite }
        let windows = (stored["windows"] as? [String: Double] ?? [:]).reduce(into: [UInt32: Double]()) { result, item in
            if let id = UInt32(item.key), item.value.isFinite { result[id] = item.value }
        }
        return Record(apps: apps, windows: windows)
    }

    static func save(_ record: Record, to defaults: UserDefaults, mac: String) {
        let apps = record.apps.filter { $0.value.isFinite }
        let windows = Dictionary(uniqueKeysWithValues: record.windows.filter { $0.value.isFinite }.map { (String($0.key), $0.value) })
        defaults.set(["apps": apps, "windows": windows], forKey: key(for: mac))
    }
}
