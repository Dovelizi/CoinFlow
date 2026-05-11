//  StatsGaugeView.swift
//  CoinFlow · V2 Stats · 存钱率（半圆仪表盘）
//
//  设计基线：design/screens/05-stats/year-view-light.png（实际是 gauge）
//  - 半圆仪表盘 + 中心百分比
//  - 收入/支出/结余三栏
//  - 已达成目标 30% 的胶囊状态条
//  - 近 6 月存钱率柱图（达标绿、未达标黄）+ 30% 红虚线参考
//  - 数据洞察（最高存钱率月）

import SwiftUI
import Charts

struct StatsGaugeView: View {
    @StateObject private var vm: StatsViewModel
    @Environment(\.colorScheme) private var scheme

    private let targetRate: Double = 0.30

    init(month: YearMonth = .current) {
        _vm = StateObject(wrappedValue: StatsViewModel(month: month))
    }

    private var saveRate: Double {
        guard vm.monthlyIncome > 0 else { return 0 }
        let net = ((vm.monthlyIncome - vm.monthlyExpense) as NSDecimalNumber).doubleValue
        return max(0, net / (vm.monthlyIncome as NSDecimalNumber).doubleValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            StatsSubNavBar(title: "存钱率",
                           subtitle: StatsFormat.ymSubtitle(vm.month),
                           trailingIcon: "target")
            ScrollView {
                VStack(spacing: NotionTheme.space7) {
                    if vm.monthlyIncome > 0 {
                        gaugeCard
                        historyCard
                        insightCard
                    } else {
                        StatsEmptyState(title: "本月暂无收入",
                                        subtitle: "记录收入后才能计算存钱率")
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

    private var gaugeCard: some View {
        VStack(spacing: NotionTheme.space5) {
            ZStack {
                StatsGaugeArc(rate: saveRate, target: targetRate, scheme: scheme)
                    .frame(width: 240, height: 140)
                VStack(spacing: 0) {
                    Text(String(format: "%.0f%%", saveRate * 100))
                        .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(saveRate >= targetRate
                                         ? NotionColor.green.text(scheme)
                                         : NotionColor.yellow.text(scheme))
                    Text("本月存钱率")
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.inkTertiary)
                }
                .padding(.top, NotionTheme.space5)
            }

            HStack(spacing: NotionTheme.space5) {
                gaugeMini("收入", value: "¥" + StatsFormat.decimalGrouped(vm.monthlyIncome),
                          tone: DirectionColor.amountForeground(kind: .income))
                gaugeMini("支出", value: "¥" + StatsFormat.decimalGrouped(vm.monthlyExpense),
                          tone: DirectionColor.amountForeground(kind: .expense))
                gaugeMini("结余",
                          value: "¥" + StatsFormat.decimalGrouped(vm.monthlyNet >= 0
                                                              ? vm.monthlyNet
                                                              : 0),
                          tone: Color.inkPrimary)
            }
            .padding(NotionTheme.space5)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                    .fill(Color.hoverBg.opacity(0.5))
            )

            HStack(spacing: 6) {
                Image(systemName: saveRate >= targetRate
                      ? "checkmark.circle.fill"
                      : "exclamationmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(saveRate >= targetRate
                                     ? NotionColor.green.text(scheme)
                                     : NotionColor.yellow.text(scheme))
                Text(saveRate >= targetRate
                     ? "已达成目标 30%"
                     : "距目标还差 \(String(format: "%.1f%%", (targetRate - saveRate) * 100))")
                    .font(.custom("PingFangSC-Semibold", size: 13))
                    .foregroundStyle(Color.inkPrimary)
            }
            .padding(.horizontal, NotionTheme.space5).padding(.vertical, 10)
            .background(
                Capsule().fill(saveRate >= targetRate
                               ? NotionColor.green.background(scheme)
                               : NotionColor.yellow.background(scheme))
            )
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            Text("近 6 个月存钱率")
                .font(.custom("PingFangSC-Semibold", size: 14))
                .foregroundStyle(Color.inkPrimary)
                .padding(.leading, 4)

            Chart {
                ForEach(vm.saveRateHistory, id: \.month) { h in
                    BarMark(x: .value("月", h.month),
                            y: .value("率", h.rate * 100))
                    .foregroundStyle(h.rate >= targetRate
                                     ? NotionColor.green.text(scheme)
                                     : NotionColor.yellow.text(scheme))
                    .cornerRadius(4)
                }
                RuleMark(y: .value("目标", targetRate * 100))
                    .foregroundStyle(NotionColor.red.text(scheme).opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("目标 30%")
                            .font(.custom("PingFangSC-Regular", size: 9))
                            .foregroundStyle(NotionColor.red.text(scheme))
                    }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50]) { value in
                    AxisGridLine().foregroundStyle(Color.divider)
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)%")
                                .font(.custom("PingFangSC-Regular", size: 9))
                                .foregroundStyle(Color.inkTertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let s = value.as(String.self) {
                            Text(s)
                                .font(.custom("PingFangSC-Regular", size: 9))
                                .foregroundStyle(Color.inkTertiary)
                        }
                    }
                }
            }
            .frame(height: 160)
            .padding(NotionTheme.space5)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                    .fill(Color.hoverBg.opacity(0.5))
            )
        }
    }

    private var insightCard: some View {
        let best = vm.saveRateHistory.max(by: { $0.rate < $1.rate })
        let okCount = vm.saveRateHistory.filter { $0.rate >= targetRate }.count
        return VStack(alignment: .leading, spacing: NotionTheme.space3) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(NotionColor.yellow.text(scheme))
                Text(best.map { "近 6 月最高存钱率：\($0.month) \(Int($0.rate * 100))%" }
                     ?? "近 6 月暂无完整数据")
                    .font(.custom("PingFangSC-Semibold", size: 13))
                    .foregroundStyle(Color.inkPrimary)
            }
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentBlue)
                Text("达成率 \(okCount)/\(vm.saveRateHistory.count) 次")
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .fill(Color.hoverBg.opacity(0.5))
        )
    }

    @ViewBuilder
    private func gaugeMini(_ label: String, value: String, tone: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 半圆仪表盘弧形（自绘）。
struct StatsGaugeArc: View {
    let rate: Double
    let target: Double
    let scheme: ColorScheme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let center = CGPoint(x: w / 2, y: h)
            let radius = min(w / 2, h) - 12

            ZStack {
                Path { p in
                    p.addArc(center: center, radius: radius,
                             startAngle: .degrees(180), endAngle: .degrees(360),
                             clockwise: false)
                }
                .strokedPath(StrokeStyle(lineWidth: 16, lineCap: .round))
                .foregroundColor(Color.hoverBg)

                Path { p in
                    let endAngle = 180 + min(rate, 1.0) * 180
                    p.addArc(center: center, radius: radius,
                             startAngle: .degrees(180), endAngle: .degrees(endAngle),
                             clockwise: false)
                }
                .strokedPath(StrokeStyle(lineWidth: 16, lineCap: .round))
                .foregroundColor(rate >= target
                                 ? NotionColor.green.text(scheme)
                                 : NotionColor.yellow.text(scheme))

                let targetAngle = 180 + target * 180
                let tx = center.x + radius * cos(targetAngle * .pi / 180)
                let ty = center.y + radius * sin(targetAngle * .pi / 180)
                Path { p in
                    p.move(to: CGPoint(x: tx, y: ty - 18))
                    p.addLine(to: CGPoint(x: tx - 4, y: ty - 26))
                    p.addLine(to: CGPoint(x: tx + 4, y: ty - 26))
                    p.closeSubpath()
                }
                .fill(NotionColor.red.text(scheme))

                Text("0%")
                    .font(.custom("PingFangSC-Regular", size: 10))
                    .foregroundStyle(Color.inkTertiary)
                    .position(x: 12, y: h - 4)
                Text("100%")
                    .font(.custom("PingFangSC-Regular", size: 10))
                    .foregroundStyle(Color.inkTertiary)
                    .position(x: w - 18, y: h - 4)
            }
        }
    }
}
