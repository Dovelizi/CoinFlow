//  StatsHourlyView.swift
//  CoinFlow · V2 Stats · 时段分布
//
//  设计基线：design/screens/05-stats/hub-light.png（命名错位，实际是 hourly）
//  - 顶部"高峰时段"卡（hh:00 - hh+1:00 + 金额 + 时钟图标）
//  - 24 小时柱图（峰值红色，>0.6 阈值蓝色，其他浅蓝）
//  - 时段汇总：凌晨/早间/午间/晚间四块占比

import SwiftUI
import Charts

struct StatsHourlyView: View {
    @StateObject private var vm = StatsViewModel()
    @Environment(\.colorScheme) private var scheme

    private var maxHourly: Double {
        vm.hourlyDistribution.map { ($0.amount as NSDecimalNumber).doubleValue }.max() ?? 1
    }
    private var peakHour: Int {
        vm.hourlyDistribution.max(by: {
            ($0.amount as NSDecimalNumber).doubleValue
                < ($1.amount as NSDecimalNumber).doubleValue
        })?.hour ?? 0
    }
    private var totalHourly: Decimal {
        vm.hourlyDistribution.map(\.amount).reduce(0, +)
    }

    var body: some View {
        VStack(spacing: 0) {
            StatsSubNavBar(title: "时段分布",
                           subtitle: "\(StatsFormat.ymSubtitle(vm.month)) · 24 小时",
                           trailingIcon: "calendar")
            ScrollView {
                VStack(spacing: NotionTheme.space7) {
                    if totalHourly > 0 {
                        insightTop
                        chartCard
                        timeBlockCards
                    } else {
                        StatsEmptyState(title: "本月暂无支出",
                                        subtitle: "记录一些支出后，这里会展示 24 小时消费分布")
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

    private var insightTop: some View {
        HStack(spacing: NotionTheme.space5) {
            VStack(alignment: .leading, spacing: 4) {
                Text("高峰时段")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
                Text(String(format: "%02d:00 - %02d:00", peakHour, (peakHour + 1) % 24))
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(DirectionColor.amountForeground(kind: .expense))
                Text("¥" + StatsFormat.intGrouped(vm.hourlyDistribution[peakHour].amount))
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer()
            Image(systemName: "clock.fill")
                .font(.system(size: 36))
                .foregroundStyle(DirectionColor.amountForeground(kind: .expense).opacity(0.18))
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .fill(Color.hoverBg.opacity(0.5))
        )
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            Text("各时段消费")
                .font(.custom("PingFangSC-Semibold", size: 14))
                .foregroundStyle(Color.inkPrimary)
                .padding(.leading, 4)

            Chart {
                ForEach(vm.hourlyDistribution) { item in
                    let v = (item.amount as NSDecimalNumber).doubleValue
                    BarMark(x: .value("时", item.hour),
                            y: .value("金额", v))
                    .foregroundStyle(barColor(for: item.hour, value: v))
                    .cornerRadius(2)
                }
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisGridLine().foregroundStyle(Color.divider.opacity(0.5))
                    AxisValueLabel {
                        if let h = value.as(Int.self) {
                            Text("\(h)时")
                                .font(.custom("PingFangSC-Regular", size: 9))
                                .foregroundStyle(Color.inkTertiary)
                        }
                    }
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
            .frame(height: 200)
            .padding(NotionTheme.space5)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                    .fill(Color.hoverBg.opacity(0.5))
            )
        }
    }

    private func barColor(for hour: Int, value: Double) -> Color {
        if hour == peakHour { return NotionColor.red.text(scheme) }
        return value / maxHourly > 0.6
            ? Color.accentBlue
            : Color.accentBlue.opacity(0.55)
    }

    private var timeBlockCards: some View {
        let blocks: [(label: String, range: ClosedRange<Int>, icon: String, color: NotionColor)] = [
            ("凌晨 0-6 时",  0...5,   "moon.stars.fill", .purple),
            ("早间 6-11 时", 6...11,  "sunrise.fill",    .orange),
            ("午间 12-17 时",12...17, "sun.max.fill",    .yellow),
            ("晚间 18-23 时",18...23, "moon.fill",       .blue),
        ]
        return VStack(alignment: .leading, spacing: NotionTheme.space4) {
            Text("时段汇总")
                .font(.custom("PingFangSC-Semibold", size: 14))
                .foregroundStyle(Color.inkPrimary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { idx, b in
                    blockRow(label: b.label, range: b.range, icon: b.icon, color: b.color)
                    if idx < blocks.count - 1 {
                        Rectangle().fill(Color.divider).frame(height: 0.5)
                            .padding(.leading, NotionTheme.space5 + 28 + NotionTheme.space5)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                    .fill(Color.hoverBg.opacity(0.5))
            )
        }
    }

    @ViewBuilder
    private func blockRow(label: String, range: ClosedRange<Int>,
                          icon: String, color: NotionColor) -> some View {
        let total = vm.hourlyDistribution
            .filter { range.contains($0.hour) }
            .map(\.amount).reduce(Decimal(0), +)
        let pct = totalHourly > 0
            ? (total as NSDecimalNumber).doubleValue
              / (totalHourly as NSDecimalNumber).doubleValue * 100
            : 0
        HStack(spacing: NotionTheme.space5) {
            ZStack {
                RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                    .fill(color.background(scheme))
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color.text(scheme))
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.inkPrimary)
                Text(String(format: "占比 %.1f%%", pct))
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer()
            Text("¥" + StatsFormat.intGrouped(total))
                .font(NotionFont.amount(size: 15))
                .foregroundStyle(Color.inkPrimary)
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 12)
    }
}
