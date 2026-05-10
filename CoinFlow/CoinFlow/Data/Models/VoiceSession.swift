//  VoiceSession.swift
//  CoinFlow · M1

import Foundation

enum ASREngine: String, Codable {
    case speechLocal = "speech_local"
    case whisper
    case aliyun
}

enum ParserEngine: String, Codable {
    case llmDeepseek = "llm_deepseek"
    case llmGPT4o    = "llm_gpt4o"
    case llmQwen     = "llm_qwen"
    case llmDoubao   = "llm_doubao"
    case ruleOnly    = "rule_only"
}

enum VoiceSessionStatus: String, Codable {
    case recording
    case asrDone     = "asr_done"
    case parsed
    case confirming
    case completed
    case cancelled
}

/// 语音录制会话（对应 `voice_session` 表）。
/// 一次录音 = 一行 = 多笔 record。
struct VoiceSession: Identifiable, Codable, Equatable {
    let id: String                  // UUID
    var startedAt: Date
    var durationSec: Double
    var audioPath: String?          // 临时文件路径，识别完即删
    var asrEngine: ASREngine
    var asrText: String             // ASR 转写原文（人工核对用）
    var asrConfidence: Double?      // 整段平均置信度
    var parserEngine: ParserEngine?
    var parserRawJSON: String?      // 审计 + bug 复现
    var parsedCount: Int = 0
    var confirmedCount: Int = 0
    var status: VoiceSessionStatus
    var error: String?
    var createdAt: Date
}
