//  TabBarVisibility.swift
//  CoinFlow · M7 · 底部胶囊 TabBar 滚动联动隐藏
//
//  MainTabView 持有 TabBarVisibility 并通过 environmentObject 注入子页面。
//  子页面在 ScrollView 外层调用 `.trackScrollForTabBar()` 即可自动上报偏移。
//  滚动方向判定（delta > threshold）在 observer 内部节流处理，
//  子页面不关心任何逻辑，只需挂 modifier。
//
//  M11 升级：新增"二级页隐藏"引用计数。
//    - 一级 tab（首页/流水/统计/我的）显示胶囊（同时受滚动联动影响）。
//    - 任意 push 进二级页面：在二级页根挂 `.hideTabBar()` 即可隐藏胶囊。
//    - 二级页 pop 回一级页：自动恢复显示。
//    - 嵌套 push（二级 → 三级）通过引用计数（hideStackDepth）保持隐藏，
//      pop 回二级仍隐藏，回到一级才显示。
//
//  iOS 16+ 实现：GeometryReader 在 ScrollView 内部固定一个 0 高度 anchor，
//  读 minY 通过 PreferenceKey 冒泡到容器 view；MainTabView 拿到 delta 后判定。

import SwiftUI

/// 胶囊 TabBar 可见性控制（单例样式，作为 @StateObject 挂在 MainTabView 上）
@MainActor
final class TabBarVisibility: ObservableObject {
    /// 当前是否可见（外部观察）
    /// 派生自 `scrollSaysShow && hideStackDepth == 0`，由 `recompute()` 同步。
    @Published private(set) var isVisible: Bool = true

    /// 滚动联动给出的可见性意见（向下滚 → false；向上滚 → true）。
    /// 仅由 `report(offset:)` / `forceShow()` 维护。
    private var scrollSaysShow: Bool = true

    /// 二级及以上页面的隐藏请求引用计数。
    /// `.hideTabBar()` modifier 在 onAppear 时 +1，在 onDisappear 时 -1。
    /// 大于 0 时强制隐藏胶囊，与 scrollSaysShow 无关。
    private var hideStackDepth: Int = 0

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
        scrollSaysShow = delta > 0
        recompute(animated: true)
    }

    /// 切换 tab / 显式请求时调用，立即显示
    /// 注意：仅当当前没有任何二级页隐藏请求（hideStackDepth == 0）时才真的会显示；
    /// 否则只重置 scrollSaysShow 状态，待二级页 pop 后再露面。
    func forceShow() {
        scrollSaysShow = true
        lastOffset = 0
        recompute(animated: false, snap: true)
    }

    /// 二级页面进入时调用：引用计数 +1，立即隐藏。
    /// 由 `.hideTabBar()` modifier 在 `.onAppear` 时调用。
    func pushHide() {
        hideStackDepth += 1
        recompute(animated: true)
    }

    /// 二级页面退出时调用：引用计数 -1（最低 0），若为 0 则自动恢复。
    /// 由 `.hideTabBar()` modifier 在 `.onDisappear` 时调用。
    func popHide() {
        hideStackDepth = max(0, hideStackDepth - 1)
        // 离开二级页自动重置滚动判定，避免回到一级页因为 scrollSaysShow=false 而仍隐藏。
        if hideStackDepth == 0 {
            scrollSaysShow = true
            lastOffset = 0
        }
        recompute(animated: true)
    }

    /// 同步 isVisible = scrollSaysShow && hideStackDepth == 0
    private func recompute(animated: Bool, snap: Bool = false) {
        let target = scrollSaysShow && hideStackDepth == 0
        guard target != isVisible else { return }
        if animated {
            withAnimation(snap ? Motion.snap : Motion.smooth) {
                isVisible = target
            }
        } else {
            isVisible = target
        }
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

    /// 二级及以上页面挂在根视图上：进入时隐藏底部浮动胶囊 TabBar，离开时恢复。
    /// 内部走 TabBarVisibility 的引用计数（hideStackDepth），支持嵌套 push 场景。
    /// 一级 tab 根页面（首页/流水/统计/我的）**不要**挂此 modifier。
    func hideTabBar() -> some View {
        modifier(HideTabBarModifier(active: true))
    }

    /// 条件挂载版：`active = true` 才隐藏胶囊；常用于"既能作为一级 tab 嵌入、
    /// 也能从其他 tab push"的双身份页面（如 SettingsView）。
    /// 用 `if` 包裹会改变视图 identity，所以提供该重载避免分支挂载。
    func hideTabBar(if active: Bool) -> some View {
        modifier(HideTabBarModifier(active: active))
    }
}

/// `.hideTabBar()` 的实现细节：onAppear/onDisappear 配对调用引用计数 API。
/// 注意：环境对象 `TabBarVisibility` 由 MainTabView 注入；如果当前视图栈
/// 找不到（比如 #Preview 单独跑某个二级页），不会注入对象，会运行时报错——
/// 设计上二级页只可能从 MainTabView 进入，不存在游离场景；预览写 Preview
/// 时若需要单独跑可手动 `.environmentObject(TabBarVisibility())`。
private struct HideTabBarModifier: ViewModifier {
    /// 是否启用本次隐藏请求。false 时 modifier 退化为 no-op，
    /// onAppear/onDisappear 都不会触碰引用计数——既保留了 modifier 挂载的稳定 identity，
    /// 又允许调用方根据 props 决定是否真隐藏（如 SettingsView 的 embeddedInTab）。
    let active: Bool

    @EnvironmentObject private var tabBarVisibility: TabBarVisibility

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard active else { return }
                tabBarVisibility.pushHide()
            }
            .onDisappear {
                guard active else { return }
                tabBarVisibility.popHide()
            }
    }
}