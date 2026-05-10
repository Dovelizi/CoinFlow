// LiquidGlassRealTheme.swift
//
// CoinFlow · 第三主题「Liquid Glass」（真·iOS 26 液态玻璃）
// ─────────────────────────────────────────────────────────────
// 设计目标：
//   - 严格遵循 iOS 26 Liquid Glass 设计语言：折射、反光、互动、流变
//   - 完全使用原生 SwiftUI API：`.glassEffect(...)`、`GlassEffectContainer`
//   - 跟随系统明暗模式（不强制深色），文字色板提供 light/dark 双值
//   - 以独立"玻璃修饰器"对外提供 API，不替换/不污染既有 LGATheme
//
// 主题切换桥接位于 LiquidGlassATheme.swift 中 cardSurface / appTabPillBackground
// 等修饰器内通过 AppThemeStore.shared.kind 三态分支接入本文件提供的修饰器。
//
// 命名约定：
//   - LiquidGlass*  → 真玻璃主题专属常量 / 修饰器 / 视图
//   - 与 LGATheme（v4 实色深炭灰）解耦，二者并存

import SwiftUI

// MARK: - 设计 Token

/// Liquid Glass 真玻璃主题的设计 token 常量集
///
/// 间距 / 圆角与 NotionTheme 对齐，主题切换不引起结构跳动。
enum LiquidGlassTheme {

    // MARK: 圆角（与 LGATheme / NotionTheme 完全一致）
    static let radiusSM: CGFloat = 10
    static let radiusMD: CGFloat = 12
    static let radiusLG: CGFloat = 14
    static let radiusXL: CGFloat = 18

    // MARK: 间距（同步 LGATheme，避免主题切换布局跳动）
    static let space2: CGFloat = 4
    static let space3: CGFloat = 6
    static let space4: CGFloat = 8
    static let space5: CGFloat = 12
    static let space6: CGFloat = 16
    static let space7: CGFloat = 24

    // MARK: GlassEffectContainer 默认间距（控制玻璃元素是否合并）
    static let containerSpacing: CGFloat = 20

    // MARK: 强调色（系统蓝，跟随系统亮暗自动适配）
    static let accent: Color = .accentColor

    /// 选中态描边色（玻璃模式下用 accent 半透叠加，呼应折射）
    static let accentSelection: Color = .accentColor
}

// MARK: - 主题感知文字色（跟随系统）

extension Color {

    /// Liquid Glass 主题主文本色：浅色模式深墨、深色模式纯白
    static var liquidGlassTextPrimary: Color {
        Color.adaptive(
            light: Color(red: 0.11, green: 0.11, blue: 0.12),
            dark: Color.white
        )
    }

    /// Liquid Glass 主题次文本色：标准 iOS 副标题灰
    static var liquidGlassTextSecondary: Color {
        Color.adaptive(
            light: Color(red: 0.39, green: 0.39, blue: 0.42),
            dark: Color(red: 0.56, green: 0.56, blue: 0.58)
        )
    }

    /// Liquid Glass 主题三级文本色（更弱的 caption）
    static var liquidGlassTextTertiary: Color {
        Color.adaptive(
            light: Color(red: 0.56, green: 0.56, blue: 0.58),
            dark: Color(red: 0.42, green: 0.42, blue: 0.44)
        )
    }
}

// MARK: - 玻璃卡片修饰器（受 #available 保护）

/// 真玻璃卡片：圆角矩形 + `.glassEffect(.regular, in: rect)`
///
/// - 不再依赖 LGA 的实色 `cardFill`；玻璃自身负责模糊与反光
/// - `interactive` 默认 false（卡片整体非可点击）；可点击场景由调用方包 Button
private struct LiquidGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var interactive: Bool

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            // 真玻璃：.glassEffect 内部不允许干预，但外层可以叠加阴影
            // 塑造“玻璃卡片浮在背景上”的层次感
            Group {
                if interactive {
                    content.glassEffect(
                        .regular.interactive(),
                        in: .rect(cornerRadius: cornerRadius)
                    )
                } else {
                    content.glassEffect(
                        .regular,
                        in: .rect(cornerRadius: cornerRadius)
                    )
                }
            }
            // 双层阴影塑造悬浮感（与 fallback v6 同步）
            .shadow(color: .black.opacity(0.18), radius: 4,  x: 0, y: 2)
            .shadow(color: .black.opacity(0.28), radius: 20, x: 0, y: 10)
        } else {
            content.modifier(GlassFallbackCardModifier(cornerRadius: cornerRadius))
        }
        #else
        // Xcode 16 及以下：iOS 26 SDK 不可用，fallback 为 thinMaterial + 高光描边强化玻璃感
        content.modifier(GlassFallbackCardModifier(cornerRadius: cornerRadius))
        #endif
    }
}

