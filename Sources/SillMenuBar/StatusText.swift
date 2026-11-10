import Foundation
import SillHostCore
import StreamProtocol

/// Everything the status item, its card and its menu say, as plain values. Made by
/// `StatusText.present` from the host's snapshot, so the same words appear in the menu, the
/// tooltip and the previews.
/// 日志通过独立英文文案路径生成，避免界面语言改变控制台输出。
struct StatusPresentation: Equatable {
    /// A line with a symbol: the stream's source, or one device.
    struct Row: Equatable, Identifiable {
        var id: String
        var symbol: String
        var title: String
        var detail: String?
    }

    /// Something that needs the user, shown in the menu with an orange warning.
    struct Attention: Equatable, Identifiable {
        enum Action: Equatable {
            case allowScreenRecording, allowAccessibility, showRemoteAccess, showDevices
            /// Settings › General, where the macOS firewall's line has the command that unblocks Sill.
            case showGeneral
            /// "‹device› Wants to Pair": its window forward while it shows the code (`showing`), else
            /// a window opened on the Mac, asked by that device (its paired-style name).
            case pairingRequest(name: String, showing: Bool)
            case none
        }
        var title: String
        var subtitle: String
        var action: Action
        var id: String { title }
    }

    var glyph: StatusGlyph.State
    var header: String
    var subtitle: String?
    var source: Row?
    var devices: [Row]
    var attention: [Attention]
    /// Under the menu's Virtual Display item.
    var virtualDisplayNote: String
    var tooltip: String
    var accessibilityLabel: String
    /// The name devices see this Mac as, once Bonjour has registered it.
    var advertisedName: String?
    /// Under the menu's Remote Access… item: "Off", "On · Tailscale"… Nil on a host without
    /// remote access (no item then).
    var remoteAccessNote: String?
    /// Pair iPhone or iPad… can open a pairing window (the Mac has an identity).
    var canPair = false
    /// Every connected device is away from home, so the away quality is the target: the menu's
    /// Quality subtitle says so (docs/remote-bundle-plan.md §5.7).
    var away = false
}

/// Whether Sill holds its two permissions, as last read.
struct PermissionState: Equatable {
    var screenRecording: Bool
    var accessibility: Bool
}

/// The status copy. Title case in menus, sentence case in explanations, typographic quotes.
enum StatusText {
    /// How long the menu says an iPhone or iPad needs Sill updated after the home door refused one
    /// of its plain connections (docs/home-pairing-plan.md §6.4).
    static let olderDeviceShownFor: TimeInterval = 600

