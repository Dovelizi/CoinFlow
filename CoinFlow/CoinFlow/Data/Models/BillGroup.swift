//  BillGroup.swift
//  CoinFlow · M13 · 账单分组

import Foundation

/// 账单分组（对应 SQLite `bill_group` 表）。
/// 用于对个人账本内的流水按事件/项目聚合（如"日常消费""云南旅游""装修"）。
struct BillGroup: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var emoji: String
    var note: String?
    var sortOrder: Int
    var isDefault: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
}
