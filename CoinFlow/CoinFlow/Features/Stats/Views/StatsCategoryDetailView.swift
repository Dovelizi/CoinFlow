//  StatsCategoryDetailView.swift
//  CoinFlow · V2 Stats · 单分类下钻
//
//  设计基线：design/screens/05-stats/hourly-light.png（命名错位，实际是 category-detail）
//  - 顶部 64pt 圆形 icon + 本月支出大数字
//  - 笔数 / 笔均 / 环比 三栏
//  - 近 6 个月柱图（当月高亮）
//  - 本月该分类明细列表（按 occurredAt desc）
//
//  数据：从 ViewModel 拿 expenseCategorySlices；分类 id 来自 init 参数。
//        默认选第一名（金额最大的）支出分类。

import SwiftUI
import Charts

struct StatsCategoryDetailView: View {
    /// 外部指定分类 id；nil = 用本月最大支出分类。
    let preferredCategoryId: String?

    @StateObject private var vm = StatsViewModel()
    @Environment(\.colorScheme) private var scheme

    /// 用户在切换器上选中的分类 id；nil 表示走默认（preferredCategoryId 或 top 1）
    @State private var selectedCategoryId: String? = nil

    init(preferredCategoryId: String? = nil) {
        self.preferredCategoryId = preferredCategoryId
    }

    /// 选中的分类 slice（本月）
    /// 优先级：用户切换 > 外部指定 > 默认 top 1
    private var slice: StatsCategorySlice? {
        if let sid = selectedCategoryId,
           let s = vm.expenseCategorySlices.first(where: { $0.id == sid }) {
            return s
        }
        if let pid = preferredCategoryId,
           let s = vm.expenseCategorySlices.first(where: { $0.id == pid }) {
            return s
        }
        return vm.expenseCategorySlices.first
    }

    /// 上月同分类支出（用于环比）
    private var prevAmount: Decimal {
        guard let cid = slice?.id else { return 0 }
        let cal = Calendar.current
        let prev = vm.month.adding(months: -1).dateInterval(in: cal)
        return vm.allRecords
            .filter { prev.contains($0.occurredAt) && $0.categoryId == cid }
            .map(\.amount).reduce(0, +)
    }

    /// 近 6 月该分类支出
    private var sixMonths: [(month: String, amount: Decimal, isCurrent: Bool)] {
        guard let cid = slice?.id else { return [] }
        let cal = Calendar.current
        return (0..<6).reversed().map { offset in
            let ym = vm.month.adding(months: -offset)
            let interval = ym.dateInterval(in: cal)
            let amt = vm.allRecords
                .filter { interval.contains($0.occurredAt) && $0.categoryId == cid }
                .map(\.amount).reduce(Decimal(0), +)
            return ("\(ym.month)月", amt, offset == 0)
        }
    }

