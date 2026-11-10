import Foundation
import Network
import StreamProtocol

/// 语音输入的 Mac 端（docs/voice-and-immersive-plan.md 第 2.5 节）：发现本机的 meeppo-voice，把设备发来的
/// 片段（kind 100）转给它的 `/api/process`，把识别出的文字交给协调器当作这台设备打的字输入（`inject`，与
/// kind 8 的文字同一入口），再把结果（kind 101）回给这台设备。规则在 VoicePolicy。
///
/// - 发现：读数据目录下的 `local-api.json`，每 2 秒（有设备连着时）或 10 秒（没有时）看一次，可用与否变化时
///   通知协调器重发窗口列表（`WindowList.voice`）。
/// - 每台设备（每条连接）同一时间只处理一个片段，第二个回 `busy`；设备发 kind 102 或断开时取消请求。
/// - 请求只发往 127.0.0.1，不走系统代理，不带 Origin，90 秒超时。
/// - 日志每个片段一行，不写识别出的文字（VoicePolicy.logLine）。
///
/// 主线程（@MainActor）只做调度；网络请求在 URLSession 自己的队列上，回答回到主线程处理。
@MainActor
final class VoiceBridge {
    // 协调器在自己的 init 里接上（StreamCoordinator）。
    /// 数据目录，每次发现时读（配置可能变）。
    var directory: () -> String = { (NSHomeDirectory() as NSString).appendingPathComponent(VoicePolicy.defaultDataDirectory) }
    /// 发一条消息给一条连接。
    var send: (StreamMessage, NWConnection) -> Void = { _, _ in }
    /// 把文字当作这条连接的设备打的字输入，回落点。
    var inject: (String, NWConnection) async -> VoicePolicy.Landing = { _, _ in .nothingStreams }
    /// 设备的名字（日志用）。
    var deviceName: (NWConnection) -> String = { "\($0.endpoint)" }
    /// 可用与否变了（第二个参数：是否要重发窗口列表；发列表途中看的那次不重发）。
    var onAvailabilityChanged: ((Bool, Bool) -> Void)?

    /// 最近一次发现的结果。
    private(set) var available = false
    private var pollTask: Task<Void, Never>?
    /// 有设备连着时看得勤些（文件变化 5 秒内反映到窗口列表）。
    var devicesConnected = false

