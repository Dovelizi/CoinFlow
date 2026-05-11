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

// MARK: - 应用主题三态枚举

/// 应用全局主题枚举
///
/// - notion: 现有 Notion 风格（实色扁平，浅色为主）
/// - darkLiquid: v4 深炭灰实色（即旧版 "Dark Liquid"，并非真玻璃）
/// - liquidGlass: iOS 26 真·液态玻璃（跟随系统亮暗，使用 .glassEffect API）
enum AppTheme: String, CaseIterable {
    case notion
    case darkLiquid
    case liquidGlass
}

// MARK: - 全局开关（持久化到 UserDefaults）

/// 应用主题运行时存储
///
/// - 新版持久化 key：`theme.app.kind`（String）
/// - 旧版兼容：若新 key 不存在但旧 `theme.lga.enabled` 为 true，则迁移到 .darkLiquid
/// - 兼容计算属性 `isEnabled` 等价 `kind == .darkLiquid`，保旧调用点零改动
final class LGAThemeStore: ObservableObject {

    static let shared = LGAThemeStore()

    private static let storageKey = "theme.app.kind"
    private static let legacyBoolKey = "theme.lga.enabled"

    @Published var kind: AppTheme {
        didSet {
            UserDefaults.standard.set(kind.rawValue, forKey: Self.storageKey)
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Self.storageKey),
           let parsed = AppTheme(rawValue: raw) {
            self.kind = parsed
        } else if defaults.bool(forKey: Self.legacyBoolKey) {
            // 旧版 Dark Liquid 用户：迁移到 darkLiquid
            self.kind = .darkLiquid
        } else {
            self.kind = .notion
        }
    }

    /// 旧 API 兼容：等价 `kind == .darkLiquid`
    var isEnabled: Bool {
        get { kind == .darkLiquid }
        set {
            // 仅当显式 setEnabled(true/false) 才会落到旧语义
            kind = newValue ? .darkLiquid : .notion
        }
    }

    /// 旧 API：开关 darkLiquid（保留以兼容历史调用）
    @MainActor
    func setEnabled(_ newValue: Bool, animated: Bool = true) {
        let target: AppTheme = newValue ? .darkLiquid : .notion
        setKind(target, animated: animated)
    }

    /// 新 API：直接切换三态主题
    @MainActor
    func setKind(_ newValue: AppTheme, animated: Bool = true) {
        guard kind != newValue else { return }
        if animated {
            withAnimation(Motion.glass) {
                kind = newValue
            }
        } else {
            kind = newValue
        }
    }
}

/// 静态查询接口（非响应式，用于 ViewModifier body 内做一次性分支）
enum LGAThemeRuntime {
    /// 旧 API：等价 darkLiquid（保留兼容）
    static var isEnabled: Bool { LGAThemeStore.shared.kind == .darkLiquid }

    /// 新 API：当前主题枚举
    static var kind: AppTheme { LGAThemeStore.shared.kind }

    /// 是否为 Liquid Glass 真玻璃主题
    static var isLiquidGlass: Bool { LGAThemeStore.shared.kind == .liquidGlass }
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
        switch store.kind {
        case .liquidGlass:
            // 真玻璃卡片：iOS 26 .glassEffect()，跟随系统亮暗
            content._lgRealCard(cornerRadius: cornerRadius)
        case .darkLiquid:
            // v5：LGA 模式也尊重调用方的 cornerRadius，主题切换时圆角保持一致
            content.modifier(GlassACardModifier(
                radius: cornerRadius,
                highlight: lgaHighlight,
                shadow: lgaShadow
            ))
        case .notion:
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
        switch store.kind {
        case .liquidGlass:
            // 真玻璃浮岛：iOS 26 .glassEffect(.regular.interactive(), in: .capsule)
            content._lgRealPill()
        case .darkLiquid:
            content.modifier(GlassAPillModifier())
        case .notion:
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
        switch LGAThemeStore.shared.kind {
        case .liquidGlass:
            self._lgRealChip(cornerRadius: radius, tint: tint)
        case .darkLiquid:
            self.modifier(GlassAChipModifier(radius: radius, tint: tint))
        case .notion:
            self
        }
    }
}

// MARK: - 主题感知的画布色

extension Color {
    /// 主流程页面全屏背景
    ///
    /// - notion: 维持原 canvasBG（白/纯黑）
    /// - darkLiquid / liquidGlass: 透明，由 ThemedBackgroundLayer 提供主题专属背景
    static var appCanvas: Color {
        switch LGAThemeStore.shared.kind {
        case .notion:                    return Color.canvasBG
        case .darkLiquid, .liquidGlass:  return Color.clear
        }
    }

