//  BackTapSetupView.swift
//  CoinFlow · M6 · §6.1 Back Tap 配置说明
//
//  Back Tap 是 iOS 14+ 提供的物理敲背快捷指令链路：
//    设置 → 辅助功能 → 触控 → 轻点背面 → 选择"双击/三击" → 选 Shortcut
//  Shortcut 调用 App Intent 触发 CoinFlow 的截屏识别流程。
//
//  M6 范围：
//  - 本视图作为 App 内说明页（"如何配置"图文向导）
//  - App Intent 骨架（CoinFlowCaptureIntent）已在 Features/Capture/CoinFlowCaptureIntent.swift 注册
//  - Shortcut 配置走系统快捷指令 App，由用户手动添加；本页提供步骤截图占位

import SwiftUI

struct BackTapSetupView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            ThemedBackgroundLayer(kind: .settings)
            VStack(spacing: 0) {
                navBar
                ScrollView {
                    VStack(alignment: .leading, spacing: NotionTheme.space6) {
                        introCard
                        stepsCard
                        notesCard
                    }
                    .padding(NotionTheme.space5)
                }
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Nav

    private var navBar: some View {
        ZStack {
            Text("Back Tap 配置")
                .font(NotionFont.h3())
                .foregroundStyle(Color.inkPrimary)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.inkPrimary)
                        .frame(width: 36, height: 36)
                }.buttonStyle(.pressableSoft)
                Spacer()
            }
            .padding(.horizontal, NotionTheme.space5)
        }
        .frame(height: NotionTheme.topbarHeight)
        .background(Color.appCanvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.divider).frame(height: NotionTheme.borderWidth)
        }
    }

    // MARK: - Sections

    private var introCard: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            HStack(spacing: NotionTheme.space3) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color.accentBlue)
                Text("一键截屏识账")
                    .font(NotionFont.h3())
                    .foregroundStyle(Color.inkPrimary)
            }
            Text("用 iPhone 背面双击/三击触发截屏并自动识别账单——不用打开 CoinFlow，操作 ≤ 5 秒。")
                .font(NotionFont.body())
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(NotionTheme.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                .fill(Color.surfaceOverlay)
        )
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            Text("配置步骤")
                .font(NotionFont.bodyBold())
                .foregroundStyle(Color.inkPrimary)
            stepRow(num: 1, title: "在 iOS 系统打开",
                    detail: "设置 → 辅助功能 → 触控 → 轻点背面")
            stepRow(num: 2, title: "选择触发方式",
                    detail: "双击 或 三击（推荐三击避免误触）")
            stepRow(num: 3, title: "在快捷指令列表中选择 CoinFlow",
                    detail: "选择「CoinFlow · 截屏识账」→ 完成")
            stepRow(num: 4, title: "测试触发",
                    detail: "对准账单截屏 → 敲击背面 → 自动跳到确认页")
        }
        .padding(NotionTheme.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                .fill(Color.surfaceOverlay)
        )
    }

    private func stepRow(num: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: NotionTheme.space4) {
            ZStack {
                // 实心填充 + 白字以确保 dark/light 双主题下 ≥ 4.5:1 WCAG AA 对比度
                Circle()
                    .fill(Color.accentBlue)
                    .frame(width: 24, height: 24)
                Text("\(num)")
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(NotionFont.body())
                    .foregroundStyle(Color.inkPrimary)
                Text(detail)
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
            }
        }
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            Text("注意事项")
                .font(NotionFont.bodyBold())
                .foregroundStyle(Color.inkPrimary)
            bullet("仅 iPhone 8 及以上支持 Back Tap")
            bullet("快捷指令首次触发需授权访问「相册」读取截屏")
            bullet("识别完成后，截图会自动从相册删除（隐私优先）")
        }
        .padding(NotionTheme.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                .fill(Color.surfaceOverlay)
        )
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: NotionTheme.space3) {
            Text("•")
                .font(NotionFont.body())
                .foregroundStyle(Color.inkTertiary)
            Text(s)
                .font(NotionFont.small())
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
