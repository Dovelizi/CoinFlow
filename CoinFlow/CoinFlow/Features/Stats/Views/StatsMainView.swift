//  StatsMainView.swift
//  CoinFlow · V2 Stats · 本月汇总
//
//  设计基线：design/screens/05-stats/hourly-light.png 中"统计 / 2026 年 5 月" 主页样式
//  （命名是 hourly 但实际内容是 main 页：本月净增 hero + 收入/支出/笔数 + 日历热力 + 分类环 + 排行）
//
//  数据：StatsViewModel.dailyExpenseInMonth / expenseCategorySlices / monthlyIncome / Expense

import SwiftUI

struct StatsMainView: View {
    @StateObject private var vm = StatsViewModel()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            StatsSubNavBar(title: "统计",
                           subtitle: StatsFormat.ymSubtitle(vm.month),
                           trailingIcon: "square.and.arrow.up")
            ScrollView {
                VStack(spacing: NotionTheme.space7) {
                    summarySection
                    if vm.hasAnyData {
                        calendarHeatmap
                        if !vm.expenseCategorySlices.isEmpty {
                            categoryDonut
                            topCategoriesList
                        }
                    } else {
                        emptyHint
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

    // MARK: 概览 hero（净增 + 收/支/笔数 三栏）

    private var summarySection: some View {
        VStack(spacing: NotionTheme.space5) {
            VStack(spacing: 4) {
                Text("本月净增")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
                // ¥ 与数字字重/字体/比例统一（全局规则 §AmountSymbolStyle）
                // 用 attributed string 拼接 → 整组等比例缩小
                let digitSize: CGFloat = 38
                let symbolSize = digitSize * AmountSymbolStyle.symbolScale
                let tone = toneColor(for: vm.monthlyNet)
                let amountStr = StatsFormat.intGrouped(absDecimal(vm.monthlyNet))
                let heroAttr: AttributedString = {
                    var a = AttributedString("¥")
                    a.font = .system(size: symbolSize, weight: .semibold, design: .rounded)
                    a.foregroundColor = tone
                    var n = AttributedString(amountStr)
                    n.font = .system(size: digitSize, weight: .semibold, design: .rounded).monospacedDigit()
                    n.foregroundColor = tone
                    a.append(n)
                    return a
                }()
                Text(heroAttr)
                    .amountGroupAutoFit(scaleFloor: 0.4)
                    .padding(.horizontal, NotionTheme.space5)
            }

            HStack(spacing: NotionTheme.space5) {
                statCell(label: "收入",
                         text: "¥" + StatsFormat.intGrouped(vm.monthlyIncome),
                         tone: NotionColor.green.text(scheme))
                vDivider
                statCell(label: "支出",
                         text: "¥" + StatsFormat.intGrouped(vm.monthlyExpense),
                         tone: NotionColor.red.text(scheme))
                vDivider
                statCell(label: "笔数",
                         text: "\(vm.monthlyCount)",
                         tone: Color.inkPrimary)
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.vertical, NotionTheme.space5)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                    .fill(Color.hoverBg.opacity(0.5))
            )
        }
    }

    @ViewBuilder
    private func statCell(label: String, text: String, tone: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
            Text(text)
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var vDivider: some View {
        Rectangle().fill(Color.divider).frame(width: 0.5, height: 28)
    }

    // MARK: 日历热力图（Notion 风格 5 档绿色族）

    private var calendarHeatmap: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            sectionHeader("日历热力")

            let maxAmount = vm.dailyExpenseInMonth.map(\.expense).max() ?? 1
            let cal = Calendar.current
            let firstWeekday = cal.dateComponents([.weekday], from: vm.dailyExpenseInMonth.first?.date ?? Date()).weekday ?? 1
            // weekday: 周日=1，要把它映射到"一二三四五六日"列（周一=0，周日=6）
            let leadingBlanks = (firstWeekday + 5) % 7

            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(["一","二","三","四","五","六","日"], id: \.self) { w in
                        Text(w)
                            .font(.custom("PingFangSC-Regular", size: 10))
                            .foregroundStyle(Color.inkTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                let rows = makeWeekRows(leadingBlanks: leadingBlanks,
                                        days: vm.dailyExpenseInMonth.count)
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(row, id: \.self) { dayOrZero in
                            heatCell(day: dayOrZero, max: maxAmount)
                        }
                    }
                }
                heatLegend.padding(.top, NotionTheme.space4)
            }
            .padding(NotionTheme.space5)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                    .fill(Color.hoverBg.opacity(0.5))
            )
        }
    }

    /// 把 1...N 天均分成 7 列若干行，row 内 0 = 占位空格。
    private func makeWeekRows(leadingBlanks: Int, days: Int) -> [[Int]] {
        var flat: [Int] = Array(repeating: 0, count: leadingBlanks) + Array(1...days)
        // 末尾补齐到 7 倍数
        while flat.count % 7 != 0 { flat.append(0) }
        return stride(from: 0, to: flat.count, by: 7).map { Array(flat[$0..<($0+7)]) }
    }

    @ViewBuilder
    private func heatCell(day: Int, max: Decimal) -> some View {
        let valid = day >= 1
        let amount = valid
            ? (vm.dailyExpenseInMonth.first(where: { $0.id == day })?.expense ?? 0)
            : Decimal(0)
        let level = valid ? heatLevel(amount: amount, max: max) : -1
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(valid ? heatColor(level: level) : Color.clear)
                .aspectRatio(1, contentMode: .fit)
            if valid {
                Text("\(day)")
                    .font(.custom("PingFangSC-Regular", size: 10))
                    .foregroundStyle(level >= 3 ? Color.white : Color.inkSecondary)
            }
        }
    }

    private func heatLevel(amount: Decimal, max: Decimal) -> Int {
        guard max > 0 else { return 0 }
        let ratio = (amount as NSDecimalNumber).doubleValue
                  / (max as NSDecimalNumber).doubleValue
        switch ratio {
        case ..<0.001: return 0
        case ..<0.20:  return 1
        case ..<0.45:  return 2
        case ..<0.70:  return 3
        default:       return 4
        }
    }

    private func heatColor(level: Int) -> Color {
        let green = NotionColor.green.text(scheme)
        switch level {
        case 0:  return Color.hoverBg
        case 1:  return green.opacity(0.20)
        case 2:  return green.opacity(0.40)
        case 3:  return green.opacity(0.65)
        case 4:  return green.opacity(0.95)
        default: return Color.hoverBg
        }
    }

    private var heatLegend: some View {
        HStack(spacing: 6) {
            Text("少").font(NotionFont.micro()).foregroundStyle(Color.inkTertiary)
            ForEach(0..<5) { lv in
                RoundedRectangle(cornerRadius: 2)
                    .fill(heatColor(level: lv))
                    .frame(width: 12, height: 12)
            }
            Text("多").font(NotionFont.micro()).foregroundStyle(Color.inkTertiary)
            Spacer()
            Text("基于本月日支出").font(NotionFont.micro()).foregroundStyle(Color.inkTertiary)
        }
    }

    // MARK: 分类构成（环形图）

    private var categoryDonut: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            sectionHeader("分类构成")
            HStack(spacing: NotionTheme.space6) {
                StatsDonutChart(items: vm.expenseCategorySlices, scheme: scheme)
                    .frame(width: 140, height: 140)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(vm.expenseCategorySlices.prefix(5)) { cat in
                        legendRow(cat)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(NotionTheme.space5)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                    .fill(Color.hoverBg.opacity(0.5))
            )
        }
    }

    @ViewBuilder
    private func legendRow(_ cat: StatsCategorySlice) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(cat.tone.text(scheme))
                .frame(width: 8, height: 8)
            Text(cat.name)
                .font(NotionFont.small())
                .foregroundStyle(Color.inkPrimary)
            Spacer(minLength: 0)
            Text("\(Int(cat.percentage * 100))%")
                .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.inkSecondary)
        }
    }

    // MARK: Top5 分类列表

    private var topCategoriesList: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            sectionHeader("分类排行")
            VStack(spacing: 0) {
                let items = vm.expenseCategorySlices.prefix(5)
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, cat in
                    categoryRow(rank: idx + 1, cat: cat)
                    if idx < items.count - 1 {
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
    private func categoryRow(rank: Int, cat: StatsCategorySlice) -> some View {
        HStack(spacing: NotionTheme.space5) {
            Text("\(rank)")
                .font(.custom("PingFangSC-Semibold", size: 13))
                .foregroundStyle(Color.inkTertiary)
                .frame(width: 14)
            ZStack {
                RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                    .fill(cat.tone.background(scheme))
                Image(systemName: cat.icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(cat.tone.text(scheme))
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(cat.name)
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.inkPrimary)
                Text("\(cat.count) 笔 · \(Int(cat.percentage * 100))%")
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer()
            Text("¥" + StatsFormat.intGrouped(cat.amount))
                .font(NotionFont.amount(size: 15))
                .foregroundStyle(DirectionColor.amountForeground(kind: .expense))
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 12)
    }

    // MARK: 空态

    private var emptyHint: some View {
        VStack(spacing: NotionTheme.space5) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(Color.inkTertiary)
                .padding(.top, NotionTheme.space9)
            Text("本月还没有任何流水")
                .font(NotionFont.bodyBold())
                .foregroundStyle(Color.inkSecondary)
            Text("记录一笔后，统计图表会自动出现")
                .font(NotionFont.small())
                .foregroundStyle(Color.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, NotionTheme.space9)
    }

    // MARK: helpers

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.custom("PingFangSC-Semibold", size: 14))
                .foregroundStyle(Color.inkPrimary)
            Spacer()
        }
        .padding(.leading, 4)
    }

    private func toneColor(for net: Decimal) -> Color {
        net >= 0
            ? DirectionColor.amountForeground(kind: .income)
            : DirectionColor.amountForeground(kind: .expense)
    }

    private func absDecimal(_ d: Decimal) -> Decimal { d < 0 ? -d : d }
}