    /// Sheet/cover 内页全屏背景（独立 presentation 层级无法透出根背景）
    ///
    /// - notion / darkLiquid：返回原实色（行为不变）
    /// - liquidGlass：返回 clear，由调用点叠加 `themedSheetSurface()` 注入
    ///   `LiquidGlassBackground` 渐变 + `presentationBackground(.clear)`，
    ///   让 sheet 整层呈现真玻璃折射
    static var appSheetCanvas: Color {
        switch LGAThemeStore.shared.kind {
        case .notion:       return Color.canvasBG
        case .darkLiquid:   return LGATheme.canvas
        case .liquidGlass:  return Color.clear
        }
    }
}

// MARK: - 主题感知的 Sheet/Cover 表面修饰器

/// `.themedSheetSurface(kind:)` —— 应用于 sheet / fullScreenCover / popover 的根视图
///
/// 设计目标：sheet 在 `liquidGlass` 主题下整体呈现真玻璃折射感。
///
/// - notion / darkLiquid：等价 `Color.appSheetCanvas.ignoresSafeArea()`，行为不变
/// - liquidGlass：
///   1. 底层叠 `LiquidGlassBackground`（暗夜紫 + 三色光斑）作为色彩内容
///   2. 调用 `.presentationBackground(.clear)` 让 sheet 容器透明，
///      使下层应用主背景能与 sheet 内 `LiquidGlassBackground` 共同形成
///      "玻璃折射" 视觉
///
/// 用法：把现有 sheet 内 `Color.appSheetCanvas.ignoresSafeArea()` 替换为
///       `.themedSheetSurface()` 即可
private struct ThemedSheetSurfaceModifier: ViewModifier {
    @ObservedObject private var store = LGAThemeStore.shared
    var kind: LGAPageKind

    func body(content: Content) -> some View {
        ZStack {
            switch store.kind {
            case .liquidGlass:
                // Sheet 场景专用暗化：
                // 直接复用全屏 `LiquidGlassBackground` 在 200~600pt 高度的 sheet 里会被
                // 420pt 半径的顶部靖蓝光斑整体覆盖，叠 `.screen` 后观感偏亮（"奶白"），
                // 与全屏主题背景对不上。这里在玻璃背景之上叠一层 25% 黑遮罩，
                // 保留玻璃折射色彩信息的同时让整体亮度回到主页同档。
                // 只作用于 sheet，全屏页（`themedBackground`）不受影响。
                ZStack {
                    LiquidGlassBackground(kind: kind)
                    Color.black.opacity(0.25).ignoresSafeArea()
                }
            case .darkLiquid:
                LGATheme.canvas.ignoresSafeArea()
            case .notion:
                Color.canvasBG.ignoresSafeArea()
            }
            content
        }
        .modifier(ThemedPresentationBackgroundModifier())
    }
}

/// `.themedPresentationBackground()` —— 仅 liquidGlass 主题给 sheet 容器透明化
///
/// 通过 `.presentationBackground(.clear)` 让 sheet 自身的灰色卡背景消失，
/// 露出我们自绘的 `LiquidGlassBackground` 渐变 + 折射玻璃效果。
private struct ThemedPresentationBackgroundModifier: ViewModifier {
    @ObservedObject private var store = LGAThemeStore.shared

    func body(content: Content) -> some View {
        if store.kind == .liquidGlass {
            if #available(iOS 16.4, *) {
                content.presentationBackground(.clear)
            } else {
                content
            }
        } else {
            content
        }
    }
}

extension View {
    /// 主题感知的 sheet/cover 表面：
    /// - 在 liquidGlass 主题下叠 LiquidGlassBackground 并透明化 sheet 容器
    /// - 在 notion / darkLiquid 主题下回退到旧实色背景，行为完全等价
    ///
    /// 使用方式：替换原来 sheet 内的 `Color.appSheetCanvas.ignoresSafeArea()` 为
    /// `.themedSheetSurface()` 即可（注意要包裹整个 sheet 内容）
    func themedSheetSurface(kind: LGAPageKind = .default) -> some View {
        modifier(ThemedSheetSurfaceModifier(kind: kind))
    }

    /// 仅 liquidGlass 主题对 sheet 容器自身做透明化（用于无法直接包裹 ZStack 的场景）
    func themedPresentationBackground() -> some View {
        modifier(ThemedPresentationBackgroundModifier())
    }
}

// MARK: - 主题感知的页面背景修饰器

private struct ThemedPageBackground: ViewModifier {
    @ObservedObject private var store = LGAThemeStore.shared
    var kind: LGAPageKind

    func body(content: Content) -> some View {
        ZStack {
            switch store.kind {
            case .liquidGlass:
                LiquidGlassBackground(kind: kind)
            case .darkLiquid:
                LiquidGlassABackground(kind: kind)
            case .notion:
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
        switch store.kind {
        case .liquidGlass:
            LiquidGlassBackground(kind: kind)
        case .darkLiquid:
            LiquidGlassABackground(kind: kind)
        case .notion:
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
