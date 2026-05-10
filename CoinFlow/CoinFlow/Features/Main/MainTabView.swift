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
        .fixedSize()
        .frame(maxWidth: .infinity)
        // 底部胶囊距 home indicator 的距离（用户要求当前距离减半：4pt → 2pt）
        .padding(.bottom, 2)
    }

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
