//  StatsBudgetView.swift
//  CoinFlow · V2 Stats · 本月预算
//
//  设计基线：design/screens/05-stats/budget-light.png
//  - 总预算大环（红/黄/绿三档）+ 中心 已用% / 已用/总额
//  - 剩余/剩余天数/日均可用 三栏
//  - 分类预算列表（icon + 已超支胶囊 + 进度 bar + 已用/预算）
//  - 底部黄色提示 banner（超支建议）
//
//  数据：真实"分类支出" + 启发式预算阈值（上月同分类支出 × 1.1 作为建议预算）。
//        预算"持久化"是 V2 范围内的另一项功能（user_settings 表），M7 暂不引入设置 UI；
//        仅展示"基于上月数据估算的预算线"，并显式 banner 说明"自动估算"。
//        这样既忠实呈现设计稿视觉，也避免"假装真实"的 UX 欺骗。

import SwiftUI

struct StatsBudgetView: View {
    @StateObject private var vm: StatsViewModel
    @Environment(\.colorScheme) private var scheme
    @State private var showSettings = false

    /// 用户自定义月度总预算；nil = 使用启发式估算。
    /// 持久化键：以"yyyy-MM"为粒度，避免修改本月不影响下月。
    @AppStorage("stats.budget.custom.totalAmount") private var customTotalAmountStr: String = ""
    @AppStorage("stats.budget.custom.month") private var customTotalMonth: String = ""

    init(month: YearMonth = .current) {
        _vm = StateObject(wrappedValue: StatsViewModel(month: month))
    }

    private var todayDay: Int {
        Calendar.current.component(.day, from: Date())
    }
    private var daysInMonth: Int {
        Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
    }
    private var daysLeft: Int { max(0, daysInMonth - todayDay) }

    /// 当前月份的自定义总预算；非本月或未设置 → nil。
    private var customTotalForCurrentMonth: Decimal? {
        guard customTotalMonth == vm.month.idString,
              !customTotalAmountStr.isEmpty,
              let v = Decimal(string: customTotalAmountStr),
              v > 0 else { return nil }
        return v
    }

    /// 启发式预算：上月同分类支出 × 1.1，并按当前实际支出向上对齐到 100 元整。
    /// 上月无数据的分类用本月支出 × 1.2 兜底。
    private var categoryBudgets: [(slice: StatsCategorySlice, budget: Decimal)] {
        let cal = Calendar.current
        let prevYM = vm.month.adding(months: -1)
        let prevInterval = prevYM.dateInterval(in: cal)
        let prevExpenseByCat = Dictionary(
            grouping: vm.allRecords.filter {
                prevInterval.contains($0.occurredAt) &&
                (vm.categoriesById[$0.categoryId]?.kind ?? .expense) == .expense
            },
            by: { $0.categoryId }
        ).mapValues { $0.map(\.amount).reduce(Decimal(0), +) }

        return vm.expenseCategorySlices.map { slice in
            let prev = prevExpenseByCat[slice.id] ?? 0
            let raw: Decimal = prev > 0
                ? prev * Decimal(string: "1.1")!
                : slice.amount * Decimal(string: "1.2")!
            // 向上对齐到 100 元
            let cents = (raw as NSDecimalNumber).doubleValue
            let aligned = max(100, ceil(cents / 100) * 100)
            return (slice, Decimal(aligned))
        }
    }

    private var totalBudget: Decimal {
        // 用户自定义总预算优先；否则用启发式估算之和。
        if let custom = customTotalForCurrentMonth { return custom }
        return categoryBudgets.map(\.budget).reduce(0, +)
    }
    private var totalUsed: Decimal { vm.monthlyExpense }
    private var totalPct: Double {
        guard totalBudget > 0 else { return 0 }
        return (totalUsed as NSDecimalNumber).doubleValue
             / (totalBudget as NSDecimalNumber).doubleValue
    }
    private var remaining: Decimal { totalBudget - totalUsed }
    private var dailyAvail: Decimal {
        guard daysLeft > 0, remaining > 0 else { return 0 }
        return remaining / Decimal(daysLeft)
    }

