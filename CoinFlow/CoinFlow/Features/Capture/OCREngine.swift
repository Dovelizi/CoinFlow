//  OCREngine.swift
//  CoinFlow · M4 · §6.3 / §7
//
//  三档 OCR 路由的接口抽象 + 档 1（Vision 本地）实现。
//  档 2/3（API/LLM）M6 接真服务；M4 给一个返回 nil 的占位实现。
//
//  设计原则：
//  - OCRBackend 协议：返回 ParsedReceipt（金额/商户/时间/置信度）
//  - 业务层调用 OCRRouter 决定走哪一档
//  - Vision 走系统 API，零网络

import Foundation
import UIKit
@preconcurrency import Vision

/// 解析后的小票/账单（原始数据；用户后续可改）。
struct ParsedReceipt: Equatable {
    var amount: Decimal?
    var merchant: String?
    var occurredAt: Date?
    /// 置信度 0~1（Vision 单字符的均值；API/LLM 各家定义略有不同）
    var confidence: Double
    /// 原始 OCR 全文（debug 与备注预填用）
    var rawText: String
}

/// 引擎选择标识。
enum OCREngineKind: String {
    case vision     // 档 1：Vision 本地
    case api        // 档 2：腾讯/百度（M6）
    case llm        // 档 3：豆包/Qwen-VL（M6）
}

/// 通用引擎抽象。
protocol OCRBackend {
    var kind: OCREngineKind { get }
    func recognize(_ image: UIImage) async throws -> ParsedReceipt
}

/// OCR 通用错误。
enum OCRError: Error, LocalizedError {
    case imageInvalid
    case visionFailed(underlying: Error)
    case quotaExhausted(engine: OCREngineKind)
    case notImplemented(engine: OCREngineKind)

    var errorDescription: String? {
        switch self {
        case .imageInvalid:                    return "图像无效（无法转 CGImage）"
        case .visionFailed(let e):             return "Vision 识别失败：\(e.localizedDescription)"
        case .quotaExhausted(let k):           return "本月 \(k.rawValue) 配额已用尽"
        case .notImplemented(let k):           return "\(k.rawValue) 引擎尚未接入（M6 启用）"
        }
    }
}

// MARK: - Vision 实现

final class VisionOCRBackend: OCRBackend {

    let kind: OCREngineKind = .vision

    func recognize(_ image: UIImage) async throws -> ParsedReceipt {
        guard let cg = image.cgImage else { throw OCRError.imageInvalid }
        return try await withCheckedThrowingContinuation { cont in
            let req = VNRecognizeTextRequest { request, error in
                if let error = error {
                    cont.resume(throwing: OCRError.visionFailed(underlying: error))
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines: [(String, Float)] = observations.compactMap { obs in
                    guard let top = obs.topCandidates(1).first else { return nil }
                    return (top.string, top.confidence)
                }
                let avgConf = lines.isEmpty ? 0
                    : Double(lines.map(\.1).reduce(0, +) / Float(lines.count))
                let allText = lines.map(\.0).joined(separator: "\n")
                let parsed = ReceiptParser.parse(rawText: allText, confidence: avgConf)
                cont.resume(returning: parsed)
            }
            req.recognitionLanguages = ["zh-Hans", "en-US"]
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([req])
                } catch {
                    cont.resume(throwing: OCRError.visionFailed(underlying: error))
                }
            }
        }
    }
}

// MARK: - API / LLM 占位（M6 真实现）

final class StubAPIOCRBackend: OCRBackend {
    let kind: OCREngineKind = .api
    func recognize(_ image: UIImage) async throws -> ParsedReceipt {
        throw OCRError.notImplemented(engine: .api)
    }
}

final class StubLLMOCRBackend: OCRBackend {
    let kind: OCREngineKind = .llm
    func recognize(_ image: UIImage) async throws -> ParsedReceipt {
        throw OCRError.notImplemented(engine: .llm)
    }
}
