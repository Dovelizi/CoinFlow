// LiquidGlassATheme.swift
//
// CoinFlow 的 "Dark Glass" 主题（暗色 · 实色深炭灰）。
//
// ⚠️ v4 重构（2026-05-10）— 严格对齐参考图（image.a18a87f8a0）:
//   - 背景：#0A0A0C 接近纯黑炭灰，无任何光晕渐变（参考图整屏纯净）
//   - 卡片：#1C1C1F 实色（去掉 ultraThinMaterial 与白色描边，"Dark Glass" 名义保留但视觉转向 Solid Charcoal）
//   - 选中态描边：#5B7FFF 冷蓝紫（参考图外观切换器卡边色）
//   - Toggle：iOS 系统蓝（让 SwiftUI 原生 Toggle 与参考图一致）
//
// 对外 API 契约保持不变（25 个消费者依赖）：
//   Color.appCanvas / Color.appSheetCanvas
//   View.cardSurface(...) / View.appTabPillBackground() / View.glassChipIfLGA(...)
//   View.themedBackground(kind:) / View.themedRootBackground() / ThemedBackgroundLayer(kind:)
//   LGATheme.canvas / cardFill / cardStroke / dgAccent / accentIndigo / accentViolet / accentIce
//   LGATheme.radiusSM / radiusMD / radiusLG / radiusXL / space2~space7
//   LGATheme.glassStroke / glassDivider / chipBg / chipBgStrong
//   LGATheme.textPrimary / textSecondary / segmentTrack / segmentSelected / switchTrackOff
//   LGATheme.accentSelection / ambientGlow / ambientGlowAlt
//   LGAThemeStore.shared / setEnabled(_:animated:)  / LGAThemeRuntime.isEnabled
//   LGAPageKind 枚举
//
// 与 Notion 主题的解耦不变：
//   - LGA 关闭：完全等价 Notion 视觉
//   - LGA 开启：实色深炭灰直接对齐参考图

import SwiftUI

// MARK: - 全局开关（持久化到 UserDefaults）

/// LGA 主题运行时开关（key = "theme.lga.enabled"）
final class LGAThemeStore: ObservableObject {

    static let shared = LGAThemeStore()

    private static let storageKey = "theme.lga.enabled"

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.storageKey) }
    }

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.storageKey)
    }

    @MainActor
    func setEnabled(_ newValue: Bool, animated: Bool = true) {
        guard isEnabled != newValue else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) {
                isEnabled = newValue
            }
        } else {
            isEnabled = newValue
        }
    }
}

/// 静态查询接口（非响应式，用于 ViewModifier body 内做一次性分支）
enum LGAThemeRuntime {
    static var isEnabled: Bool { LGAThemeStore.shared.isEnabled }
}

// MARK: - 主题常量（v4 实色深炭灰）

enum LGATheme {

    // MARK: 圆角（v5 与 Notion 完全统一，主题切换仅样式不变结构）
    static let radiusSM: CGFloat = 10
    static let radiusMD: CGFloat = 12
    static let radiusLG: CGFloat = 14      // v5 由 18 → 14，主题切换时圆角不变
    static let radiusXL: CGFloat = 18

    // MARK: 间距
    static let space2: CGFloat = 4
    static let space3: CGFloat = 6
    static let space4: CGFloat = 8
    static let space5: CGFloat = 12
    static let space6: CGFloat = 16
    static let space7: CGFloat = 24

    // MARK: 基础色（v4 实色深炭灰）

    /// 桌面底色：#0A0A0C 接近纯黑炭灰，无渐变无光晕
    static let canvas: Color = Color(red: 0x0A / 255.0,
                                     green: 0x0A / 255.0,
                                     blue: 0x0C / 255.0)

    /// 桌面顶色（保留 API；与 canvas 同色）
    static let canvasTop: Color = canvas

    /// 卡片填充：#1C1C1F 实色（v4 不透明，无 material 模糊）
    static let cardFill: Color = Color(red: 0x1C / 255.0,
                                       green: 0x1C / 255.0,
                                       blue: 0x1F / 255.0)

