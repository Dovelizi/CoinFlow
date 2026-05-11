//  StatsYearView.swift
//  CoinFlow · V2 Stats · 年度回顾
//
//  设计基线：design/screens/05-stats/main-light.png（实际是 year-view 视觉）
//  - 顶部"年度收入 / 年度支出 / 月均支出"三栏
//  - 月度收支对比柱图（双柱并列）
//  - 同比 / 环比对比卡（本月 vs 上月 / 本月 vs 去年同期 / 本年累计 vs 去年）

import SwiftUI
import Charts

struct StatsYearView: View {
    @StateObject private var vm: StatsViewModel
    @Environment(\.colorScheme) private var scheme

    init(month: YearMonth = .current) {
        _vm = StateObject(wrappedValue: StatsViewModel(month: month))
    }

    private var totalIncome:  Decimal { vm.last12Months.map(\.income).reduce(0, +) }
    private var totalExpense: Decimal { vm.last12Months.map(\.expense).reduce(0, +) }
    private var avgExpense:   Decimal {
        vm.last12Months.isEmpty ? 0 : totalExpense / Decimal(vm.last12Months.count)
    }

    private var subtitle: String {
        guard let first = vm.last12Months.first, let last = vm.last12Months.last else {
            return "近 12 个月"
        }
        return "\(first.id) 至 \(last.id)"
    }