    /// `now`: the clock the menu's items that last a while are judged by (fixed in the previews).
    static func present(snapshot s: HostStatusSnapshot, permissions: PermissionState,
                        startupError: String?, hasCoordinator: Bool, now: Date = Date()) -> StatusPresentation {
        let (header, subtitle) = headline(s, permissions, startupError, hasCoordinator)

        var attention: [StatusPresentation.Attention] = []
        if !permissions.screenRecording {
            attention.append(.init(title: String(localized: "Allow Screen Recording…", comment: "状态菜单权限提醒标题"), subtitle: String(localized: "Needed to show your windows on your devices.", comment: "状态菜单屏幕录制权限说明"),
                                   action: .allowScreenRecording))
        }
        if !permissions.accessibility {
            attention.append(.init(title: String(localized: "Allow Accessibility…", comment: "状态菜单辅助功能权限提醒标题"), subtitle: String(localized: "Devices can watch but not click or type.", comment: "状态菜单辅助功能权限说明"),
                                   action: .allowAccessibility))
        }
        // Kept to one line no wider than the rest of the menu: a menu item's subtitle does not wrap.
        if s.softwareEncoder, s.hardwareEncoderStuck {
            attention.append(.init(title: String(localized: "Hardware Encoder Stuck", comment: "状态菜单硬件编码器卡住提醒"),
                                   subtitle: String(localized: "Streaming with the software encoder, up to 60 fps. Restarting the Mac fixes this.", comment: "状态菜单编码器卡住说明"),
                                   action: .none))
        } else if s.softwareEncoder {
            attention.append(.init(title: String(localized: "Hardware Encoder Busy", comment: "状态菜单硬件编码器忙碌提醒"),
                                   subtitle: String(localized: "Streaming with the software encoder, up to 60 fps, until it is free again.", comment: "状态菜单编码器忙碌说明"),
                                   action: .none))
        }
        let remotePortTaken = remotePortInUse(s.remote)
        if let port = remotePortTaken {
            attention.append(.init(title: String(localized: "Remote Access Can’t Start", comment: "状态菜单远程访问提醒标题"), subtitle: String(localized: "Port \(String(port)) is in use by another app.", comment: "状态菜单端口冲突说明，插值为端口号"),
                                   action: .showRemoteAccess))
        }
        // Pairing at home (docs/home-pairing-plan.md §6.4).
        let request = pairingRequest(s.remote, now: now)
        if let request { attention.append(request) }
        if let at = s.remote?.olderDeviceAt, now.timeIntervalSince(at) < olderDeviceShownFor {
            attention.append(.init(title: String(localized: "An iPhone or iPad Needs Sill Updated", comment: "状态菜单旧版设备提醒标题"), subtitle: String(localized: "It tried to connect with an older Sill.", comment: "状态菜单旧版设备提醒说明"),
                                   action: .none))
        }
        let homeDoorClosed = homeDoorUnavailable(s.remote)
        if homeDoorClosed {
            attention.append(.init(title: String(localized: "Devices Can’t Connect", comment: "状态菜单设备连接提醒标题"), subtitle: String(localized: "Sill couldn’t use its key in your keychain.", comment: "状态菜单钥匙串异常说明"),
                                   action: .showDevices))
        }
        // The macOS firewall blocks Sill (FirewallRule): its line and command are in Settings › General.
        // Not beside the keychain's: with no home door there is nothing for the firewall to block.
        let firewallBlocks = !homeDoorClosed ? s.firewall.flatMap(FirewallRule.Copy.menuSubtitle) : nil
        if let firewallBlocks {
            attention.append(.init(title: String(localized: "Devices Can’t Connect", comment: "状态菜单设备连接提醒标题"), subtitle: firewallBlocks, action: .showGeneral))
        }

        // The attention glyph means "Sill needs you". The test pattern needs no permission. A device
        // waiting to pair, a closed home door and a firewall that blocks Sill need the user too; an
        // older device is only news.
        let glyph: StatusGlyph.State
        if startupError != nil || isFailed(s.network) || remotePortTaken != nil || request != nil || homeDoorClosed
            || firewallBlocks != nil
            || (!s.synthetic && !(permissions.screenRecording && permissions.accessibility)) {
            glyph = .attention
        } else if s.stream != nil {
            glyph = .streaming
        } else if !s.devices.isEmpty {
            glyph = .connected
        } else {
            glyph = .idle
        }

        var name: String?
        if case .advertising(let n) = s.network { name = n }

        return StatusPresentation(glyph: glyph, header: header, subtitle: subtitle,
                                  source: sourceRow(s), devices: s.devices.map(deviceRow), attention: attention,
                                  virtualDisplayNote: virtualDisplayNote(s),
                                  tooltip: String(localized: "Sill — \(header)", comment: "菜单栏工具提示，插值为当前状态"), accessibilityLabel: String(localized: "Sill, \(header)", comment: "菜单栏辅助功能标签，插值为当前状态"),
                                  advertisedName: name, remoteAccessNote: remoteAccessNote(s.remote),
                                  canPair: s.remote.map { $0.identityProblem == nil } ?? false, away: s.away)
    }

    /// "iPad Wants to Pair", for 5 minutes after a device's ask (the host ends it sooner: when the
    /// window showing its code closes, and when that device pairs): "A code is showing." while that
    /// window is up, "Click to show a code." when the ask limits kept one from opening, the unlock
    /// line when this Mac was locked. Sentences with a full stop, as every attention subtitle is.
    /// Never for an ask from this Mac itself (the host sets none).
    private static func pairingRequest(_ r: RemoteStatus?, now: Date) -> StatusPresentation.Attention? {
        guard let request = r?.pairingRequest, now.timeIntervalSince(request.at) < RemoteStatus.PairingRequest.shownFor else { return nil }
        let short = shortName(request.name)
        let subtitle: String
        switch request.reason {
        case "showing": subtitle = String(localized: "A code is showing.", comment: "配对请求提醒，验证码已显示")
        case "locked": subtitle = String(localized: "Unlock this Mac, then tap it on the \(short) again.", comment: "配对请求提醒，插值为设备简称")
        default: subtitle = String(localized: "Click to show a code.", comment: "配对请求提醒，提示显示验证码")
        }
        return .init(title: String(localized: "\(short) Wants to Pair", comment: "配对请求标题，插值为设备简称"), subtitle: subtitle,
                     action: .pairingRequest(name: request.name, showing: request.reason == "showing"))
    }

