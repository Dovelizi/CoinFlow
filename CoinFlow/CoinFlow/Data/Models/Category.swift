//  Category.swift
//  CoinFlow · M1

import Foundation

/// 收支方向。
enum CategoryKind: String, Codable {
    case income
    case expense
}

/// 用户分类（对应 SQLite `category` 表）。
/// 注意：因 Swift 标准库已有 `Category`，业务侧可视情况用 `CFCategory` 别名避免冲突，
/// 但 SwiftUI 项目里通常无歧义，因此此处保留原名。
struct Category: Identifiable, Codable, Equatable {
    let id: String              // UUID
    var name: String
    var kind: CategoryKind
    var icon: String            // SF Symbols 名称
    var colorHex: String        // 形如 "#FF5722"
    var parentId: String?       // 二级分类指向父
    var sortOrder: Int
    var isPreset: Bool          // 预设分类不可删
    var deletedAt: Date?
}
