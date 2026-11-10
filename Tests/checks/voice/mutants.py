"""语音输入的 mutants（Sources/SillHost/VoicePolicy.swift、iOSClient/VoiceInputPolicy.swift、Sources/StreamProtocol/Voice.swift）：
每个改一处，必须能编译并让 voice/main.swift 失败。usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
V = "Sources/SillHost/VoicePolicy.swift"
P = "iOSClient/VoiceInputPolicy.swift"
W = "Sources/StreamProtocol/Voice.swift"
K = "Sources/StreamProtocol/StreamMessage.swift"
M = [
    # 协议
    ("kind 100 改成 45", K, "case voiceClip = 100", "case voiceClip = 45"),
    ("片段号小端", W, "        d.appendBigEndian(clip)\n", "        var le = clip.littleEndian; Swift.withUnsafeBytes(of: &le) { d.append(contentsOf: $0) }\n"),
    ("解析不查长度", W, "        guard payload.count >= headerLength else { return nil }\n", "        guard payload.count >= 4 else { return nil }\n"),
    ("解析的格式字节错位", W, "        let format = payload[payload.startIndex + 4]", "        let format = payload[payload.startIndex + 3]"),
    ("上限 2 MiB", W, "public static let maxAudioBytes = 4 << 20", "public static let maxAudioBytes = 2 << 20"),
    ("预览上限 100", W, "public static let maxPreviewCharacters = 200", "public static let maxPreviewCharacters = 100"),
    # 发现
    ("默认目录写错", V, 'static let defaultDataDirectory = "Library/Application Support/TypefreeDemo"', 'static let defaultDataDirectory = "Library/Application Support/meeppo-voice"'),
    ("配置优先于测试钩子", V, "return usable(testOverride) ?? usable(configured) ??", "return usable(configured) ?? usable(testOverride) ??"),
    ("~ 不展开", V, '            if s.hasPrefix("~/") { return (home as NSString).appendingPathComponent(String(s.dropFirst(2))) }\n', ""),
    ("空白不算没给", V, "            guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }",
     "            guard let s else { return nil }"),
    ("不查版本", V, "        guard version == 1 else { return .failure(.wrongVersion(version)) }\n", ""),
    ("端口上限 65536", V, "(1...65535).contains(port) else { return .failure(.badPort) }", "(1...65536).contains(port) else { return .failure(.badPort) }"),
    ("端口 0 可以", V, "(1...65535).contains(port) else { return .failure(.badPort) }", "(0...65535).contains(port) else { return .failure(.badPort) }"),
    ("空令牌可以", V, 'guard let token = json["token"] as? String, !token.isEmpty else', 'guard let token = json["token"] as? String else'),
    ("pid 0 可以", V, "guard let pid = integer(json[\"pid\"]), pid > 0,", "guard let pid = integer(json[\"pid\"]), pid >= 0,"),
    ("不查 pid 是否活着", V, "        guard isAlive(Int32(pid)) else { return .failure(.notRunning(Int32(pid))) }\n", ""),
    ("布尔值当整数", V, "guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }",
     "guard let n = value as? NSNumber else { return nil }"),
    ("小数当整数", V, "guard d.isFinite, d == d.rounded(), abs(d) < 1e15 else { return nil }", "guard d.isFinite, abs(d) < 1e15 else { return nil }"),
    # 片段
    ("上限多 1 字节可以", V, "guard audio.count <= VoiceClip.maxAudioBytes else {", "guard audio.count <= VoiceClip.maxAudioBytes + 1 else {"),
    ("超限回 serviceError", V, "return .refuse(clip: clip, reason: .tooLarge, message: message(.tooLarge))", "return .refuse(clip: clip, reason: .serviceError, message: message(.tooLarge))"),
    ("不查格式", V, "guard format == VoiceClip.formatM4A else {", "guard format == format else {"),
    ("空音频可以", V, "        guard !audio.isEmpty else {", "        guard audio.isEmpty || !audio.isEmpty else {"),
    ("主机读的上限只有 1 MiB", V, "static let maxReadPayload = 2 * VoiceClip.maxAudioBytes + VoiceClip.headerLength",
     "static let maxReadPayload = 1 << 20"),
    # 请求
    ("超时 30 秒", V, "static let timeout: TimeInterval = 90", "static let timeout: TimeInterval = 30"),
    ("令牌头写错", V, 'static let tokenHeader = "X-Typefree-Token"', 'static let tokenHeader = "Authorization"'),
    ("发往 localhost", V, 'URL(string: "http://127.0.0.1:\\(port)/api/process")', 'URL(string: "http://localhost:\\(port)/api/process")'),
    # 回答
    ("recognizedText 优先", V, 'for key in ["polishedText", "recognizedText"] {', 'for key in ["recognizedText", "polishedText"] {'),
    ("不去首尾空白", V, "                return .text(text.trimmingCharacters(in: .whitespacesAndNewlines))", "                return .text(text)"),
    ("只有空白也算文字", V, 'if let text = json[key] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {',
     'if let text = json[key] as? String, !text.isEmpty {'),
    ("任何 2xx 都算", V, "        guard status == 200 else {", "        guard (200...299).contains(status) else {"),
    ("不用 error 字段", V, "            let text = error.isEmpty\n", "            let text = true\n"),
    ("超时回 serviceError", V, "        case NSURLErrorTimedOut: return .timeout", "        case NSURLErrorTimedOut: return .serviceError"),
    ("连不上回 serviceError", V, "        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorNetworkConnectionLost,",
     "        case NSURLErrorCannotFindHost, NSURLErrorNetworkConnectionLost,"),
    # 结果
    ("锁屏回 nothingStreams", V, "        case .locked: return failed(clip: clip, .locked)", "        case .locked: return failed(clip: clip, .nothingStreams)"),
    ("成功不截预览", V, "        VoiceResult(clip: clip, ok: true, text: preview(text))", "        VoiceResult(clip: clip, ok: true, text: text)"),
    ("预览多一个字符", V, "        return String(text.prefix(limit - 1)) + \"…\"", "        return String(text.prefix(limit)) + \"…\""),
    ("预览按 UTF-16 截", V, "        guard text.count > limit else { return text }", "        guard text.utf16.count > limit else { return text }"),
    ("日志不带原因", V, '        parts.append(reason ?? "ok")\n', ""),
    # 设备状态机
    ("提交用下一个片段号", P, "            return (.sending(clip: clip, since: now), [.stopAndSend(clip: clip)])\n        case (.sending, .tap):",
     "            return (.sending(clip: nextClip, since: now), [.stopAndSend(clip: nextClip)])\n        case (.sending, .tap):"),
    ("发送中点按重新录", P, "        case (.sending, .tap):\n            return (phase, [])", "        case (.sending, .tap(let now)):\n            return (.recording(clip: nextClip, since: now), [.startRecording(clip: nextClip)])"),
    ("录音中 Esc 也发取消", P, "        case (.recording, .cancel), (.recording, .hidden):\n            return (.idle, [.discardRecording])",
     "        case (.recording(let clip, _), .cancel), (.recording(let clip, _), .hidden):\n            return (.idle, [.sendCancel(clip: clip)])"),
    ("发送中 Esc 不发取消", P, "            return (.idle, [.sendCancel(clip: clip)])", "            _ = clip; return (.idle, [])"),
    ("别的片段的结果也算", P, "        case (.sending(let clip, _), .result(let r, let now)) where r.clip == clip:", "        case (.sending(let clip, _), .result(let r, let now)) where r.clip == clip || true:"),
    ("预览 4 秒", P, "static let previewSeconds = 2.0", "static let previewSeconds = 4.0"),
    ("失败不念", P, "            return (.failed(message: words, until: now + failureSeconds), [.announce(words)])\n        case (.recording, .permissionDenied",
     "            return (.failed(message: words, until: now + failureSeconds), [])\n        case (.recording, .permissionDenied"),
    ("完成到时不回空闲", P, "        case (.done(_, let until), .tick(let now)) where now >= until,", "        case (.done(_, let until), .tick(let now)) where now > until + 1,"),
    ("发送不超时", P, "        case (.sending(_, let since), .tick(let now)) where now - since >= sendTimeout:", "        case (.sending(_, let since), .tick(let now)) where now - since >= sendTimeout * 100:"),
    ("录音不自动提交", P, "        case (.recording(let clip, let since), .tick(let now)) where now - since >= maxRecordingSeconds:",
     "        case (.recording(let clip, let since), .tick(let now)) where now - since >= maxRecordingSeconds * 100:"),
    ("最长录音太长", P, "static let maxRecordingSeconds = 600.0", "static let maxRecordingSeconds = 1200.0"),
    ("空闲时 Esc 归球", P, "        case .recording, .sending: return true\n        default: return false", "        default: return true"),
    ("片段号到顶回 0", P, "clip == UInt32.max ? 1 : clip + 1", "clip == UInt32.max ? 0 : clip + 1"),
    ("未知原因用通用话", P, "        case nil:\n            return result.message ??", "        case nil:\n            return nil ??"),
    ("serviceError 不用 Mac 的说明", P, "            return result.message ?? String(localized: \"meeppo-voice couldn’t recognize the recording.\"",
     "            return nil ?? String(localized: \"meeppo-voice couldn’t recognize the recording.\""),
    # 显示与开关
    ("老 Mac 也显示", P, "(hostVoice ?? 0) >= VoiceSupport.generation", "(hostVoice ?? 1) >= VoiceSupport.generation"),
    ("被盖住也显示", P, "&& switchOn && !covered", "&& switchOn"),
    ("开关默认关", P, "        case nil: return true\n        case let n as NSNumber", "        case nil: return false\n        case let n as NSNumber"),
    ("字符串 \"0\" 也算开", P, '!["0", "no", "false", "off"].contains', '!["no", "false", "off"].contains'),
    ("能发的上限多 1 字节", P, "bytes <= VoiceClip.maxAudioBytes }", "bytes <= VoiceClip.maxAudioBytes + 1 }"),
    # 位置
    ("直径 44", P, "static let diameter: CGFloat = 56", "static let diameter: CGFloat = 44"),
    ("方向不分开记", P, 'landscape ? "Sill.voiceBall.landscape" : "Sill.voiceBall.portrait"', '"Sill.voiceBall"'),
    ("编码不夹", P, 'String(format: "%.3f", min(max(spot.y, 0), 1))', 'String(format: "%.3f", spot.y)'),
    ("读回不查段数", P, "guard parts.count == 2, let side", "guard parts.count >= 2, let side"),
    ("读回不查有限", P, "let y = Double(parts[1]), y.isFinite else", "let y = Double(parts[1]) else"),
    ("贴边按左三分之一", P, "let side: Side = center.x < area.midX ? .leading : .trailing", "let side: Side = center.x < area.minX + area.width / 3 ? .leading : .trailing"),
    ("左右反了", P, "let x: CGFloat = spot.side == .leading ? area.minX + margin + r : area.maxX - margin - r",
     "let x: CGFloat = spot.side == .trailing ? area.minX + margin + r : area.maxX - margin - r"),
    ("不离边", P, "let low = area.minY + margin + r, high = area.maxY - margin - r", "let low = area.minY + r, high = area.maxY - r"),
    ("不避让", P, "        if free(y) { return CGPoint(x: x, y: y) }", "        if true { return CGPoint(x: x, y: y) }"),
    ("避让不留空", P, "let blocks = avoiding.map { $0.insetBy(dx: -clearance, dy: -clearance) }", "let blocks = avoiding"),
    ("避让挪远处", P, ".min { abs($0 - y) < abs($1 - y) }", ".max { abs($0 - y) < abs($1 - y) }"),
    ("避让可挪出区域", P, ".filter { range.contains($0) && free($0) }", ".filter { free($0) }"),
    # 文字
    ("时长不补零", P, 'String(format: "%d:%02d", s / 60, s % 60)', 'String(format: "%d:%d", s / 60, s % 60)'),
    ("音量从 -60 dB 起", P, "return Double(min(max((power + 50) / 50, 0), 1))", "return Double(min(max((power + 60) / 60, 0), 1))"),
    ("VoiceOver 标签写错", P, 'String(localized: "Voice input", comment: "语音悬浮球：无障碍标签")', 'String(localized: "Dictation", comment: "语音悬浮球：无障碍标签")'),
]
sys.exit(0 if module.mutate("voice", M, sys.argv[1]) else 1)