    /// The home door has no listener: the identity (its key, the trust list) could not be used.
    private static func homeDoorUnavailable(_ r: RemoteStatus?) -> Bool {
        if case .unavailable? = r?.homeDoor { return true }
        return false
    }

    /// The remote door's port while Remote Access is on and another app holds that port.
    private static func remotePortInUse(_ r: RemoteStatus?) -> Int? {
        guard let r, r.remoteAccess, r.identityProblem == nil, case .portInUse(let port) = r.listener else { return nil }
        return port
    }

    /// The Remote Access… item's subtitle: "Off", "On · Tailscale", "On · Tailscale and the
    /// internet", "On · no VPN on this Mac", "Port 7455 is in use" or "Unavailable: the keychain
    /// couldn’t be used".
    static func remoteAccessNote(_ r: RemoteStatus?) -> String? {
        guard let r else { return nil }
        if r.identityProblem != nil { return String(localized: "Unavailable: the keychain couldn’t be used", comment: "远程访问菜单副标题，钥匙串不可用") }
        guard r.remoteAccess else { return String(localized: "Off", comment: "远程访问菜单副标题，当前已关闭") }
        switch r.listener {
        case .portInUse(let port): return String(localized: "Port \(String(port)) is in use", comment: "远程访问菜单副标题，插值为端口号")
        case .failed: return String(localized: "Couldn’t start; trying again", comment: "远程访问菜单副标题，正在重试启动")
        case .off, .listening: break
        }
        var ways: [String] = []
        for a in r.addresses where a.kind == MacAddress.vpn && !ways.contains(a.via) { ways.append(a.via) }
        if r.internetAccess {
            guard !ways.isEmpty else { return String(localized: "On · the internet", comment: "远程访问菜单副标题，仅通过互联网") }
            let vpns = ways.joined(separator: ", ")
            return String(localized: "On · \(vpns) and the internet", comment: "远程访问菜单副标题，插值为 VPN 名称列表")
        }
        guard let last = ways.last else { return String(localized: "On · no VPN on this Mac", comment: "远程访问菜单副标题，此 Mac 没有 VPN") }
        if ways.count == 1 { return String(localized: "On · \(last)", comment: "远程访问菜单副标题，插值为 VPN 名称") }
        let first = ways.dropLast().joined(separator: ", ")
        return String(localized: "On · \(first) and \(last)", comment: "远程访问菜单副标题，插值为前面的 VPN 名称列表和最后一个名称")
    }

    /// 日志专用英文状态，匹配原有优先级与原文，不读取界面本地化结果。
    private static func logHeadline(_ s: HostStatusSnapshot, _ permissions: PermissionState, _ startupError: String?,
                                 _ hasCoordinator: Bool) -> (String, String?) {
        if let startupError { return ("Sill Couldn’t Start", startupError) }
        if !hasCoordinator { return ("Starting…", nil) }
        if homeDoorUnavailable(s.remote) {
            return ("Not Visible on the Network",
                    "Sill couldn’t use its key in your keychain. Quit Sill and open it again, and choose Always Allow if the keychain asks.")
        }
        switch s.network {
        case .starting:
            return ("Starting…", nil)
        case .failed(let error):
            return ("Not Visible on the Network", "\(error). Quit and reopen Sill to try again.")
        case .waiting:
            return ("Waiting for the Network",
                    "Sill appears on your iPhone and iPad once this Mac is on Wi-Fi or Ethernet and Local Network access is allowed.")
        case .notAdvertised(let port):
            return ("Test Pattern Mode", "Not advertised; test clients connect to port \(port).")
        case .registering, .advertising:
            break
        }
        if !permissions.screenRecording {
            return ("Screen Recording Is Off", "Devices can connect but can’t see any windows.")
        }
        let count = s.devices.count
        if count > 0 {
            let who = count == 1 ? (s.devices[0].name.map(shortName) ?? "a Device") : "\(count) Devices"
            if s.stream != nil { return ("Streaming to \(who)", nil) }
            let connected = count == 1 ? (s.devices[0].name.map(shortName) ?? "Device") : "\(count) Devices"
            return ("\(connected) Connected", "Pick a window on the device to start streaming.")
        }
        if case .advertising(let name) = s.network {
            return ("Waiting for a Device", "Open Sill on your iPhone or iPad. This Mac appears as “\(name)”.")
        }
        return ("Waiting for a Device", "Registering on the local network…")
    }

