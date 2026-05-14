//  AAShare.swift
//  CoinFlow · M11 AA 分账
//
//  AA 流水分摊明细（对应 SQLite `aa_share` 表）。
//  每条 record 在分账下可拆为 N 行 share（每位参与成员一行），每行表示该成员对该笔流水的应付金额。
//  - `isCustom = false`：由 AASplitService 按"金额 / 参与者数"自动平均分摊
//  - `isCustom = true`：用户在高级模式手动调整的金额；之和必须等于 record.amount

import Foundation

struct AAShare: Identifiable, Codable, Equatable {
    let id: String                  // UUID
    var recordId: String            // 关联的 Record id
    var memberId: String            // 关联的 AAMember id
    var amount: Decimal             // 该成员对该笔流水的应付金额（Decimal，B1）
    var isCustom: Bool              // 是否为用户自定义（true 时 AASplitService.recompute 不会覆盖）
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
}
