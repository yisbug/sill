import CoreGraphics
import Foundation
#if canImport(StreamProtocol)
import StreamProtocol
#endif

/// iPhone 上的串流界面（本 fork，docs/fork-changes.md F14）：强制横屏、和 iPad 一样的图标 Dock 栏、
/// 默认把文字大小（Aa）调到 0.75×，且这个值在设置面板里也能改。
///
/// 纯规则：只依赖 Foundation / CoreGraphics / StreamProtocol 的 `TextScale`，由 Tests/checks/phone-stream
/// 单独检查。「是不是 iPhone」由调用方传入（`DuoLayout.phoneArrangement`，含 DEBUG 的 `-SillIdiom`）。
enum PhoneStream {
    /// 串流界面显示时是否只允许横屏：只有 iPhone；连接界面等其他界面不受影响。
    static func locksLandscape(phone: Bool, streamShown: Bool) -> Bool { phone && streamShown }

    /// 这块屏幕是否画横屏布局（Dock 栏 + 画面）：iPhone 永远是（旋转未完成时屏幕还是竖的，也按横屏画，
    /// 免得布局先跳到竖屏再跳回来）；其他设备看尺寸，宽大于高才是。
    static func drawsLandscape(phone: Bool, size: CGSize) -> Bool { phone || size.width > size.height }

    /// 是否现在就把视口发给 Mac：iPhone 上屏幕还是竖的（旋转没完成）时不发，免得 Mac 先按竖屏尺寸改一次窗口；
    /// 旋转完成后面板尺寸变化会再触发一次。其他设备照旧发。
    static func sendsViewport(phone: Bool, screen: CGSize) -> Bool { !phone || screen.width > screen.height }

    // MARK: 灵动岛一侧留黑边

    /// 屏幕的左或右。
    enum Side: Equatable { case left, right }

    /// 横屏时灵动岛（刘海）在屏幕的哪一侧：界面方向是 landscapeRight（机身顶部朝左）时在左，landscapeLeft 时在右。
    /// 不是 iPhone，或者方向还不知道（刚出现、还竖着）时是 nil。
    static func islandSide(phone: Bool, landscapeRight: Bool?) -> Side? {
        guard phone, let landscapeRight else { return nil }
        return landscapeRight ? .left : .right
    }

    /// 串流画面和顶栏底色往哪一侧伸进安全区。iPhone：只伸进没有灵动岛的那一侧，灵动岛那一侧留黑边（画面不被它挡住）；
    /// 方向还不知道时两侧都不伸。其他设备两侧都伸（iPad 横屏两侧本来就没有安全区）。
    static func fills(phone: Bool, island: Side?) -> (left: Bool, right: Bool) {
        guard phone else { return (true, true) }
        switch island {
        case .left?: return (false, true)
        case .right?: return (true, false)
        case nil: return (false, false)
        }
    }

    // MARK: 文字大小的存储

    /// 缩放的持久化键（顶栏的 Aa 和设置面板的「Text Size」读写同一个值）。
    static let textScaleKey = "Sill.textScale"

    /// 没存过时的默认值：iPhone 0.75×，其他设备 nil（Off，和以前一样）。
    static func defaultTextScale(phone: Bool) -> Double? { phone ? 0.75 : nil }

    /// 从 UserDefaults 读出的原始值（nil、数字，或启动参数给的字符串）得到缩放：没存或不是有限数字 → 默认值；
    /// `TextScale.off` → nil（Off）；其他 → 贴到 `TextScale.scales` 最近的一档。
    static func textScale(stored: Any?, phone: Bool) -> Double? {
        let value: Double
        switch stored {
        case let number as NSNumber: value = number.doubleValue
        case let text as String:
            guard let parsed = Double(text.trimmingCharacters(in: .whitespaces)) else { return defaultTextScale(phone: phone) }
            value = parsed
        default: return defaultTextScale(phone: phone)
        }
        guard value.isFinite else { return defaultTextScale(phone: phone) }
        if value == TextScale.off { return nil }
        return TextScale.scales.min { abs($0 - value) < abs($1 - value) }
    }

    /// 要写进 UserDefaults 的值：nil（Off）写 `TextScale.off`，其他写缩放本身。
    static func stored(for scale: Double?) -> Double { scale ?? TextScale.off }

    // MARK: 设置行的文案

    /// 设置面板「Text Size」行的标题。
    static var textSizeTitle: String {
        String(localized: "Text Size", comment: "设置面板里文字大小一行的标题，和顶栏的 Aa 是同一项设置")
    }

    /// 这一行下面的脚注。
    static var textSizeFootnote: String {
        String(localized: "A smaller size shows more of the Mac’s window, with smaller text. It is the same setting as Aa in the toolbar.",
               comment: "设置面板里文字大小一行的脚注")
    }
}
