import SwiftUI

// 本分支不再支持 iPhone Duo：iOS 27.1 的折叠屏接口（onHingeChange、reservedRegions(.division)）
// 已去掉，以便用 Xcode 26 编译。真机上姿态恒为 unknown，各布局按普通 iPhone/iPad 处理；
// DuoPosture 的纯规则和调试用的 stand-in 保留，供布局检查与截图沿用。
//
// DEBUG: the harness's `-SillHinge closed|half|flat` stands in for all of it (ContentView's
// LayoutHarness): a hinge, and a fold given in the fake display's named space.

/// What the app's root knows of the hinge, for the screens below it.
struct DuoEnvironment: Equatable {
    var hinge: DuoPosture.Hinge = .unknown
    /// Where the fold comes from: iOS's reserved regions, or the harness's stand-in (in the fake
    /// display's space, `DuoPosture.displaySpace`; nil for none, as on the cover).
    var source: Source = .reservedRegions

    enum Source: Equatable {
        case reservedRegions
        case standIn(CGRect?)
    }
}

private struct DuoEnvironmentKey: EnvironmentKey {
    static let defaultValue = DuoEnvironment()
}

private struct DuoFoldKey: EnvironmentKey {
    static let defaultValue: FoldInfo = .inferred
}

extension EnvironmentValues {
    /// The hinge, from the app's root (`readsDuoPosture`) or the harness.
    var duoEnvironment: DuoEnvironment {
        get { self[DuoEnvironmentKey.self] }
        set { self[DuoEnvironmentKey.self] = newValue }
    }

    /// The fold across the stream screen, in its own space (StreamScreen sets it for its layouts and
    /// overlays, which share that space).
    var duoFold: FoldInfo {
        get { self[DuoFoldKey.self] }
        set { self[DuoFoldKey.self] = newValue }
    }
}

extension View {
    /// The app's root: the Duo's hinge into the environment. Nothing at all before iOS 27.1.
    func readsDuoPosture() -> some View { modifier(DuoPostureReader()) }

    /// The stream screen's status bar (DuoPosture.hidesStatusBar): hidden on the inner display in
    /// every pose, so the picture keeps the 82 pt above the fold upright and the 84 pt strip's
    /// width sideways; shown everywhere else, as before. In a background, so that hiding and
    /// showing it never rebuilds the screen's views; off the Duo it adds nothing.
    func duoStatusBar(_ posture: DuoPosture, size: CGSize) -> some View {
        background {
            if DuoPosture.hidesStatusBar(posture.pose(size)) {
                Color.clear.statusBarHidden(true)
            }
        }
    }

    /// The stream screen's fold for everything under it, and, in DEBUG, one console line each time
    /// the posture changes ("duo: stream screen: book, the fold x 455.5–495.5 in the way, 951×669").
    func duoFold(_ posture: DuoPosture, size: CGSize, screen: String) -> some View {
        modifier(DuoFoldSetter(fold: posture.info(in: size), line: posture.describe(size), screen: screen,
                               known: posture.hinge != .unknown))
    }

    /// The same console line for a screen that keeps its fold to itself (the connect screen).
    func duoLog(_ posture: DuoPosture, size: CGSize, screen: String) -> some View {
        modifier(DuoLogger(line: posture.describe(size), screen: screen, known: posture.hinge != .unknown))
    }
}

private struct DuoPostureReader: ViewModifier {
    func body(content: Content) -> some View {
        // 不再支持 iPhone Duo：iOS 27.1 的 onHingeChange 已去掉，铰链只来自调试用的 -SillHinge。
        content
    }
}

extension DuoPosture {
    /// The posture as the view `geo` measures sees it: the hinge from the environment (before its
    /// first report, from the fold: `hinge(reported:regionActive:)`), the fold in that view's own
    /// space (the reserved region's frame, as iOS 27.1 gives it to a GeometryProxy; or the harness's
    /// stand-in, moved into that space). `unknown` before iOS 27.1, on a device without a hinge, and
    /// in the harness without `-SillHinge`.
    static func read(_ geo: GeometryProxy, _ environment: DuoEnvironment) -> DuoPosture {
        switch environment.source {
        case .standIn(let fold):
            guard environment.hinge != .unknown else { return .unknown }
            let origin = geo.frame(in: .named(displaySpace)).origin
            return DuoPosture(hinge: environment.hinge, fold: fold?.offsetBy(dx: -origin.x, dy: -origin.y))
        case .reservedRegions:
            return .unknown
        }
    }
}

private struct DuoFoldSetter: ViewModifier {
    let fold: FoldInfo
    let line: String
    let screen: String
    let known: Bool

    func body(content: Content) -> some View {
        content
            .environment(\.duoFold, fold)
            .modifier(DuoLogger(line: line, screen: screen, known: known))
    }
}

private struct DuoLogger: ViewModifier {
    let line: String
    let screen: String
    let known: Bool

    func body(content: Content) -> some View {
        #if DEBUG
        content.onChange(of: line, initial: true) { _, now in
            if known { print("duo: \(screen): \(now)") }
        }
        #else
        content
        #endif
    }
}

// MARK: - What the layouts ask

extension BarMetrics {
    /// This bar in the book pose (DuoPosture.bookBar): the right group's buttons and gaps as they
    /// clear the fold, the strip's width so that it ends short of it (nil: as before), the Settings
    /// panel no wider than the room past it. Unchanged anywhere else.
    func clearing(_ fold: FoldInfo, width: CGFloat) -> (bar: BarMetrics, stripWidth: CGFloat?) {
        // Menus, Aa, Keyboard, Desktop and Settings: Menus counted whether or not it shows, so the
        // bar never moves when the Mac's menus come and go.
        let book = DuoPosture.bookBar(width: width, fold: fold, padding: padding, gap: gap, buttonWidth: buttonWidth,
                                      compactButtonWidth: BarMetrics.compact.buttonWidth, buttons: 5,
                                      panelWidth: settingsWidth)
        guard book.stripWidth != nil else { return (self, nil) }
        let bar = BarMetrics(height: height, padding: padding, gap: book.gap,
                             buttonWidth: book.buttonWidth, buttonHeight: buttonHeight, buttonSpacing: buttonSpacing,
                             thumbWidth: thumbWidth, thumbHeight: thumbHeight, thumbRadius: thumbRadius,
                             thumbSpacing: thumbSpacing, thumbPad: thumbPad, thumbFade: thumbFade,
                             showsTextSize: showsTextSize, settingsWidth: book.panelWidth)
        return (bar, book.stripWidth)
    }
}

extension PortraitMetrics {
    /// The halves' controls but the trackpad: the bar, the key row, their gaps and paddings.
    var controlsHeight: CGFloat { padTop + barHeight + 2 * rowGap + keyBlockHeight + padBottom }
}

extension StreamClient {
    /// The Duo open flat, upright: the picture pane's shape (DuoPosture.paneAspect). The Mac fits a
    /// window to the pane once Aa is set, or on the virtual display; never the Desktop.
    func duoPaneAspect(textScale: Double?) -> CGFloat {
        var window = false
        if case .window = active { window = true }
        let fitted = window && (textScale != nil || settings.host?.stream?.onVirtualDisplay == true)
        return DuoPosture.paneAspect(video: videoSize, fitsWindowToPane: fitted)
    }
}