    var body: some View {
        VStack(spacing: 0) {
            StatsSubNavBar(title: "本月预算",
                           subtitle: StatsFormat.ymSubtitle(vm.month),
                           trailingIcon: "slider.horizontal.3",
                           trailingAction: { showSettings = true },
                           trailingAccessibility: "预算设置")
            ScrollView {
                VStack(spacing: NotionTheme.space7) {
                    if vm.expenseCategorySlices.isEmpty {
                        StatsEmptyState(title: "本月暂无支出",
                                        subtitle: "记录支出后会基于历史数据估算预算")
                            .frame(height: 360)
                    } else {
                        autoEstimateBanner
                        totalCard
                        categoriesCard
                        if let suggestion = suggestionTip {
                            tipBanner(suggestion)
                        }
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
        .sheet(isPresented: $showSettings) {
            BudgetSettingsSheet(
                monthId: vm.month.idString,
                estimatedTotal: categoryBudgets.map(\.budget).reduce(0, +),
                customAmountStr: $customTotalAmountStr,
                customMonth: $customTotalMonth
            )
        }
    }

    private var autoEstimateBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: customTotalForCurrentMonth != nil ? "checkmark.seal.fill" : "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(Color.accentBlue)
            Text(customTotalForCurrentMonth != nil
                 ? "已使用自定义月度总预算 · 可点击右上角调整"
                 : "预算根据上月支出 × 1.1 自动估算 · 点击右上角自定义")
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                .fill(Color.accentBlueBG)
        )
    }

    private var totalCard: some View {
        VStack(spacing: NotionTheme.space5) {
            ZStack {
                Circle()
                    .stroke(Color.hoverBg, lineWidth: 18)
                    .frame(width: 168, height: 168)
                Circle()
                    .trim(from: 0, to: min(totalPct, 1.0))
                    .stroke(arcColor(for: totalPct),
                            style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 168, height: 168)
                VStack(spacing: 2) {
                    Text("已用")
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.inkTertiary)
                    Text(String(format: "%.0f%%", totalPct * 100))
                        .font(.system(size: 36, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(totalPct > 0.9
                                         ? NotionColor.red.text(scheme)
                                         : Color.inkPrimary)
                    Text("¥\(StatsFormat.decimalGrouped(totalUsed)) / ¥\(StatsFormat.decimalGrouped(totalBudget))")
                        .font(NotionFont.small())
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            .padding(.top, NotionTheme.space4)

            HStack(spacing: NotionTheme.space5) {
                miniCell("剩余", value: "¥" + StatsFormat.decimalGrouped(remaining < 0 ? -remaining : remaining),
                         tone: remaining < 0
                            ? NotionColor.red.text(scheme)
                            : Color.inkPrimary,
                         prefix: remaining < 0 ? "超支 " : nil)
                vDivider
                miniCell("剩余天数", value: "\(daysLeft)")
                vDivider
                miniCell("日均可用",
                         value: remaining > 0 ? "¥" + StatsFormat.decimalGrouped(dailyAvail) : "—",
                         tone: remaining > 0 ? Color.inkPrimary : Color.inkTertiary)
            }
            .padding(NotionTheme.space5)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                    .fill(Color.hoverBg.opacity(0.5))
            )
        }
    }

    private func arcColor(for pct: Double) -> Color {
        if pct > 0.9 { return NotionColor.red.text(scheme) }
        if pct > 0.7 { return NotionColor.yellow.text(scheme) }
        return NotionColor.green.text(scheme)
    }

    private var categoriesCard: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            Text("分类预算")
                .font(.custom("PingFangSC-Semibold", size: 14))
                .foregroundStyle(Color.inkPrimary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                let items = categoryBudgets.prefix(8)
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    categoryBudgetRow(slice: item.slice, budget: item.budget)
                    if idx < items.count - 1 {
                        Rectangle().fill(Color.divider).frame(height: 0.5)
                            .padding(.leading, NotionTheme.space5)
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
    private func categoryBudgetRow(slice: StatsCategorySlice, budget: Decimal) -> some View {
        let used = slice.amount
        let p = budget > 0
            ? (used as NSDecimalNumber).doubleValue
              / (budget as NSDecimalNumber).doubleValue
            : 0
        let isOver = used > budget
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            HStack(spacing: NotionTheme.space4) {
                ZStack {
                    RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                        .fill(slice.tone.background(scheme))
                    Image(systemName: slice.icon)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(slice.tone.text(scheme))
                }
                .frame(width: 24, height: 24)

                Text(slice.name)
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.inkPrimary)

                if isOver {
                    Text("已超支")
                        .font(.custom("PingFangSC-Semibold", size: 10))
                        .foregroundStyle(NotionColor.red.text(scheme))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(NotionColor.red.background(scheme)))
                }
                Spacer()
                Text("¥\(StatsFormat.decimalGrouped(used)) / ¥\(StatsFormat.decimalGrouped(budget))")
                    .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.inkSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.hoverBg).frame(height: 6)
                    Capsule()
                        .fill(barColor(over: isOver, p: p, slice: slice))
                        .frame(width: geo.size.width * min(p, 1.0), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, NotionTheme.space4)
    }

    private func barColor(over: Bool, p: Double, slice: StatsCategorySlice) -> Color {
        if over { return NotionColor.red.text(scheme) }
        if p > 0.85 { return NotionColor.yellow.text(scheme) }
        return slice.tone.text(scheme)
    }

    /// 找最大超支分类作为提示。
    private var suggestionTip: (StatsCategorySlice, Decimal)? {
        let over = categoryBudgets
            .filter { $0.slice.amount > $0.budget }
            .max(by: { ($0.slice.amount - $0.budget) < ($1.slice.amount - $1.budget) })
        return over.map { ($0.slice, $0.slice.amount - $0.budget) }
    }

    @ViewBuilder
    private func tipBanner(_ tuple: (StatsCategorySlice, Decimal)) -> some View {
        let (slice, overAmt) = tuple
        HStack(alignment: .top, spacing: NotionTheme.space4) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14))
                .foregroundStyle(NotionColor.yellow.text(scheme))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(slice.name)已超出预算 ¥\(StatsFormat.decimalGrouped(overAmt))")
                    .font(.custom("PingFangSC-Semibold", size: 13))
                    .foregroundStyle(Color.inkPrimary)
                Text("建议下月将 \(slice.name) 预算上调，或减少该分类支出")
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .fill(NotionColor.yellow.background(scheme))
        )
    }

    @ViewBuilder
    private func miniCell(_ label: String, value: String,
                          tone: Color = .inkPrimary,
                          prefix: String? = nil) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
            Text((prefix ?? "") + value)
                .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var vDivider: some View {
        Rectangle().fill(Color.divider).frame(width: 0.5, height: 28)
    }
}

// MARK: - 预算设置 Sheet
//
// "简洁优先"原则：M7 阶段只支持自定义"月度总预算"。分类预算等真实预算系统（V2）上线再说。
// 自定义值持久化到 UserDefaults（按月独立），方便用户切换月份后看到对应的预算。

private struct BudgetSettingsSheet: View {
    let monthId: String
    let estimatedTotal: Decimal
    @Binding var customAmountStr: String
    @Binding var customMonth: String

