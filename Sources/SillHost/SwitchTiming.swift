import Foundation

/// 本 fork：一次切换（StreamCoordinator.select 换源或重启当前源）各段的耗时，写进日志，两行：
///
///     Switch to Google Chrome — Sill: 512 ms (old capture stopped 38 ms, source placed 301 ms, encoder and capture started 173 ms).
///     Switch: first frame out 548 ms after it began.
///
/// "source placed" 是停掉旧采集之后、建编码器之前的全部准备：旧窗口回原位、新窗口搬上虚拟显示器并等它稳定
/// （或者常规模式下把窗口提到前面、按设备的面板改尺寸），要新建虚拟显示器时也算在里面。重启当前源写
/// "Restart of"。只在流真的起来时写；从 select 开始算，不含这次选择在网络上和排队等主线程的时间。
/// 设备那一侧"从选到画面"的耗时在它的调试控制台里（iOSClient/PickFlow.swift）。
final class SwitchTiming: @unchecked Sendable {
    private let lock = NSLock()
    private let clock: () -> TimeInterval
    private let restart: Bool
    private let began: TimeInterval
    private var stoppedAt: TimeInterval?
    private var placedAt: TimeInterval?
    private var firstFrameSaid = false

    init(restart: Bool, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.restart = restart
        self.clock = clock
        began = clock()
    }

    /// 旧的采集停了、它的队列排空了。
    func stopped() { lock.lock(); stoppedAt = clock(); lock.unlock() }

    /// 新的源准备好了，接下来建编码器、启动采集。
    func placed() { lock.lock(); placedAt = clock(); lock.unlock() }

    /// 编码器和采集都起来了：日志的第一行。
    func started(_ describe: String) -> String {
        let now = clock()
        lock.lock()
        let stopped = stoppedAt ?? began, placed = placedAt ?? stoppedAt ?? began
        lock.unlock()
        return "\(restart ? "Restart of" : "Switch to") \(describe): \(Self.ms(now - began)) ms (old capture stopped \(Self.ms(stopped - began)) ms, "
            + "source placed \(Self.ms(placed - stopped)) ms, encoder and capture started \(Self.ms(now - placed)) ms)."
    }

    /// 新流的第一帧编码完、发给设备了：日志的第二行，一次切换只说一次。编码器的回调线程上调用。
    func firstFrame() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !firstFrameSaid else { return nil }
        firstFrameSaid = true
        return "\(restart ? "Restart" : "Switch"): first frame out \(Self.ms(clock() - began)) ms after it began."
    }

    private static func ms(_ seconds: TimeInterval) -> Int { Int((seconds * 1000).rounded()) }
}