    static func logLine(snapshot: HostStatusSnapshot, permissions: PermissionState,
                        startupError: String?, hasCoordinator: Bool) -> String {
        let (header, subtitle) = logHeadline(snapshot, permissions, startupError, hasCoordinator)
        return subtitle.map { "\(header) — \($0)" } ?? header
    }

    /// The header and its explanation; the first match wins.
    private static func headline(_ s: HostStatusSnapshot, _ permissions: PermissionState, _ startupError: String?,
                                 _ hasCoordinator: Bool) -> (String, String?) {
        if let startupError { return (String(localized: "Sill Couldn’t Start", comment: "状态卡标题，启动失败"), startupError) }
        if !hasCoordinator { return (String(localized: "Starting…", comment: "状态卡标题，正在启动"), nil) }
        // No listener at all (fail closed): no device can find or reach this Mac.
        if homeDoorUnavailable(s.remote) {
            return (String(localized: "Not Visible on the Network", comment: "状态卡标题，网络不可见"),
                    String(localized: "Sill couldn’t use its key in your keychain. Quit Sill and open it again, and choose Always Allow if the keychain asks.", comment: "状态卡钥匙串异常说明"))
        }
        switch s.network {
        case .starting:
            return (String(localized: "Starting…", comment: "状态卡标题，正在启动"), nil)
        case .failed(let error):
            return (String(localized: "Not Visible on the Network", comment: "状态卡标题，网络不可见"), String(localized: "\(error). Quit and reopen Sill to try again.", comment: "状态卡网络失败说明，插值为错误信息"))
        case .waiting:
            return (String(localized: "Waiting for the Network", comment: "状态卡标题，等待网络"),
                    String(localized: "Sill appears on your iPhone and iPad once this Mac is on Wi-Fi or Ethernet and Local Network access is allowed.", comment: "状态卡等待网络说明"))
        case .notAdvertised(let port):
            return (String(localized: "Test Pattern Mode", comment: "状态卡标题，测试图案模式"), String(localized: "Not advertised; test clients connect to port \(String(port)).", comment: "状态卡测试图案说明，插值为端口号"))
        case .registering, .advertising:
            break
        }
        if !permissions.screenRecording {
            return (String(localized: "Screen Recording Is Off", comment: "状态卡标题，屏幕录制未授权"), String(localized: "Devices can connect but can’t see any windows.", comment: "状态卡屏幕录制权限说明"))
        }
        let count = s.devices.count
        if count > 0 {
            let header: String
            if s.stream != nil {
                if count == 1, let name = s.devices[0].name {
                    header = String(localized: "Streaming to \(shortName(name))", comment: "状态卡串流标题，插值为设备简称")
                } else if count == 1 {
                    header = String(localized: "Streaming to a Device", comment: "状态卡串流标题，设备名称未知")
                } else {
                    header = String(localized: "Streaming to \(count.formatted(.number.grouping(.never))) Devices", comment: "状态卡串流标题，插值为设备数量")
                }
                return (header, nil)
            }
            if count == 1, let name = s.devices[0].name {
                header = String(localized: "\(shortName(name)) Connected", comment: "状态卡连接标题，插值为设备简称")
            } else if count == 1 {
                header = String(localized: "Device Connected", comment: "状态卡连接标题，设备名称未知")
            } else {
                header = String(localized: "\(count.formatted(.number.grouping(.never))) Devices Connected", comment: "状态卡连接标题，插值为设备数量")
            }
            return (header, String(localized: "Pick a window on the device to start streaming.", comment: "状态卡已连接设备说明"))
        }
        if case .advertising(let name) = s.network {
            return (String(localized: "Waiting for a Device", comment: "状态卡标题，等待设备"), String(localized: "Open Sill on your iPhone or iPad. This Mac appears as “\(name)”.", comment: "状态卡等待设备说明，插值为此 Mac 的名称"))
        }
        return (String(localized: "Waiting for a Device", comment: "状态卡标题，等待设备"), String(localized: "Registering on the local network…", comment: "状态卡说明，正在注册本地网络"))
    }

