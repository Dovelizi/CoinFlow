//  BillsSummaryPushBanner.swift
//  CoinFlow · M10-Fix4 · 首页推送 banner
//
//  形态：
//  - 顶部下滑进入的 banner，距 safe area top 4pt
//  - 左 emoji + 主标题 + 副标题 + 右 chevron + 右上 ✕
//  - 关闭策略（任一触发即关）：
//      a) 用户主动点 ✕
//      b) 用户点击正文 3 次（每次点击都会触发 onTap 唤出浮窗，第 3 次同时关闭）
//      c) 出现后 10 分钟自动关闭（被新 push 打断时通过 `.id(push.id)` 重建重置计时）
//  - ✕ 独立命中区，点击仅关闭不触发 onTap
//
//  设计取舍：
//  - 保持 HomeMainView 的入口复杂度不变：banner 的定时 / 动画全部封装在组件内
//  - 使用 NotionTheme token，与其它卡片视觉一致

import SwiftUI

/// 首页推送 banner 的数据载体。HomeMainView 持有 @State BillsSummaryPush?，非 nil 就展示。
struct BillsSummaryPush: Identifiable, Equatable {
    let id: String        // 同 summary.id，用于外部去重
    let summary: BillsSummary

    init(_ s: BillsSummary) {
        self.id = s.id
        self.summary = s
    }
}

struct BillsSummaryPushBanner: View {

    let push: BillsSummaryPush
    let onTap: () -> Void
    let onDismiss: () -> Void

    /// 10 分钟自动关闭；新 push 进来时组件会被 `.id(push.id)` 整体重建 → timer 自动重置
    @State private var autoCloseTask: Task<Void, Never>?
    /// 用户点击正文累计次数；达到 3 次后随该次点击一并关闭
    @State private var tapCount: Int = 0

    /// 自动关闭时长（10 分钟）
    private static let autoCloseInterval: UInt64 = 600 * 1_000_000_000
    /// 点击关闭阈值
    private static let tapDismissThreshold: Int = 3

    var body: some View {
        Button {
            // 每次点击都唤出浮窗（外部 onTap 已经清 pendingSummaryPush 并打开浮窗）
            tapCount += 1
            if tapCount >= Self.tapDismissThreshold {
                onDismiss()
            }
            onTap()
        } label: {
            HStack(spacing: NotionTheme.space3) {
                // 左 emoji 圆标
                ZStack {
                    Circle()
                        .fill(Color.accentBlueBG)
                        .frame(width: 36, height: 36)
                    Text(kindEmoji)
                        .font(.system(size: 18))
                }
                // 主副标题
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(NotionFont.bodyBold())
                        .foregroundStyle(Color.inkPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                }
                Spacer()
                // 右 chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.inkTertiary)
                // ✕ 关闭（独立命中区）
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.inkTertiary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.vertical, NotionTheme.space3)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                    .fill(Color.canvasBG)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                    .stroke(Color.border, lineWidth: NotionTheme.borderWidth)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, NotionTheme.space5)
        .padding(.top, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear { scheduleAutoClose() }
        .onDisappear { autoCloseTask?.cancel() }
    }

    // MARK: - 计算属性

    private var title: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = .current
        let label: String
        switch push.summary.periodKind {
        case .week:
            f.dateFormat = "M/d"
            let start = f.string(from: push.summary.periodStart)
            let end = f.string(from: push.summary.periodEnd)
            label = "本周（\(start) — \(end)）"
        case .month:
            f.dateFormat = "yyyy 年 M 月"
            label = f.string(from: push.summary.periodStart)
        case .year:
            f.dateFormat = "yyyy 年度"
            label = f.string(from: push.summary.periodStart)
        }
        return "\(label)账单复盘已就绪"
    }

    private var subtitle: String {
        let digest = push.summary.summaryDigest
        if !digest.isEmpty {
            return digest
        }
        return "\(push.summary.recordCount) 笔 · 点击查看完整复盘"
    }

    private var kindEmoji: String {
        switch push.summary.periodKind {
        case .week:  return "✨"
        case .month: return "📊"
        case .year:  return "🎊"
        }
    }

    // MARK: - Auto close

    private func scheduleAutoClose() {
        autoCloseTask?.cancel()
        autoCloseTask = Task {
            try? await Task.sleep(nanoseconds: Self.autoCloseInterval)
            guard !Task.isCancelled else { return }
            await MainActor.run { onDismiss() }
        }
    }
}