    /// 卡片描边：透明（v4 完全去除卡片描边；保留 token 兼容旧 API）
    static let cardStroke: Color = Color.clear

    // MARK: Accent（冷蓝紫 · #5B7FFF · 对齐参考图）

    /// 主 accent · #5B7FFF（冷蓝紫；选中描边 / Toggle 不再用此色）
    static let accentIndigo: Color = Color(red: 0x5B / 255.0,
                                           green: 0x7F / 255.0,
                                           blue: 0xFF / 255.0)

    /// 选中态描边 · 与参考图外观切换器边色一致 #5B7FFF
    static let accentSelection: Color = Color(red: 0x5B / 255.0,
                                              green: 0x7F / 255.0,
                                              blue: 0xFF / 255.0)

    /// 环境光（v4 不再使用；保留 API 兼容旧调用点）
    static let ambientGlow: Color = Color.clear
    static let ambientGlowAlt: Color = Color.clear

    /// 兼容保留（紫/冰蓝；非主路径使用）
    static let accentViolet: Color = Color(red: 0xAF / 255.0,
                                           green: 0x52 / 255.0,
                                           blue: 0xDE / 255.0)
    static let accentIce: Color = Color(red: 0x5A / 255.0,
                                        green: 0xC8 / 255.0,
                                        blue: 0xFA / 255.0)

    /// 当前 LGA 主 accent
    static let dgAccent: Color = accentIndigo

    // MARK: 玻璃描边 / 分割（v4 兼容保留；都改极淡或透明）

    static let glassStroke: Color = Color.clear
    static let glassDivider: Color = Color.white.opacity(0.05)

    static let chipBg: Color = Color.white.opacity(0.06)
    static let chipBgStrong: Color = Color.white.opacity(0.10)

    // MARK: 文字色（v4 不变）

    /// 主标题 / 选项主文本：#FFFFFF
    static let textPrimary: Color = Color.white

    /// 副标题 / 说明文字：#8E8E93（参考图副标题颜色）
    static let textSecondary: Color = Color(red: 0x8E / 255.0,
                                            green: 0x8E / 255.0,
                                            blue: 0x93 / 255.0)

    // MARK: 分段控制器

    /// 分段控制器容器底色：与 cardFill 一致（v4）
    static let segmentTrack: Color = cardFill

    /// 分段控制器选中项底色（保留 API）
    static let segmentSelected: Color = cardFill

    /// Toggle 关闭态轨道色（保留 API；SwiftUI 原生 Toggle 不可控）
    static let switchTrackOff: Color = Color(red: 0x39 / 255.0,
                                             green: 0x39 / 255.0,
                                             blue: 0x3D / 255.0)
}

// MARK: - 页面类别枚举（兼容保留；v4 全局统一无差异）

enum LGAPageKind {
    case home
    case records
    case stats
    case settings
    case categories
    case sync
    case onboarding
    case lock
    case `default`
}

// MARK: - 全屏背景（v4 纯净深炭灰，无光晕）

struct LiquidGlassABackground: View {

    /// 页面类别形参保留（API 兼容）；v4 全局统一无差异
    var kind: LGAPageKind = .default

    var body: some View {
        // v4 单层纯色背景，参考图整屏纯净深炭灰
        LGATheme.canvas
            .ignoresSafeArea()
    }
}

// MARK: - 实色卡片（v4 无 material / 无描边 / 圆角 18）

private struct GlassACardModifier: ViewModifier {
    var radius: CGFloat
    /// 兼容旧参数（已废弃；v4 无顶白 rim light）
    var highlight: Bool
    /// 兼容旧参数（已废弃；v4 卡片无阴影）
    var shadow: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LGATheme.cardFill)
            )
    }
}

// MARK: - 浮岛胶囊（TabBar）— v4 实色深灰 + 极轻阴影衬托悬浮感

private struct GlassAPillModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Capsule(style: .continuous)
                    .fill(LGATheme.cardFill)
            )
            .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
    }
}

// MARK: - chip（小标签）— v4 简化为实色低对比

private struct GlassAChipModifier: ViewModifier {
    var radius: CGFloat
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tint?.opacity(0.18) ?? Color.white.opacity(0.06))
            )
    }
}

