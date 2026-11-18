import Foundation

/// 本 fork：几台设备同时连着时，Mac 上的窗口按哪一台的面板来定尺寸。纯逻辑，`Tests/checks/viewport-owner` 单独检查。
///
/// 一路串流只有一个窗口尺寸。上游的做法是"谁最后发视口就按谁的"：每次换源，每台设备都会把自己的视口重发一遍
/// （StreamScreen 的 `onChange(of: client.active)`），于是 iPhone 和 iPad 同时连着时窗口尺寸在两者之间来回跳，
/// 每次切换之后还多重启一次串流（2026-11-18 的日志：每次 "Switch to" 后 50–100 ms 就跟一个 450–600 ms 的 "Restart of"）。
///
/// 这里的规则：每台设备的视口各记各的；窗口按"正在用的那一台"的来（`owner`）：最近一次有人操作的设备
/// （触摸、按键、手势、点窗口的按钮、选菜单项、打开应用、选了一个窗口；设备自己发的不算，见
/// StreamCoordinator 调 `used` 的地方）。别的设备发来视口只记下，不改窗口。正在用的那台走了，换成剩下的里面最近用过的。
/// 只有一台设备时和上游完全一样。
struct ViewportOwner<ID: Hashable, V: Equatable> {
    private var viewports: [ID: V] = [:]
    /// 用过的先后：最近的在最后。只含还连着的设备。
    private var recent: [ID] = []
    private(set) var owner: ID?

    /// 窗口按它来定尺寸的视口；还没有任何设备发过就是 nil。
    var chosen: V? { owner.flatMap { viewports[$0] } }

    /// `id` 发来了视口。true：选中的视口变了（要按新的改窗口）。还没有主人时，第一个发视口的就是。
    mutating func received(_ viewport: V, from id: ID) -> Bool {
        let before = chosen
        viewports[id] = viewport
        if owner == nil || owner.flatMap({ viewports[$0] }) == nil { owner = id }
        return chosen != before
    }

    /// 有人在 `id` 这台设备上操作了。true：选中的视口变了。它还没发过视口时主人不变（没有面板可按）。
    mutating func used(by id: ID) -> Bool {
        recent.removeAll { $0 == id }
        recent.append(id)
        guard owner != id, viewports[id] != nil else { return false }
        let before = chosen
        owner = id
        return chosen != before
    }

    /// `id` 断开了。true：选中的视口变了。主人走了就换成剩下的、发过视口的设备里最近用过的；都没用过就任取一个
    /// （按 `order` 给的顺序里的第一个，调用方给连接的先后，结果才确定）。
    mutating func left(_ id: ID, order: [ID] = []) -> Bool {
        let before = chosen
        viewports[id] = nil
        recent.removeAll { $0 == id }
        if owner == id {
            owner = recent.last { viewports[$0] != nil } ?? order.first { viewports[$0] != nil } ?? viewports.keys.first
        }
        return chosen != before
    }

    /// 没有设备了：下一台从头开始。
    mutating func reset() {
        viewports = [:]
        recent = []
        owner = nil
    }
}
