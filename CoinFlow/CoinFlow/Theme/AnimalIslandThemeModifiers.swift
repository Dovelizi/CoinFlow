//  AnimalIslandThemeModifiers.swift
//  CoinFlow · Animal Island 主题专属 View Modifier
//
//  严格对照 animal-island-ui SKILL.md 设计规范：
//  - Card：20px 大圆角 + 奶油白底 + 无 shadow（依赖 border 分层）
//  - Pill/TabBar：暖调柔 shadow + 2px solid 边框
//  - Chip：温暖 bgSecondary 底 + 1.5px light 边框

import SwiftUI

// MARK: - 动物森友会卡片表面（SKILL §2 Card）

/// 对照 SKILL Card 默认：20px 圆角、bgContent 底、NO box-shadow、2px 暖调边框
private struct AnimalIslandCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var fill: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AnimalIslandTheme.borderLight, lineWidth: 2)
            )
    }
}

// MARK: - 动物森友会 dashed 卡片（SKILL §2 Card dashed）

/// dashed 类型卡片：2px dashed 边框 + 稍亮奶油底
struct AnimalIslandDashedCardModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 250/255, green: 248/255, blue: 242/255))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .foregroundColor(Color(hex: "#e8dcc8"))
            )
    }
}

// MARK: - 浮岛胶囊（TabBar）

/// SKILL shadow-base：0 3px 10px 0 rgba(61,52,40,0.10) + 2px solid 边框
private struct AnimalIslandPillModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Capsule(style: .continuous)
                    .fill(AnimalIslandTheme.bgContent)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(AnimalIslandTheme.borderColor, lineWidth: 2)
            )
            .compositingGroup()
            .shadow(color: AnimalIslandTheme.shadowBase, radius: 10, x: 0, y: 3)
    }
}

// MARK: - Chip/标签

private struct AnimalIslandChipModifier: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(AnimalIslandTheme.bgSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(AnimalIslandTheme.borderLight, lineWidth: 1.5)
            )
    }
}

// MARK: - View 扩展（供 LiquidGlassATheme.swift 桥接调用）

extension View {

    /// Animal Island 卡片表面（默认：无 shadow，依赖 border 分层）
    func _aiCard(cornerRadius: CGFloat, fill: Color = AnimalIslandTheme.bgContent) -> some View {
        modifier(AnimalIslandCardModifier(cornerRadius: cornerRadius, fill: fill))
    }

    /// Animal Island dashed 卡片
    func _aiDashedCard(cornerRadius: CGFloat) -> some View {
        modifier(AnimalIslandDashedCardModifier(cornerRadius: cornerRadius))
    }

    /// Animal Island 浮岛胶囊
    func _aiPill() -> some View {
        modifier(AnimalIslandPillModifier())
    }

    /// Animal Island chip
    func _aiChip(radius: CGFloat) -> some View {
        modifier(AnimalIslandChipModifier(radius: radius))
    }
}
