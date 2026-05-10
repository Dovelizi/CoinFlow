//  BillsPromptBuilder.swift
//  CoinFlow · Prompt 调度入口（薄壳）
//
//  历史：M5 起这里是统一 Prompt 模板，用 source: .voice/.ocr 在文案上切换"来源标签"。
//  现版（按用户要求）：拆为两份独立 Prompt
//    - 语音：BillsVoicePromptBuilder（含按天展开规则，上限 14）
//    - 截图：BillsOCRPromptBuilder（防订单号误判 / 商户识别 / 分期取当月）
//  本文件保留 `build(...)` API 不破坏调用方（BillsLLMParser）。
//
//  输出 schema 两份 Prompt 完全一致：
//      {"bills":[{occurred_at, amount, direction, category, note, merchant_type?, missing_fields?}]}

import Foundation

enum BillsSourceHint: String {
    case voice    // 口述
    case ocr      // 截图 OCR 文本（视觉 LLM 直识图走 BillsOCRPromptBuilder.buildForImage）
}

enum BillsPromptBuilder {

    /// 统一入口：按 source 选 builder。
    /// - Parameters:
    ///   - asrText:           语音原文（source=.voice）或 OCR 文本（source=.ocr）
    ///   - allowedCategories: 用户分类白名单
    ///   - requiredFields:    保留参数（当前两份新 Prompt 不再消费此项；客户端 normalizedMissing 仍会做最终校验）
    static func build(asrText: String,
                      today: Date,
                      tz: TimeZone,
                      allowedCategories: [String],
                      requiredFields: [String],
                      source: BillsSourceHint = .voice) -> String {
        switch source {
        case .voice:
            return BillsVoicePromptBuilder.build(
                asrText: asrText,
                today: today,
                tz: tz,
                allowedCategories: allowedCategories
            )
        case .ocr:
            return BillsOCRPromptBuilder.buildForText(
                rawText: asrText,
                today: today,
                tz: tz,
                allowedCategories: allowedCategories
            )
        }
    }
}