    private static func isFailed(_ n: HostStatusSnapshot.Network) -> Bool {
        if case .failed = n { return true }
        return false
    }

    /// "iPad" from "iPad (iPad14,1)".
    static func shortName(_ device: String) -> String {
        let name = device.components(separatedBy: " (").first ?? device
        return name.isEmpty ? device : name
    }

    /// What streams: "Safari — Apple Developer" over "3024×1898 · 118 of 120 fps · 30 Mbps" (a still
    /// picture: "120 fps, still"), and with one device, how it is connected: "… · 30 Mbps · Wi-Fi".
    /// With two or more, each device's own row says it. "· sound" ends it while a device gets the
    /// Mac's sound.
    private static func sourceRow(_ s: HostStatusSnapshot) -> StatusPresentation.Row? {
        guard let stream = s.stream else { return nil }
        let title: String, symbol: String
        switch stream.kind {
        case .window: title = middleTruncated(stream.title, to: 44); symbol = "macwindow"
        case .desktop: title = String(localized: "Whole Desktop", comment: "状态卡串流来源名称，整个桌面"); symbol = "menubar.dock.rectangle"
        case .testPattern: title = String(localized: "Test Pattern", comment: "状态卡串流来源名称，测试图案"); symbol = "checkerboard.rectangle"
        }
        // The encoder only produces a frame when the picture changed (ScreenCaptureKit delivers
        // frames on repaint), so 0 means a still window, not a stalled stream. "120 fps, still" is
        // about as wide as a one-digit count ("5 of 120 fps"), so a row wraps the same still as
        // changing, unless the count's own digits tip it: the open menu resizes the card on every
        // change, and "nothing changing" with the route word made it jump a line each time a
        // window stopped or started changing.
        let rate = s.encodedFPS > 0 ? String(localized: "\((min(s.encodedFPS, stream.fps)).formatted(.number.grouping(.never))) of \((stream.fps).formatted(.number.grouping(.never))) fps", comment: "状态卡帧率，插值为当前帧率和上限") : String(localized: "\((stream.fps).formatted(.number.grouping(.never))) fps, still", comment: "状态卡静止画面帧率，插值为帧率上限")
        var details = [String(localized: "\(String(stream.width))×\(String(stream.height)) · \(rate) · \((stream.mbps).formatted(.number.grouping(.never))) Mbps", comment: "状态卡串流参数，插值为尺寸、帧率和码率")]
        if s.devices.count == 1, let route = routeWord(s.devices[0]) { details.append(route) }
        if stream.onVirtualDisplay {
            details.append(String(localized: "virtual display", comment: "状态卡串流参数中的虚拟显示器状态项目"))
        } else if s.virtualDisplayOn, stream.kind == .window {
            let problem = s.lastStageFailure ?? s.virtualDisplayProblem ?? String(localized: "unavailable", comment: "状态卡虚拟显示器不可用原因的回退显示")
            details.append(String(localized: "real window (virtual display: \(problem))", comment: "状态卡串流参数中的实体窗口状态项目，插值为虚拟显示器不可用原因"))
        }
        if stream.softwareEncoder { details.append(String(localized: "software encoder", comment: "状态卡串流参数中的软件编码器状态项目")) }
        // The Mac's sound goes out too, while a device gets it (docs/audio-plan.md, Q9).
        if s.audio?.devices ?? 0 > 0 { details.append(String(localized: "sound", comment: "状态卡串流参数中的声音状态项目")) }
        return StatusPresentation.Row(id: "source", symbol: symbol, title: title, detail: details.joined(separator: " · "))
    }