/// Xcode 16 / iOS 18 fallback v6 · 立体感强化版
///
/// v5 问题：
///   - 描边太弱（顶部 50% · 0.8pt）→ 边缘与背景融化
///   - 阴影太薄（radius=8, opacity=0.10）→ 深色背景上看不到“浮起”
///   - 缺少“内高光”→ 玻璃顶面没有反光光泽
///
/// v6 修正：
///   - 双层描边：顶高光 + 底暗影，塑造玻璃厚度
///   - 双层阴影：远景软阴影 + 近景锐阴影，增强悬浮感
///   - 内高光：顶部 1/3 区域叠加白色渐隐反光带
private struct GlassFallbackCardModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // 1. 玻璃主体填充（v6 · 轻微提亮，强化体积感）
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            Color.adaptive(
                                light: Color.white.opacity(0.50),
                                dark:  Color.white.opacity(0.22)
                            )
                        )

                    // 2. 内高光：顶部白色反光带（玻璃表面光泽）
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.30),
                                    Color.white.opacity(0.08),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.45)
                            )
                        )
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
            )
            .overlay(
                // 3. 双层描边：顶高光 + 底暗影，塑造“玻璃厚度”
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.65),    // 顶高光
                                Color.white.opacity(0.18),    // 中段过渡
                                Color.white.opacity(0.05),    // 底部接近透明
                                Color.black.opacity(0.18)     // 底暗影（“玻璃下边缘”）
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.0
                    )
                    .allowsHitTesting(false)
            )
            // 4. 双层阴影：近景锐 + 远景柔，带出“悬浮”的层次感
            .shadow(color: .black.opacity(0.18), radius: 4,  x: 0, y: 2)
            .shadow(color: .black.opacity(0.28), radius: 20, x: 0, y: 10)
    }
}

/// 真玻璃浮岛（胶囊 TabBar / 浮动按钮）
///
/// 使用 `.capsule` 形状 + interactive 玻璃，符合 iOS 26 浮岛规范
private struct LiquidGlassPillModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
                // 胶囊阴影加强：让 TabBar / 浮岱明显“脱离背景”
                .shadow(color: .black.opacity(0.20), radius: 4,  x: 0, y: 2)
                .shadow(color: .black.opacity(0.32), radius: 22, x: 0, y: 10)
        } else {
            content.modifier(GlassFallbackPillModifier())
        }
        #else
        content.modifier(GlassFallbackPillModifier())
        #endif
    }
}

/// Fallback 胶囊玻璃 v6 · 立体感强化：双层描边 + 内高光 + 双层阴影
private struct GlassFallbackPillModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // 主体填充
                    Capsule(style: .continuous)
                        .fill(
                            Color.adaptive(
                                light: Color.white.opacity(0.55),
                                dark:  Color.white.opacity(0.24)
                            )
                        )
                    // 内高光（顶部反光带）
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.35),
                                    Color.white.opacity(0.05),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.55)
                            )
                        )
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
            )
            .overlay(
                // 双层描边：顶高光 + 底暗影
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.70),
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.05),
                                Color.black.opacity(0.20)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.0
                    )
                    .allowsHitTesting(false)
            )
            // 双层阴影：近景锐 + 远景柔（胶囊浮起感）
            .shadow(color: .black.opacity(0.20), radius: 4,  x: 0, y: 2)
            .shadow(color: .black.opacity(0.32), radius: 22, x: 0, y: 10)
    }
}

