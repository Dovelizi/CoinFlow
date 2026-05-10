//  InlineStatsBar.swift
//  CoinFlow · M3.2 · §5.5.8
//
//  「支出 ¥xx / 收入 ¥xx / 结余 ¥xx」三段，等分剩余宽度。
//
//  v2（2026-05-10 用户反馈）：
//  - 改为卡片样式，对齐首页 heroData KPI 卡（cardSurface r=14 / hoverBgStrong）
//  - 圆角 14pt 更圆润；移除上下 hairline；保留竖线 divider 区分三段
//  - 高度 56 → 64（卡片内 padding + label/value 视觉透气度）

import SwiftUI

struct InlineStatsBar: View {

    let expense: Decimal
    let income: Decimal
    var balance: Decimal { income - expense }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            stat(label: "支出", value: AmountFormatter.display(expense),
                 valueColor: DirectionColor.amountForeground(kind: .expense))
            divider
            stat(label: "收入", value: AmountFormatter.display(income),
                 valueColor: DirectionColor.amountForeground(kind: .income))
            divider
            stat(label: "结余", value: AmountFormatter.display(balance),
                 valueColor: balance >= 0
                    ? DirectionColor.amountForeground(kind: .income)
                    : DirectionColor.amountForeground(kind: .expense))
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, NotionTheme.space4)
        .frame(maxWidth: .infinity)
        .cardSurface(cornerRadius: 14, notionFill: Color.hoverBgStrong)
    }

    private func stat(label: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .center, spacing: NotionTheme.space2) {
            Text(label)
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
            Text(value)
                .font(NotionFont.amountBold(size: 17))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(width: NotionTheme.borderWidth, height: 24)
    }
}

#if DEBUG
#Preview {
    InlineStatsBar(expense: 1843, income: 7200)
        .padding()
        .background(Color.canvasBG)
        .preferredColorScheme(.dark)
}
#endif
