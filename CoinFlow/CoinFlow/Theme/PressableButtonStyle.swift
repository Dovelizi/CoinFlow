//  PressableButtonStyle.swift
//  CoinFlow · 通用"按下反馈"按钮样式
//
//  原项目大量按钮使用 .buttonStyle(.plain)，导致点击无任何视觉反馈，
//  在液玻璃/暗色卡片上尤其"哑"。本文件提供 6 个按钮样式 + 2 个 modifier：
//
//  1. PressableScaleStyle ── 默认通用：scale 0.97 + opacity 0.85，spring 弹回
//  2. PressableSoftStyle  ── 大卡片用：scale 0.985，更克制
//  3. PressableTabItemStyle ── TabBar 胶囊项用：scale 0.94 + opacity 0.7
//  4. PressableRowStyle   ── 列表行用：仅背景色变化，不缩放（避免 list cell 抖动）
//  5. PressableIconStyle  ── 顶栏图标按钮：scale 0.88 + opacity 0.6（更"敲实"）
//  6. PressableAccentStyle── 主 CTA 按钮：scale 0.96 + brightness 微暗 + medium 触觉
//
//  7. AnimalIslandButtonStyle ── 动森 3D 游戏按键（Capsule + 底部厚阴影 + 下压动画）
//  8. AnimalIslandButtonSurface ── 按钮表面 ViewModifier，供 label 直接调用
//
//  主题桥接：Animal Island 激活时，pressableAccent / pressableSoft 自动注入 3D 游戏反馈。

import SwiftUI

// MARK: - 0. Animal Island 3D 游戏按钮表面 Modifier

/// 给任意按钮 label 套上 Animal Island 3D 游戏按键表面。
///
/// Web spec 等价：
/// - Capsule / pill 形（radius 50px）
/// - `box-shadow: 0 5px 0 0 #bdaea0`
/// - 按压时自身下移 2pt，阴影收缩到 1pt
struct AnimalIslandButtonSurface: ViewModifier {
    var isPressed: Bool
    var fill: Color = AnimalIslandTheme.bgCanvas
    var borderColor: Color = AnimalIslandTheme.bgCanvas
    var shadowColor: Color = AnimalIslandTheme.shadowBtn

    func body(content: Content) -> some View {
        content
            .background(
                Capsule(style: .continuous)
                    .fill(shadowColor)
                    .offset(y: isPressed ? 1 : 5)
            )
            .background(
                Capsule(style: .continuous)
                    .fill(fill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 2)
            )
            .offset(y: isPressed ? 2 : 0)
    }
}

/// 将 View 套上 Animal Island 游戏按键表面（底部 3D 阴影 + pill 形）。
/// 调用方仍需自行处理 scale/opacity 动画。
extension View {
    func aiButtonSurface(isPressed: Bool = false,
                         fill: Color = AnimalIslandTheme.bgCanvas,
                         borderColor: Color = AnimalIslandTheme.bgCanvas,
                         shadowColor: Color = AnimalIslandTheme.shadowBtn) -> some View {
        modifier(AnimalIslandButtonSurface(
            isPressed: isPressed,
            fill: fill,
            borderColor: borderColor,
            shadowColor: shadowColor
        ))
    }
}

// MARK: - 1. Scale style（默认）

/// 默认按下反馈：缩放 + 透明度 + spring 回弹 + 轻触觉
struct PressableScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var pressedOpacity: CGFloat = 0.85
    var haptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(ConditionalAIButtonSurface(isPressed: configuration.isPressed))
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(Motion.snap, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { newValue in
                if newValue && haptic { Haptics.tap() }
            }
    }
}

// MARK: - 2. Soft style（大卡片）

/// 卡片/行按下反馈：克制的 0.985 缩放，避免大块视觉跳动。
/// Animal Island 主题时自动注入 3D 游戏按键表面。
struct PressableSoftStyle: ButtonStyle {
    var haptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(ConditionalAIButtonSurface(isPressed: configuration.isPressed))
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(Motion.snap, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { newValue in
                if newValue && haptic { Haptics.soft() }
            }
    }
}

// MARK: - 3. TabItem style（TabBar 胶囊项）

struct PressableTabItemStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(Motion.snap, value: configuration.isPressed)
    }
}

// MARK: - 4. Row style（列表行）

/// 列表行按下反馈：仅背景色变化，不缩放（避免相邻 cell 视觉抖动）
struct PressableRowStyle: ButtonStyle {
    var pressedFill: Color = Color.white.opacity(0.06)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Rectangle()
                    .fill(
                        configuration.isPressed
                            ? (LGAThemeRuntime.isAnimalIsland
                               ? AnimalIslandTheme.primaryColor.opacity(0.12)
                               : pressedFill)
                            : Color.clear
                    )
                    .animation(Motion.snap, value: configuration.isPressed)
            )
            .contentShape(Rectangle())
    }
}

// MARK: - 5. Icon style（顶栏 / 工具栏图标）

struct PressableIconStyle: ButtonStyle {
    var haptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(Motion.snap, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { newValue in
                if newValue && haptic { Haptics.tap() }
            }
    }
}

// MARK: - 6. Accent style（主 CTA 按钮）

