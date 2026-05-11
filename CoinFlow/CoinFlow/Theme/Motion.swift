//  Motion.swift
//  CoinFlow · 全局动画 / 触觉反馈设计系统
//
//  为什么需要这个文件：
//  - 此前各 View 散落 `easeInOut(0.18)` `easeOut(0.42)` 等魔数，缓动/时长不一致，
//    用户在 Tab 切换、抽屉弹出、按钮反馈、列表展开间会感到节奏不齐。
//  - iOS 系统级动画基本都使用 spring（响应式弹簧），相比纯 timingCurve 在用户中断
//    手势时能优雅打断重定向，且自带轻微的"物理感"。
//
//  设计原则（对齐 Apple HIG / iOS 17+ spring API）：
//  - 短交互（按钮、点选）：Motion.snap，response=0.28、damping=0.86，无视觉超调
//  - 默认过渡（页面切换、抽屉、卡片）：Motion.smooth，response=0.40、damping=0.86
//  - 强调/弹性（首次出现、欢迎元素）：Motion.bouncy，response=0.50、damping=0.78
//  - 列表项删除/出入：Motion.list，response=0.34、damping=0.92
//  - 每一种动画"配套"一个 transition + 一个 timing-curve fallback
//
//  使用方式：
//      withAnimation(Motion.smooth) { showSheet = true }
//      .animation(Motion.snap, value: isPressed)
//      .transition(Motion.fadeSlide(edge: .bottom))
//
//  触觉反馈：
//      Haptics.tap()         // 按钮按下
//      Haptics.select()      // segmented / picker 切换
//      Haptics.success()     // 保存成功
//      Haptics.warn()        // 边界 / 拦截
//
//  M8 升级（2026-05-11）：
//  - 新增 `page` / `sheet` / `glass` / `tabSwitch` / `numericChange` 语义化 spring
//  - 新增 `Motion.respect(_:)`：reduceMotion 开启时自动退化为短淡入淡出
//  - 新增 transitions：tabSwitchSlide / sheetRise / popReveal / shrinkFade
//  - 新增 view modifiers：.shimmer() / .pulse() / .shake(trigger:) / .softAppear(delay:)
//  - 新增 NumericTransition：数字变化时的 contentTransition.numericText 包装

import SwiftUI
import UIKit

enum Motion {

    // MARK: - Spring（首选）

    /// 短交互：按钮按下回弹、segmented 切换、checkmark 点选
    /// response 0.28 + damping 0.86 → 总体约 0.30s 完成，无视觉超调，跟手
    static let snap: Animation = .spring(response: 0.28, dampingFraction: 0.86)

    /// 默认过渡：sheet/抽屉/popover 弹出收起、tab 切换、卡片入场
    /// response 0.40 + damping 0.86 → 平滑、无回弹的"减速到位"，符合 iOS 系统态势
    static let smooth: Animation = .spring(response: 0.40, dampingFraction: 0.86)

    /// 强调动画：欢迎页 / 首次出现 / 用户重要操作的成功反馈
    /// response 0.50 + damping 0.78 → 末段轻微回弹，赋予"活的"气质
    static let bouncy: Animation = .spring(response: 0.50, dampingFraction: 0.78)

    /// 列表插入/删除：avoid 过度回弹影响相邻 cell 阅读
    static let list: Animation = .spring(response: 0.34, dampingFraction: 0.92)

