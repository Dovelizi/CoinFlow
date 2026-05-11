//  MainTabView.swift
//  CoinFlow · M7 · 全局导航
//
//  4 个 Tab（首页 / 流水 / 统计 / 我的）。
//  M11 升级（小红书风格滑块）：
//  - 选中态从「tab 内部背景」改为「独立 indicator overlay」，所有 tab 项视觉对齐
//  - indicator 用 .matchedGeometryEffect 跟随选中 tab，spring 平移过渡
//  - 用户可以按住 tab bar 横向拖动：indicator 跟手位移；松手时 indicator 中心落在哪个 tab 的 frame，就切到哪个 tab
//  - 仍然支持点击切换；底部胶囊 tabbar 默认常驻，子页面 ScrollView 下滑时隐藏

import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case home    = "首页"
    case records = "流水"
    case stats   = "统计"
    case me      = "我的"

    var icon: String {
        switch self {
        case .home:    return "house"
        case .records: return "list.bullet.rectangle.portrait"
        case .stats:   return "chart.pie"
        case .me:      return "person.circle"
        }
    }

    var iconFilled: String {
        switch self {
        case .home:    return "house.fill"
        case .records: return "list.bullet.rectangle.portrait.fill"
        case .stats:   return "chart.pie.fill"
        case .me:      return "person.circle.fill"
        }
    }
}

// MARK: - 每个 tab 的 frame 收集（PreferenceKey）

/// 每个 tab 在 tabbar 局部坐标系中的几何信息
private struct TabFrame: Equatable {
    let tab: AppTab
    let midX: CGFloat
    let midY: CGFloat
    let width: CGFloat
}

private struct TabFramesKey: PreferenceKey {
    static var defaultValue: [TabFrame] = []
    static func reduce(value: inout [TabFrame], nextValue: () -> [TabFrame]) {
        value.append(contentsOf: nextValue())
    }
}

struct MainTabView: View {

    @State private var selected: AppTab = .home
    @State private var lastDirectionReversed: Bool = false
    @StateObject private var coordinator = MainCoordinator()
    @StateObject private var tabBarVisibility = TabBarVisibility()
    @EnvironmentObject private var amountTint: AmountTintStore

    /// 每个 tab 在 tabbar 内部的水平位置（midX、width）
    @State private var tabFrames: [TabFrame] = []
    /// indicator 拖动期间的额外 X 偏移（手指落点 - 起始落点）；非拖动时为 0
    @State private var dragTranslation: CGFloat = 0
    /// 拖动开始时的"基准 tab"，用于计算 indicator 起始 anchor
    @State private var dragAnchorTab: AppTab? = nil
    /// 当前是否正在拖动（拖动时禁用 implicit animation 实现"跟手"效果）
    @State private var isDragging: Bool = false
    /// 拖动期间 indicator 圈住的 tab（hover 预选态，涨不切换页面）
    /// 非拖动时为 nil；拖动中跟随 indicator 中心实时更新。松手后用作切换目标。
    @State private var hoverTab: AppTab? = nil