    /// "iPad (iPad14,1)" over "118 fps · frame age 9 ms · RTT 7 ms · Wi-Fi" (from away: "… · through
    /// Tailscale"); the address until the device's first report (within a second; a remote device
    /// shows its paired name), and until then the route alone. A second without a sample reads
    /// "–", as in the host's log line and the device's HUD: a still window sends no frames
    /// (ScreenCaptureKit delivers only repaints), and a second can pass without a pong. While its
    /// link does not keep up (docs/remote-bundle-plan.md §6.6) the numbers give way to it, the frame
    /// age dropping out to keep the row short: "3 fps, the link can’t carry Pro · RTT 531 ms ·
    /// through Tailscale", or "Nothing is getting through · through Tailscale".
    private static func deviceRow(_ d: HostStatusSnapshot.Device) -> StatusPresentation.Row {
        let name = d.name ?? d.endpoint
        let symbol = name.localizedCaseInsensitiveContains("iphone") ? "iphone" : "ipad"
        var parts: [String] = []
        if let link = d.link {
            parts.append(linkWords(link, fps: d.fps, rttMs: d.rttMs))
        } else if let fps = d.fps, let age = d.frameAgeMs, let rtt = d.rttMs {
            parts.append(String(localized: "\((fps).formatted(.number.grouping(.never))) fps · frame age \(ms(age)) · RTT \(ms(rtt))", comment: "状态卡设备统计，插值为帧率、画面延迟和往返延迟"))
        }
        if let route = routeWord(d) { parts.append(route) }
        return StatusPresentation.Row(id: String(describing: d.id), symbol: symbol, title: name,
                                      detail: parts.isEmpty ? nil : parts.joined(separator: " · "))
    }

    /// A device's link that does not keep up, as its row says it: behind, "3 fps, the link can’t carry
    /// Pro · RTT 531 ms" (the fps and the round trip when its stats have come); stalled, "Nothing is
    /// getting through".
    static func linkWords(_ link: HostStatusSnapshot.LinkStatus, fps: Int?, rttMs: Int?) -> String {
        switch link.state {
        case .stalled:
            return String(localized: "Nothing is getting through", comment: "状态卡连接停滞说明")
        case .behind:
            let quality = MacQualityText.name(forBitrate: link.bitrate).replacingOccurrences(of: " ", with: "\u{00A0}")
            if let fps, let rtt = rttMs {
                return String(localized: "\((fps).formatted(.number.grouping(.never))) fps, the link can’t carry \(quality) · RTT \(ms(rtt))", comment: "状态卡连接跟不上，插值为帧率、画质和往返延迟")
            }
            if let fps {
                return String(localized: "\((fps).formatted(.number.grouping(.never))) fps, the link can’t carry \(quality)", comment: "状态卡连接跟不上，插值为帧率和画质")
            }
            if let rtt = rttMs {
                return String(localized: "The link can’t carry \(quality) · RTT \(ms(rtt))", comment: "状态卡连接跟不上，插值为画质和往返延迟")
            }
            return String(localized: "The link can’t carry \(quality)", comment: "状态卡连接跟不上，插值为画质")
        }
    }

    /// How a device reaches this Mac, the one place the card decides it (the device's row, and the
    /// source row while it is the only device). A remote session says how it came ("through
    /// Tailscale", "over the internet"; RemoteServer's label), which always wins: its link from
    /// this Mac's side would read "Wi-Fi" for a session over the internet. A home device gets its
    /// link from this Mac's side of its connection (ClientLink.route), in the words the device's
    /// connect screen and Settings panel use; nil when neither says (loopback, an interface of no
    /// known kind). Either is kept whole when a detail wraps: a remote label's spaces are no-break
    /// ones (the source row wrapped "through" and "Tailscale" onto two lines), as Wi-Fi's hyphen is.
    private static func routeWord(_ d: HostStatusSnapshot.Device) -> String? {
        if let remote = d.remoteRoute { return MacRouteText.display(remote).replacingOccurrences(of: " ", with: "\u{00A0}") }
        return d.route.map(word)
    }

    /// A home device's link as the card words it. "Wi-Fi" has a non-breaking hyphen, so a wrapped
    /// detail never splits it.
    private static func word(_ route: ClientLink.Route) -> String {
        switch route {
        case .wired: return String(localized: "Wired", comment: "状态卡有线连接名称")
        case .wifi: return String(localized: "Wi\u{2011}Fi", comment: "状态卡无线连接名称")
        case .direct: return String(localized: "Direct", comment: "状态卡直连名称")
        }
    }

    /// One of a device's reported times. Negative is the client's "no sample this second" (-1),
    /// never a time.
    private static func ms(_ v: Int) -> String { v < 0 ? "–" : String(localized: "\((v).formatted(.number.grouping(.never))) ms", comment: "状态卡时间，插值为毫秒数") }