    /// 本月该分类明细，按 occurredAt 降序
    private var thisMonthRecords: [Record] {
        guard let cid = slice?.id else { return [] }
        let cal = Calendar.current
        let interval = vm.month.dateInterval(in: cal)
        return vm.allRecords
            .filter { interval.contains($0.occurredAt) && $0.categoryId == cid }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            customNav
            // 多分类切换器：横向滚动 chip，仅在有 ≥2 个分类时展示
            if vm.expenseCategorySlices.count >= 2 {
                categorySwitcher
            }
            ScrollView {
                if let slice = slice {
                    VStack(spacing: NotionTheme.space7) {
                        categoryHero(slice: slice)
                        if !sixMonths.isEmpty {
                            monthlyTrendCard(slice: slice)
                        }
                        if !thisMonthRecords.isEmpty {
                            recordsList(slice: slice)
                        }
                    }
                    .padding(.horizontal, NotionTheme.space5)
                    .padding(.top, NotionTheme.space6)
                    .padding(.bottom, NotionTheme.space9)
                } else {
                    StatsEmptyState(title: "暂无支出分类",
                                    subtitle: "本月还没有任何支出记录")
                        .frame(height: 360)
                }
            }
        }
        .background(ThemedBackgroundLayer(kind: .stats))
        .navigationBarHidden(true)
        .onAppear { vm.reload() }
    }

    /// 横向 chip 切换器：列出本月所有支出分类（按金额降序），点击切换 hero/trend/records。
    private var categorySwitcher: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: NotionTheme.space3) {
                    ForEach(vm.expenseCategorySlices) { cat in
                        categoryChip(cat)
                            .id(cat.id)
                    }
                }
                .padding(.horizontal, NotionTheme.space5)
                .padding(.vertical, NotionTheme.space4)
            }
            .onChange(of: slice?.id) { newId in
                // 切换时把选中 chip 滚到可见区
                if let newId {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(newId, anchor: .center)
                    }
                }
            }
            .onAppear {
                // 首次进入时把当前选中 chip 滚到中央（外部带 preferredCategoryId 时常态非首位）
                if let sid = slice?.id {
                    DispatchQueue.main.async {
                        proxy.scrollTo(sid, anchor: .center)
                    }
                }
            }
        }
        .background(Color.appCanvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.divider).frame(height: NotionTheme.borderWidth)
        }
    }

    @ViewBuilder
    private func categoryChip(_ cat: StatsCategorySlice) -> some View {
        let isActive = (slice?.id == cat.id)
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategoryId = cat.id
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: cat.icon)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(isActive ? cat.tone.text(scheme) : Color.inkSecondary)
                Text(cat.name)
                    .font(.custom("PingFangSC-Semibold", size: 13))
                    .foregroundStyle(isActive ? cat.tone.text(scheme) : Color.inkSecondary)
            }
            .padding(.horizontal, NotionTheme.space4)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? cat.tone.background(scheme) : Color.hoverBg)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isActive ? cat.tone.text(scheme).opacity(0.3) : Color.clear,
                                  lineWidth: isActive ? 1 : 0)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(cat.name) 分类\(isActive ? "，已选中" : "")")
    }

    private var customNav: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(slice?.name ?? "分类详情")
                    .font(.custom("PingFangSC-Semibold", size: 17))
                    .foregroundStyle(Color.inkPrimary)
                Text(StatsFormat.ymSubtitle(vm.month))
                    .font(.custom("PingFangSC-Regular", size: 11))
                    .foregroundStyle(Color.inkTertiary)
            }
            HStack {
                BackButton()
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, NotionTheme.space4)
        .frame(height: 52)
        .background(Color.appCanvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.divider).frame(height: NotionTheme.borderWidth)
        }
    }

    @ViewBuilder
    private func categoryHero(slice: StatsCategorySlice) -> some View {
        VStack(spacing: NotionTheme.space5) {
            ZStack {
                Circle()
                    .fill(slice.tone.background(scheme))
                    .frame(width: 64, height: 64)
                Image(systemName: slice.icon)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(slice.tone.text(scheme))
            }

            VStack(spacing: 4) {
                Text("本月支出")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
                Text("¥" + StatsFormat.intGrouped(slice.amount))
                    .font(.system(size: 36, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(slice.tone.text(scheme))
            }

            HStack(spacing: NotionTheme.space5) {
                miniStat(label: "笔数", value: "\(slice.count)")
                vDivider
                miniStat(label: "笔均",
                         value: "¥" + StatsFormat.intGrouped(slice.count > 0
                                                            ? slice.amount / Decimal(slice.count)
                                                            : 0))
                vDivider
                let pctText: String = {
                    guard prevAmount > 0 else { return slice.amount > 0 ? "新增" : "—" }
                    let cur = (slice.amount as NSDecimalNumber).doubleValue
                    let prv = (prevAmount as NSDecimalNumber).doubleValue
                    let pct = (cur - prv) / prv * 100
                    return String(format: "%@%.1f%%", pct >= 0 ? "+" : "", pct)
                }()
                let pctTone: Color = {
                    guard prevAmount > 0 else { return Color.inkSecondary }
                    return slice.amount >= prevAmount
                        ? NotionColor.red.text(scheme)
                        : NotionColor.green.text(scheme)
                }()
                miniStat(label: "环比", value: pctText, tone: pctTone)
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
    private func miniStat(label: String, value: String, tone: Color = .inkPrimary) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
            Text(value)
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

    @ViewBuilder
    private func monthlyTrendCard(slice: StatsCategorySlice) -> some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            Text("\(slice.name) · 近 6 个月")
                .font(.custom("PingFangSC-Semibold", size: 14))
                .foregroundStyle(Color.inkPrimary)
                .padding(.leading, 4)

            Chart {
                ForEach(Array(sixMonths.enumerated()), id: \.offset) { _, m in
                    BarMark(x: .value("月份", m.month),
                            y: .value("金额", (m.amount as NSDecimalNumber).doubleValue))
                    .foregroundStyle(slice.tone.text(scheme).opacity(m.isCurrent ? 1.0 : 0.65))
                    .cornerRadius(4)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let s = value.as(String.self) {
                            Text(s)
                                .font(.custom("PingFangSC-Regular", size: 10))
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
            .frame(height: 160)
            .padding(NotionTheme.space5)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                    .fill(Color.hoverBg.opacity(0.5))
            )
        }
    }

    @ViewBuilder
    private func recordsList(slice: StatsCategorySlice) -> some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            HStack {
                Text("本月明细")
                    .font(.custom("PingFangSC-Semibold", size: 14))
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
                Text("共 \(thisMonthRecords.count) 笔")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
            }
            .padding(.leading, 4)
            VStack(spacing: 0) {
                let items = thisMonthRecords.prefix(20)
                let arr = Array(items)
                ForEach(Array(arr.enumerated()), id: \.element.id) { idx, r in
                    detailRow(record: r)
                    if idx < arr.count - 1 {
                        Rectangle().fill(Color.divider).frame(height: 0.5)
                            .padding(.leading, NotionTheme.space5 + 36 + NotionTheme.space4)
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
    private func detailRow(record: Record) -> some View {
        let dateText = StatsCategoryDetailView.formatMD(record.occurredAt)
        HStack(spacing: NotionTheme.space4) {
            Text(dateText)
                .font(.custom("PingFangSC-Semibold", size: 13))
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 36, alignment: .leading)
            Text(record.note?.isEmpty == false ? record.note! : "—")
                .font(NotionFont.body())
                .foregroundStyle(Color.inkPrimary)
                .lineLimit(1)
            Spacer()
            Text("-¥" + StatsFormat.intGrouped(record.amount))
                .font(NotionFont.amount(size: 14))
                .foregroundStyle(NotionColor.red.text(scheme))
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 14)
    }

    private static func formatMD(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: d)
    }
}

/// 通用的 NavBar 返回按钮，复用 dismiss 环境。
private struct BackButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.inkPrimary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("返回")
    }
}