    /// 全局 ScreenshotInbox 协调器：负责"双击背面截图 → 识别记账"链路。
    /// 提到根层挂载，是因为 ScreenshotInbox 通过 PassthroughSubject 即时分发，
    /// 订阅者必须在 App active 那一刻就在视图树里。之前只有 HomeMainView 订阅，
    /// 导致用户上次离开 App 时不在首页时事件丢失（HomeMainView 不在树中）。
    /// 在 MainTabView 根层订阅可覆盖任意 tab，且不强制切换当前 tab。
    @StateObject private var screenshotInboxCoord = PhotoCaptureCoordinator()

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                switch selected {
                case .home:
                    HomeMainView(switchTab: { switchTo($0) }, coordinator: coordinator)
                case .records:
                    RecordsListView(coordinator: coordinator)
                case .stats:
                    StatsHubView()
                case .me:
                    NavigationStack {
                        SettingsView(embeddedInTab: true)
                    }
                }
            }
            .id(selected)
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environmentObject(tabBarVisibility)
            .animation(Motion.respect(Motion.smooth), value: selected)

            if tabBarVisibility.isVisible {
                customTabBar
                    .padding(.bottom, -8)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        // 全局订阅 ScreenshotInbox：快捷指令 Intent 把截图放剪贴板后，CoinFlowApp
        // 在 scenePhase==.active 时通过 imageSubject 发布；这里在 MainTabView 根层订阅，
        // 任何 tab 下都能立即接收并触发 CaptureConfirmView 识别流程。
        .onReceive(ScreenshotInbox.shared.imageSubject) { image in
            Task { await screenshotInboxCoord.handle(image: image) }
        }
        .sheet(item: Binding(
            get: {
                screenshotInboxCoord.sourceImage.map {
                    ScreenshotInboxSession(id: screenshotInboxCoord.captureId, image: $0)
                }
            },
            set: { _ in screenshotInboxCoord.reset() }
        )) { session in
            // 与 HomeMainView 完全一致的 CaptureConfirmView 入口：
            // 内部跑 OCR + LLM，未配置 LLM 时回退单笔流程。
            CaptureConfirmView(
                sourceImage: session.image,
                scrollToBottom: false,
                onSaved: { _ in screenshotInboxCoord.reset() },
                onRetake: { screenshotInboxCoord.retake() }
            )
        }
    }

    /// 切 tab：cross-fade 过渡（与外层 .animation(Motion.smooth, value: selected) 联动）
    private func switchTo(_ tab: AppTab) {
        guard tab != selected else { return }
        if let from = AppTab.allCases.firstIndex(of: selected),
           let to = AppTab.allCases.firstIndex(of: tab) {
            lastDirectionReversed = to < from
        }
        withAnimation(Motion.respect(Motion.smooth)) {
            selected = tab
        }
        tabBarVisibility.forceShow()
    }

    // MARK: - Custom tab bar (浮动 indicator + 可拖拽)

    private var customTabBar: some View {
        // 关键裁切链路（已验证）：
        //  1. iOS 26 .appTabPillBackground() 用 .glassEffect(in: .capsule)，按 capsule 裁切其 content
        //     → 解决：indicator 必须放在 .appTabPillBackground 之外
        //  2. .fixedSize() 把 ZStack 的 layout frame 锁死为子视图最大自然尺寸（tab 主体 280×52），
        //     即使 indicator 用 .position() 不参与 layout，渲染时也会被 fixedSize 锁死的 frame 隐式裁切
        //     → 解决：indicator 必须放到 .fixedSize() 之后的 overlay 里 —— overlay 默认不裁切，
        //            .position() 视图可以自由溢出 overlay 范围（凸出 tab bar 上下左右边界）
        //  3. coordinateSpace("tabbar") 仍设在 HStack 父级，overlay 内的 indicator 仍能正确读到该坐标系
        HStack(spacing: NotionTheme.space3) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabItem(tab, selected: tab == effectiveSelectedTab)
                    .background(tabFrameReader(for: tab))
                    .onTapGesture {
                        switchTo(tab)
                    }
            }
        }
        .padding(.horizontal, NotionTheme.space4)
        .padding(.vertical, NotionTheme.space4)
        .appTabPillBackground()
        .contentShape(Capsule())
        .coordinateSpace(name: "tabbar")
        .fixedSize()
        // ⬇️ indicator 在 .fixedSize() 之后挂到 overlay —— 不受 fixedSize 锁死的 frame 限制，
        //    放大后可以自由凸出 tab bar 上下左右四个方向（参考图独立气泡视觉）
        .overlay(
            indicatorView
                .allowsHitTesting(false)
        )
        .onPreferenceChange(TabFramesKey.self) { frames in
            self.tabFrames = frames
        }
        // 拖拽手势：UIKit 桥接，避免 .glassEffect(.interactive) 吞 SwiftUI gesture
        .background(
            HorizontalPanRecognizer(
                onBegan: handleDragBegan,
                onChanged: handleDragChanged,
                onEnded: handleDragEnded
            )
        )
        .frame(maxWidth: .infinity)
        // 键盘弹起时不跟随上浮，保持在屏幕底部、被键盘正常遮挡（与系统 UITabBar 一致）。
        // 直接挂在 customTabBar 的最外层修饰链尾，不放到外层 if 分支，避免被结构调整改丢。
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    /// 拖动期间为 tab item 提供的"选中态"计算属性：
    /// - 拖动中：indicator 圈住的 hoverTab 显示为宽态高亮（预选反馈），但页面 selected 未变
    /// - 非拖动时：返回真实的 selected
    private var effectiveSelectedTab: AppTab {
        isDragging ? (hoverTab ?? selected) : selected
    }

    /// 选中胶囊 indicator —— 绝对定位到当前 selected tab 的 midX
    /// 拖动期间 = selected tab midX + dragTranslation；松手时 spring 吸附到目标 tab
    /// 按住拖动时：indicator 转变为"独立浮起浅色气泡"——横向 1.30 / 纵向 1.55 显著放大，
    /// 凸出 tab bar 上下边界，并切换到高亮浅色填充 + 强阴影，形成参考图的"放大镜悬浮"视觉。
    /// 因为 .appTabPillBackground() 用 .background() 实现，indicator 放大不会被裁切。
    @ViewBuilder
    private var indicatorView: some View {
        if let frame = currentIndicatorFrame {
            indicatorShape(highlighted: isDragging)
                .frame(width: frame.width, height: frame.height)
                // 拖动时显著放大成独立浮起气泡（容许横向略超出单 tab——参考图也是这样）
                .scaleEffect(x: isDragging ? 1.28 : 1.0,
                             y: isDragging ? 1.85 : 1.0,
                             anchor: .center)
                .shadow(color: Color.black.opacity(isDragging ? 0.45 : 0),
                        radius: isDragging ? 20 : 0,
                        x: 0,
                        y: isDragging ? 10 : 0)
                .position(x: frame.midX, y: frame.midY)
                // zIndex 提升确保浮起的浅色气泡盖在所有 tab content 之上
                .zIndex(isDragging ? 10 : 0)
                // 静态切换走 smooth spring；拖动期间禁用 implicit animation 实现"跟手"
                .animation(isDragging ? nil : Motion.respect(Motion.smooth),
                           value: frame.midX)
                // 缩放/阴影/填充专门走一个轻量 spring，与位移动画解耦
                .animation(.spring(response: 0.32, dampingFraction: 0.72),
                           value: isDragging)
        }
    }

    /// indicator 视觉
    /// - 形状：胶囊（Capsule）
    /// - 静止状态（highlighted = false）：深色半透明，贴合 tab bar
    /// - 按住放大状态（highlighted = true）：浅色高对比，独立浮起气泡
    @ViewBuilder
    private func indicatorShape(highlighted: Bool) -> some View {
        if LGAThemeRuntime.isEnabled {
            Capsule()
                .fill(highlighted
                      ? Color.white.opacity(0.22)
                      : LGATheme.dgAccent.opacity(0.14))
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        highlighted ? Color.white.opacity(0.55)
                                    : LGATheme.dgAccent.opacity(0.45),
                        lineWidth: highlighted ? 0.8 : 0.6)
                )
        } else {
            Capsule()
                .fill(highlighted
                      ? Color.white.opacity(0.18)
                      : Color.hoverBg.opacity(0.92))
                .overlay(
                    Capsule().strokeBorder(
                        highlighted ? Color.white.opacity(0.45)
                                    : Color.white.opacity(0.06),
                        lineWidth: highlighted ? 0.7 : 0.5)
                )
        }
    }

    /// 计算 indicator 当前应该占据的 frame（在 tabbar coordinate space 中）
    /// - 优先用拖动落点对应 tab；非拖动时用 selected tab
    private var currentIndicatorFrame: (midX: CGFloat, midY: CGFloat, width: CGFloat, height: CGFloat)? {
        guard !tabFrames.isEmpty else { return nil }
        // 选中 tab 的几何信息
        // 关键：只要 dragAnchorTab 存在（拖动中 + 松手过渡阶段），就用 dragAnchorTab；
        // 否则才用 selected。这样阶段 1（isDragging=false 但 dragAnchorTab=target）时
        // indicator 位置 = target.midX，避免气泡瞬间跳回 selected（旧 tab）位置。
        let baseTab: AppTab = dragAnchorTab ?? selected
        guard let base = tabFrames.first(where: { $0.tab == baseTab }) else { return nil }
        // 计算 indicator center: base.midX + dragTranslation
        // 限制范围：在"最左 tab.midX - overflow" ~ "最右 tab.midX + overflow"之间。
        // overflow 让 indicator 在首页/我的边缘 tab 上拖动时能轻微“冲出"tab 胶囊左右边缘，呈现“气泡可以边跳出”的手感。
        let overflow: CGFloat = 14
        let minX = (tabFrames.map(\.midX).min() ?? base.midX) - overflow
        let maxX = (tabFrames.map(\.midX).max() ?? base.midX) + overflow
        let rawX = base.midX + (isDragging ? dragTranslation : 0)
        let clampedX = max(minX, min(maxX, rawX))

        // indicator 宽度：跟随当前命中 tab 宽度（不同 tab icon 长度不同）
        let hitTab = nearestTab(forIndicatorMidX: clampedX) ?? baseTab
        let hit = tabFrames.first(where: { $0.tab == hitTab }) ?? base

        // indicator 比 tab content 略宽 + 略高，营造"包裹感"（参考图）
        let extraW: CGFloat = 8
        let height: CGFloat = 40

        // tab 在 HStack 中垂直居中，所有 tab 的 midY 一致，直接取 base.midY
        return (clampedX, base.midY, hit.width + extraW, height)
    }

    /// 拖动期间：根据 indicator 中心 x 找出最近的 tab
    private func nearestTab(forIndicatorMidX x: CGFloat) -> AppTab? {
        guard !tabFrames.isEmpty else { return nil }
        return tabFrames.min(by: { abs($0.midX - x) < abs($1.midX - x) })?.tab
    }

    // MARK: - 手势处理

    private func handleDragBegan() {
        dragAnchorTab = selected
        hoverTab = selected
        dragTranslation = 0
        isDragging = true
        tabBarVisibility.forceShow()
    }

    private func handleDragChanged(_ translation: CGFloat) {
        dragTranslation = translation
        // 拖动期间仅更新 hoverTab（预选态），不切换 selected——页面保持不变。
        // 页面切换在松手后的气泡收缩动画完成后才发生。
        guard let anchor = dragAnchorTab,
              let base = tabFrames.first(where: { $0.tab == anchor }) else { return }
        let x = base.midX + translation
        if let nearest = nearestTab(forIndicatorMidX: x), nearest != hoverTab {
            // hoverTab 切换走轻 spring，让 tab item 的宽态/窄态平滑变形
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                hoverTab = nearest
            }
        }
    }

    private func handleDragEnded(_ translation: CGFloat) {
        // 两阶段动画：
        //  阶段 1：indicator 气泡先 spring 收缩到正常尺寸（isDragging = false），同时吸附到目标 tab 位置
        //  阶段 2：气泡收缩动画近于完成后（~0.32s）再将 selected = target，页面 cross-fade 切换
        guard let anchor = dragAnchorTab,
              let base = tabFrames.first(where: { $0.tab == anchor }) else {
            isDragging = false
            dragTranslation = 0
            dragAnchorTab = nil
            hoverTab = nil
            return
        }
        let x = base.midX + translation
        let target = nearestTab(forIndicatorMidX: x) ?? selected

        // 阶段 1：气泡收缩、吸附到 target tab 位置（selected 还未改，页面不切）
        // 这里需要让 currentIndicatorFrame 在动画中从 base.midX + translation 平滑过渡到 target.midX。
        // 做法：把 dragAnchorTab 改为 target，dragTranslation 清零，isDragging = false——
        // 这样 indicator 位置从"anchor.midX + translation"变为"target.midX + 0"，动画平滑
        withAnimation(Motion.respect(Motion.smooth)) {
            dragAnchorTab = target
            dragTranslation = 0
            isDragging = false
            hoverTab = target  // 保持宽态高亮不闪烁
        }

        // 阶段 2：等气泡收缩近完后再切页面。延迟 0.30s（spring response 0.32 的 ~95% 进度）。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            // 中途如果用户又拖起来了（isDragging 变 true）则放弃这次切换
            guard !self.isDragging else { return }
            self.switchTo(target)
            // 清理过渡状态
            self.dragAnchorTab = nil
            self.hoverTab = nil
        }
    }

    // MARK: - tab item view + 几何收集

    /// 每个 tab 的视觉样式：选中态高亮文字+icon，未选中态灰色
    /// 已不再带胶囊背景，改由顶层 indicator overlay 提供
    @ViewBuilder
    private func tabItem(_ tab: AppTab, selected: Bool) -> some View {
        if selected {
            HStack(spacing: 6) {
                Image(systemName: tab.iconFilled)
                    .font(.system(size: 16, weight: .regular))
                Text(tab.rawValue)
                    .font(NotionFont.bodyBold())
            }
            .foregroundStyle(LGAThemeRuntime.isEnabled ? LGATheme.dgAccent : Color.inkPrimary)
            .padding(.horizontal, NotionTheme.space6)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .accessibilityLabel("\(tab.rawValue)（当前选中）")
        } else {
            Image(systemName: tab.icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.inkSecondary)
                .padding(.horizontal, NotionTheme.space6)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .accessibilityLabel(tab.rawValue)
        }
    }

    /// 几何收集：把每个 tab 在 "tabbar" coordinate space 下的 midX / width 报上去
    private func tabFrameReader(for tab: AppTab) -> some View {
        GeometryReader { geo in
            let f = geo.frame(in: .named("tabbar"))
            Color.clear
                .preference(
                    key: TabFramesKey.self,
                    value: [TabFrame(tab: tab, midX: f.midX, midY: f.midY, width: f.width)]
                )
        }
    }
}