    private static func virtualDisplayNote(_ s: HostStatusSnapshot) -> String {
        if let problem = s.virtualDisplayProblem { return String(localized: "Unavailable: \(problem)", comment: "虚拟显示器菜单副标题，插值为不可用原因") }
        if s.virtualDisplayOn, s.stream?.onVirtualDisplay == true { return String(localized: "The streamed window is on the virtual display", comment: "虚拟显示器菜单副标题，窗口已移至虚拟显示器") }
        return String(localized: "Picked windows leave this screen while they stream", comment: "虚拟显示器菜单副标题，说明窗口移动行为")
    }

    /// "Safari — A very long window title that goes on" → "Safari — A very long…that goes on".
    static func middleTruncated(_ text: String, to limit: Int) -> String {
        guard text.count > limit, limit > 1 else { return text }
        let keep = limit - 1
        return String(text.prefix((keep + 1) / 2)) + "…" + String(text.suffix(keep / 2))
    }
}

enum MacQualityText {
    static func name(forBitrate bitrate: Int) -> String {
        switch QualityPreset(rawValue: bitrate) {
        case .low: return String(localized: "Low", comment: "Mac 画质预设名称")
        case .efficient: return String(localized: "Efficient", comment: "Mac 画质预设名称")
        case .balanced: return String(localized: "Balanced", comment: "Mac 画质预设名称")
        case .high: return String(localized: "High", comment: "Mac 画质预设名称")
        case .pro: return String(localized: "Pro", comment: "Mac 画质预设名称")
        case .ultra: return String(localized: "Ultra", comment: "Mac 画质预设名称")
        case .extreme: return String(localized: "Extreme", comment: "Mac 画质预设名称")
        case nil: return String(localized: "\(QualityPreset.localizedMbps(bitrate)) Mbps", comment: "Mac 自定义画质名称，插值为码率")
        }
    }

    static func title(forBitrate bitrate: Int) -> String {
        if QualityPreset(rawValue: bitrate) != nil {
            return String(localized: "\(name(forBitrate: bitrate)) — \((bitrate / 1_000_000).formatted(.number.grouping(.never))) Mbps", comment: "Mac 画质菜单标题，插值为预设名称和码率")
        }
        return String(localized: "Custom — \(QualityPreset.localizedMbps(bitrate)) Mbps", comment: "Mac 自定义画质菜单标题，插值为码率")
    }

    static func shortTitle(bitrate: Int, captureScale: Double) -> String {
        if captureScale >= 1.5 {
            return String(localized: "\(name(forBitrate: bitrate)) · Retina", comment: "Mac 画质及分辨率摘要，插值为画质名称")
        }
        return String(localized: "\(name(forBitrate: bitrate)) · Standard", comment: "Mac 画质及分辨率摘要，插值为画质名称")
    }

    static var fastLinkNote: String {
        QualityPreset.fastLinkNote
    }
}

enum MacRouteText {
    static func display(_ route: String) -> String {
        switch route {
        case "through your VPN": return String(localized: "through your VPN", comment: "Mac 设备连接路径，通过 VPN")
        case "over the internet": return String(localized: "over the internet", comment: "Mac 设备连接路径，通过互联网")
        case "by address": return String(localized: "by address", comment: "Mac 设备连接路径，通过地址连接")
        case "over the USB cable": return String(localized: "over the USB cable", comment: "Mac 设备连接路径，通过 USB 线缆")
        case "on this Mac": return String(localized: "on this Mac", comment: "Mac 设备连接路径，来自此 Mac")
        case "directly": return String(localized: "directly", comment: "Mac 设备连接路径，直接无线连接")
        case "over Wi\u{2011}Fi": return String(localized: "over Wi\u{2011}Fi", comment: "Mac 设备连接路径，通过 Wi-Fi")
        case "over Ethernet": return String(localized: "over Ethernet", comment: "Mac 设备连接路径，通过以太网")
        case "at home": return String(localized: "at home", comment: "Mac 设备连接路径，在本地网络")
        default:
            guard route.hasPrefix("through ") else { return route }
            let service = String(route.dropFirst("through ".count))
            return String(localized: "through \(service)", comment: "Mac 设备连接路径，插值为 VPN 服务名称")
        }
    }
}
