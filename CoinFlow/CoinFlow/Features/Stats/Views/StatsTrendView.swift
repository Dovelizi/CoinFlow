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
    @StateObject private var vm: StatsViewModel
    @Environment(\.colorScheme) private var scheme
    @State private var range: TrendRange = .days30

    init(month: YearMonth = .current) {
        _vm = StateObject(wrappedValue: StatsViewModel(month: month))
    }

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

    /// 上下对称的 Y 轴区间：入为正、出为负，0 始终在中间。
    private var yAxisDomain: ClosedRange<Double> {
        let maxIncome  = trendData.map { ($0.income  as NSDecimalNumber).doubleValue }.max() ?? 0
        let maxExpense = trendData.map { ($0.expense as NSDecimalNumber).doubleValue }.max() ?? 0
        let bound = max(maxIncome, maxExpense)
        // 避免底部/顶部贴边，加 10% 余量；空数据兴逻辑交给上层 hasAnyData 拦截。
        let padded = max(bound * 1.1, 1)
        return -padded ... padded
    }

    var body: some View {
        VStack(spacing: 0) {
            StatsSubNavBar(title: "趋势曲线",
                           subtitle: "近 \(range.rawValue)")
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
        // liquidGlass 主题下 Color.canvasBG 是页面深色底，叠在彩色卡片上选中段呈黑块。
        // 与 NewRecordModal/SettingsView 段控件保持同一兜底方案：液态玻璃下走半透白高亮。
        let activeFill: Color = LGAThemeRuntime.isLiquidGlass
            ? Color.white.opacity(0.18)
            : Color.canvasBG
        return HStack(spacing: 0) {
            ForEach(TrendRange.allCases, id: \.self) { r in
                Text(r.rawValue)
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(range == r ? Color.inkPrimary : Color.inkTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(range == r ? activeFill : Color.clear)
                    .cornerRadius(6)
                    .padding(2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(Motion.snap) { range = r }
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
                    legendDot(color: DirectionColor.amountForeground(kind: .income), label: "收入")
                    legendDot(color: DirectionColor.amountForeground(kind: .expense), label: "支出")
                }
            }
            .padding(.leading, 4)

            Chart {
                ForEach(trendData) { d in
                    AreaMark(x: .value("日期", d.date),
                             y: .value("金额", (d.income as NSDecimalNumber).doubleValue),
                             series: .value("类型", "收入"),
                            stacking: .unstacked)
                    .foregroundStyle(
                        LinearGradient(colors: [
                            DirectionColor.amountForeground(kind: .income).opacity(0.70),
                            DirectionColor.amountForeground(kind: .income).opacity(0.25)
                        ], startPoint: .top, endPoint: .bottom)
                    )
                    .interpolationMethod(.catmullRom)

                    AreaMark(x: .value("日期", d.date),
                             y: .value("金额", -(d.expense as NSDecimalNumber).doubleValue),
                             series: .value("类型", "支出"),
                             stacking: .unstacked)
                    .foregroundStyle(
                        LinearGradient(colors: [
                            DirectionColor.amountForeground(kind: .expense).opacity(0.70),
                            DirectionColor.amountForeground(kind: .expense).opacity(0.25)
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
                            // 支出为负值，标签显示绝对值
                            Text("\(Int(abs(v)))")
                                .font(.custom("PingFangSC-Regular", size: 9))
                                .foregroundStyle(Color.inkTertiary)
                        }
                    }
                }
            }
            .chartYScale(domain: yAxisDomain)
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
                           iconColor: DirectionColor.amountForeground(kind: .expense),
                           title: "支出峰值", detail: stats.peak)
                Rectangle().fill(Color.divider).frame(height: 0.5)
                    .padding(.leading, NotionTheme.space5 + 24 + NotionTheme.space5)
                insightRow(icon: "arrow.down.circle.fill",
                           iconColor: DirectionColor.amountForeground(kind: .income),
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
            peak: "\(f.string(from: peakPoint.date)) · ¥\(StatsFormat.decimalGrouped(peakPoint.expense))",
            valley: peakPoint.expense > 0
                ? "\(f.string(from: valleyPoint.date)) · ¥\(StatsFormat.decimalGrouped(valleyPoint.expense))"
                : "暂无支出记录",
            avg: String(format: "¥%.2f（共 %d 天）", avg, data.count)
        )
    }
}