    var body: some View {
        VStack(spacing: 0) {
            StatsSubNavBar(title: "年度回顾",
                           subtitle: subtitle)
            ScrollView {
                VStack(spacing: NotionTheme.space7) {
                    yearSummary
                    if vm.hasAnyData {
                        barChartCard
                        yoyComparison
                    } else {
                        StatsEmptyState(title: "暂无年度数据",
                                        subtitle: "记账满 1 个月以上后，这里会展示年度对比")
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

    private var yearSummary: some View {
        HStack(spacing: NotionTheme.space5) {
            yearStatCell("年度收入", amount: totalIncome,
                         tone: DirectionColor.amountForeground(kind: .income))
            yearStatCell("年度支出", amount: totalExpense,
                         tone: DirectionColor.amountForeground(kind: .expense))
            yearStatCell("月均支出", amount: avgExpense,
                         tone: Color.inkPrimary)
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .fill(Color.hoverBg.opacity(0.5))
        )
    }

    @ViewBuilder
    private func yearStatCell(_ label: String, amount: Decimal, tone: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
            Text("¥" + StatsFormat.compactK(amount))
                .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var barChartCard: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            HStack {
                Text("月度收支对比")
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
                ForEach(vm.last12Months) { m in
                    BarMark(x: .value("月份", m.monthShort),
                            y: .value("收入", (m.income as NSDecimalNumber).doubleValue))
                    .foregroundStyle(NotionColor.green.text(scheme).opacity(0.85))
                    .position(by: .value("类型", "收入"))
                    .cornerRadius(3)
                    BarMark(x: .value("月份", m.monthShort),
                            y: .value("支出", (m.expense as NSDecimalNumber).doubleValue))
                    .foregroundStyle(NotionColor.red.text(scheme).opacity(0.85))
                    .position(by: .value("类型", "支出"))
                    .cornerRadius(3)
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
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color.divider)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(v >= 1000 ? "\(Int(v / 1000))k" : "\(Int(v))")
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

    @ViewBuilder
    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkSecondary)
        }
    }

    // MARK: 同比 / 环比

    private enum CompareDir { case higher, lower, flat }

    private var yoyComparison: some View {
        let cur = vm.monthlyExpense
        let prev = vm.prevMonthExpense
        // last12Months 共 12 项，按时间从前到后；suffix(vm.month.month) 取近 N 个月恰好是「本年至今」（仅当当前月 = vm.month.month 时成立）
        // 去年同期：last12Months 第 0 项即 12 个月前同月份
        let yoy = vm.last12Months.first?.expense ?? Decimal(0)
        // 本年累计 vs 去年同期累计：
        // last12Months 长度=12，索引 0..11 对应 (m-11) 月..m 月
        // 本年 1..m 月 = last12Months 末尾 m 项（suffix）
        // 去年 1..m 月 = last12Months 索引 (12-m)..(11)? 不对。
        // 重新推导：last12Months[0..<m] 等于"上一年同期 (m+1)..12 月"，不符合。
        // 正确方式：用 allRecords 直接按年份过滤（避免 12 个月窗口的歧义）。
        let ytdPair = computeYTDPair()

        return VStack(alignment: .leading, spacing: NotionTheme.space4) {
            Text("同比 / 环比")
                .font(.custom("PingFangSC-Semibold", size: 14))
                .foregroundStyle(Color.inkPrimary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                comparisonRow(label: "本月支出 vs 上月",
                              current: cur, previous: prev)
                Rectangle().fill(Color.divider).frame(height: 0.5)
                    .padding(.leading, NotionTheme.space5)
                comparisonRow(label: "本月支出 vs 去年同期",
                              current: cur, previous: yoy)
                Rectangle().fill(Color.divider).frame(height: 0.5)
                    .padding(.leading, NotionTheme.space5)
                comparisonRow(label: "本年累计 vs 去年同期",
                              current: ytdPair.current, previous: ytdPair.previous)
            }
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                    .fill(Color.hoverBg.opacity(0.5))
            )
        }
    }

    /// 计算"本年截至当前月累计支出 vs 去年同期累计支出"。
    /// 依赖 `vm.allRecords` 而非 12 月窗口，避免索引偏移歧义。
    private func computeYTDPair() -> (current: Decimal, previous: Decimal) {
        let cal = Calendar.current
        let curYear = vm.month.year
        let prevYear = curYear - 1
        let curMonth = vm.month.month
        var cur: Decimal = 0
        var prv: Decimal = 0
        for r in vm.allRecords where (vm.categoriesById[r.categoryId]?.kind ?? .expense) == .expense {
            let comps = cal.dateComponents([.year, .month], from: r.occurredAt)
            guard let y = comps.year, let m = comps.month, m <= curMonth else { continue }
            if y == curYear { cur += r.amount }
            else if y == prevYear { prv += r.amount }
        }
        return (cur, prv)
    }

    @ViewBuilder
    private func comparisonRow(label: String, current: Decimal, previous: Decimal) -> some View {
        let direction: CompareDir = {
            if previous == 0 && current == 0 { return .flat }
            if previous == 0 { return .higher }
            if current > previous { return .higher }
            if current < previous { return .lower }
            return .flat
        }()
        let pct: Double = {
            guard previous > 0 else { return current > 0 ? 100 : 0 }
            let diff = ((current - previous) as NSDecimalNumber).doubleValue
            return abs(diff) / (previous as NSDecimalNumber).doubleValue * 100
        }()

        HStack(spacing: NotionTheme.space5) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(NotionFont.body())
                    .foregroundStyle(Color.inkPrimary)
                Text("¥\(StatsFormat.compactK(current)) vs ¥\(StatsFormat.compactK(previous))")
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: directionIcon(direction))
                    .font(.system(size: 12, weight: .semibold))
                Text(direction == .flat ? "持平" : String(format: "%.1f%%", pct))
                    .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
            }
            .foregroundStyle(directionColor(direction))
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 14)
    }

    private func directionIcon(_ d: CompareDir) -> String {
        switch d {
        case .higher: return "arrow.up.right"
        case .lower:  return "arrow.down.right"
        case .flat:   return "equal"
        }
    }

    private func directionColor(_ d: CompareDir) -> Color {
        switch d {
        case .higher: return NotionColor.red.text(scheme)
        case .lower:  return NotionColor.green.text(scheme)
        case .flat:   return Color.inkSecondary
        }
    }
}
