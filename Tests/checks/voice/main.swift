// 语音输入的纯规则（docs/voice-and-immersive-plan.md 第 2 节）：Mac 端的 VoicePolicy（Sources/SillHost）与设备端的
// VoiceInputPolicy（iOSClient），连同 StreamProtocol 的 Voice.swift，作为一个模块编译（../module.py）。
//   - 协议：kind 100–102 的编号，片段的编码与解析，结果与取消的 JSON，`WindowList.voice` 只增不改（nil 时不写）。
//   - 发现：数据目录（测试钩子、配置、默认、~ 展开），发现文件的每种坏法，pid 是否活着。
//   - 片段：4 MiB 上限的两侧，格式，空音频，读不出片段号；主机读的上限。
//   - 回答：polishedText 优先、空则 recognizedText、都空失败，非 200 用 error 字段，读不懂；URLError 的映射。
//   - 结果：落点三种，预览 200 个字符，各原因的说明，日志行不含文字。
//   - 设备状态机：每个状态遇到每个事件，片段号不串，超时与自动提交，Esc 归谁。
//   - 位置：贴边、比例、编码与读回、避让，随机网格上的不变式。
import Foundation
import CoreGraphics

var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1 } else { fails += 1; print("FAIL \(name)") } }

// MARK: - 协议