/// 真玻璃 chip（小标签）
///
/// 可选 tint 注入颜色暗示语义（成功/警告/类别色），玻璃保持半透
private struct LiquidGlassChipModifier: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if let tint {
                content.glassEffect(
                    .regular.tint(tint.opacity(0.35)).interactive(),
                    in: .rect(cornerRadius: cornerRadius)
                )
            } else {
                content.glassEffect(
                    .regular,
                    in: .rect(cornerRadius: cornerRadius)
                )
            }
        } else {
            content.modifier(GlassFallbackChipModifier(cornerRadius: cornerRadius, tint: tint))
        }
        #else
        content.modifier(GlassFallbackChipModifier(cornerRadius: cornerRadius, tint: tint))
        #endif
    }
}

/// Fallback chip v5：半透明填充 + 可选 tint + 描边
private struct GlassFallbackChipModifier: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            Color.adaptive(
                                light: Color.white.opacity(0.45),
                                dark:  Color.white.opacity(0.18)
                            )
                        )
                    if let tint {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.20))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5)
                    .allowsHitTesting(false)
            )
    }
}

// MARK: - View 扩展（专属 API；不污染既有桥接器）

extension View {

    /// 应用真玻璃卡片背景（仅供 cardSurface 桥接器在 .liquidGlass 主题下调用）
    fileprivate func liquidGlassCard(
        cornerRadius: CGFloat,
        interactive: Bool = false
    ) -> some View {
        modifier(LiquidGlassCardModifier(
            cornerRadius: cornerRadius,
            interactive: interactive
        ))
    }

    /// 应用真玻璃浮岛胶囊背景（TabBar / FAB 容器）
    fileprivate func liquidGlassPill() -> some View {
        modifier(LiquidGlassPillModifier())
    }

    /// 应用真玻璃 chip 背景
    fileprivate func liquidGlassChip(
        cornerRadius: CGFloat = 8,
        tint: Color? = nil
    ) -> some View {
        modifier(LiquidGlassChipModifier(cornerRadius: cornerRadius, tint: tint))
    }
}

// MARK: - 公开桥接（供 LiquidGlassATheme.swift 中的 modifier 调用）
//
// 由于 fileprivate 修饰符无法跨文件访问，这里再暴露一组 internal 工厂方法。
// 仅 cardSurface / appTabPillBackground / glassChipIfLGA 在 .liquidGlass 分支调用。

extension View {

    /// 内部桥接：真玻璃卡片
    @ViewBuilder
    func _lgRealCard(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        modifier(LiquidGlassCardModifier(
            cornerRadius: cornerRadius,
            interactive: interactive
        ))
    }

    /// 内部桥接：真玻璃浮岛胶囊
    @ViewBuilder
    func _lgRealPill() -> some View {
        modifier(LiquidGlassPillModifier())
    }

    /// 内部桥接：真玻璃 chip
    @ViewBuilder
    func _lgRealChip(cornerRadius: CGFloat, tint: Color?) -> some View {
        modifier(LiquidGlassChipModifier(cornerRadius: cornerRadius, tint: tint))
    }
}

// MARK: - 全屏背景

/// Liquid Glass 主题全屏背景
///
/// 设计原则：
///   - 玻璃需要"色彩内容"才能产生折射，不能是纯黑/纯白
///   - 浅色模式：暖白 → 淡粉蓝渐变，三个彩色光斑（珊瑚/青/紫）
///   - 深色模式：深蓝紫 → 深青渐变，三个彩色光斑（珊瑚紫/蓝紫/青绿）
///   - 光斑使用 RadialGradient + plusLighter 混合，营造"玻璃后面有光源"的错觉
struct LiquidGlassBackground: View {

    var kind: LGAPageKind = .default

