//  StatsTrendView.swift
//  CoinFlow · V2 Stats · 趋势曲线
//
//  设计基线：design/screens/05-stats/main-light.png（命名错位，实际是 trend）
//  - 顶部 30/90/180 分段
//  - 主曲线：收入（绿）vs 支出（红 + 渐变面积）
//  - 数据洞察：峰值/谷值/日均
//
//  数据：StatsViewModel.dailyTrend30/90/180

import SwiftUI
import Charts

struct StatsTrendView: View {
    @StateObject private var vm = StatsViewModel()
    @Environment(\.colorScheme) private var scheme
    @State private var range: TrendRange = .days30

    enum TrendRange: String, CaseIterable {
        case days30  = "30 天"
        case days90  = "90 天"
        case days180 = "180 天"
    }

    private var trendData: [StatsDailyPoint] {
        switch range {
        case .days30:  return vm.dailyTrend30
        case .days90:  return vm.dailyTrend90
        case .days180: return vm.dailyTrend180
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            StatsSubNavBar(title: "趋势曲线",
                           subtitle: "近 \(range.rawValue)",
                           trailingIcon: "square.and.arrow.up")
            ScrollView {
                VStack(spacing: NotionTheme.space7) {
                    rangeSwitcher
                    if vm.hasAnyData {
                        trendChart
                        insightCards
                    } else {
                        StatsEmptyState(title: "暂无趋势数据",
                                        subtitle: "记录几笔流水后，这里会展示日趋势")
                            .frame(height: 360)
                    }
                }
                .padding(.horizontal, NotionTheme.space5)
                .padding(.top, NotionTheme.space6)
                .padding(.bottom, NotionTheme.space9)
            }
        }
        .background(ThemedBackgroundLayer(kind: .stats))
        .navigationBarHidden(true)
        .onAppear { vm.reload() }
    }

    private var rangeSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(TrendRange.allCases, id: \.self) { r in
                Text(r.rawValue)
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(range == r ? Color.inkPrimary : Color.inkTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(range == r ? Color.canvasBG : Color.clear)
                    .cornerRadius(6)
                    .padding(2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) { range = r }
                    }
            }
        }
        .background(Color.hoverBg)
        .cornerRadius(NotionTheme.radiusCard)
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            HStack {
                Text("收入 vs 支出")
                    .font(.custom("PingFangSC-Semibold", size: 14))
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
                HStack(spacing: NotionTheme.space4) {
                    legendDot(color: NotionColor.green.text(scheme), label: "收入")
                    legendDot(color: NotionColor.red.text(scheme), label: "支出")
                }
            }
            .padding(.leading, 4)

            Chart {
                ForEach(trendData) { d in
                    LineMark(x: .value("日期", d.date),
                             y: .value("收入", (d.income as NSDecimalNumber).doubleValue))
                    .foregroundStyle(NotionColor.green.text(scheme))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    LineMark(x: .value("日期", d.date),
                             y: .value("支出", (d.expense as NSDecimalNumber).doubleValue))
                    .foregroundStyle(NotionColor.red.text(scheme))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    AreaMark(x: .value("日期", d.date),
                             y: .value("支出", (d.expense as NSDecimalNumber).doubleValue))
                    .foregroundStyle(
                        LinearGradient(colors: [
                            NotionColor.red.text(scheme).opacity(0.18),
                            NotionColor.red.text(scheme).opacity(0.0)
                        ], startPoint: .top, endPoint: .bottom)
                    )
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: max(1, trendData.count / 5))) { _ in
                    AxisGridLine().foregroundStyle(Color.divider.opacity(0.6))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.custom("PingFangSC-Regular", size: 9))
                        .foregroundStyle(Color.inkTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color.divider)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))")
                                .font(.custom("PingFangSC-Regular", size: 9))
                                .foregroundStyle(Color.inkTertiary)
                        }
                    }
                }
            }
            .frame(height: 220)
            .padding(NotionTheme.space5)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                    .fill(Color.hoverBg.opacity(0.5))
            )
        }
    }

    private var insightCards: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            Text("数据洞察")
                .font(.custom("PingFangSC-Semibold", size: 14))
                .foregroundStyle(Color.inkPrimary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                let stats = computeInsights()
                insightRow(icon: "arrow.up.circle.fill",
                           iconColor: NotionColor.red.text(scheme),
                           title: "支出峰值", detail: stats.peak)
                Rectangle().fill(Color.divider).frame(height: 0.5)
                    .padding(.leading, NotionTheme.space5 + 24 + NotionTheme.space5)
                insightRow(icon: "arrow.down.circle.fill",
                           iconColor: NotionColor.green.text(scheme),
                           title: "支出谷值", detail: stats.valley)
                Rectangle().fill(Color.divider).frame(height: 0.5)
                    .padding(.leading, NotionTheme.space5 + 24 + NotionTheme.space5)
                insightRow(icon: "equal.circle.fill",
                           iconColor: Color.accentBlue,
                           title: "日均支出", detail: stats.avg)
            }
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                    .fill(Color.hoverBg.opacity(0.5))
            )
        }
    }

    @ViewBuilder
    private func insightRow(icon: String, iconColor: Color, title: String, detail: String) -> some View {
        HStack(spacing: NotionTheme.space5) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(iconColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.inkPrimary)
                Text(detail)
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkSecondary)
        }
    }

    private struct InsightSummary {
        let peak: String
        let valley: String
        let avg: String
    }

    private func computeInsights() -> InsightSummary {
        let data = trendData
        guard !data.isEmpty else {
            return .init(peak: "—", valley: "—", avg: "—")
        }
        let f = DateFormatter()
        f.dateFormat = "M 月 d 日"
        let peakPoint = data.max(by: { $0.expense < $1.expense }) ?? data[0]
        let valleyPoint = data
            .filter { $0.expense > 0 }
            .min(by: { $0.expense < $1.expense }) ?? data[0]
        let totalExpense = data.map(\.expense).reduce(Decimal(0), +)
        let avg = (totalExpense as NSDecimalNumber).doubleValue / Double(data.count)
        return .init(
            peak: "\(f.string(from: peakPoint.date)) · ¥\(StatsFormat.intGrouped(peakPoint.expense))",
            valley: peakPoint.expense > 0
                ? "\(f.string(from: valleyPoint.date)) · ¥\(StatsFormat.intGrouped(valleyPoint.expense))"
                : "暂无支出记录",
            avg: String(format: "¥%.2f（共 %d 天）", avg, data.count)
        )
    }
}
