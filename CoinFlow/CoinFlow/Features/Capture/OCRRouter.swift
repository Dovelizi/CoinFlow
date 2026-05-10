//  OCRRouter.swift
//  CoinFlow · M4 · §7.1 决策树
//
//  v2（2026-05-10 用户反馈：移除 Tencent OCR / Aliyun ASR 模块）：
//  路径：Vision 本地 → 置信度 < 0.6 或金额未识别 → LLM 视觉
//  原档 2（Tencent OCR）已整体移除；trail 中不再出现 .api。

import UIKit

@MainActor
final class OCRRouter {

    static let shared = OCRRouter()
    private init() {}

    private let vision = VisionOCRBackend()
    private let llm: OCRBackend = StubLLMOCRBackend()
    private let quota = QuotaService.shared

    /// 路由结果：解析数据 + 实际使用的引擎
    struct RouteResult {
        let receipt: ParsedReceipt?
        let usedEngine: OCREngineKind
        /// 自动升级链路（debug 用）：["vision", "llm"] 表示 vision 不行升级到 llm
        let trail: [OCREngineKind]
    }

    /// 默认走档 1 → 不行升档 LLM → 配额不足兜底返回档 1 结果（让用户手动改）
    func route(image: UIImage) async -> RouteResult {
        var trail: [OCREngineKind] = []

        // 档 1：Vision（仅调用一次，结果同时用于决策与兜底）
        trail.append(.vision)
        let visionResult: ParsedReceipt? = try? await vision.recognize(image)
        if let v = visionResult,
           v.amount != nil, v.confidence >= 0.6 {
            return RouteResult(receipt: v, usedEngine: .vision, trail: trail)
        }

        // 档 2：LLM 视觉
        if quota.canUse(.ocrLLM) {
            trail.append(.llm)
            if let l = try? await llm.recognize(image) {
                quota.increment(.ocrLLM)
                return RouteResult(receipt: l, usedEngine: .llm, trail: trail)
            }
        }

        // 全部失败：返回 Vision 原始数据（让用户手填）
        return RouteResult(receipt: visionResult, usedEngine: .vision, trail: trail)
    }
}