check("kind 100 voiceClip", StreamMessageKind(rawValue: 100) == .voiceClip && StreamMessageKind.voiceClip.rawValue == 100)
check("kind 101 voiceResult", StreamMessageKind(rawValue: 101) == .voiceResult)
check("kind 102 voiceCancel", StreamMessageKind(rawValue: 102) == .voiceCancel)
check("99 与 103 不是本版的", StreamMessageKind(rawValue: 99) == nil && StreamMessageKind(rawValue: 103) == nil)
let enc = VoiceClip.encode(clip: 0x01020304, format: VoiceClip.formatM4A, audio: Data([9, 8, 7]))
check("片段的编码：大端片段号、格式、音频", Array(enc) == [1, 2, 3, 4, 1, 9, 8, 7])
if let p = VoiceClip.parse(enc) { check("片段的解析", p.clip == 0x01020304 && p.format == 1 && p.audio == Data([9, 8, 7])) } else { check("片段的解析", false) }
check("不足 5 字节读不出", VoiceClip.parse(Data([1, 2, 3, 4])) == nil && VoiceClip.parse(Data()) == nil)
if let p = VoiceClip.parse(Data([0, 0, 0, 7, 1])) { check("只有头的片段：空音频", p.clip == 7 && p.audio.isEmpty) } else { check("只有头的片段", false) }
// 切片（startIndex 不为 0）也读对。
let sliced = (Data([0xFF, 0xFF]) + enc).dropFirst(2)
check("切片的解析", VoiceClip.parse(Data(sliced))?.clip == 0x01020304 && VoiceClip.parse(sliced)?.clip == 0x01020304)
check("上限 4 MiB", VoiceClip.maxAudioBytes == 4_194_304 && VoiceClip.headerLength == 5 && VoiceClip.formatM4A == 1)
let result = VoiceResult(clip: 3, ok: false, reason: "busy", message: "m")
check("结果的 JSON 往返", Wire.decode(VoiceResult.self, from: Wire.encode(result)) == result)
check("结果：nil 的字段不写", !(String(data: Wire.encode(VoiceResult(clip: 1, ok: true, text: "x")), encoding: .utf8) ?? "").contains("reason"))
check("结果：未知字段跳过、未知原因保留为字符串",
      Wire.decode(VoiceResult.self, from: Data(#"{"clip":5,"ok":false,"reason":"later","x":1}"#.utf8))?.reason == "later")
check("取消的 JSON", Wire.decode(VoiceCancel.self, from: Data(#"{"clip":9}"#.utf8)) == VoiceCancel(clip: 9))
var list = WindowList(macName: "M", windows: [], active: .none)
let before = Wire.encode(list)
check("WindowList.voice 为 nil 时不写", !(String(data: before, encoding: .utf8) ?? "").contains("voice"))
list.voice = VoiceSupport.generation
check("WindowList.voice 往返", Wire.decode(WindowList.self, from: Wire.encode(list))?.voice == 1)
check("老的列表读出 voice 为 nil", Wire.decode(WindowList.self, from: before)?.voice == nil)
check("预览上限 200", VoiceResult.maxPreviewCharacters == 200)
check("原因七种", Set(VoiceReason.allCases.map(\.rawValue)) == ["noService", "timeout", "serviceError", "locked", "nothingStreams", "tooLarge", "busy"])

// MARK: - 发现

typealias V = VoicePolicy
check("默认目录", V.dataDirectory(home: "/Users/u", configured: nil, testOverride: nil) == "/Users/u/Library/Application Support/TypefreeDemo")
check("配置优先于默认", V.dataDirectory(home: "/Users/u", configured: "/x/y", testOverride: nil) == "/x/y")
check("测试钩子优先于配置", V.dataDirectory(home: "/Users/u", configured: "/x/y", testOverride: "/t") == "/t")
check("空的当作没给", V.dataDirectory(home: "/Users/u", configured: "  ", testOverride: "") == "/Users/u/Library/Application Support/TypefreeDemo")
check("~ 展开", V.dataDirectory(home: "/Users/u", configured: "~/v", testOverride: nil) == "/Users/u/v"
      && V.dataDirectory(home: "/Users/u", configured: "~", testOverride: nil) == "/Users/u")
check("文件名", V.discoveryFileName == "local-api.json")
func j(_ s: String) -> Data { Data(s.utf8) }
let alive: (Int32) -> Bool = { _ in true }
let good = j(#"{"version":1,"port":8765,"token":"abc","pid":123,"startedAt":"2026-11-10T00:00:00Z"}"#)
check("好的发现文件", (try? V.discover(good, isAlive: alive).get()) == V.Service(port: 8765, token: "abc", pid: 123))
func refused(_ d: Data?, _ why: V.Unusable, alive: @escaping (Int32) -> Bool = { _ in true }) -> Bool {
    if case .failure(let w) = V.discover(d, isAlive: alive) { return w == why }
    return false
}
check("没有文件", refused(nil, .missing))
check("不是 JSON", refused(j("nope"), .unreadable))
check("JSON 数组", refused(j("[1]"), .unreadable))
check("版本 2", refused(j(#"{"version":2,"port":1,"token":"a","pid":1}"#), .wrongVersion(2)))
check("没有版本", refused(j(#"{"port":1,"token":"a","pid":1}"#), .wrongVersion(nil)))
check("版本是字符串", refused(j(#"{"version":"1","port":1,"token":"a","pid":1}"#), .wrongVersion(nil)))
check("版本是 true", refused(j(#"{"version":true,"port":1,"token":"a","pid":1}"#), .wrongVersion(nil)))
check("版本 1.5", refused(j(#"{"version":1.5,"port":1,"token":"a","pid":1}"#), .wrongVersion(nil)))
check("端口 0", refused(j(#"{"version":1,"port":0,"token":"a","pid":1}"#), .badPort))
check("端口 65536", refused(j(#"{"version":1,"port":65536,"token":"a","pid":1}"#), .badPort))
check("端口 65535 可以", (try? V.discover(j(#"{"version":1,"port":65535,"token":"a","pid":1}"#), isAlive: alive).get())?.port == 65535)
check("端口 1 可以", (try? V.discover(j(#"{"version":1,"port":1,"token":"a","pid":1}"#), isAlive: alive).get())?.port == 1)
check("端口是字符串", refused(j(#"{"version":1,"port":"80","token":"a","pid":1}"#), .badPort))
check("没有令牌", refused(j(#"{"version":1,"port":80,"pid":1}"#), .noToken))
check("令牌为空", refused(j(#"{"version":1,"port":80,"token":"","pid":1}"#), .noToken))
check("令牌是数字", refused(j(#"{"version":1,"port":80,"token":5,"pid":1}"#), .noToken))
check("没有 pid", refused(j(#"{"version":1,"port":80,"token":"a"}"#), .badPid))
check("pid 0", refused(j(#"{"version":1,"port":80,"token":"a","pid":0}"#), .badPid))
check("pid 负数", refused(j(#"{"version":1,"port":80,"token":"a","pid":-4}"#), .badPid))
check("pid 超出 Int32", refused(j(#"{"version":1,"port":80,"token":"a","pid":4294967296}"#), .badPid))
check("进程不在了", refused(good, .notRunning(123), alive: { _ in false }))
var askedPid: Int32 = 0
_ = V.discover(good, isAlive: { askedPid = $0; return true })
check("问的是文件里的 pid", askedPid == 123)
check("原因的说法", V.Unusable.missing.words.contains("local-api.json") && V.Unusable.notRunning(9).words.contains("9"))

// MARK: - 片段

func clip(_ id: UInt32, _ format: UInt8, _ n: Int) -> Data { VoiceClip.encode(clip: id, format: format, audio: Data(count: n)) }
check("正常的片段", V.clip(clip(4, 1, 10)) == .audio(clip: 4, audio: Data(count: 10)))
check("刚好 4 MiB 可以", { if case .audio(4, let a) = V.clip(clip(4, 1, VoiceClip.maxAudioBytes)) { return a.count == VoiceClip.maxAudioBytes }; return false }())
check("多 1 字节回 tooLarge", { if case .refuse(4, .tooLarge, _) = V.clip(clip(4, 1, VoiceClip.maxAudioBytes + 1)) { return true }; return false }())
check("未知格式回 serviceError", { if case .refuse(4, .serviceError, _) = V.clip(clip(4, 2, 10)) { return true }; return false }())
check("空音频回 serviceError", { if case .refuse(4, .serviceError, _) = V.clip(clip(4, 1, 0)) { return true }; return false }())
check("读不出片段号：丢弃", V.clip(Data([1, 2])) == .malformed)
check("主机读的上限：大于 4 MiB 加头、小于 32 MiB", V.maxReadPayload > VoiceClip.maxAudioBytes + VoiceClip.headerLength && V.maxReadPayload <= 32 << 20)
check("超限的判断先于格式", { if case .refuse(_, .tooLarge, _) = V.clip(clip(4, 9, VoiceClip.maxAudioBytes + 1)) { return true }; return false }())

// MARK: - 请求

check("超时 90 秒", V.timeout == 90)
check("令牌请求头", V.tokenHeader == "X-Typefree-Token")
check("Content-Type", V.contentType == "audio/mp4")
check("只发往 127.0.0.1", V.processURL(port: 8765)?.absoluteString == "http://127.0.0.1:8765/api/process")
check("坏端口没有地址", V.processURL(port: 0) == nil && V.processURL(port: 70000) == nil)

// MARK: - 回答

check("polishedText 优先", V.answer(status: 200, body: j(#"{"recognizedText":"ni hao","polishedText":"你好。"}"#)) == .text("你好。"))
check("polishedText 为空用 recognizedText", V.answer(status: 200, body: j(#"{"recognizedText":"ni hao","polishedText":""}"#)) == .text("ni hao"))
check("polishedText 只有空白用 recognizedText", V.answer(status: 200, body: j(#"{"recognizedText":"ni hao","polishedText":"  \n"}"#)) == .text("ni hao"))
check("没有 polishedText 用 recognizedText", V.answer(status: 200, body: j(#"{"recognizedText":"a"}"#)) == .text("a"))
check("首尾空白去掉", V.answer(status: 200, body: j(#"{"polishedText":" 好 \n"}"#)) == .text("好"))
check("polishedText 不是字符串时用 recognizedText", V.answer(status: 200, body: j(#"{"polishedText":5,"recognizedText":"b"}"#)) == .text("b"))
check("都空：serviceError", { if case .failed(.serviceError, _) = V.answer(status: 200, body: j(#"{"recognizedText":"","polishedText":""}"#)) { return true }; return false }())
check("200 但读不懂：serviceError", { if case .failed(.serviceError, _) = V.answer(status: 200, body: j("x")) { return true }; return false }())
check("403 用 error 字段", { if case .failed(.serviceError, let m) = V.answer(status: 403, body: j(#"{"error":"forbidden"}"#)) { return m.contains("forbidden") }; return false }())
check("500 没有 error：说状态码", { if case .failed(.serviceError, let m) = V.answer(status: 500, body: j("{}")) { return m.contains("500") }; return false }())
check("非 200 即使有文字也失败", { if case .failed = V.answer(status: 201, body: j(#"{"polishedText":"x"}"#)) { return true }; return false }())
check("error 字段换行不进说明", { if case .failed(_, let m) = V.answer(status: 400, body: j(#"{"error":"a\nb"}"#)) { return !m.contains("\n") }; return false }())
check("超时", V.failure(urlErrorCode: NSURLErrorTimedOut) == .timeout)
check("连不上：noService", V.failure(urlErrorCode: NSURLErrorCannotConnectToHost) == .noService)
check("连接断了：noService", V.failure(urlErrorCode: NSURLErrorNetworkConnectionLost) == .noService)
check("其他：serviceError", V.failure(urlErrorCode: NSURLErrorBadServerResponse) == .serviceError && V.failure(urlErrorCode: -1) == .serviceError)

// MARK: - 结果

check("打进去了：ok 与预览", V.result(clip: 2, text: "你好", landing: .typed) == VoiceResult(clip: 2, ok: true, text: "你好"))
check("锁屏", V.result(clip: 2, text: "x", landing: .locked).reason == "locked" && V.result(clip: 2, text: "x", landing: .locked).ok == false)
check("无处可落", V.result(clip: 2, text: "x", landing: .nothingStreams).reason == "nothingStreams")
check("失败的结果不带文字", V.result(clip: 2, text: "x", landing: .locked).text == nil)
check("失败带默认说明", V.failed(clip: 1, .busy).message == V.message(.busy))
check("失败可带自己的说明", V.failed(clip: 1, .serviceError, message: "m").message == "m")
check("每个原因都有说明", VoiceReason.allCases.allSatisfy { !V.message($0).isEmpty })
check("说明各不相同", Set(VoiceReason.allCases.map { V.message($0) }).count == VoiceReason.allCases.count)
let long = String(repeating: "字", count: 500)
check("预览 200 个字符", V.preview(long).count == 200 && V.preview(long).hasSuffix("…"))
check("刚好 200 不截", V.preview(String(repeating: "a", count: 200)) == String(repeating: "a", count: 200))
check("201 截成 200", V.preview(String(repeating: "a", count: 201)).count == 200)
let emoji = String(repeating: "👨‍👩‍👧", count: 250)
check("按字符截，不拆组合", V.preview(emoji).count == 200 && V.preview(emoji).dropLast().allSatisfy { $0 == "👨‍👩‍👧" })
let family150 = String(repeating: "👨‍👩‍👧", count: 150)
check("150 个组合字符（UTF-16 远超 200）不截", V.preview(family150) == family150)
check("成功的结果用预览", V.typed(clip: 1, text: long).text?.count == 200)
let line = V.logLine(clip: 3, device: "iPad", bytes: 8671, seconds: 1.234, characters: 6, reason: nil)
check("日志行", line == "Voice clip 3 from iPad: 8671 bytes, 1.23 s, 6 characters, ok")
check("日志行：原因", V.logLine(clip: 3, device: "iPad", bytes: 10, seconds: nil, characters: nil, reason: "busy") == "Voice clip 3 from iPad: 10 bytes, busy")

// MARK: - 设备状态机

typealias P = VoiceInputPolicy
let r0 = P.next(.idle, .tap(now: 10), nextClip: 7)
check("空闲点按：开始录音", r0.0 == .recording(clip: 7, since: 10) && r0.1 == [.startRecording(clip: 7)])
let r1 = P.next(.recording(clip: 7, since: 10), .tap(now: 13), nextClip: 8)
check("录音中点按：提交", r1.0 == .sending(clip: 7, since: 13) && r1.1 == [.stopAndSend(clip: 7)])
check("发送中点按：不理", P.next(.sending(clip: 7, since: 13), .tap(now: 14), nextClip: 8) == (.sending(clip: 7, since: 13), []))
let ok = VoiceResult(clip: 7, ok: true, text: "你好")
let r2 = P.next(.sending(clip: 7, since: 13), .result(ok, now: 15), nextClip: 8)
check("结果：完成，预览 2 秒", r2.0 == .done(text: "你好", until: 17) && r2.1 == [.announce(P.typedAnnouncement("你好"))])
check("别的片段的结果：不理", P.next(.sending(clip: 7, since: 13), .result(VoiceResult(clip: 6, ok: true, text: "x"), now: 15), nextClip: 8).0 == .sending(clip: 7, since: 13))
check("空闲时来的结果：不理", P.next(.idle, .result(ok, now: 15), nextClip: 8).0 == .idle)
let bad = VoiceResult(clip: 7, ok: false, reason: "locked", message: "Mac 的话")
let r3 = P.next(.sending(clip: 7, since: 13), .result(bad, now: 15), nextClip: 8)
check("失败：说明 4 秒，用设备的语言", r3.0 == .failed(message: P.message(for: bad), until: 19) && P.message(for: bad) != "Mac 的话")
check("失败：VoiceOver 念说明", r3.1 == [.announce(P.message(for: bad))])
check("未知原因显示 Mac 的说明", P.message(for: VoiceResult(clip: 1, ok: false, reason: "later", message: "Mac 的话")) == "Mac 的话")
check("没有原因也没有说明：通用的话", !P.message(for: VoiceResult(clip: 1, ok: false)).isEmpty)
check("serviceError 显示 Mac 的说明（服务原文）", P.message(for: VoiceResult(clip: 1, ok: false, reason: "serviceError", message: "meeppo-voice: x")) == "meeppo-voice: x")
check("每个已知原因都有设备的话", VoiceReason.allCases.allSatisfy { !P.message(for: VoiceResult(clip: 1, ok: false, reason: $0.rawValue)).isEmpty })
check("tooLarge 的结果", P.tooLarge(clip: 3) == VoiceResult(clip: 3, ok: false, reason: "tooLarge"))
check("录音中 Esc：丢弃", P.next(.recording(clip: 7, since: 10), .cancel, nextClip: 8) == (.idle, [.discardRecording]))
check("发送中 Esc：发取消", P.next(.sending(clip: 7, since: 10), .cancel, nextClip: 8) == (.idle, [.sendCancel(clip: 7)]))
check("空闲 Esc：什么都不做", P.next(.idle, .cancel, nextClip: 8) == (.idle, []))
check("完成时 Esc：收起", P.next(.done(text: "x", until: 5), .cancel, nextClip: 8).0 == .idle)
check("录音中藏起：丢弃", P.next(.recording(clip: 7, since: 10), .hidden, nextClip: 8) == (.idle, [.discardRecording]))
check("发送中藏起：照常等结果", P.next(.sending(clip: 7, since: 10), .hidden, nextClip: 8).0 == .sending(clip: 7, since: 10))
check("完成后到时回空闲", P.next(.done(text: "x", until: 17), .tick(now: 17), nextClip: 8).0 == .idle)
check("完成后未到时不动", P.next(.done(text: "x", until: 17), .tick(now: 16.9), nextClip: 8).0 == .done(text: "x", until: 17))
check("失败后到时回空闲", P.next(.failed(message: "m", until: 19), .tick(now: 19.5), nextClip: 8).0 == .idle)
let late = P.next(.sending(clip: 7, since: 13), .tick(now: 13 + P.sendTimeout), nextClip: 8)
check("发送超时：失败", late.0 == .failed(message: P.noAnswerMessage, until: 13 + P.sendTimeout + P.failureSeconds))
check("发送未超时：不动", P.next(.sending(clip: 7, since: 13), .tick(now: 13 + P.sendTimeout - 0.1), nextClip: 8).0 == .sending(clip: 7, since: 13))
let auto = P.next(.recording(clip: 7, since: 0), .tick(now: P.maxRecordingSeconds), nextClip: 8)
check("录到最长时自动提交", auto.0 == .sending(clip: 7, since: P.maxRecordingSeconds) && auto.1 == [.stopAndSend(clip: 7)])
check("录音未到最长：不动", P.next(.recording(clip: 7, since: 0), .tick(now: P.maxRecordingSeconds - 1), nextClip: 8).1.isEmpty)
check("最长录音在 4 MiB 之内（32 kbps）", P.maxRecordingSeconds * 32_000 / 8 < Double(VoiceClip.maxAudioBytes))
check("完成时再点：开始新的录音", P.next(.done(text: "x", until: 99), .tap(now: 20), nextClip: 9) == (.recording(clip: 9, since: 20), [.startRecording(clip: 9)]))
check("失败时再点：开始新的录音", P.next(.failed(message: "m", until: 99), .tap(now: 20), nextClip: 9).0 == .recording(clip: 9, since: 20))
let denied = P.next(.recording(clip: 7, since: 0), .permissionDenied(now: 2), nextClip: 8)
check("权限被拒：失败说去设置", denied.0 == .failed(message: P.permissionMessage, until: 2 + P.failureSeconds) && P.permissionMessage.contains("Settings"))
check("录音坏了：失败", P.next(.recording(clip: 7, since: 0), .recorderFailed(now: 2), nextClip: 8).0 == .failed(message: P.recorderMessage, until: 2 + P.failureSeconds))
check("Esc 归球：录音中与发送中", P.takesEscape(.recording(clip: 1, since: 0)) && P.takesEscape(.sending(clip: 1, since: 0))
      && !P.takesEscape(.idle) && !P.takesEscape(.done(text: "", until: 0)) && !P.takesEscape(.failed(message: "", until: 0)))
check("片段号：+1，到顶回到 1", P.clip(after: 1) == 2 && P.clip(after: UInt32.max) == 1)
// 随机事件序列：片段号只在开始录音时用，提交与取消的总是当前录的那一段；没有效果的事件不改片段。
var gen = SystemRandomNumberGenerator()
var invariants = true
for _ in 0..<5_000 {
    var phase = P.Phase.idle, next: UInt32 = 1, now = 0.0
    for _ in 0..<30 {
        now += Double.random(in: 0...60, using: &gen)
        let event: P.Event
        switch Int.random(in: 0...6, using: &gen) {
        case 0, 1: event = .tap(now: now)
        case 2: event = .cancel
        case 3: event = .result(VoiceResult(clip: UInt32.random(in: max(1, next) - 1...next, using: &gen), ok: Bool.random(using: &gen), text: "t", reason: "busy"), now: now)
        case 4: event = .tick(now: now)
        case 5: event = .hidden
        default: event = .permissionDenied(now: now)
        }
        let (after, effects) = P.next(phase, event, nextClip: next)
        for e in effects {
            switch e {
            case .startRecording(let c): if c != next { invariants = false }; if case .recording(c, _) = after {} else { invariants = false }; next = P.clip(after: next)
            case .stopAndSend(let c): if case .recording(c, _) = phase {} else { invariants = false }
            case .sendCancel(let c): if case .sending(c, _) = phase {} else { invariants = false }
            case .discardRecording: if case .recording = phase {} else { invariants = false }
            case .announce(let s): if s.isEmpty { invariants = false }
            }
        }
        if case .sending = after {
            switch phase { case .recording, .sending: break; default: invariants = false }
        }
        phase = after
    }
}
check("随机序列的不变式（5,000 段）", invariants)

// MARK: - 显示与开关

check("显示：Mac 说能接、开关开、没被盖住", P.shows(hostVoice: 1, switchOn: true, covered: false))
check("老 Mac（nil）不显示", !P.shows(hostVoice: nil, switchOn: true, covered: false))
check("voice 0 不显示", !P.shows(hostVoice: 0, switchOn: true, covered: false))
check("以后的版本 2 也显示", P.shows(hostVoice: 2, switchOn: true, covered: false))
check("开关关了不显示", !P.shows(hostVoice: 1, switchOn: false, covered: false))
check("被盖住不显示", !P.shows(hostVoice: 1, switchOn: true, covered: true))
check("开关的键", P.switchKey == "Sill.voiceInput")
check("开关：没存过为开", P.switchOn(stored: nil))
check("开关：布尔与数字", !P.switchOn(stored: false) && P.switchOn(stored: true) && !P.switchOn(stored: 0) && P.switchOn(stored: 1))
check("开关：启动参数的字符串", !P.switchOn(stored: "0") && !P.switchOn(stored: "NO") && P.switchOn(stored: "1") && P.switchOn(stored: "YES"))
check("能发：1 字节到 4 MiB", P.sendable(bytes: 1) && P.sendable(bytes: VoiceClip.maxAudioBytes) && !P.sendable(bytes: VoiceClip.maxAudioBytes + 1) && !P.sendable(bytes: 0))

// MARK: - 位置

check("直径 56", P.diameter == 56)
check("方向分开记", P.spotKey(landscape: true) != P.spotKey(landscape: false) && P.spotKey(landscape: true).hasPrefix("Sill."))
check("编码", P.encode(P.Spot(side: .leading, y: 0.25)) == "leading:0.250")
check("编码时夹在 0…1", P.encode(P.Spot(side: .trailing, y: 7)) == "trailing:1.000")
check("读回", P.decode("trailing:0.400") == P.Spot(side: .trailing, y: 0.4))
check("读回时夹在 0…1", P.decode("leading:-3") == P.Spot(side: .leading, y: 0))
check("读不懂：nil", P.decode(nil) == nil && P.decode("x") == nil && P.decode("up:0.5") == nil && P.decode("leading:nan") == nil && P.decode("leading:0.5:1") == nil)
check("默认：右边靠下", P.defaultSpot == P.Spot(side: .trailing, y: 0.75))
let area = CGRect(x: 0, y: 50, width: 1000, height: 600)
let rightTop = P.center(for: P.Spot(side: .trailing, y: 0), in: area)
check("右上：离边 12", rightTop == CGPoint(x: 1000 - 12 - 28, y: 50 + 12 + 28))
let leftBottom = P.center(for: P.Spot(side: .leading, y: 1), in: area)
check("左下：离边 12", leftBottom == CGPoint(x: 12 + 28, y: 650 - 12 - 28))
check("松手在左半边贴左", P.snap(CGPoint(x: 499, y: 300), in: area).side == .leading)
check("松手在右半边贴右", P.snap(CGPoint(x: 501, y: 300), in: area).side == .trailing)
check("松手在区域外夹住", P.snap(CGPoint(x: -500, y: -900), in: area) == P.Spot(side: .leading, y: 0)
      && P.snap(CGPoint(x: 5000, y: 9000), in: area) == P.Spot(side: .trailing, y: 1))
let tiny = CGRect(x: 0, y: 0, width: 300, height: 40)
check("太矮的区域：在中线", P.center(for: P.Spot(side: .leading, y: 0.9), in: tiny).y == 20 && P.snap(CGPoint(x: 0, y: 3), in: tiny).y == 0.5)
// 避让：右下角的芯片。
let chip = CGRect(x: 700, y: 580, width: 300, height: 70)
let moved = P.center(for: P.Spot(side: .trailing, y: 1), in: area, avoiding: [chip])
let ball = { (c: CGPoint) in CGRect(x: c.x - 28, y: c.y - 28, width: 56, height: 56) }
check("避开芯片", !ball(moved).intersects(chip.insetBy(dx: -P.clearance, dy: -P.clearance)) && moved.x == rightTop.x)
check("挪到芯片上方紧贴处", abs(moved.y - (chip.minY - P.clearance - 28 - 0.5)) < 0.001)
check("不相交时不挪", P.center(for: P.Spot(side: .leading, y: 1), in: area, avoiding: [chip]) == leftBottom)
// 中间的一块，球心略在它上方：上下都能挪时挪到近的那边（上方）。
let mid = P.center(for: P.Spot(side: .trailing, y: 0.5), in: area)
let band = CGRect(x: 800, y: mid.y - 10, width: 200, height: 40)
let near = P.center(for: P.Spot(side: .trailing, y: 0.5), in: area, avoiding: [band])
check("上下都能挪时挪到近处", abs(near.y - (band.minY - P.clearance - 28 - 0.5)) < 0.001)
let wall = CGRect(x: 900, y: 0, width: 100, height: 1000)
check("挪不开时留在原处", P.center(for: P.Spot(side: .trailing, y: 0.5), in: area, avoiding: [wall]).y == P.center(for: P.Spot(side: .trailing, y: 0.5), in: area).y)
// 随机网格：球总在区域之内，贴着一边，松手再放回原处。
var placementOK = true
for _ in 0..<20_000 {
    let a = CGRect(x: Double.random(in: -200...200, using: &gen), y: Double.random(in: -200...200, using: &gen),
                   width: Double.random(in: 90...1400, using: &gen), height: Double.random(in: 90...1400, using: &gen))
    let spot = P.Spot(side: Bool.random(using: &gen) ? .leading : .trailing, y: Double.random(in: 0...1, using: &gen))
    let c = P.center(for: spot, in: a)
    if !a.insetBy(dx: P.margin - 0.001, dy: P.margin - 0.001).contains(ball(c)) { placementOK = false }
    let back = P.snap(c, in: a)
    if back.side != spot.side || abs(back.y - spot.y) > 1e-9 { placementOK = false }
    let block = CGRect(x: a.minX + Double.random(in: 0...a.width, using: &gen), y: a.minY + Double.random(in: 0...a.height, using: &gen),
                       width: 80, height: 40)
    let d = P.center(for: spot, in: a, avoiding: [block])
    let clear = !ball(d).intersects(block.insetBy(dx: -P.clearance, dy: -P.clearance))
    if d.x != c.x || (d != c && !clear) || d.y < a.minY + P.margin + 28 - 0.6 || d.y > a.maxY - P.margin - 28 + 0.6 { placementOK = false }
}
check("随机网格上的位置不变式（20,000 个）", placementOK)

// MARK: - 文字

check("时长 0:07", P.elapsedText(7.9) == "0:07")
check("时长 12:03", P.elapsedText(723) == "12:03")
check("时长不为负、不是数", P.elapsedText(-3) == "0:00" && P.elapsedText(.nan) == "0:00")
check("音量：-50 dB 以下 0，0 dB 为 1", P.level(power: -160) == 0 && P.level(power: -50) == 0 && P.level(power: 0) == 1 && abs(P.level(power: -25) - 0.5) < 1e-9)
check("音量：超过 0 夹住、不是数为 0", P.level(power: 6) == 1 && P.level(power: .nan) == 0)
check("VoiceOver 标签", P.accessibilityLabel == "Voice input")
check("录音中的值含时长", P.accessibilityValue(.recording(clip: 1, since: 0), now: 65).contains("1:05"))
check("提示：录音中说提交，空闲说开始", P.accessibilityHint(.recording(clip: 1, since: 0)) != P.accessibilityHint(.idle) && !P.accessibilityHint(.idle).isEmpty)

print("\(passes) checks, \(fails) failed")
exit(fails == 0 ? 0 : 1)