    /// 持续/连续值（如音量条、滚动联动）：用 .interactiveSpring 避免抢占
    static let interactive: Animation = .interactiveSpring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.12)

    /// 页面级切换（NavigationStack / 自定义 tab content）：响应稍长，更"重"
    static let page: Animation = .spring(response: 0.46, dampingFraction: 0.88)

    /// Sheet/抽屉抬起：略带轻盈感，对应底部弹出
    static let sheet: Animation = .spring(response: 0.42, dampingFraction: 0.84)

    /// 玻璃材质过渡（color/opacity/blur 联动）：偏长 + 高阻尼，避免抖动
    static let glass: Animation = .spring(response: 0.55, dampingFraction: 0.92)

    /// Tab 切换横滑：响应中等 + 较强阻尼，类比系统 Page Sheet
    static let tabSwitch: Animation = .spring(response: 0.36, dampingFraction: 0.88)

    /// 数字变化（金额/计数）：稍弹性，让数字"跳"一下
    static let numericChange: Animation = .spring(response: 0.32, dampingFraction: 0.78)

    // MARK: - Timing Curve（用于"非弹簧"诉求场景，如 toast 淡入淡出）

    /// 标准曲线：一般淡入淡出（0.4, 0, 0.2, 1）—— Material/iOS 通用
    static func standard(_ duration: Double = 0.24) -> Animation {
        .timingCurve(0.4, 0, 0.2, 1, duration: duration)
    }

    /// 强调曲线：进场用（0.2, 0, 0, 1）—— 起步快、末端缓
    static func emphasized(_ duration: Double = 0.32) -> Animation {
        .timingCurve(0.2, 0, 0, 1, duration: duration)
    }

    /// 退场曲线：（0.4, 0, 1, 1）—— 起步缓、末端快，符合"消失"心智
    static func exit(_ duration: Double = 0.20) -> Animation {
        .timingCurve(0.4, 0, 1, 1, duration: duration)
    }

    // MARK: - Reduce-Motion 自适应

    /// 在 reduceMotion 开启时，把任意 spring/timing 退化为 0.18s 淡入淡出，
    /// 避免眩晕用户的同时仍提供必要的状态变化感知。
    static func respect(_ animation: Animation) -> Animation {
        if UIAccessibility.isReduceMotionEnabled {
            return .easeInOut(duration: 0.18)
        }
        return animation
    }

    // MARK: - Transitions（成对的 in/out 组合）

    /// 抽屉/底部 sheet 入场：从底部滑入 + fade
    static func slideUp(distance: CGFloat = 12) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity.animation(Motion.exit(0.18))
        )
    }

    /// 顶部下拉的 banner / 搜索栏：自顶部插入
    static let dropDown: AnyTransition = .asymmetric(
        insertion: .move(edge: .top).combined(with: .opacity),
        removal: .opacity.combined(with: .move(edge: .top))
    )

    /// 卡片切换的水平方向滑入（左/右），用于 tab/页签
    static func horizontalSlide(reversed: Bool) -> AnyTransition {
        let inEdge: Edge = reversed ? .leading : .trailing
        let outEdge: Edge = reversed ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: inEdge).combined(with: .opacity),
            removal: .move(edge: outEdge).combined(with: .opacity)
        )
    }

    /// Tab 切换专用：方向感知的轻量 slide + fade（位移幅度 24pt，避免视觉过度滑动）
    /// reversed=true 表示用户从右往左切（即新选 tab 在原 tab 左侧）
    static func tabSwitchSlide(reversed: Bool) -> AnyTransition {
        let dx: CGFloat = reversed ? -24 : 24
        return .asymmetric(
            insertion: .modifier(
                active: TabSlideEffect(offset: -dx, opacity: 0),
                identity: TabSlideEffect(offset: 0, opacity: 1)
            ),
            removal: .modifier(
                active: TabSlideEffect(offset: dx, opacity: 0),
                identity: TabSlideEffect(offset: 0, opacity: 1)
            )
        )
    }

    /// Sheet/Modal 抬起入场（缩放 + 上推 + 透明度）—— 类系统 page sheet 质感
    static let sheetRise: AnyTransition = .asymmetric(
        insertion: .scale(scale: 0.96, anchor: .bottom)
            .combined(with: .move(edge: .bottom).combined(with: .opacity)),
        removal: .opacity.combined(with: .move(edge: .bottom))
    )

    /// Popover/Menu 出现：从锚点缩放 + fade（带 anchor）
    static func popReveal(anchor: UnitPoint = .top) -> AnyTransition {
        .scale(scale: 0.92, anchor: anchor).combined(with: .opacity)
    }

    /// 收起/移除：略微缩小 + 透明，比单纯 .opacity 有"被吸走"的体感
    static let shrinkFade: AnyTransition = .scale(scale: 0.98).combined(with: .opacity)

    /// 缩放 + 透明度：popover / floating card / modal hub
    static let scaleFade: AnyTransition = .scale(scale: 0.96, anchor: .center)
        .combined(with: .opacity)

    /// toast 弹出：从底部抬起 + 透明
    static let toast: AnyTransition = .opacity
        .combined(with: .move(edge: .bottom))

    // MARK: - Durations（用于非 SwiftUI 场景，如 DispatchQueue 调度）

    static let durFast: Double = 0.20
    static let durBase: Double = 0.28
    static let durSlow: Double = 0.40
}

// MARK: - TabSlideEffect

/// Tab 切换时的位移 + 透明度复合修饰
private struct TabSlideEffect: ViewModifier, Animatable {
    var offset: CGFloat
    var opacity: Double