// MARK: - 主题感知桥接（业务视图调用入口；API 不变）

private struct CardSurfaceModifier: ViewModifier {
    @ObservedObject private var store = LGAThemeStore.shared
    var cornerRadius: CGFloat
    var notionFill: Color
    var notionStroke: Color?
    var lgaHighlight: Bool
    var lgaShadow: Bool

    func body(content: Content) -> some View {
        if store.isEnabled {
            // v5：LGA 模式也尊重调用方的 cornerRadius，主题切换时圆角保持一致
            content.modifier(GlassACardModifier(
                radius: cornerRadius,
                highlight: lgaHighlight,
                shadow: lgaShadow
            ))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(notionFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(notionStroke ?? .clear, lineWidth: notionStroke == nil ? 0 : 0.5)
                )
        }
    }
}

private struct AppTabPillBackgroundModifier: ViewModifier {
    @ObservedObject private var store = LGAThemeStore.shared

    func body(content: Content) -> some View {
        if store.isEnabled {
            content.modifier(GlassAPillModifier())
        } else {
            content
                .background(
                    Capsule()
                        .fill(.regularMaterial)
                        .overlay(
                            Capsule().stroke(Color.divider.opacity(0.5),
                                             lineWidth: 0.5)
                        )
                )
        }
    }
}

extension View {
    /// 主题感知卡片底层
    /// - LGA 开启：实色深炭灰卡片 18pt 圆角，无描边无 material
    /// - LGA 关闭：Notion 风 RoundedRectangle 实色
    func cardSurface(cornerRadius: CGFloat,
                     notionFill: Color = .surfaceOverlay,
                     notionStroke: Color? = nil,
                     lgaRefraction: Bool = true,
                     lgaHighlight: Bool = true,
                     lgaShadow: Bool = true) -> some View {
        _ = lgaRefraction
        return modifier(CardSurfaceModifier(
            cornerRadius: cornerRadius,
            notionFill: notionFill,
            notionStroke: notionStroke,
            lgaHighlight: lgaHighlight,
            lgaShadow: lgaShadow
        ))
    }

    func appTabPillBackground() -> some View {
        modifier(AppTabPillBackgroundModifier())
    }

    @ViewBuilder
    func glassChipIfLGA(radius: CGFloat = 8, tint: Color? = nil) -> some View {
        if LGAThemeRuntime.isEnabled {
            modifier(GlassAChipModifier(radius: radius, tint: tint))
        } else {
            self
        }
    }
}

// MARK: - 主题感知的画布色

extension Color {
    /// 主流程页面全屏背景
    static var appCanvas: Color {
        LGAThemeRuntime.isEnabled ? Color.clear : Color.canvasBG
    }

    /// Sheet/cover 内页全屏背景（独立 presentation 层级无法透出根背景）
    static var appSheetCanvas: Color {
        LGAThemeRuntime.isEnabled ? LGATheme.canvas : Color.canvasBG
    }
}

// MARK: - 主题感知的页面背景修饰器

private struct ThemedPageBackground: ViewModifier {
    @ObservedObject private var store = LGAThemeStore.shared
    var kind: LGAPageKind

    func body(content: Content) -> some View {
        ZStack {
            if store.isEnabled {
                LiquidGlassABackground(kind: kind)
            } else {
                Color.canvasBG.ignoresSafeArea()
            }
            content
        }
    }
}

extension View {
    func themedBackground(kind: LGAPageKind = .default) -> some View {
        modifier(ThemedPageBackground(kind: kind))
    }
}

struct ThemedBackgroundLayer: View {
    @ObservedObject private var store = LGAThemeStore.shared
    var kind: LGAPageKind

    init(kind: LGAPageKind = .default) {
        self.kind = kind
    }

    var body: some View {
        if store.isEnabled {
            LiquidGlassABackground(kind: kind)
        } else {
            Color.canvasBG.ignoresSafeArea()
        }
    }
}

// MARK: - 主题感知的根容器（API 兼容保留）

struct ThemeRootBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

extension View {
    func themedRootBackground() -> some View {
        modifier(ThemeRootBackground())
    }
}
