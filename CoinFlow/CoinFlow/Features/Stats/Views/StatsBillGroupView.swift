//  StatsBillGroupView.swift
//  CoinFlow · M13 · 账单分组排行详情页

import SwiftUI

struct StatsBillGroupView: View {
    @StateObject private var vm: StatsViewModel
    @Environment(\.colorScheme) private var scheme

    init(month: YearMonth = .current) {
        _vm = StateObject(wrappedValue: StatsViewModel(month: month))
    }

    var body: some View {
        VStack(spacing: 0) {
            StatsSubNavBar(title: "账单分组",
                           subtitle: StatsFormat.ymSubtitle(vm.month))
            if vm.billGroupSlices.isEmpty {
                StatsEmptyState(title: "暂无账单分组数据",
                                subtitle: "添加流水后自动按分组统计")
            } else {
                ScrollView {
                    VStack(spacing: NotionTheme.space4) {
                        totalHeader
                        ForEach(Array(vm.billGroupSlices.enumerated()), id: \.element.id) { idx, slice in
                            billGroupRow(rank: idx + 1, slice: slice)
                        }
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

    private var totalHeader: some View {
        HStack {
            Text("共 \(vm.billGroupSlices.count) 个分组")
                .font(NotionFont.small())
                .foregroundStyle(Color.inkSecondary)
            Spacer()
            Text("总支出 ¥\(StatsFormat.decimalGrouped(vm.monthlyExpense))")
                .font(NotionFont.small())
                .foregroundStyle(Color.inkTertiary)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func billGroupRow(rank: Int, slice: StatsBillGroupSlice) -> some View {
        NavigationLink(value: BillGroupDetailTarget(billGroupId: slice.id, month: vm.month)) {
            HStack(spacing: NotionTheme.space4) {
                Text("\(rank)")
                    .font(.custom("PingFangSC-Semibold", size: 13))
                    .foregroundStyle(rank <= 3 ? Color.accentBlue : Color.inkTertiary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(slice.name)
                        .font(NotionFont.bodyBold())
                        .foregroundStyle(Color.inkPrimary)
                    Text("\(slice.count) 笔 · \(Int(slice.percentage * 100))%")
                        .font(NotionFont.small())
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer()
                Text("¥" + StatsFormat.decimalGrouped(slice.amount))
                    .font(NotionFont.amount(size: 15))
                    .foregroundStyle(DirectionColor.amountForeground(kind: .expense))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.inkTertiary)
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                    .fill(Color.hoverBg.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
    }
}
