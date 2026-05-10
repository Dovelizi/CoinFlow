//  AudioRecorder.swift
//  CoinFlow · M5 · §7.5 录音流水
//
//  使用 AVAudioRecorder 录 m4a（AAC-LC 16kHz 单声道，§7.5.2 录音参数）。
//  设计选择说明：
//    - 未选 AVAudioEngine buffer 流式 ASR：本期本地档走 SFSpeechURLRecognitionRequest（§12.7），
//      用文件路径最简单、无需音频回调打桩。M6 若接入云端流式 ASR 再升级到 AVAudioEngine。
//    - 临时文件落 NSTemporaryDirectory()，识别完立即 delete（§7.5.2 "识别完成后立即删除"）。
//  权限：NSMicrophoneUsageDescription 已由 gen_xcodeproj.py 注入 Info.plist。

import Foundation
import AVFoundation

/// 录音错误。
enum AudioRecorderError: Error, LocalizedError {
    case permissionDenied
    case sessionConfigFailed(underlying: Error)
    case recorderInitFailed(underlying: Error)
    case recorderStartFailed
    case notRecording

    var errorDescription: String? {
        switch self {
        case .permissionDenied:         return "麦克风权限被拒绝"
        case .sessionConfigFailed(let e): return "音频会话配置失败：\(e.localizedDescription)"
        case .recorderInitFailed(let e):  return "录音初始化失败：\(e.localizedDescription)"
        case .recorderStartFailed:      return "开始录音失败"
        case .notRecording:             return "当前未处于录音状态"
        }
    }
}

@MainActor
final class AudioRecorder: NSObject, ObservableObject {

    /// 对外观察：录音是否进行中
    @Published private(set) var isRecording: Bool = false
    /// 对外观察：实时音量（0~1，UI 波形用）
    @Published private(set) var level: Float = 0
    /// 录音起始时间；停止时用来计算 duration
    private(set) var startedAt: Date?

    /// 当前录音文件 URL（录音结束后返回给调用方，调用方 consume 后 cleanup()）
    private(set) var audioURL: URL?

    private var recorder: AVAudioRecorder?
    private var levelTimer: Timer?

    /// 最长录音时长（秒）。V11 单次 SFSpeechRecognitionRequest ≤ 60s。
    static let maxDurationSec: TimeInterval = 60

    // MARK: - Authorization

    /// iOS 17+ 用 AVAudioApplication.requestRecordPermission；16 用 AVAudioSession.requestRecordPermission。
    /// 统一封装为 async Bool。
    static func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await withCheckedContinuation { cont in
                AVAudioApplication.requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        } else {
            return await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Start / Stop

    /// 开始录音。成功时设置 isRecording=true，调用方轮询 level 画波形。
    func start() throws {
        // 1. 会话配置
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .measurement,
                                    options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            // 兜底：确保 session 未激活，避免后续 start 累积副作用
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw AudioRecorderError.sessionConfigFailed(underlying: error)
        }

        // 2. 临时文件
        let url = Self.makeTempFileURL()
        self.audioURL = url

        // 3. AVAudioRecorder（AAC-LC / 16k / mono，Whisper 与本地 SFSpeech 都友好）
        let settings: [String: Any] = [
            AVFormatIDKey:            kAudioFormatMPEG4AAC,
            AVSampleRateKey:          16_000.0,
            AVNumberOfChannelsKey:    1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        let rec: AVAudioRecorder
        do {
            rec = try AVAudioRecorder(url: url, settings: settings)
        } catch {
            throw AudioRecorderError.recorderInitFailed(underlying: error)
        }
        rec.delegate = self
        rec.isMeteringEnabled = true
        rec.prepareToRecord()
        guard rec.record(forDuration: Self.maxDurationSec) else {
            throw AudioRecorderError.recorderStartFailed
        }

        self.recorder = rec
        self.startedAt = Date()
        self.isRecording = true
        self.level = 0

        // 4. 启动电平轮询（0.05s ≈ 20fps）
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollLevel() }
        }
        self.levelTimer = timer
    }

    /// 停止录音并返回 (文件 URL, 时长秒)。
    /// 若从未开始，抛 notRecording。
    @discardableResult
    func stop() throws -> (url: URL, duration: TimeInterval) {
        guard let rec = recorder, let started = startedAt, let url = audioURL else {
            throw AudioRecorderError.notRecording
        }
        rec.stop()
        levelTimer?.invalidate()
        levelTimer = nil
        isRecording = false
        let duration = Date().timeIntervalSince(started)
        // 注：不在这里 setActive(false)——SFSpeech 仍需要 session active 读取文件；
        // 由 VM 在识别完成后统一 tearDown()
        recorder = nil
        return (url, duration)
    }

    /// 取消：停止 + 立即删除临时文件。
    func cancel() {
        recorder?.stop()
        levelTimer?.invalidate()
        levelTimer = nil
        isRecording = false
        if let url = audioURL { try? FileManager.default.removeItem(at: url) }
        audioURL = nil
        recorder = nil
        startedAt = nil
    }

    /// 清理临时文件（识别完成后调用）。
    func cleanup() {
        if let url = audioURL {
            try? FileManager.default.removeItem(at: url)
        }
        audioURL = nil
        startedAt = nil
        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: .notifyOthersOnDeactivation)
    }

    // MARK: - Level polling

    private func pollLevel() {
        guard let rec = recorder, rec.isRecording else { return }
        rec.updateMeters()
        let db = rec.averagePower(forChannel: 0)              // dBFS，范围 [-160, 0]
        // 线性化：-50dB = 0，0dB = 1
        let normalized = max(0, min(1, (db + 50) / 50))
        self.level = normalized
    }

    // MARK: - Helpers

    private static func makeTempFileURL() -> URL {
        let ts = Int(Date().timeIntervalSince1970)
        let name = "voice_\(ts).m4a"
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // 触达 maxDurationSec 自动停止会走到这里；保证 isRecording = false 即使
        // UI tickTimer 因 sheet 被下拉 dismiss 而失联（防临时文件泄漏的兜底）。
        Task { @MainActor in
            self.isRecording = false
            self.levelTimer?.invalidate()
            self.levelTimer = nil
            // 不主动删 audioURL：VM 仍可能需要 consume 文件。由 VM 在 stopRecordingAndProcess
            // / cancelRecording / cleanup 三个路径统一清理。
        }
    }
}
