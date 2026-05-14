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

/// 流水的"种类"——区分普通流水与系统生成的特殊占位。
/// 个人账单列表渲染、统计聚合、点击行为都依赖此字段。
enum RecordSourceKind: String, Codable {
    /// 默认：用户手动/OCR/语音录入的普通流水
    case normal
    /// AA 分账结算占位：当某 AA 账本进入"结算中"时，
    /// 系统在 default-ledger 上为当前用户生成 1 条净额占位（仅"我"）。
    /// 配合 settlementStatus 渲染"AA 分账·结算中/已结算"徽标，点击只读 + 跳转 AA 详情。
    case aaSettlement = "aa_settlement"
}

/// AA 占位的结算状态。
/// - settling：AA 账本处于结算中阶段（用户可能还在调整成员/分摊）
/// - settled：AA 账本已完成结算（金额冻结）
/// 普通流水（sourceKind == .normal）此字段为 nil。
enum AASettlementStatus: String, Codable {
    case settling
    case settled
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
    /// M11 AA 分账：当本流水是「分账完成回写」生成的（即写在 default-ledger 上的
    /// 收入/支出流水），该字段写入对应 AA Ledger 的 id，用于在 RecordDetailSheet
    /// 反向跳转到 AA 详情页。普通流水为 nil。
    var aaSettlementId: String?
    /// M12 AA 重构：流水种类（普通 / AA 占位）。默认 .normal 兼容老数据。
    var sourceKind: RecordSourceKind = .normal
    /// M12 AA 重构：仅当 sourceKind == .aaSettlement 时有值，
    /// 表示该占位对应 AA 账本所处的结算阶段。
    var settlementStatus: AASettlementStatus?
    // 时间戳
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
}
