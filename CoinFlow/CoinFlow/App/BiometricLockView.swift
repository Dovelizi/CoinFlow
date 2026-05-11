//  BiometricLockView.swift
//  CoinFlow · M6 · §11 Face ID 启动锁屏
//
//  职责：
//  - 全屏拦截，居中按钮 "使用 Face ID 解锁"
//  - 进入即自动调一次 evaluatePolicy（用户首次冷启动直接弹原生 Face ID）
//  - 失败 → 显示错误文案 + 提供"再试一次"按钮
//  - 用户取消 → 保持锁定，不退出 App（让用户主动重试）

import SwiftUI

struct BiometricLockView: View {

    @EnvironmentObject private var appState: AppState
    @State private var lastError: String?
    @State private var isAuthenticating = false

    private var biometricKindName: String {
        BiometricAuthService.shared.availableKind.displayName
    }

    var body: some View {
        ZStack {
            ThemedBackgroundLayer(kind: .lock)
            VStack(spacing: NotionTheme.space6) {
                Spacer()
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Color.accentBlue)
                VStack(spacing: NotionTheme.space3) {
                    Text("CoinFlow 已锁定")
                        .font(NotionFont.h3())
                        .foregroundStyle(Color.inkPrimary)
                    Text("使用 \(biometricKindName) 解锁查看流水")
                        .font(NotionFont.small())
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer()
                Button {
                    Task { await runAuth() }
                } label: {
                    HStack(spacing: NotionTheme.space3) {
                        Image(systemName: BiometricAuthService.shared.availableKind == .faceID
                              ? "faceid" : "touchid")
                            .font(.system(size: 18, weight: .regular))
                        Text(isAuthenticating ? "正在验证…" : "解锁")
                            .font(NotionFont.bodyBold())
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                            .fill(Color.accentBlue)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSoft)
                .disabled(isAuthenticating)
                .padding(.horizontal, NotionTheme.space6)
                // 错误文案放在 CTA 下方，保持主区域稳定（首次进入与失败时 layout 一致）
                if let err = lastError {
                    Text(err)
                        .font(NotionFont.small())
                        .foregroundStyle(Color(hex: "#DF5452"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, NotionTheme.space7)
                } else {
                    // 占位高度，避免有 / 无错误时 CTA 上下抖动
                    Color.clear.frame(height: 16)
                }
                Spacer().frame(height: NotionTheme.space5)
            }
        }
        .task { await runAuth() }
    }

    private func runAuth() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        let result = await appState.unlockWithBiometrics()
        isAuthenticating = false
        switch result {
        case .success: lastError = nil
        case .failure(let err): lastError = err.localizedDescription
        }
    }
}
