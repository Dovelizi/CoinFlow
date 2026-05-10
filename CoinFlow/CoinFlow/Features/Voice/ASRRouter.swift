//  ASRRouter.swift
//  CoinFlow · M5 · §7.5.2
//
//  v2（2026-05-10 用户反馈：移除 Tencent OCR / Aliyun ASR 模块）：
//  仅保留档 1（本地 SFSpeechRecognizer）；原档 2（阿里云 ASR）整体移除。
//  本地失败 → 直接抛 allBackendsFailed，UI 层提示"手动输入"。

import Foundation

@MainActor
final class ASRRouter {

    static let shared = ASRRouter()
    private init() {}

    private let local: ASRBackend = LocalASRBackend()

    struct RouteResult {
        let text: String
        let confidence: Double
        let usedEngine: ASREngine            // 复用 Model/VoiceSession.ASREngine
        /// 降级链路（debug 用）
        let trail: [ASRBackendKind]
    }

    enum RouteError: Error, LocalizedError {
        case allBackendsFailed(lastError: Error?)

        var errorDescription: String? {
            switch self {
            case .allBackendsFailed(let e):
                return "ASR 失败：\(e?.localizedDescription ?? "未知错误")"
            }
        }
    }

    /// 仅本地路径。`preferred` 形参保留 API 兼容（旧调用点可能传 .cloud；现忽略，统一走本地）。
    func transcribe(audioURL: URL,
                    preferred: ASRBackendKind = .local) async throws -> RouteResult {
        _ = preferred  // 已无云端档，参数保留兼容旧调用

        var trail: [ASRBackendKind] = [.local]
        do {
            let r = try await local.transcribe(audioURL: audioURL)
            return RouteResult(text: r.text, confidence: r.confidence,
                               usedEngine: .speechLocal, trail: trail)
        } catch {
            _ = trail   // silence unused
            throw RouteError.allBackendsFailed(lastError: error)
        }
    }
}