    @State private var input: String = ""
    @Environment(\.dismiss) private var dismiss

    /// 当前是否已自定义本月预算
    private var isCurrentlyCustomized: Bool {
        customMonth == monthId && !customAmountStr.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("¥")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.inkSecondary)
                        TextField("输入月度总预算", text: $input)
                            .keyboardType(.numberPad)
                            .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                    }
                } header: {
                    Text("月度总预算")
                } footer: {
                    Text("自定义后将覆盖系统启发式估算（上月支出 × 1.1）")
                }

                Section("当前自动估算") {
                    HStack {
                        Text("¥" + StatsFormat.decimalGrouped(estimatedTotal))
                            .font(.system(size: 15, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.inkPrimary)
                        Spacer()
                        Button("使用此估算") {
                            input = (estimatedTotal as NSDecimalNumber).stringValue
                        }
                        .font(NotionFont.small())
                    }
                }

                if isCurrentlyCustomized {
                    Section {
                        Button(role: .destructive) {
                            customAmountStr = ""
                            customMonth = ""
                            dismiss()
                        } label: {
                            Text("清除自定义预算")
                        }
                    }
                }
            }
            .navigationTitle("预算设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(Decimal(string: input.trimmingCharacters(in: .whitespaces))
                                    .map { $0 <= 0 } ?? true)
                }
            }
            .onAppear {
                if isCurrentlyCustomized { input = customAmountStr }
            }
        }
    }

    private func save() {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard let v = Decimal(string: trimmed), v > 0 else { return }
        customAmountStr = (v as NSDecimalNumber).stringValue
        customMonth = monthId
        dismiss()
    }
}
