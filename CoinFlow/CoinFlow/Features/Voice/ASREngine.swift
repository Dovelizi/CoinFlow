//  ASREngine.swift
//  CoinFlow · M5 · §7.5.2 三档 ASR 路由 / §12.7 LocalASR
//
//  与 OCREngine 同构：
//  - ASRBackend 协议：输入音频 URL → (text, confidence)
//  - LocalASRBackend：SFSpeechRecognizer 强制 onDevice；zh-CN；单次 ≤ 60s
//  - StubCloudASRBackend：M6 接入真云端 ASR（阿里云/讯飞/Whisper）；当前抛 notImplemented
//
//  错误分类：
//  - authorizationDenied：用户拒绝 Speech 权限
//  - recognizerUnavailable：zh-CN recognizer 在本机不可用
//  - onDeviceUnavailable：机器不支持或语言包未下载；调用方应降级云端
//  - recognitionFailed：识别过程中 Speech 框架抛错
//  - notImplemented：Stub 专用

import Foundation
import Speech

/// ASR 引擎种类。
enum ASRBackendKind: String {
    case local  = "speech_local"   // 与 Model/VoiceSession.ASREngine.speechLocal 对齐
    case cloud  = "whisper"        // M6 真接入时会扩展 aliyun
}

/// ASR 引擎错误。
enum ASRError: Error, LocalizedError {
    case authorizationDenied
    case recognizerUnavailable
    case onDeviceUnavailable
    case recognitionFailed(underlying: Error)
    case notImplemented(kind: ASRBackendKind)

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:      return "语音识别权限被拒绝，请在 设置 → CoinFlow 中开启"
        case .recognizerUnavailable:    return "当前设备不支持中文语音识别"
        case .onDeviceUnavailable:
            return "本地中文语音识别未就绪，请在 设置 → 通用 → 键盘 → 启用听写 中下载中文语言包"
        case .recognitionFailed(let e): return "识别失败：\(e.localizedDescription)"
        case .notImplemented(let k):    return "\(k.rawValue) 引擎尚未接入（M6 启用）"
        }
    }
}

/// ASR 引擎抽象。
protocol ASRBackend {
    var kind: ASRBackendKind { get }
    /// - Returns: 识别文本 + 整段置信度（0~1）
    func transcribe(audioURL: URL) async throws -> (text: String, confidence: Double)
}

// MARK: - 档 1：SFSpeechRecognizer 本地

final class LocalASRBackend: ASRBackend {

    let kind: ASRBackendKind = .local

    private let recognizer: SFSpeechRecognizer?

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    /// 当前是否可用（可调度）。调用方用来决定是否走本地档。
    /// 注意：`requiresOnDeviceRecognition` 需要 `supportsOnDeviceRecognition == true`，
    /// iOS 模拟器常见返回 false → 调用方应优雅降级到云端或抛 `.onDeviceUnavailable`
    var isOnDeviceAvailable: Bool {
        (recognizer?.isAvailable ?? false) && (recognizer?.supportsOnDeviceRecognition ?? false)
    }

    /// 请求语音识别权限（一次 App 生命周期只需调一次）。
    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
    }

    func transcribe(audioURL: URL) async throws -> (text: String, confidence: Double) {
        guard let rec = recognizer else { throw ASRError.recognizerUnavailable }
        guard rec.isAvailable else { throw ASRError.recognizerUnavailable }

        let req = SFSpeechURLRecognitionRequest(url: audioURL)
        req.shouldReportPartialResults = false
        if rec.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        } else {
            // 模拟器/低端机 Fallback：这里我们选择抛错让 Router 升级云端，
            // 而不是偷偷走联网，与文档 §11.1「隐私优先」一致。
            throw ASRError.onDeviceUnavailable
        }

        return try await withCheckedThrowingContinuation { cont in
            // recognitionTask 是非结构化回调，用局部状态确保 resume 只调用一次
            nonisolated(unsafe) var resumed = false
            rec.recognitionTask(with: req) { result, error in
                if resumed { return }
                if let error = error {
                    resumed = true
                    cont.resume(throwing: ASRError.recognitionFailed(underlying: error))
                    return
                }
                guard let r = result, r.isFinal else { return }
                let segs = r.bestTranscription.segments
                let avg: Double = segs.isEmpty
                    ? 0
                    : Double(segs.map(\.confidence).reduce(0, +) / Float(segs.count))
                resumed = true
                cont.resume(returning: (r.bestTranscription.formattedString, avg))
            }
        }
    }
}

// MARK: - 档 2：Stub 云端（M6 接真）

final class StubCloudASRBackend: ASRBackend {
    let kind: ASRBackendKind = .cloud
    func transcribe(audioURL: URL) async throws -> (text: String, confidence: Double) {
        throw ASRError.notImplemented(kind: .cloud)
    }
}
