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
//  并提供 View 扩展 `.pressable()` 和 `.tappableCard()` 用于无 Button 包裹的场景。

import SwiftUI

// MARK: - 1. Scale style（默认）

/// 默认按下反馈：缩放 + 透明度 + spring 回弹 + 轻触觉
struct PressableScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var pressedOpacity: CGFloat = 0.85
    /// 是否触发触觉反馈（仅在 down → up 完成 tap 时触发，避免拖拽连发）
    var haptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(Motion.snap, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { newValue in
                // 按下瞬间触发轻触觉（松开不再触发，避免双重反馈）
                if newValue && haptic {
                    Haptics.tap()
                }
            }
    }
}

// MARK: - 2. Soft style（大卡片）

/// 卡片按下反馈：克制的 0.985 缩放，避免大块视觉跳动
struct PressableSoftStyle: ButtonStyle {
    var haptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(Motion.snap, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { newValue in
                if newValue && haptic {
                    Haptics.soft()
                }
            }
    }
}

// MARK: - 3. TabItem style（TabBar 胶囊项）

/// TabBar 胶囊项专用：缩放更明显（0.94），透明度更深（0.7），强调"按下了"
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
                    .fill(configuration.isPressed ? pressedFill : Color.clear)
                    .animation(Motion.snap, value: configuration.isPressed)
            )
            .contentShape(Rectangle())
    }
}

// MARK: - 5. Icon style（顶栏 / 工具栏图标）

/// 顶栏 / 工具栏的小图标按钮：缩放更"敲"（0.88）+ 透明度大幅变化（0.6）+ 轻触觉
struct PressableIconStyle: ButtonStyle {
    var haptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(Motion.snap, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { newValue in
                if newValue && haptic {
                    Haptics.tap()
                }
            }
    }
}

// MARK: - 6. Accent style（主 CTA 按钮）

/// 主操作按钮："开启 CoinFlow"、"保存"、"立即同步" 等。比 Scale 更"重"：medium 触觉
struct PressableAccentStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    var pressedOpacity: CGFloat = 0.88

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(Motion.snap, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { newValue in
                if newValue { Haptics.medium() }
            }
    }
}

// MARK: - View 扩展：在非 Button 场景下手动注入按下反馈

/// 在 onTapGesture 等场景下使用：通过 DragGesture(minimumDistance: 0) 检测按压。
/// 适合无法用 Button 包装的复杂 hit-test 场景（如带 swipeActions 的 row）。
struct PressableModifier: ViewModifier {
    var scale: CGFloat = 0.985
    var haptic: Bool = true
    @State private var pressed = false

    func body(content: Content) -> some View {
        content
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
                    .onEnded { _ in
                        pressed = false
                    }
            )
    }
}

/// TappableCard：用于卡片整体可点击的场景（不能用 Button 包，比如卡片内含 NavigationLink）。
/// 提供与 PressableSoftStyle 一致的视觉反馈：scale 0.985 + opacity 0.92 + soft 触觉
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
                    .onEnded { _ in
                        pressed = false
                    }
            )
    }
}

extension View {
    /// 通用按下反馈（仅缩放/透明度/触觉，不修改背景）
    func pressable(scale: CGFloat = 0.985, haptic: Bool = true) -> some View {
        modifier(PressableModifier(scale: scale, haptic: haptic))
    }

    /// 整张卡片可点击（同 PressableSoftStyle，但不需要 Button 包裹）
    func tappableCard(enabled: Bool = true, onTap: (() -> Void)? = nil) -> some View {
        modifier(TappableCardModifier(enabled: enabled, onTap: onTap))
    }
}

// MARK: - ButtonStyle 简写工厂

extension ButtonStyle where Self == PressableScaleStyle {
    /// 默认按下反馈：scale 0.97 + 透明度 + 触觉
    static var pressable: PressableScaleStyle { PressableScaleStyle() }
    static func pressable(haptic: Bool) -> PressableScaleStyle {
        PressableScaleStyle(haptic: haptic)
    }
}

extension ButtonStyle where Self == PressableSoftStyle {
    /// 卡片按下反馈：scale 0.985，更克制
    static var pressableSoft: PressableSoftStyle { PressableSoftStyle() }
}

extension ButtonStyle where Self == PressableTabItemStyle {
    /// TabBar 胶囊项专用
    static var pressableTab: PressableTabItemStyle { PressableTabItemStyle() }
}

extension ButtonStyle where Self == PressableRowStyle {
    /// 列表行按下反馈（仅背景色变化）
    static var pressableRow: PressableRowStyle { PressableRowStyle() }
}

extension ButtonStyle where Self == PressableIconStyle {
    /// 顶栏 / 工具栏图标按钮
    static var pressableIcon: PressableIconStyle { PressableIconStyle() }
}

extension ButtonStyle where Self == PressableAccentStyle {
    /// 主 CTA 按钮（保存、开启 CoinFlow、立即同步）
    static var pressableAccent: PressableAccentStyle { PressableAccentStyle() }
}