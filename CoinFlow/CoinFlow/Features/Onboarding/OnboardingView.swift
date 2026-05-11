//  OnboardingView.swift
//  CoinFlow · M7 · [13-1]
//
//  设计基线：design/screens/13-onboarding/main-{light,dark}.png +
//           CoinFlowPreview MiscScreensView.OnboardingView（L595-642）
//
//  单屏引导：钱袋 64pt icon + "CoinFlow" 36pt + slogan + 底部 CTA。
//  CTA 触发 AppState.completeOnboarding() → 切主流程。

import SwiftUI

struct OnboardingView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            ThemedBackgroundLayer(kind: .onboarding)
            VStack(spacing: 0) {
                Spacer()
                welcomeContent
                Spacer()
                ctaButton
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.bottom, NotionTheme.space7)
        }
        .accessibilityLabel("欢迎进入 CoinFlow")
    }

    private var welcomeContent: some View {
        VStack(spacing: NotionTheme.space7) {
            Image(systemName: "bag")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(Color.inkPrimary)
                .accessibilityHidden(true)
                .softAppear(delay: 0.05, distance: 16)

            VStack(spacing: NotionTheme.space3) {
                Text("CoinFlow")
                    .font(.custom("PingFangSC-Semibold", size: 36))
                    .foregroundStyle(Color.inkPrimary)
                    .tracking(-0.5)
                    .softAppear(delay: 0.18, distance: 12)
                Text("一句话，一张图，一笔账")
                    .font(.custom("PingFangSC-Regular", size: 17))
                    .foregroundStyle(Color.inkSecondary)
                    .softAppear(delay: 0.30, distance: 12)
            }
        }
    }

    private var ctaButton: some View {
        Button {
            // 引导完成是关键节点：success 触觉 + 由 AppState 切换主流程
            Haptics.success()
            appState.completeOnboarding()
        } label: {
            Text("开启 CoinFlow")
                .font(.custom("PingFangSC-Semibold", size: 17))
                .foregroundStyle(Color.canvasBG)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.inkPrimary)
                )
        }
        .buttonStyle(.pressableAccent)
        .softAppear(delay: 0.45, distance: 16)
        .accessibilityLabel("开启 CoinFlow")
        .accessibilityHint("完成首次启动引导，进入主页面")
    }
}

#if DEBUG
#Preview {
    OnboardingView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
#endif
