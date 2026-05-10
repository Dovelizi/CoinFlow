//  PrivacyShieldView.swift
//  CoinFlow · M6 · §11 后台预览模糊化
//
//  当 App 进入 inactive / background 时，覆盖一层模糊 + Logo + "CoinFlow" 占位，
//  让 iOS 应用切换器（App Switcher）看到的是脱敏画面而非真实流水。
//
//  实现策略：
//  - 由 CoinFlowApp 监听 scenePhase；非 .active 时叠在 RecordsListView 上方
//  - 使用 .ultraThinMaterial 提供原生模糊
//  - .transition(.opacity) 给 0.2s 渐显避免突兀

import SwiftUI

struct PrivacyShieldView: View {
    var body: some View {
        ZStack {
            // 底层用 surfaceOverlay：dark 时 #252525，light 时浅色
            // 比 canvasBG（light=纯白）更能在 App Switcher 缩略图中形成可辨识的"卡片"轮廓
            Color.surfaceOverlay.ignoresSafeArea()
            // material 模糊层（柔化）
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            // 再叠一层半透明 canvas，确保 light 下也有明显灰底而非全白
            Color.canvasBG.opacity(0.35).ignoresSafeArea()
            // Logo + 应用名占位
            VStack(spacing: NotionTheme.space5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color.inkSecondary)
                Text("CoinFlow")
                    .font(NotionFont.h3())
                    .foregroundStyle(Color.inkPrimary)
                Text("已隐藏内容")
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkTertiary)
            }
        }
        .accessibilityHidden(true)
    }
}
