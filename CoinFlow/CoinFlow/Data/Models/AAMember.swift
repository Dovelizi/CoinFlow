//  AAMember.swift
//  CoinFlow · M11 AA 分账
//
//  AA 分账成员（对应 SQLite `aa_member` 表）。
//  本 App 单用户单设备，"成员"是用户在本地维护的人名标签 + 可选 emoji 头像。
//  支付状态由用户单方面勾选（无真实支付通道）。

import Foundation

/// 成员的支付确认状态。
/// - `pending`：待支付（默认；用户尚未勾选"已收到该成员还款"）
/// - `paid`：已支付（用户已勾选；`paidAt` 同步写入）
enum AAMemberStatus: String, Codable {
    case pending
    case paid
}

struct AAMember: Identifiable, Codable, Equatable {
    let id: String                  // UUID
    var ledgerId: String            // 归属的 AA Ledger
    var name: String                // 昵称（同 ledger 下不可重名）
    var avatarEmoji: String?        // 可选封面 emoji
    var status: AAMemberStatus      // pending / paid
    var paidAt: Date?               // 标记已支付的时间（status = paid 时写入）
    var sortOrder: Int              // 列表排序
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
}
