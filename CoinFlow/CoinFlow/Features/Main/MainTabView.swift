//  MainTabView.swift
//  CoinFlow · M7 · 全局导航
//
//  4 个 Tab（首页 / 流水 / 统计 / 我的），仅能通过点击胶囊切换。
//  - 使用条件渲染 + .opacity transition，不再使用 TabView(.page)；
//    横滑手势彻底让给各 subview 内部的 NavigationStack（系统级返回）。
//  - 底部胶囊 tabbar 默认常驻；当子页面 ScrollView 向下滚动（阅读更多）时隐藏，
//    向上滚动（回顶）时显示。通过 TabBarVisibility 环境对象驱动。

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

struct MainTabView: View {

    @State private var selected: AppTab = .home
    /// M7 [G2]：全局意图 coordinator，在 Home/Records 间传递 picker/voice/new 意图
    @StateObject private var coordinator = MainCoordinator()
    /// 底部胶囊可见性（滚动联动隐藏）
    @StateObject private var tabBarVisibility = TabBarVisibility()
    /// 订阅金额配色：用户在设置里切换"系统/鲜亮"时，本 View 及其子树全部 rebuild，
    /// 从而让 DirectionColor.amountForeground / Color.incomeGreen 等读到新值后的文字刷新颜色。
    /// 不直接使用此属性，仅用于订阅刷新。
    @EnvironmentObject private var amountTint: AmountTintStore

    var body: some View {
        ZStack(alignment: .bottom) {
            // 条件渲染 + 淡入淡出；横滑手势不再触发 tab 切换
            ZStack {
                switch selected {
                case .home:
                    HomeMainView(switchTab: { switchTo($0) }, coordinator: coordinator)
                        .transition(.opacity)
                case .records:
                    RecordsListView(coordinator: coordinator)
                        .transition(.opacity)
                case .stats:
                    StatsHubView()
                        .transition(.opacity)
                case .me:
                    NavigationStack {
                        SettingsView(embeddedInTab: true)
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environmentObject(tabBarVisibility)

            // 底部胶囊 tabbar —— 由 TabBarVisibility 驱动显隐
            if tabBarVisibility.isVisible {
                customTabBar
                    // 胶囊更贴近 home indicator：负 padding 侵入 safe area 8pt
                    .padding(.bottom, -8)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
    }

    /// 切 tab：淡入淡出 + 立即显示 tabbar
    private func switchTo(_ tab: AppTab) {
        guard tab != selected else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            selected = tab
        }
        tabBarVisibility.forceShow()
    }

    // MARK: - Custom tab bar (Notion capsule style)

    private var customTabBar: some View {
        HStack(spacing: NotionTheme.space3) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabItem(tab, selected: tab == selected)
                    .onTapGesture {
                        switchTo(tab)
                    }
            }
        }
        .padding(.horizontal, NotionTheme.space4)
        .padding(.vertical, NotionTheme.space4)
        .appTabPillBackground()
        .contentShape(Capsule())
        .fixedSize()
        // 横滑切 tab：HorizontalPanRecognizer 使用 background + window 挂载手势方案，
        // hitTest 返回 nil，tap 直接落到上层胶囊的 onTapGesture；pan recognizer 挂在 window 上能识别 touch。
        .background(
            HorizontalPanRecognizer(
                threshold: 28,
                onSwipe: { direction in
                    let all = AppTab.allCases
                    guard let idx = all.firstIndex(of: selected) else { return }
                    switch direction {
                    case .left:
                        if idx < all.count - 1 { switchTo(all[idx + 1]) }
                    case .right:
                        if idx > 0 { switchTo(all[idx - 1]) }
                    }
                }
            )
        )
        .frame(maxWidth: .infinity)
    }

    // 旧的 SwiftUI DragGesture 已移除：在 .glassEffect(.interactive) 下任何优先级的 SwiftUI 手势都会被玻璃吞掉。
    // 改用下方 HorizontalPanRecognizer（UIKit 桥接）解决。

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
            .padding(.horizontal, NotionTheme.space5)
            .padding(.vertical, 8)
            .background(selectedPillBackground)
            .accessibilityLabel("\(tab.rawValue)（当前选中）")
        } else {
            Image(systemName: tab.icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.inkSecondary)
                .padding(.horizontal, NotionTheme.space5)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .accessibilityLabel(tab.rawValue)
        }
    }

