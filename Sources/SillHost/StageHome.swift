import CoreGraphics
import Foundation

/// 本 fork：虚拟显示器上的窗口送回原位之后，确认它真的回到了原来的位置和大小。纯逻辑，`Tests/checks/stage-home` 单独检查；
/// VirtualStage 执行。
///
/// 起因（2026-11-18 的日志）：送回原位只写一次位置和大小、不回读（WindowSizer.restore）。Chrome、Tabbit 这类 Chromium
/// 窗口随后会把大小改回它在虚拟显示器上的那个（左下角不动，所以位置也跟着偏）：Tabbit 原位 (776,31,2395×997)，
/// 送回后停在 (776,276,1824×752)；而下次它再上虚拟显示器时，这个框又被当成新的"原位"记下，越切越偏。
/// Obsidian、iTerm 没有这个问题。
///
/// 两条规则：
/// - 送回之后在 `looks` 这几个时刻回读窗口的框（`verdict`）：在原位就好；又是舞台上的大小（`wearsStage`）就再写一次原位
///   （先大小后位置，Chromium 认这个顺序）；是别的大小或别的位置，是人在 Mac 上动了它，不再管。
/// - 窗口再次上虚拟显示器时（`home`）：它还带着上次舞台上的大小、而上次的原位不是这个大小，原位就用上次记下的那个，
///   不用它现在的框。
enum StageHome {
    /// 两个框算"一样"的误差（pt），和 WindowRestore 的一致。
    static let tolerance: CGFloat = 2
    /// 送回原位之后回读的时刻（秒）。Chromium 改回去发生在送回后的几百毫秒里；多看两次是为了改回去之后又改一次的。
    static let looks: [TimeInterval] = [0.15, 0.4, 0.9, 1.6, 2.5]

    /// 上次送回时记下的：原位，和它在舞台上的大小。
    struct Memory: Equatable {
        let home: CGRect
        let staged: CGSize
    }

    enum Verdict: Equatable {
        /// 在原位，大小也对。
        case home
        /// 又是舞台上的大小（应用把送回时写的大小改回去了）：再写一次原位。
        case wearsStage
        /// 别的大小，或者原来的大小但在别处：人动过，不再管。
        case elsewhere
    }

    static func same(_ a: CGSize, _ b: CGSize) -> Bool {
        abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    static func same(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
    }

    /// 送回之后窗口现在的框 `now`，对照原位 `home` 和它在舞台上的大小 `staged`。
    static func verdict(now: CGRect, home: CGRect, staged: CGSize) -> Verdict {
        if same(now.size, home.size) { return same(now.origin, home.origin) ? .home : .elsewhere }
        return same(now.size, staged) ? .wearsStage : .elsewhere
    }

    /// 回读可以提前结束：连续两次都在原位，而且已经过了 Chromium 改回去的那段时间（第三次回读起）。
    static func settled(homesInARow: Int, look: Int) -> Bool {
        homesInARow >= 2 && look >= 2
    }

    /// 窗口再次上虚拟显示器时该记的原位：`found` 是它现在的框。它还带着上次舞台上的大小（而上次的原位不是这个大小），
    /// 就用上次记下的原位；否则就是它现在的框（人在 Mac 上动过它，或者没有上次）。
    static func home(found: CGRect, remembered: Memory?) -> CGRect {
        guard let m = remembered, same(found.size, m.staged), !same(m.staged, m.home.size) else { return found }
        return m.home
    }
}
