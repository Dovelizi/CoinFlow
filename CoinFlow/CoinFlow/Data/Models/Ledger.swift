//  Ledger.swift
//  CoinFlow · M1 — 数据模型（纯 Swift struct，与持久化解耦）

import Foundation

/// 账本类型。
enum LedgerType: String, Codable {
    case personal
    case aa
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
}