/// 主操作按钮。"开启 CoinFlow"、"保存"、"立即同步" 等。
/// Animal Island 主题时自动注入 3D 游戏按键：游戏黄色底 + 底部厚阴影 + 下压动画。
struct PressableAccentStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    var pressedOpacity: CGFloat = 0.88

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(AccentAIButtonSurface(isPressed: configuration.isPressed))
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(Motion.snap, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { newValue in
                if newValue { Haptics.medium() }
            }
    }
}

// MARK: - 8. Animal Island 游戏按键 3D 立体按钮（显式使用）

/// 显式指定 Animal Island 3D 游戏按键（不依赖主题开关）。
/// 背景：bgCanvas + pill 形 + 底部 5pt 阴影 + 按压下压 2pt
struct AnimalIslandButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var fill: Color = AnimalIslandTheme.bgCanvas
    var borderColor: Color = AnimalIslandTheme.bgCanvas
    var shadowColor: Color = AnimalIslandTheme.shadowBtn

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .aiButtonSurface(
                isPressed: configuration.isPressed,
                fill: fill,
                borderColor: borderColor,
                shadowColor: shadowColor
            )
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(Motion.snap, value: configuration.isPressed)
    }
}

// MARK: - Conditional AI wrappers（主题感知桥接）

/// 仅当 Animal Island 主题激活时注入 3D 游戏按键表面；否则透传。
private struct ConditionalAIButtonSurface: ViewModifier {
    var isPressed: Bool

    func body(content: Content) -> some View {
        if LGAThemeRuntime.isAnimalIsland {
            content.aiButtonSurface(isPressed: isPressed)
        } else {
            content
        }
    }
}

/// Accent 版 AI 表面：游戏黄色底（#ffcc00）+ error shadow 用于 danger
private struct AccentAIButtonSurface: ViewModifier {
    var isPressed: Bool
    @ObservedObject private var store = LGAThemeStore.shared

    func body(content: Content) -> some View {
        if store.kind == .animalIsland {
            content.aiButtonSurface(
                isPressed: isPressed,
                fill: AnimalIslandTheme.focusYellow,
                borderColor: AnimalIslandTheme.focusYellow,
                shadowColor: AnimalIslandTheme.focusYellowDark
            )
        } else {
            content
        }
    }
}

// MARK: - View 扩展：在非 Button 场景下手动注入按下反馈

struct PressableModifier: ViewModifier {
    var scale: CGFloat = 0.985
    var haptic: Bool = true
    @State private var pressed = false

    func body(content: Content) -> some View {
        content
            .modifier(ConditionalAIButtonSurface(isPressed: pressed))
            .scaleEffect(pressed ? scale : 1.0)
            .opacity(pressed ? 0.92 : 1.0)
            .animation(Motion.snap, value: pressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed {
                            pressed = true
                            if haptic { Haptics.tap() }
                        }
                    }
                    .onEnded { _ in pressed = false }
            )
    }
}

struct TappableCardModifier: ViewModifier {
    var enabled: Bool = true
    @State private var pressed = false
    var onTap: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.985 : 1.0)
            .opacity(pressed ? 0.92 : 1.0)
            .animation(Motion.snap, value: pressed)
            .contentShape(Rectangle())
            .onTapGesture {
                guard enabled else { return }
                Haptics.soft()
                onTap?()
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard enabled, !pressed else { return }
                        pressed = true
                    }
                    .onEnded { _ in pressed = false }
            )
    }
}

extension View {
    func pressable(scale: CGFloat = 0.985, haptic: Bool = true) -> some View {
        modifier(PressableModifier(scale: scale, haptic: haptic))
    }

    func tappableCard(enabled: Bool = true, onTap: (() -> Void)? = nil) -> some View {
        modifier(TappableCardModifier(enabled: enabled, onTap: onTap))
    }
}

// MARK: - ButtonStyle 简写工厂

extension ButtonStyle where Self == PressableScaleStyle {
    static var pressable: PressableScaleStyle { PressableScaleStyle() }
    static func pressable(haptic: Bool) -> PressableScaleStyle {
        PressableScaleStyle(haptic: haptic)
    }
}

extension ButtonStyle where Self == PressableSoftStyle {
    static var pressableSoft: PressableSoftStyle { PressableSoftStyle() }
}

extension ButtonStyle where Self == PressableTabItemStyle {
    static var pressableTab: PressableTabItemStyle { PressableTabItemStyle() }
}

extension ButtonStyle where Self == PressableRowStyle {
    static var pressableRow: PressableRowStyle { PressableRowStyle() }
}

extension ButtonStyle where Self == PressableIconStyle {
    static var pressableIcon: PressableIconStyle { PressableIconStyle() }
}

extension ButtonStyle where Self == PressableAccentStyle {
    static var pressableAccent: PressableAccentStyle { PressableAccentStyle() }
}

extension ButtonStyle where Self == AnimalIslandButtonStyle {
    static var animalIsland: AnimalIslandButtonStyle { AnimalIslandButtonStyle() }
    static func animalIsland(fill: Color, borderColor: Color? = nil, shadowColor: Color? = nil) -> AnimalIslandButtonStyle {
        AnimalIslandButtonStyle(
            fill: fill,
            borderColor: borderColor ?? fill,
            shadowColor: shadowColor ?? AnimalIslandTheme.shadowBtn
        )
    }
}