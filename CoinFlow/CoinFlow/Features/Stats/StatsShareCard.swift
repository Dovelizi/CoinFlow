//  StatsShareCard.swift
//  CoinFlow · V2 Stats · 分享卡片
//
//  4 个统计页面（本月/趋势/资金流向/年度）共用的"分享出去的图片"载体。
//  内容：标题 + 副标题 + 核心数字（净增/收入/支出/笔数）+ 底部 App 名 + 日期。
//  风格：与 App 内 stats 卡片一致（圆角 + 浅色卡片 + 苹方字）。
//
//  使用：StatsSnapshot.render { StatsShareCard(...) } 渲染为 UIImage。

import SwiftUI

/// 通用统计分享卡。各页面把"主要数据"塞进这一个布局，避免每个页面单独画一份。
struct StatsShareCard: View {
    let title: String
    let subtitle: String
    let net: Decimal
    let income: Decimal
    let expense: Decimal
    let count: Int

    /// 子页面可传额外的"对比数据"行（如年度回顾的同比/环比）。
    var extras: [(label: String, value: String)] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            mainCard
            footer
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.custom("PingFangSC-Semibold", size: 18))
                .foregroundColor(.primary)
            Text(subtitle)
                .font(.custom("PingFangSC-Regular", size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.top, 28)
        .padding(.bottom, 16)
    }

    private var mainCard: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("本月净增")
                    .font(.custom("PingFangSC-Regular", size: 11))
                    .foregroundColor(.secondary)
                Text(formatNet(net))
                    .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundColor(net >= 0 ? .green : .red)
            }

            HStack(spacing: 0) {
                shareCell(label: "收入",
                          text: "¥" + StatsFormat.decimalGrouped(income),
                          tone: .green)
                divider
                shareCell(label: "支出",
                          text: "¥" + StatsFormat.decimalGrouped(expense),
                          tone: .red)
                divider
                shareCell(label: "笔数",
                          text: "\(count)",
                          tone: .primary)
            }

            if !extras.isEmpty {
                Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 0.5)
                VStack(spacing: 10) {
                    ForEach(Array(extras.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item.label)
                                .font(.custom("PingFangSC-Regular", size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(item.value)
                                .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.08))
        )
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func shareCell(label: String, text: String, tone: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.custom("PingFangSC-Regular", size: 11))
                .foregroundColor(.secondary)
            Text(text)
                .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundColor(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 0.5, height: 28)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
            Text("CoinFlow · 来自我的账本")
                .font(.custom("PingFangSC-Regular", size: 10))
                .foregroundColor(.secondary)
            Spacer()
            Text(Self.dateString())
                .font(.custom("PingFangSC-Regular", size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 22)
    }

    private func formatNet(_ d: Decimal) -> String {
        let abs = d < 0 ? -d : d
        let sign = d >= 0 ? "+" : "-"
        return "\(sign)¥\(StatsFormat.decimalGrouped(abs))"
    }

    private static func dateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