#if DEBUG
#Preview {
    MainTabView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
#endif

// MARK: - UIKit Pan Recognizer 桥接（实时 translation 流版）
//
// 升级动机：
// 旧版只回调 swipe direction 一次（threshold 触发后 fire）。新版本需要"跟手 indicator"，
// 必须暴露 began / changed(translation) / ended 三阶段，让 SwiftUI 实时更新 indicator 偏移。
// 仍走 window 挂载 + cancelsTouchesInView=false 方案，不被 .glassEffect(.interactive) 吞。

// MARK: - 全局截图识别 sheet 的 Identifiable 包装
//
// `.sheet(item:)` 要求传入 Identifiable 类型；PhotoCaptureCoordinator 的
// `sourceImage: UIImage?` 不是 Identifiable，所以这里包一层。`captureId` 由
// coordinator 内部生成，每次 reset 后 handle 新图会换新 id，从而触发 sheet 重建。
private struct ScreenshotInboxSession: Identifiable {
    let id: UUID
    let image: UIImage
}

private struct HorizontalPanRecognizer: UIViewRepresentable {
    let onBegan: () -> Void
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegan: onBegan, onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> UIView {
        let view = HostMountView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onBegan: () -> Void
        var onChanged: (CGFloat) -> Void
        var onEnded: (CGFloat) -> Void
        /// 是否已经判定为"水平滑"（避免与垂直滑/点击混淆）
        private var horizontalCommitted = false
        /// 起始判定阈值：dx 超过 6pt 且 |dx| > |dy| 才开始派发 began
        private let activationThreshold: CGFloat = 6
        weak var attachedView: UIView?
        weak var installedRecognizer: UIPanGestureRecognizer?

        init(onBegan: @escaping () -> Void,
             onChanged: @escaping (CGFloat) -> Void,
             onEnded: @escaping (CGFloat) -> Void) {
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        func install(on window: UIWindow, anchor: UIView) {
            if let existing = installedRecognizer, existing.view === window {
                attachedView = anchor
                return
            }
            attachedView = anchor
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            pan.cancelsTouchesInView = false
            pan.delegate = self
            window.addGestureRecognizer(pan)
            installedRecognizer = pan
        }

        func uninstall() {
            if let pan = installedRecognizer, let win = pan.view {
                win.removeGestureRecognizer(pan)
            }
            installedRecognizer = nil
            attachedView = nil
        }

        @objc func handle(_ pan: UIPanGestureRecognizer) {
            guard let anchor = attachedView else { return }
            let t = pan.translation(in: anchor)
            switch pan.state {
            case .began:
                horizontalCommitted = false
            case .changed:
                if !horizontalCommitted {
                    // 仅水平方向占主导且超过阈值才"提交"为横滑
                    if abs(t.x) >= activationThreshold, abs(t.x) > abs(t.y) {
                        horizontalCommitted = true
                        onBegan()
                        onChanged(t.x)
                    }
                } else {
                    onChanged(t.x)
                }
            case .ended, .cancelled, .failed:
                if horizontalCommitted {
                    onEnded(t.x)
                }
                horizontalCommitted = false
            default:
                break
            }
        }

        // 仅响应胶囊 frame 内的 touch
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let anchor = attachedView else { return false }
            let p = touch.location(in: anchor)
            return anchor.bounds.insetBy(dx: -8, dy: -8).contains(p)
        }

        // 允许与 SwiftUI 内部手势/tap 共存
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }

    private final class HostMountView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let win = window {
                coordinator?.install(on: win, anchor: self)
            } else {
                coordinator?.uninstall()
            }
        }
    }
}