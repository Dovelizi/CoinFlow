//  AmountTintStore.swift
//  CoinFlow · 收支金额配色
//
//  两套 palette：
//   - system：iOS 系统色（默认）
//       收入 #34C759  支出 #FF3B30
//   - vivid：Material + iOS 混搭
//       收入 #00C853  支出 #FF5252
//
//  设计：
//  - 通过 UserSettings 持久化（key = "theme.amount_palette"）
//  - @MainActor ObservableObject；SettingsView 切换时动画过渡
//  - 全局单例 shared；配合 Color 扩展暴露 `Color.incomeGreen` / `Color.expenseRed`
//    SwiftUI View 可通过 @StateObject / @EnvironmentObject 订阅变化自动刷新
//  - Color 静态便捷属性读 shared.palette 当前值（非响应式，供非 @ObservedObject
//    场景使用；响应式场景用 @EnvironmentObject AmountTintStore 注入）
//
//  迁移策略：历史代码里的 dangerRed / statusSuccess 仍保留不动（作为 UI 状态色用途
//  保留），收支金额场景改用新 token `incomeGreen` / `expenseRed`。

import SwiftUI

enum AmountPalette: String, Codable, CaseIterable, Identifiable {
    /// iOS 系统色（默认）
    case system
    /// Material + iOS 混搭：收入更纯绿，支出更亮
    case vivid
    /// Notion 原生：低饱和哑光，与深色 canvas 最融合
    case notion
    /// Tailwind Emerald + Coral：优雅现代
    case emerald
    /// 深森林 + 枫红：复古信纸质感
    case forest

    var id: String { rawValue }

    var incomeHex: String {
        switch self {
        case .system:  return "#34C759"   // iOS 系统绿
        case .vivid:   return "#00C853"   // Material Design 绿
        case .notion:  return "#448361"   // Notion dark green
        case .emerald: return "#10B981"   // Tailwind Emerald 500
        case .forest:  return "#2E7D5E"   // 深森林绿
        }
    }

    var expenseHex: String {
        switch self {
        case .system:  return "#FF3B30"   // iOS 系统红
        case .vivid:   return "#FF5252"   // Material 西瓜红
        case .notion:  return "#D44C47"   // Notion dark red
        case .emerald: return "#F87171"   // Tailwind Coral
        case .forest:  return "#C75450"   // 枫红
        }
    }

    var displayName: String {
        switch self {
        case .system:  return "系统"
        case .vivid:   return "鲜亮"
        case .notion:  return "Notion 原生"
        case .emerald: return "墨绿珊瑚"
        case .forest:  return "森林枫红"
        }
    }

    var subtitle: String {
        switch self {
        case .system:  return "iOS 标准绿红"
        case .vivid:   return "翡翠绿 + 西瓜红"
        case .notion:  return "低饱和哑光，深色下护眼"
        case .emerald: return "Tailwind 生态，优雅现代"
        case .forest:  return "复古信纸质感"
        }
    }
}

@MainActor
final class AmountTintStore: ObservableObject {

    static let shared = AmountTintStore()

    /// 持久化 key
    private static let settingsKey = "theme.amount_palette"

    @Published private(set) var palette: AmountPalette

    private init() {
        let raw = SQLiteUserSettingsRepository.shared.get(key: Self.settingsKey) ?? ""
        self.palette = AmountPalette(rawValue: raw) ?? .system
    }

    /// 外部切换入口；animated = true 走 Motion.smooth
    func setPalette(_ new: AmountPalette, animated: Bool = true) {
        guard new != palette else { return }
        if animated {
            withAnimation(Motion.smooth) {
                self.palette = new
            }
        } else {
            self.palette = new
        }
        SQLiteUserSettingsRepository.shared.set(key: Self.settingsKey, value: new.rawValue)
    }

    // MARK: - 便捷颜色访问

    var incomeColor: Color { Color(hex: palette.incomeHex) }
    var expenseColor: Color { Color(hex: palette.expenseHex) }

    /// 统一入口：按 CategoryKind 返回
    func color(for kind: CategoryKind) -> Color {
        kind == .income ? incomeColor : expenseColor
    }

    /// 按 BillDirection 返回（ParsedBill 等语音场景用）
    func color(for direction: BillDirection) -> Color {
        direction == .income ? incomeColor : expenseColor
    }
}

// MARK: - Color 便捷扩展（非响应式，读 shared 当前值）
//
// SwiftUI View body 只在 MainActor 执行，所以 Color 这两个 static var
// 用 MainActor.assumeIsolated 访问 shared 是安全的。
// （使用方如果在非 MainActor 上下文读这两个属性，会在 runtime 触发断言 —
//  实际 SwiftUI UI 代码不会走到那里。）

extension Color {
    /// 当前配色下的收入绿。**非响应式**：用于 static context（如 Capsule.fill）
    /// 响应式场景应通过 `@EnvironmentObject AmountTintStore` 订阅
    static var incomeGreen: Color {
        MainActor.assumeIsolated { AmountTintStore.shared.incomeColor }
    }

    /// 当前配色下的支出红。**非响应式**：同上
    static var expenseRed: Color {
        MainActor.assumeIsolated { AmountTintStore.shared.expenseColor }
    }
}
