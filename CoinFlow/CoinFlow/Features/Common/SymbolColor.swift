//  SymbolColor.swift
//  CoinFlow · M3.2
//
//  hex String ↔ Color 转换 + 金额方向色（红支出 / 绿收入）。

import SwiftUI

extension Color {
    /// 从 #RRGGBB / RRGGBB / #RRGGBBAA 生成 Color。
    /// 解析失败返回灰色占位，避免崩溃。
    init(hex: String, alpha: Double = 1.0) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8 else {
            self = Color.gray
            return
        }
        var rgba: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgba)
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((rgba >> 24) & 0xFF) / 255
            g = Double((rgba >> 16) & 0xFF) / 255
            b = Double((rgba >> 8)  & 0xFF) / 255
            a = Double(rgba & 0xFF) / 255
        } else {
            r = Double((rgba >> 16) & 0xFF) / 255
            g = Double((rgba >> 8)  & 0xFF) / 255
            b = Double(rgba & 0xFF) / 255
            a = alpha
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

/// 金额方向色（§5.5.2 唯一允许的彩色文字之一）。
enum DirectionColor {
    static func amountForeground(kind: CategoryKind) -> Color {
        switch kind {
        case .expense: return Color(hex: "#D44C47")  // Notion red dark variant
        case .income:  return Color(hex: "#448361")  // Notion green dark variant
        }
    }
}

/// 同步状态点的颜色（§5.5.2 唯一允许的彩色文字之二）。
enum SyncStatusColor {
    static func dot(for status: SyncStatus) -> Color {
        switch status {
        case .pending:  return Color(hex: "#CA9849")   // 黄
        case .syncing:  return Color(hex: "#5E87C9")   // 蓝
        case .synced:   return Color.inkTertiary       // 灰（已同步无需高亮）
        case .failed:   return Color(hex: "#DF5452")   // 红
        }
    }
}
