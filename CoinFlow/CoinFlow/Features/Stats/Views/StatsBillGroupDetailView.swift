//  StatsBillGroupDetailView.swift
//  CoinFlow · M13 · 账单分组详情下钻

import SwiftUI

struct StatsBillGroupDetailView: View {
    let billGroupId: String
    @StateObject private var vm: StatsViewModel
    @Environment(\.colorScheme) private var scheme

    init(billGroupId: String, month: YearMonth) {
        self.billGroupId = billGroupId
        _vm = StateObject(wrappedValue: StatsViewModel(month: month))
    }

    private var groupName: String {
        (try? SQLiteBillGroupRepository.shared.find(id: billGroupId))?.name ?? "账单分组"
    }

    /// 仅统计当月支出记录，与 StatsBillGroupView 列表页 `buildBillGroupSlices` 口径一致
    private var filteredRecords: [Record] {
        let monthInterval = vm.month.dateInterval(in: Calendar.current)
        return vm.allRecords.filter { r in
            r.billGroupId == billGroupId
            && r.deletedAt == nil
            && (vm.categoriesById[r.categoryId]?.kind ?? .expense) == .expense
            && monthInterval.contains(r.occurredAt)
        }
    }

    private var categorySlices: [StatsCategorySlice] {
        let records = filteredRecords
        guard !records.isEmpty else { return [] }
        var byCat: [String: (amount: Decimal, count: Int)] = [:]
        for r in records {
            var s = byCat[r.categoryId] ?? (0, 0)
            s.amount += r.amount
            s.count += 1
            byCat[r.categoryId] = s
        }
        let total = records.map(\.amount).reduce(Decimal(0), +)
        let totalDouble = (total as NSDecimalNumber).doubleValue
        return byCat.compactMap { (cid, s) -> StatsCategorySlice? in
            guard let cat = vm.categoriesById[cid] else { return nil }
            let pct = totalDouble > 0 ? (s.amount as NSDecimalNumber).doubleValue / totalDouble : 0
            return StatsCategorySlice(
                id: cid, name: cat.name, icon: cat.icon,
                kind: cat.kind, tone: NotionColorMapper.from(colorHex: cat.colorHex),
                amount: s.amount, count: s.count, percentage: pct
            )
        }.sorted { $0.amount > $1.amount }
    }

    var body: some View {
        VStack(spacing: 0) {
            StatsSubNavBar(title: groupName,
                           subtitle: StatsFormat.ymSubtitle(vm.month))
            if filteredRecords.isEmpty {
                StatsEmptyState(title: "该分组暂无流水",
                                subtitle: "本月没有归属于此分组的记录")
            } else {
                ScrollView {
                    VStack(spacing: NotionTheme.space7) {
                        categorySection
                        recordsSection
                    }
                    .padding(.horizontal, NotionTheme.space5)
                    .padding(.top, NotionTheme.space6)
                    .padding(.bottom, NotionTheme.space9)
                }
            }
        }
        .background(ThemedBackgroundLayer(kind: .stats))
        .navigationBarHidden(true)
        .hideTabBar()
        .onAppear { vm.reload() }
    }

    // MARK: - Category breakdown

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            sectionHeader("分类构成")
            HStack(spacing: NotionTheme.space6) {
                StatsDonutChart(items: categorySlices, scheme: scheme)
                    .frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(categorySlices.prefix(5)) { cat in
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
            Text("¥\(StatsFormat.decimalGrouped(cat.amount))")
                .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - Records list

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            sectionHeader("流水明细（\(filteredRecords.count) 笔）")
            VStack(spacing: 0) {
                let sorted = filteredRecords.sorted { $0.occurredAt > $1.occurredAt }
                ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, record in
                    RecordRow(
                        record: record,
                        category: vm.categoriesById[record.categoryId]
                    )
                    if idx < sorted.count - 1 {
                        Rectangle().fill(Color.divider).frame(height: 0.5)
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
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.custom("PingFangSC-Semibold", size: 14))
                .foregroundStyle(Color.inkPrimary)
            Spacer()
        }
        .padding(.leading, 4)
    }
}
