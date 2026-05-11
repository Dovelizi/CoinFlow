//  TabBarVisibility.swift
//  CoinFlow · M7 · 底部胶囊 TabBar 滚动联动隐藏
//
//  MainTabView 持有 TabBarVisibility 并通过 environmentObject 注入子页面。
//  子页面在 ScrollView 外层调用 `.trackScrollForTabBar()` 即可自动上报偏移。
//  滚动方向判定（delta > threshold）在 observer 内部节流处理，
//  子页面不关心任何逻辑，只需挂 modifier。
//
//  iOS 16+ 实现：GeometryReader 在 ScrollView 内部固定一个 0 高度 anchor，
//  读 minY 通过 PreferenceKey 冒泡到容器 view；MainTabView 拿到 delta 后判定。

import SwiftUI

/// 胶囊 TabBar 可见性控制（单例样式，作为 @StateObject 挂在 MainTabView 上）
@MainActor
final class TabBarVisibility: ObservableObject {
    /// 当前是否可见
    @Published var isVisible: Bool = true

    /// 上一次采集到的 scroll offset；用于计算 delta
    private var lastOffset: CGFloat = 0
    /// 方向切换阈值：短距离抖动忽略
    private let threshold: CGFloat = 8

    /// 由子页面通过 preference 上报最新偏移（offset 是 ScrollView 顶部 anchor 相对容器的 minY，
    /// 向下滚动时 anchor 向上移 → minY 减小；向上滚动时 minY 增大）
    func report(offset: CGFloat) {
        let delta = offset - lastOffset
        guard abs(delta) > threshold else { return }
        lastOffset = offset

        // delta < 0 表示手指向上推、内容向上滚（阅读更多）→ 隐藏
        // delta > 0 表示手指向下拉、内容向下滚（回到顶部）→ 显示
        let shouldShow = delta > 0
        if shouldShow != isVisible {
            withAnimation(Motion.smooth) {
                isVisible = shouldShow
            }
        }
    }

    /// 切换 tab / 显式请求时调用，立即显示
    func forceShow() {
        withAnimation(Motion.snap) {
            isVisible = true
        }
        lastOffset = 0
    }
}

// MARK: - PreferenceKey

private struct TabBarScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Modifier

extension View {
    /// 在 ScrollView 最外层挂上此 modifier；observer 为 MainTabView 注入的 TabBarVisibility。
    /// 原理：在 ScrollView 内部放一个 0 高度的 GeometryReader 做 anchor，
    /// 该 anchor 的 minY 随 ScrollView 偏移变化而变化；
    /// .coordinateSpace("TabBarScrollSpace") 让 minY 相对子页面容器（非全屏）稳定。
    func trackScrollForTabBar(_ observer: TabBarVisibility) -> some View {
        self.coordinateSpace(name: "TabBarScrollSpace")
            .onPreferenceChange(TabBarScrollOffsetKey.self) { newValue in
                Task { @MainActor in
                    observer.report(offset: newValue)
                }
            }
    }

    /// 放在 ScrollView 内容顶部的零高度探针；与 `trackScrollForTabBar` 配对使用。
    func tabBarScrollAnchor() -> some View {
        self.background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: TabBarScrollOffsetKey.self,
                    value: geo.frame(in: .named("TabBarScrollSpace")).minY
                )
            }
            .frame(height: 0)
        )
    }
}
