import AVFoundation
import Foundation

/// 语音悬浮球的录音（docs/voice-and-immersive-plan.md 第 2.4 节）：AVAudioRecorder 写一个临时的 m4a（AAC、单声道、
/// 16 kHz、32 kbps），录完把字节交出去后删掉。
///
/// 音频会话：录音时切到 `.playAndRecord`（`.defaultToSpeaker`、蓝牙耳机），Mac 的声音先暂停（StreamClient 的
/// `sound.setMuted(true)`，由调用方做），结束后把会话放掉（`notifyOthersOnDeactivation`），Mac 的声音的引擎下次
/// 开始时自己再取 `.playback`（AudioOutput 的 SharedSession）。
///
/// 主线程。
@MainActor
final class VoiceRecorder {
    enum Failure: Error, Equatable {
        /// 麦克风权限被拒（或受限）。
        case denied
        /// 会话或录音器没能开始。
        case couldNotStart(String)
    }

    private var recorder: AVAudioRecorder?
    private var url: URL?

    /// 录音设置：AAC、单声道、16 kHz、32 kbps（约 4 KB/s，4 MiB 约 17 分钟）。
    static let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32_000,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]

    /// 麦克风权限：没问过就问（第一次点按时），回是否允许。
    static func permission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default:
            return await AVAudioApplication.requestRecordPermission()
        }
    }

    /// 开始录音。失败时抛出 `Failure`，会话已放掉。
    func start() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            // `.allowBluetoothHFP`（iOS 26 前叫 `.allowBluetooth`，同一个值 0x4）：用原始值，两种 SDK 都不报弃用。
            let bluetooth = AVAudioSession.CategoryOptions(rawValue: 0x4)
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, bluetooth])
            try session.setActive(true)
        } catch {
            release()
            throw Failure.couldNotStart("\(error.localizedDescription)")
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("sill-voice-\(UUID().uuidString).m4a")
        do {
            let r = try AVAudioRecorder(url: file, settings: Self.settings)
            r.isMeteringEnabled = true
            guard r.record() else {
                release()
                throw Failure.couldNotStart("the recorder did not start")
            }
            recorder = r
            url = file
        } catch let failure as Failure {
            throw failure
        } catch {
            release()
            throw Failure.couldNotStart("\(error.localizedDescription)")
        }
        #if DEBUG
        print("voice: recording to \(file.lastPathComponent)")
        #endif
    }

    /// 现在的音量（0…1），录音中才有。
    func level() -> Double {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        return VoiceInputPolicy.level(power: recorder.averagePower(forChannel: 0))
    }

    /// 停止并交出录到的字节（文件随即删除）；没在录或读不到时为 nil。
    func finish() -> Data? {
        guard let recorder, let url else { release(); return nil }
        recorder.stop()
        let data = try? Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)
        self.recorder = nil
        self.url = nil
        release()
        #if DEBUG
        print("voice: recorded \(data?.count ?? 0) bytes")
        #endif
        return data
    }

    /// 停止并丢掉录到的。
    func discard() {
        recorder?.stop()
        recorder?.deleteRecording()
        if let url { try? FileManager.default.removeItem(at: url) }
        recorder = nil
        url = nil
        release()
    }

    var isRecording: Bool { recorder?.isRecording ?? false }

    /// 放掉会话，让别的应用（和 Mac 的声音）回来。
    private func release() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // 别的还在用会话（比如另一个窗口的 Mac 声音）时会失败：不影响录音的结果，只记一行。
            print("voice: the audio session stayed active: \(error.localizedDescription)")
        }
    }
}