    var animatableData: AnimatablePair<CGFloat, Double> {
        get { AnimatablePair(offset, opacity) }
        set { offset = newValue.first; opacity = newValue.second }
    }

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .opacity(opacity)
    }
}

// MARK: - Haptics（统一触觉反馈封装）
//
// 用户偏好：系统的点击交互不需要震动。
// 因此所有 Haptics.* 方法均为 no-op（仍保留 API，避免散落各处的调用点都需要改写）。
// 如果将来需要恢复触觉，把下方方法体改回 generator 调用即可（旧实现见 git 历史）。
enum Haptics {

    /// 普通按钮 tap（已禁用震动）
    static func tap() {}

    /// segmented / picker 选择切换（已禁用震动）
    static func select() {}

    /// 重要按钮 / 强调操作（已禁用震动）
    static func medium() {}

    /// 卡片打开 / 浮岛弹出（已禁用震动）
    static func soft() {}

    /// 长按菜单浮起（已禁用震动）
    static func rigid() {}

    /// 成功（已禁用震动）
    static func success() {}

    /// 警示 / 边界（已禁用震动）
    static func warn() {}

    /// 错误（已禁用震动）
    static func error() {}
}

// MARK: - View modifiers（动画装饰器）

/// Shimmer：骨架屏微光扫过。在 .redacted(reason: .placeholder) 之上叠加。
private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    var active: Bool

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    if active {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: Color.white.opacity(0.18), location: 0.5),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: geo.size.width * 1.6)
                        .offset(x: phase * geo.size.width * 1.6)
                        .blendMode(.plusLighter)
                        .onAppear {
                            guard !UIAccessibility.isReduceMotionEnabled else { return }
                            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                                phase = 1
                            }
                        }
                    }
                }
                .allowsHitTesting(false)
                .clipped()
            )
    }
}

/// Pulse：呼吸式缩放（录音、loading 等）
private struct PulseModifier: ViewModifier {
    @State private var pulsing = false
    var minScale: CGFloat
    var maxScale: CGFloat
    var duration: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulsing ? maxScale : minScale)
            .onAppear {
                guard !UIAccessibility.isReduceMotionEnabled else { return }
                withAnimation(
                    .easeInOut(duration: duration).repeatForever(autoreverses: true)
                ) {
                    pulsing = true
                }
            }
    }
}

/// Shake：当 trigger 值变化时，水平抖动一次（用于错误反馈、金额超限提示）
private struct ShakeModifier<T: Equatable>: ViewModifier {
    var trigger: T
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .onChange(of: trigger) { _ in
                guard !UIAccessibility.isReduceMotionEnabled else { return }
                let amplitudes: [CGFloat] = [-8, 8, -6, 6, -3, 3, 0]
                for (i, a) in amplitudes.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.04) {
                        withAnimation(.spring(response: 0.12, dampingFraction: 0.5)) {
                            offset = a
                        }
                    }
                }
            }
    }
}

/// Soft appear：延迟 + opacity + 上抬入场。用于卡片列表 stagger 效果。
private struct SoftAppearModifier: ViewModifier {
    @State private var appeared = false
    var delay: Double
    var distance: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : distance)
            .onAppear {
                if UIAccessibility.isReduceMotionEnabled {
                    appeared = true
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(Motion.smooth) { appeared = true }
                }
            }
    }
}

extension View {
    /// 骨架屏微光（搭配 .redacted 使用）
    func shimmer(active: Bool = true) -> some View {
        modifier(ShimmerModifier(active: active))
    }

    /// 呼吸式缩放：用于"等待"中的元素（如录音按钮）
    func pulse(minScale: CGFloat = 1.0, maxScale: CGFloat = 1.06, duration: Double = 0.9) -> some View {
        modifier(PulseModifier(minScale: minScale, maxScale: maxScale, duration: duration))
    }

    /// 触发抖动：trigger 值任意变化即抖一次
    func shake<T: Equatable>(trigger: T) -> some View {
        modifier(ShakeModifier(trigger: trigger))
    }

    /// 轻盈出现：常用于列表/卡片 stagger（推荐 delay = index * 0.04）
    func softAppear(delay: Double = 0, distance: CGFloat = 8) -> some View {
        modifier(SoftAppearModifier(delay: delay, distance: distance))
    }

    /// 数字变化时使用 numericText 过渡（仅 iOS 17+）
    @ViewBuilder
    func numericTransition() -> some View {
        if #available(iOS 17.0, *) {
            self.contentTransition(.numericText())
        } else {
            self
        }
    }
}
