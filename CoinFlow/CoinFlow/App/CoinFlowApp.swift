//  CoinFlowApp.swift
//  CoinFlow · M3.2 → M9
//
//  入口职责：
//  1. 构造 AppState；启动时串行 bootstrap 各子系统
//  2. 监听 ScenePhase 变化：active 时刷新数据 + 截图剪贴板探测
//  3. 渲染 OnboardingView / MainTabView 业务首页
//  4. M6: scenePhase != .active 时叠 PrivacyShieldView（应用切换器隐私）
//  5. M6: bioLocked 时叠 BiometricLockView 拦截 UI
//
//  M9 切换：飞书多维表格不需要 Firebase 那种全局 SDK 初始化，AppConfig 单例懒加载即可。

import SwiftUI

@main
struct CoinFlowApp: App {

    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                // M7 [13-1] 根路由：首次启动 → OnboardingView；否则 MainTabView
                Group {
                    if appState.hasCompletedOnboarding {
                        MainTabView()
                            .environmentObject(appState)
                    } else {
                        OnboardingView()
                            .environmentObject(appState)
                    }
                }
                .task { await appState.bootstrap() }
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        appState.onScenePhaseActive()
                        // 快捷指令剪贴板方案：Intent 触发时打了时间戳，主 App 回前台
                        // 后校验"最近 3 秒"窗口 + detectPatterns 静默探测，有图才读取。
                        // 100ms 延迟：让 HomeMainView 的 onReceive 订阅先挂上。
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            await ScreenshotInbox.shared.tryConsumePasteboardImage()
                        }
                    }
                }

                // M6: 应用切换器隐私 shield（inactive/background 即覆盖）
                if scenePhase != .active {
                    PrivacyShieldView()
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.18), value: scenePhase)
                        .zIndex(10)
                }

                // M6: 生物识别锁屏（启用 + 未解锁 时拦截）
                if appState.bioLocked {
                    BiometricLockView()
                        .environmentObject(appState)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.18), value: appState.bioLocked)
                        .zIndex(20)
                }
            }
            // LGA 主题根背景：开关启用时整树最底层叠 LiquidGlassABackground，
            // 锁屏/隐私 shield 也会跟随；关闭时不渲染任何背景，保持原 Notion 视觉零变化。
            .themedRootBackground()
            .preferredColorScheme(.dark) // 文档 B10
        }
    }
}
