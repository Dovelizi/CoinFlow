//  RecordGridView.swift
//  CoinFlow · M3.3 · §5.5.3 Grid 视图
//
//  2 列方卡。布局规范（用户调整版）：
//   - 第一行：图标左上 + 分类名水平居中于整张卡片（中轴线对齐）
//   - 金额 30pt 居中（中轴线对齐）
//   - 备注居中（中轴线对齐）
//
//  实现要点：第一行用 ZStack —— 图标用 HStack + Spacer 固定左侧；
//  分类名 frame(maxWidth: .infinity) 居中于整张卡，与下方金额、备注共用同一中轴线。

import SwiftUI

struct RecordGridView: View {

    let records: [Record]
    let categoryLookup: (Record) -> Category?
    let onTap: (Record) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: NotionTheme.space5),
        GridItem(.flexible(), spacing: NotionTheme.space5)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: NotionTheme.space5) {
            ForEach(records) { record in
                gridCard(record)
                    .onTapGesture { onTap(record) }
            }
        }
        .padding(.horizontal, NotionTheme.space5)
    }

    private func gridCard(_ record: Record) -> some View {
        let cat = categoryLookup(record)
        let kind = cat?.kind ?? .expense
        return VStack(spacing: NotionTheme.space4) {
            // 第一行：图标左 + 分类名居中于整张卡片
            ZStack {
                // 居中层：分类名水平居中于整张卡（与下方金额/备注同一中轴线）
                Text(cat?.name ?? "未分类")
                    .font(NotionFont.body())
                    .foregroundStyle(Color.inkPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)

                // 图标层：固定左上
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: NotionTheme.radiusMD, style: .continuous)
                            .fill(Color.hoverBg)
                        Image(systemName: cat?.icon ?? "questionmark")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .frame(width: 28, height: 28)
                    Spacer()
                }
            }

            // 金额：30pt 居中。
            // 关键：用 Color.clear 占位并 overlay 渲染 Text —— 这样金额的「固有宽度」
            // 不会反向把 LazyVGrid 的列宽撑开（极大金额场景会让该列变宽、邻列被挤窄）。
            // 高度由内层 Text 撑起；overlay 不参与父级 sizing，宽度严格等于父容器（卡片）。
            Color.clear
                .frame(height: 30 * 1.2)
                .overlay(
                    Text("\(kind == .expense ? "-" : "+")\(AmountFormatter.display(record.amount))")
                        .font(NotionFont.amountBold(size: 30))
                        .foregroundStyle(DirectionColor.amountForeground(kind: kind))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .allowsTightening(true)
                        .padding(.horizontal, 4)
                )

            // 备注：居中（无内容时渲染等高占位，保证同行卡片高度一致）
            if let n = record.note, !n.isEmpty {
                Text(n)
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkTertiary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            } else {
                // 占位：与备注同字号同行高，仅用于撑高，视觉不可见
                Text(" ")
                    .font(NotionFont.small())
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .padding(NotionTheme.space5)
        .frame(maxWidth: .infinity)
        // 主题感知卡片：Notion 14pt 圆角更圆润，LGA 自动 18pt 圆角实色
        .cardSurface(cornerRadius: 14,
                     notionFill: Color.surfaceOverlay,
                     notionStroke: Color.border)
    }
}