    /// 每条连接正在处理的片段。
    private struct InFlight {
        let clip: UInt32
        let task: URLSessionDataTask
        let bytes: Int
        let started: Double
        var cancelled = false
    }
    private var inFlight: [ObjectIdentifier: InFlight] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        // 只连本机回环：不走系统或用户配置的代理，不存 cookie 与缓存。
        config.connectionProxyDictionary = [:]
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = VoicePolicy.timeout
        config.timeoutIntervalForResource = VoicePolicy.timeout
        return URLSession(configuration: config)
    }()

    // MARK: 发现

    /// 开始定时看发现文件（先立刻看一次）。
    func start() {
        guard pollTask == nil else { return }
        refresh()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval: Double = (self?.devicesConnected ?? false) ? 2 : 10
                try? await Task.sleep(for: .seconds(interval))
                guard let self, !Task.isCancelled else { return }
                self.refresh()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// 现在读一次发现文件，更新 `available`；变化时打一行日志并通知。返回可用的服务。
    @discardableResult
    func refresh(broadcast: Bool = true) -> VoicePolicy.Service? {
        let path = (directory() as NSString).appendingPathComponent(VoicePolicy.discoveryFileName)
        let data = FileManager.default.contents(atPath: path)
        let found = VoicePolicy.discover(data) { pid in kill(pid, 0) == 0 || errno == EPERM }
        let service: VoicePolicy.Service?
        let unusable: VoicePolicy.Unusable?
        switch found {
        case .success(let s): service = s; unusable = nil
        case .failure(let why): service = nil; unusable = why
        }
        let now = service != nil
        // 只在可用与否变化时一行：从没找到过时不说话（CLI 的输出与没有语音时一样）。
        if now != available {
            if let service {
                print("Voice input: meeppo-voice found at 127.0.0.1:\(service.port) (process \(service.pid)).")
            } else if let unusable {
                print("Voice input: meeppo-voice no longer available (\(unusable.words)).")
            }
        }
        if now != available {
            available = now
            onAvailabilityChanged?(now, broadcast)
        }
        return service
    }

    // MARK: 片段

    /// kind 100：一个片段。
    func clip(_ payload: Data, from connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        let device = deviceName(connection)
        switch VoicePolicy.clip(payload) {
        case .malformed:
            print("Voice clip from \(device): \(payload.count) bytes, malformed (dropped)")
        case .refuse(let clip, let reason, let message):
            print(VoicePolicy.logLine(clip: clip, device: device, bytes: max(0, payload.count - VoiceClip.headerLength),
                                      seconds: nil, characters: nil, reason: reason.rawValue))
            reply(VoicePolicy.failed(clip: clip, reason, message: message), to: connection)
        case .audio(let clip, let audio):
            if inFlight[id] != nil {
                print(VoicePolicy.logLine(clip: clip, device: device, bytes: audio.count, seconds: nil, characters: nil,
                                          reason: VoiceReason.busy.rawValue))
                reply(VoicePolicy.failed(clip: clip, .busy), to: connection)
                return
            }
            guard let service = refresh(), let url = VoicePolicy.processURL(port: service.port) else {
                print(VoicePolicy.logLine(clip: clip, device: device, bytes: audio.count, seconds: nil, characters: nil,
                                          reason: VoiceReason.noService.rawValue))
                reply(VoicePolicy.failed(clip: clip, .noService), to: connection)
                return
            }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: VoicePolicy.timeout)
            request.httpMethod = "POST"
            request.setValue(service.token, forHTTPHeaderField: VoicePolicy.tokenHeader)
            request.setValue(VoicePolicy.contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = audio
            let started = ProcessInfo.processInfo.systemUptime
            let task = session.dataTask(with: request) { [weak self] data, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode
                let code = (error as? URLError)?.code.rawValue
                Task { @MainActor in
                    await self?.answered(clip: clip, connection: connection, status: status, body: data, errorCode: code,
                                         failed: error != nil)
                }
            }
            inFlight[id] = InFlight(clip: clip, task: task, bytes: audio.count, started: started)
            task.resume()
        }
    }

    /// kind 102：取消这条连接的这个片段（还在处理时）。取消的片段什么都不回。
    func cancel(_ payload: Data, from connection: NWConnection) {
        guard let cancel = Wire.decode(VoiceCancel.self, from: payload) else { return }
        let id = ObjectIdentifier(connection)
        guard var flight = inFlight[id], flight.clip == cancel.clip else { return }
        flight.cancelled = true
        inFlight[id] = flight
        flight.task.cancel()
    }

    /// 连接断开：取消它的请求。
    func clientLeft(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        guard var flight = inFlight[id] else { return }
        flight.cancelled = true
        inFlight[id] = flight
        flight.task.cancel()
    }

    private func answered(clip: UInt32, connection: NWConnection, status: Int?, body: Data?, errorCode: Int?, failed: Bool) async {
        let id = ObjectIdentifier(connection)
        guard let flight = inFlight[id], flight.clip == clip else { return }
        let device = deviceName(connection)
        let seconds = ProcessInfo.processInfo.systemUptime - flight.started
        if flight.cancelled {
            inFlight[id] = nil
            print(VoicePolicy.logLine(clip: clip, device: device, bytes: flight.bytes, seconds: seconds, characters: nil, reason: "cancelled"))
            return
        }
        let answer: VoicePolicy.Answer
        if failed || status == nil {
            let reason = VoicePolicy.failure(urlErrorCode: errorCode ?? NSURLErrorUnknown)
            answer = .failed(reason, message: VoicePolicy.message(reason))
        } else {
            answer = VoicePolicy.answer(status: status ?? 0, body: body ?? Data())
        }
        let result: VoiceResult
        var characters: Int?
        switch answer {
        case .failed(let reason, let message):
            result = VoicePolicy.failed(clip: clip, reason, message: message)
        case .text(let text):
            characters = text.count
            // 文字打进去之前这条连接仍算忙：打字途中再来的片段回 busy。
            let landing = await inject(text, connection)
            result = VoicePolicy.result(clip: clip, text: text, landing: landing)
        }
        inFlight[id] = nil
        print(VoicePolicy.logLine(clip: clip, device: device, bytes: flight.bytes, seconds: seconds, characters: characters,
                                  reason: result.reason))
        reply(result, to: connection)
    }

    private func reply(_ result: VoiceResult, to connection: NWConnection) {
        send(StreamMessage(kind: .voiceResult, timestamp: Date().timeIntervalSince1970, isKeyframe: false,
                           payload: Wire.encode(result)), connection)
    }
}
