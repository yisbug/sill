import Foundation
import CoreGraphics

/// 横屏顶栏的折叠：只在本机记住开关与顶边图标的位置；导览显示时临时展开。
/// 位置规则独立于视图，可由纯检查单独编译。
enum BarCollapse {
    static let key = "Sill.barCollapsed"
    static let handleKey = "Sill.barHandle"
    static let defaultFraction = 1.0
    static let buttonWidth: CGFloat = 44
    static let handleSize = CGSize(width: 56, height: 26)
    static let touchHeight: CGFloat = 44
    static let margin: CGFloat = 12

    /// 存的开关开着、当前为横屏且导览没在显示，才收起顶栏。
    static func hidesBar(stored: Bool, landscape: Bool, tourShown: Bool) -> Bool {
        stored && landscape && !tourShown
    }

    /// 读回存的位置：非有限数用默认值，其余夹到 0…1。
    static func fraction(stored: Double) -> Double {
        guard stored.isFinite else { return defaultFraction }
        return min(max(stored, 0), 1)
    }

    /// 图标中心可用的范围；屏幕放不下时只有中点。
    private static func horizontalRange(width: CGFloat) -> ClosedRange<CGFloat> {
        let low = margin + handleSize.width / 2
        let high = width - margin - handleSize.width / 2
        return low <= high ? low...high : (width / 2)...(width / 2)
    }

    /// 按比例放在顶边；与书本姿态的折痕相交时，移到最近且放得下的一侧。
    /// 紧贴折痕边界不算相交；等距时优先左侧，两侧都放不下则保持原位。
    static func centerX(fraction: Double, width: CGFloat, fold: ClosedRange<CGFloat>? = nil) -> CGFloat {
        let range = horizontalRange(width: width)
        let x = range.lowerBound + CGFloat(Self.fraction(stored: fraction)) * (range.upperBound - range.lowerBound)
        let half = handleSize.width / 2
        guard let fold, x + half > fold.lowerBound, x - half < fold.upperBound else { return x }
        let left = fold.lowerBound - half
        let right = fold.upperBound + half
        let candidates = [left, right].filter { range.contains($0) }
        return candidates.min { abs($0 - x) < abs($1 - x) } ?? x
    }

    /// 拖动只夹住横向位置，不避折痕；松手后再由 centerX 落位。
    static func dragged(to x: CGFloat, width: CGFloat) -> CGFloat {
        let range = horizontalRange(width: width)
        return min(max(x, range.lowerBound), range.upperBound)
    }

    /// 松手中心换回 0…1 的比例；没有可移动范围时回到默认值。
    static func fraction(centerX: CGFloat, width: CGFloat) -> Double {
        let range = horizontalRange(width: width)
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return defaultFraction }
        return Self.fraction(stored: Double((centerX - range.lowerBound) / span))
    }

    /// 图标看得见的矩形，顶边贴着 top；供语音悬浮球避让。
    static func handleRect(centerX: CGFloat, top: CGFloat) -> CGRect {
        CGRect(x: centerX - handleSize.width / 2, y: top, width: handleSize.width, height: handleSize.height)
    }
}
