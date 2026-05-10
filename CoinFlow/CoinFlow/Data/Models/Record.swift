//  Record.swift
//  CoinFlow · M1
//
//  金额必须用 Decimal（B1）。SQLite 落库时统一通过 `String(describing:)` /
//  `Decimal(string:)` 与 TEXT 列互转，禁止使用 Double 中转。

import Foundation

/// 流水来源。
enum RecordSource: String, Codable {
    case manual
    case ocrVision     = "ocr_vision"
    case ocrAPI        = "ocr_api"
    case ocrLLM        = "ocr_llm"
    case voiceLocal    = "voice_local"
    case voiceCloud    = "voice_cloud"
}

/// 同步状态。
enum SyncStatus: String, Codable {
    case pending
    case syncing
    case synced
    case failed
}

/// 流水记录（对应 SQLite `record` 表，§3.1 核心表）。
struct Record: Identifiable, Codable, Equatable {
    let id: String                  // UUID（业务主键 = Firestore document id）
    var ledgerId: String
    var categoryId: String
    var amount: Decimal             // ⚠️ 永远不要换成 Double（B1）
    var currency: String            // ISO 4217
    var occurredAt: Date            // UTC（B2）
    var timezone: String            // 记录时用户时区
    var note: String?
    var payerUserId: String?        // AA 账本付款人
    var participants: [String]?     // AA 账本：参与 uid 列表
    var source: RecordSource
    var ocrConfidence: Double?      // 0~1，仅 source != .manual 时有值
    var voiceSessionId: String?
    var missingFields: [String]?    // 缺失字段名集合，为空表示已补齐
    /// M9-Fix5 支付/收款渠道（仅 OCR 截图记账使用，手动记账为 nil）。
    /// 取值：微信 / 支付宝 / 抖音 / 银行 / 其他
    var merchantChannel: String?
    // 同步元数据
    var syncStatus: SyncStatus = .pending
    var remoteId: String?
    var lastSyncError: String?
    var syncAttempts: Int = 0
    /// M9-Fix4 OCR 附件：本地 Caches 截图绝对路径（同步成功后系统可清）
    var attachmentLocalPath: String?
    /// M9-Fix4 OCR 附件：飞书 file_token（uploadAttachment 成功后写回）
    var attachmentRemoteToken: String?
    // 时间戳
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
}
