//  NotionColor.swift
//  CoinFlow · V2 Stats
//
//  Notion 10 色族 token 化。M7 之前主项目仅用纯色 hex（DirectionColor / SymbolColor），
//  V2 统计图表需要 text/background 双轨色，沿用 Preview 的 NotionColor 枚举语义。
//
//  设计基线：参考 Notion App 实测取色（与 CoinFlowPreview 完全一致），dark/light 各一组。
//  使用方式：`NotionColor.orange.text(scheme)` / `NotionColor.green.background(scheme)`。

import SwiftUI

/// Notion 10 色族（与 CoinFlowPreview 完全一致，便于设计同源迁移）。
enum NotionColor: String, CaseIterable {
    case `default`, gray, brown, orange, yellow, green, blue, purple, pink, red

    /// 文字 / 描边 / 主图形色：与 Notion app 实测取色一致。
    func text(_ scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.default, _):       return .inkPrimary
        case (.gray, .light):     return Color(hex: "787774")
        case (.gray, .dark):      return Color(hex: "9B9A97")
        case (.brown, .light):    return Color(hex: "9F6B53")
        case (.brown, .dark):     return Color(hex: "BA856F")
        case (.orange, .light):   return Color(hex: "D9730D")
        case (.orange, .dark):    return Color(hex: "C77D48")
        case (.yellow, .light):   return Color(hex: "CB912F")
        case (.yellow, .dark):    return Color(hex: "CA9849")
        case (.green, .light):    return Color(hex: "448361")
        case (.green, .dark):     return Color(hex: "529E72")
        case (.blue, .light):     return Color(hex: "337EA9")
        case (.blue, .dark):      return Color(hex: "5E87C9")
        case (.purple, .light):   return Color(hex: "9065B0")
        case (.purple, .dark):    return Color(hex: "9D68D3")
        case (.pink, .light):     return Color(hex: "C14C8A")
        case (.pink, .dark):      return Color(hex: "D15796")
        case (.red, .light):      return Color(hex: "D44C47")
        case (.red, .dark):       return Color(hex: "DF5452")
        @unknown default:         return .inkPrimary
        }
    }

    /// 浅色族背景（按钮底 / 标签胶囊 / icon 容器）。
    func background(_ scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.default, _):     return .clear
        case (.gray, .light):   return Color(hex: "787774", alpha: 0.20)
        case (.gray, .dark):    return Color(hex: "9B9A97", alpha: 0.16)
        case (.brown, .light):  return Color(hex: "8C2E00", alpha: 0.20)
        case (.brown, .dark):   return Color(hex: "BA856F", alpha: 0.16)
        case (.orange, .light): return Color(hex: "F55D00", alpha: 0.20)
        case (.orange, .dark):  return Color(hex: "C77D48", alpha: 0.16)
        case (.yellow, .light): return Color(hex: "E9A800", alpha: 0.20)
        case (.yellow, .dark):  return Color(hex: "CA9849", alpha: 0.16)
        case (.green, .light):  return Color(hex: "00876B", alpha: 0.20)
        case (.green, .dark):   return Color(hex: "529E72", alpha: 0.16)
        case (.blue, .light):   return Color(hex: "0078DF", alpha: 0.20)
        case (.blue, .dark):    return Color(hex: "5E87C9", alpha: 0.16)
        case (.purple, .light): return Color(hex: "6724DE", alpha: 0.20)
        case (.purple, .dark):  return Color(hex: "9D68D3", alpha: 0.16)
        case (.pink, .light):   return Color(hex: "DD0081", alpha: 0.20)
        case (.pink, .dark):    return Color(hex: "D15796", alpha: 0.16)
        case (.red, .light):    return Color(hex: "FF001A", alpha: 0.20)
        case (.red, .dark):     return Color(hex: "DF5452", alpha: 0.16)
        @unknown default:       return .clear
        }
    }
}

/// 业务分类 colorHex → NotionColor 的最近邻映射。
/// DefaultSeeder 里预设分类用的 colorHex（系统色）一一对应到 NotionColor 族，
/// 让 Stats 图表的 token 化染色与流水页保持视觉一致。
enum NotionColorMapper {
    /// 预设 8 色 hex → NotionColor。其他自定义分类 colorHex 调用 `nearest` 兜底。
    private static let presetMap: [String: NotionColor] = [
        // expense 8 色（DefaultSeeder）
        "#FF9500": .orange,   // 餐饮 / 奖金
        "#007AFF": .blue,     // 交通 / 转账
        "#FF2D55": .pink,     // 购物
        "#34C759": .green,    // 居住 / 工资
        "#AF52DE": .purple,   // 娱乐 / 退款
        "#FF3B30": .red,      // 医疗
        "#5856D6": .purple,   // 教育 / 理财
        "#8E8E93": .gray,     // 其他
        // CategoryListView 自定义分类调色板（NotionTheme.swift 引用）
        "#9F6B53": .brown,
        "#CB912F": .yellow
    ]

    static func from(colorHex: String) -> NotionColor {
        let key = colorHex.uppercased()
        if let m = presetMap[key] { return m }
        // 兜底：根据 RGB 距离选最接近的。算力开销可忽略（10 个候选）。
        return nearest(hex: key)
    }

    /// RGB 欧氏距离最近邻；自定义颜色不在 presetMap 时退化路径。
    private static func nearest(hex: String) -> NotionColor {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count >= 6 else { return .gray }
        var rgba: UInt64 = 0
        Scanner(string: String(s.prefix(6))).scanHexInt64(&rgba)
        let r = Double((rgba >> 16) & 0xFF)
        let g = Double((rgba >> 8) & 0xFF)
        let b = Double(rgba & 0xFF)

        // NotionColor.dark text() 系列 RGB（用 dark 主色作为代表点）
        let candidates: [(NotionColor, Double, Double, Double)] = [
            (.gray,   0x9B, 0x9A, 0x97),
            (.brown,  0xBA, 0x85, 0x6F),
            (.orange, 0xC7, 0x7D, 0x48),
            (.yellow, 0xCA, 0x98, 0x49),
            (.green,  0x52, 0x9E, 0x72),
            (.blue,   0x5E, 0x87, 0xC9),
            (.purple, 0x9D, 0x68, 0xD3),
            (.pink,   0xD1, 0x57, 0x96),
            (.red,    0xDF, 0x54, 0x52)
        ]
        var best: NotionColor = .gray
        var bestD = Double.greatestFiniteMagnitude
        for c in candidates {
            let dr = r - c.1, dg = g - c.2, db = b - c.3
            let d = dr * dr + dg * dg + db * db
            if d < bestD { bestD = d; best = c.0 }
        }
        return best
    }
}