// MARK: - 自绘环形图组件

struct StatsDonutChart: View {
    let items: [StatsCategorySlice]
    let scheme: ColorScheme

    var body: some View {
        ZStack {
            ForEach(Array(segments().enumerated()), id: \.offset) { _, seg in
                Path { path in
                    path.addArc(center: CGPoint(x: 70, y: 70),
                                radius: 56,
                                startAngle: .degrees(seg.start - 90),
                                endAngle:   .degrees(seg.end - 90),
                                clockwise: false)
                }
                .strokedPath(StrokeStyle(lineWidth: 22, lineCap: .butt))
                .foregroundColor(seg.color)
            }
            VStack(spacing: 0) {
                Text("总支出")
                    .font(.custom("PingFangSC-Regular", size: 10))
                    .foregroundStyle(Color.inkTertiary)
                Text("¥" + StatsFormat.intGrouped(total()))
                    .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.inkPrimary)
            }
        }
    }

    private struct Seg {
        let start: Double
        let end: Double
        let color: Color
    }

    private func segments() -> [Seg] {
        var segs: [Seg] = []
        var cursor: Double = 0
        for it in items {
            let span = it.percentage * 360
            segs.append(.init(start: cursor,
                              end: cursor + span - 1.5,
                              color: it.tone.text(scheme)))
            cursor += span
        }
        return segs
    }

    private func total() -> Decimal {
        items.map(\.amount).reduce(0, +)
    }
}
