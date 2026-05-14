//  Ledger.swift
//  CoinFlow · M1 — 数据模型（纯 Swift struct，与持久化解耦）

import Foundation

/// 账本类型。
enum LedgerType: String, Codable {
    case personal
    case aa
}

/// AA 分账状态机（仅 `type = aa` 的账本使用；`personal` 账本恒为 nil）。
/// - `recording`：分账记录中（初始状态，不要求成员，可作为新建流水的目标）
/// - `settling`：分账结算中（需补齐成员、按笔分摊、逐人确认支付）
/// - `completed`：已完成结算（只读 + 已回写至个人账户）
enum AAStatus: String, Codable {
    case recording
    case settling
    case completed
}

/// 账本（对应 SQLite `ledger` 表）。
struct Ledger: Identifiable, Codable, Equatable {
    let id: String                  // UUID v4
    var name: String
    var type: LedgerType
    var firestorePath: String?      // AA 账本 V2+ 才会用
    var createdAt: Date             // UTC（B2）
    var timezone: String            // IANA 时区名，如 "Asia/Shanghai"
    var archivedAt: Date?
    var deletedAt: Date?            // 软删除（B3）
    // M11 AA 分账（v6 schema）
    var aaStatus: AAStatus?         // type=aa 时必有；type=personal 恒为 nil
    var settlingStartedAt: Date?    // 进入"结算中"的时间
    var completedAt: Date?          // 完成结算的时间（与 aaStatus = completed 同步写入）
}
