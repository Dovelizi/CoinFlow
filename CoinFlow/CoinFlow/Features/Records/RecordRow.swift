//  RecordRow.swift
//  CoinFlow · M3.2 · §5.5.7（List 视图）
//
//  左 32×32 图标徽章（hoverBg 底）+ 中分类名/备注双行 + 右金额（status color）
//  + 同步状态点（5.5.2 唯一允许彩色文字之二）

import SwiftUI

struct RecordRow: View {

    let record: Record
    let category: Category?

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
            Text(category?.name ?? "未分类")
                .font(NotionFont.bodyBold())
                .foregroundStyle(Color.inkPrimary)
                .lineLimit(1)
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
                .lineLimit(1)
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