    /// 选中态胶囊背景：
    /// - LGA 模式：accent 玻璃高亮（accentIndigo opacity 0.12 + ultraThinMaterial + accent 描边），严格对齐 ScreensLG/LGHomeView 的 selected pill
    /// - Notion 模式：原 hoverBg 实色胶囊
    @ViewBuilder
    private var selectedPillBackground: some View {
        if LGAThemeRuntime.isEnabled {
            Capsule()
                .fill(LGATheme.dgAccent.opacity(0.12))
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(LGATheme.dgAccent.opacity(0.45), lineWidth: 0.6)
                )
        } else {
            Capsule().fill(Color.hoverBg.opacity(0.9))
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

// MARK: - UIKit Pan Recognizer 桥接
//
// 为什么要 UIKit 桥接：
// iOS 26 的 .glassEffect(.regular.interactive(), in: .capsule) 会消费胶囊范围内全部
// SwiftUI 手势（gesture / simultaneousGesture / highPriorityGesture 都被吞）。
// 改用 UIPanGestureRecognizer + cancelsTouchesInView=false：
//   - UIKit 手势独立于 SwiftUI 手势系统，不会被玻璃拦截
//   - cancelsTouchesInView=false 让 touch 仍然透传给下层 SwiftUI 视图，tap 不被吞
// 用 .overlay 而非 .background：overlay 在 hit-test 顺序上位于胶囊上层，能最早识别 pan
// 但因 cancelsTouchesInView=false，识别失败时 touch 继续走到下层，tap 仍可命中。

private enum PanSwipeDirection {
    case left
    case right
}

private struct HorizontalPanRecognizer: UIViewRepresentable {
    let threshold: CGFloat
    let onSwipe: (PanSwipeDirection) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(threshold: threshold, onSwipe: onSwipe)
    }

    func makeUIView(context: Context) -> UIView {
        let view = HostMountView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false  // 本 view 不接任何 touch，tap 直接落到上层胶囊
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.threshold = threshold
        context.coordinator.onSwipe = onSwipe
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var threshold: CGFloat
        var onSwipe: (PanSwipeDirection) -> Void
        private var fired = false
        weak var attachedView: UIView?  // 胶囊 host view，用于点中判定
        weak var installedRecognizer: UIPanGestureRecognizer?

        init(threshold: CGFloat, onSwipe: @escaping (PanSwipeDirection) -> Void) {
            self.threshold = threshold
            self.onSwipe = onSwipe
        }

        /// 安装 pan recognizer 到 window。window 不被 glassEffect 包裹，recognizer 可看到所有 touch，
        /// 在 shouldReceive 中过滤仅响应胶囊 frame 内的 touch。
        func install(on window: UIWindow, anchor: UIView) {
            // 避免重复安装
            if let existing = installedRecognizer, existing.view === window {
                attachedView = anchor
                return
            }
            attachedView = anchor
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            pan.cancelsTouchesInView = false  // 不吞 tap
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
            switch pan.state {
            case .began:
                fired = false
            case .changed:
                guard !fired else { return }
                let t = pan.translation(in: anchor)
                // 仅识别明显的横滑：|dx| > |dy| 且 |dx| ≥ threshold
                if abs(t.x) > abs(t.y), abs(t.x) >= threshold {
                    fired = true
                    onSwipe(t.x < 0 ? .left : .right)
                }
            default:
                break
            }
        }

        // 仅响应胶囊 frame 内的 touch，避免干扰其他区域
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

    /// HostMountView：用作胶囊后面的透明背景 view。
    /// - 本身 `isUserInteractionEnabled = false`，完全不拦截 touch，tap 正常传给上层胶囊
    /// - 被加到 view tree 后，在 didMoveToWindow 中把 UIPanGestureRecognizer 挂到 window 上
    /// - window 层级上手势不被 glassEffect 拦截，能看到胶囊上的所有 touch 事件
    /// - 配合 `cancelsTouchesInView = false`，touch 同时也能触发上层 onTapGesture
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