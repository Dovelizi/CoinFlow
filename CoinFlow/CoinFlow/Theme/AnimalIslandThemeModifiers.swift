//  AnimalIslandThemeModifiers.swift
//  CoinFlow · Animal Island 主题专属 View Modifier
//
//  核心：游戏按键 3D 立体效果 —— 底部纯色层 offset 模拟 box-shadow 的 solid spread，
//  按下时阴影收缩 + 自身下压，还原动森"按钮被按进去"的触感。

import SwiftUI

// MARK: - 游戏按键 3D 立体卡片

private struct AnimalIslandCardModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AnimalIslandTheme.bgContent)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AnimalIslandTheme.borderLight, lineWidth: 2)
            )
            // 暖色 3D 阴影（spec: 0 4px 10px rgba(107,92,67,0.42)）
            .compositingGroup()
            .shadow(color: Color(red: 107/255, green: 92/255, blue: 67/255).opacity(0.35),
                    radius: 10, x: 0, y: 4)
    }
}

// MARK: - 浮岛胶囊（TabBar）

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
            .shadow(color: Color(red: 61/255, green: 52/255, blue: 40/255).opacity(0.16),
                    radius: 12, x: 0, y: 5)
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

    /// Animal Island 卡片表面
    func _aiCard(cornerRadius: CGFloat) -> some View {
        modifier(AnimalIslandCardModifier(cornerRadius: cornerRadius))
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
