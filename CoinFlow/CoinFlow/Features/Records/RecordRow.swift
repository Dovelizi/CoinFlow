//  RecordRow.swift
//  CoinFlow · M3.2 · §5.5.7（List 视图）
//
//  左 32×32 图标徽章（hoverBg 底）+ 中分类名/备注双行 + 右金额（status color）
//  + 同步状态点（5.5.2 唯一允许彩色文字之二）

import SwiftUI

struct RecordRow: View {

    let record: Record
    let category: Category?
    /// AA 标签（外部 VM 计算后传入）：
    /// - nil：纯个人流水
    /// - .settled：已结算 AA 回写流水（紫色"AA"）
    /// - .pending：未结算 AA 原始流水（橙色"AA · 待结算"）
    let aaBadge: RecordAABadge?

    init(record: Record, category: Category?, aaBadge: RecordAABadge? = nil) {
        self.record = record
        self.category = category
        self.aaBadge = aaBadge
    }

    var body: some View {
        HStack(alignment: .center, spacing: NotionTheme.space5) {
            iconBadge
            textBlock
            Spacer(minLength: NotionTheme.space4)
            amountBlock
        }
        .padding(.vertical, NotionTheme.space5)
        .padding(.horizontal, NotionTheme.space5)
        .contentShape(Rectangle())
    }

    // MARK: - Icon

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: NotionTheme.radiusMD, style: .continuous)
                .fill(Color.hoverBg)
                .frame(width: 32, height: 32)
            Image(systemName: category?.icon ?? "questionmark")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.inkSecondary)
        }
    }

    // MARK: - Text

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space2) {
            HStack(spacing: NotionTheme.space2) {
                Text(category?.name ?? "未分类")
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.inkPrimary)
                    .lineLimit(1)
                // M11+：AA 状态徽标（由外部 VM 决策，路径 A）
                aaBadgeView
            }
            if let note = record.note, !note.isEmpty {
                Text(note)
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkTertiary)
                    .lineLimit(1)
            } else {
                Text(timeText)
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkTertiary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var aaBadgeView: some View {
        switch aaBadge {
        case .none:
            EmptyView()
        case .settledPlaceholder:
            Text("AA · 已结算")
                .font(NotionFont.micro())
                .foregroundStyle(Color.accentPurple)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.accentPurple.opacity(0.12))
                )
        case .settlingPlaceholder:
            Text("AA · 结算中")
                .font(NotionFont.micro())
                .foregroundStyle(Color.statusWarning)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.statusWarning.opacity(0.14))
                )
        }
    }

    private var timeText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: record.occurredAt)
    }

    // MARK: - Amount

    private var amountBlock: some View {
        VStack(alignment: .trailing, spacing: NotionTheme.space2) {
            Text(amountText)
                .font(NotionFont.amount(size: 17))
                .foregroundStyle(amountColor)
                // 全局规则：金额超宽时等比例缩小，禁止截断/换行
                .amountAutoFit(base: 17)
            HStack(spacing: NotionTheme.space2) {
                if record.syncStatus != .synced {
                    Circle()
                        .fill(SyncStatusColor.dot(for: record.syncStatus))
                        .frame(width: 6, height: 6)
                }
                Text(sourceText)
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
            }
        }
    }

    private var kind: CategoryKind { category?.kind ?? .expense }

    private var amountText: String {
        let prefix = kind == .expense ? "-" : "+"
        return "\(prefix)\(AmountFormatter.display(record.amount))"
    }

    private var amountColor: Color {
        DirectionColor.amountForeground(kind: kind)
    }

    private var sourceText: String {
        switch record.source {
        case .manual:      return "手动"
        case .ocrVision:   return "本地OCR"
        case .ocrAPI:      return "OCR-API"
        case .ocrLLM:      return "大模型"
        case .voiceLocal:  return "本地语音"
        case .voiceCloud:  return "云端语音"
        }
    }
}