    var body: some View {
        ZStack {
            // 主体渐变底色（v5 · Abyss Amber）
            // 暗色：#1C1A2E 深海墨 → #2A2438 墨褐紫，略带紫褐色温，与下方琅珀金光斑同谱
            // 浅色：保留原暖白渐变（用户未要求改浅色版）
            LinearGradient(
                colors: [
                    Color.adaptive(
                        light: Color(red: 0.97, green: 0.96, blue: 0.95),
                        dark:  Color(red: 0.11, green: 0.10, blue: 0.18)   // #1C1A2E
                    ),
                    Color.adaptive(
                        light: Color(red: 0.93, green: 0.95, blue: 0.98),
                        dark:  Color(red: 0.16, green: 0.14, blue: 0.22)   // #2A2438
                    )
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // 彩色环境光斑 —— 让玻璃背后有足够色彩可折射
            colorfulAmbientLayer
                .ignoresSafeArea()
        }
    }

    /// 深海琅珀三色光斑（v5 · Abyss Amber）：顶靖蓝 / 中青绿松 / 底琅珀金
    ///
    /// 设计原则（吸取 v4 Aurora 失败教训）：
    ///   - **只用 3 色**，且三色在色轮上位置不对称，避免充加后互相抵消成中性灰
    ///   - **垂直分布**（顶/中/底），形成从冷到暖的色温过渡，有“从深海看到灯火”的叙事感
    ///   - **改用 .screen 混合**（代替 plusLighter），色彩交叠区不会过曝糊成一片
    ///   - **透明度差异化**：顶部 30%、中部 25%、底部 20%，金色不抢戏但可识别
    private var colorfulAmbientLayer: some View {
        ZStack {
            // 顶部光斑：靖蓝 #6B5BFF（冷色源，与底色同谱不冲突）
            RadialGradient(
                colors: [
                    Color.adaptive(
                        light: Color(red: 0.55, green: 0.50, blue: 1.00).opacity(0.28),
                        dark:  Color(red: 0.42, green: 0.36, blue: 1.00).opacity(0.42)
                    ),
                    Color.clear
                ],
                center: .init(x: 0.5, y: 0.0),
                startRadius: 0,
                endRadius: 420
            )

            // 中部光斑：青绿松 #00D4D4（中间过渡带，让冷暖过渡不突兑）
            RadialGradient(
                colors: [
                    Color.adaptive(
                        light: Color(red: 0.50, green: 0.85, blue: 0.85).opacity(0.22),
                        dark:  Color(red: 0.00, green: 0.83, blue: 0.83).opacity(0.32)
                    ),
                    Color.clear
                ],
                center: .init(x: 0.5, y: 0.5),
                startRadius: 0,
                endRadius: 360
            )

            // 底部光斑：琅珀金 #FFB547（暖色锦上添花，定义主题走向）
            RadialGradient(
                colors: [
                    Color.adaptive(
                        light: Color(red: 1.00, green: 0.80, blue: 0.50).opacity(0.20),
                        dark:  Color(red: 1.00, green: 0.71, blue: 0.28).opacity(0.30)
                    ),
                    Color.clear
                ],
                center: .init(x: 0.5, y: 1.0),
                startRadius: 0,
                endRadius: 380
            )
        }
        .blendMode(.screen)
    }
}

// MARK: - SwiftUI Preview

#if DEBUG
#if compiler(>=6.2)
@available(iOS 26.0, *)
private struct LiquidGlassThemePreview: View {
    var body: some View {
        ZStack {
            LiquidGlassBackground(kind: .home)
            VStack(spacing: 16) {
                Text("Liquid Glass")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.liquidGlassTextPrimary)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    ._lgRealCard(cornerRadius: 18)

                HStack(spacing: 12) {
                    Text("Tag A")
                        .font(.footnote)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        ._lgRealChip(cornerRadius: 8, tint: .blue)
                    Text("Tag B")
                        .font(.footnote)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        ._lgRealChip(cornerRadius: 8, tint: .pink)
                }

                Button("Glass Button") {}
                    .buttonStyle(.glassProminent)
            }
        }
    }
}

@available(iOS 26.0, *)
#Preview("Liquid Glass · Light") {
    LiquidGlassThemePreview()
        .preferredColorScheme(.light)
}

@available(iOS 26.0, *)
#Preview("Liquid Glass · Dark") {
    LiquidGlassThemePreview()
        .preferredColorScheme(.dark)
}
#endif
#endif
