import Foundation

// 语音输入（docs/voice-and-immersive-plan.md 第 2 节）：设备录一段语音，发给 Mac；Mac 交给本机的
// meeppo-voice 识别，再把文字当作这台设备打的字输入当前串流的应用，最后把结果回给设备。
//
// 种类号 100–102：上游已用或预留到 44（45 留给 Pencil，#81），本 fork 避开这一段，免得日后合并上游时撞号。
// 只增不改（Compatibility floor）：老版本对端把这三种读成 `.unknown` 并跳过；设备只在窗口列表的
// `voice` 为 1 时才发 kind 100，所以老主机不会收到。

/// kind 100 `voiceClip`（设备 → Mac）的二进制载荷：4 字节大端片段号 + 1 字节格式 + 音频字节。
public enum VoiceClip {
    /// 格式 1：m4a 容器里的 AAC（AVAudioRecorder 写出的文件原样发送）。其余值保留。
    public static let formatM4A: UInt8 = 1
    /// 片段号与格式占的字节数。
    public static let headerLength = 5
    /// 一个片段的音频最多 4 MiB（单声道 16 kHz、32 kbps 约 17 分钟）；超出的主机丢弃并回 `tooLarge`。
    public static let maxAudioBytes = 4 << 20

    /// 设备发出的载荷。
    public static func encode(clip: UInt32, format: UInt8, audio: Data) -> Data {
        var d = Data(capacity: headerLength + audio.count)
        d.appendBigEndian(clip)
        d.append(format)
        d.append(audio)
        return d
    }

    /// 主机读到的载荷：片段号、格式和音频；不足 5 字节时为 nil。音频的大小由读的一方判断（`maxAudioBytes`）。
    public static func parse(_ payload: Data) -> (clip: UInt32, format: UInt8, audio: Data)? {
        guard payload.count >= headerLength else { return nil }
        let clip = payload.readBigEndian(UInt32.self, at: 0)
        let format = payload[payload.startIndex + 4]
        let audio = payload.subdata(in: (payload.startIndex + headerLength)..<payload.endIndex)
        return (clip, format, audio)
    }
}

/// kind 101 `voiceResult`（Mac → 设备，JSON）：一个片段的结果。只回给发片段的那条连接。
public struct VoiceResult: Codable, Equatable, Sendable {
    public var clip: UInt32
    public var ok: Bool
    /// 输入的文字的预览，最多 `maxPreviewCharacters` 个字符；失败时为 nil。
    public var text: String?
    /// 失败原因（`VoiceReason` 的原始值）；成功时为 nil。设备遇到不认识的原因时显示 `message`。
    public var reason: String?
    /// 可直接显示的说明（Mac 的语言）。
    public var message: String?

    public init(clip: UInt32, ok: Bool, text: String? = nil, reason: String? = nil, message: String? = nil) {
        self.clip = clip; self.ok = ok; self.text = text; self.reason = reason; self.message = message
    }

    /// 预览最多 200 个字符（Character，不是字节）。
    public static let maxPreviewCharacters = 200
}

/// `VoiceResult.reason` 已知的取值。线上传字符串，以后新增的原因老设备显示其 `message`。
public enum VoiceReason: String, CaseIterable, Sendable {
    /// 这台 Mac 没有找到可用的 meeppo-voice（没打开，或发现文件失效）。
    case noService
    /// meeppo-voice 90 秒内没有回答。
    case timeout
    /// meeppo-voice 回了错误，或回答读不懂，或没识别出文字。
    case serviceError
    /// Mac 已锁屏（或切到了别的用户），文字没有打进去。
    case locked
    /// 当前什么都没在串流，文字无处可落。
    case nothingStreams
    /// 片段超过 4 MiB。
    case tooLarge
    /// 这台设备的上一个片段还在处理。
    case busy
}

/// kind 102 `voiceCancel`（设备 → Mac，JSON）：取消一个还在处理的片段。
public struct VoiceCancel: Codable, Equatable, Sendable {
    public var clip: UInt32
    public init(clip: UInt32) { self.clip = clip }
}

/// `WindowList.voice` 的取值：1 表示这台 Mac 现在能接语音（找到了可用的 meeppo-voice）。
public enum VoiceSupport {
    public static let generation = 1
}
