//  AAShareEditSection.swift
//  CoinFlow · M11 — 结算阶段·流水分摊编辑
//
//  - 列出本账本所有支出 record，每行右侧渲染参与者 chip 组（默认全选）
//  - 点选/取消选 chip → recomputeShares 重算均分
//  - 支持「高级模式」：每位参与者自定义金额（AmountTextField），实时显示差额红字

import SwiftUI

struct AAShareEditSection: View {

    @ObservedObject var vm: AASplitDetailViewModel
    @State private var advancedRecord: Record? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space5) {
            HStack {
                Text("流水分摊")
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
                Text("\(vm.visibleRecords.count) 笔")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
            }
            if vm.members.isEmpty {
                Text("先添加成员才能开始分摊")
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(NotionTheme.space5)
                    .background(
                        RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                            .fill(Color.hoverBg.opacity(0.5))
                    )
            } else if vm.visibleRecords.isEmpty {
                Text("当前账本暂无流水")
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkTertiary)
            } else {
                VStack(spacing: NotionTheme.space3) {
                    ForEach(vm.visibleRecords) { r in
                        recordRow(r)
                    }
                }
            }
        }
        .sheet(item: $advancedRecord) { r in
            AdvancedShareSheet(vm: vm, record: r)
                .presentationDetents([.medium, .large])
        }
    }

    private func recordRow(_ r: Record) -> some View {
        let participating = participatingMemberIds(for: r)
        let perHead = participating.isEmpty
            ? Decimal(0)
            : decimalDiv(r.amount, by: participating.count)
        let isCustom = vm.shares.contains(where: { $0.recordId == r.id && $0.isCustom && $0.deletedAt == nil })
        let diff = (try? vm.validateCustomBalance(recordId: r.id)) ?? 0

        return VStack(alignment: .leading, spacing: NotionTheme.space3) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.note ?? "未填备注")
                        .font(NotionFont.body())
                        .foregroundStyle(Color.inkPrimary)
                        .lineLimit(1)
                    Text("¥" + StatsFormat.decimalGrouped(r.amount))
                        .font(NotionFont.micro().monospacedDigit())
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer()
                // 高级模式标识：仅在已使用自定义分摊时展示徽标，
                // 不再提供独立按钮——点击整行打开分摊编辑器，避免与行点击重复
                if isCustom {
                    Text("自定义中")
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.accentBlue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentBlue.opacity(0.12))
                        )
                }
            }

            // 参与者 chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(vm.members) { m in
                        let on = participating.contains(m.id)
                        Button {
                            Haptics.select()
                            toggleParticipant(record: r, memberId: m.id, currentlyOn: on)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: on ? "checkmark" : "plus")
                                    .font(.system(size: 9, weight: .bold))
                                Text(m.name)
                                    .font(NotionFont.micro())
                            }
                            .foregroundStyle(on ? Color.white : Color.inkSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(on ? Color.accentBlue : Color.hoverBg)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isCustom)
                    }
                }
            }

            // 状态行
            HStack {
                if participating.isEmpty {
                    Text("无参与者 · 由当前用户独自承担")
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.inkTertiary)
                } else if !isCustom {
                    Text("人均 ¥\(StatsFormat.decimalGrouped(perHead))")
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.inkTertiary)
                } else {
                    Text("自定义模式")
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.accentBlue)
                }
                Spacer()
                if isCustom && diff != 0 {
                    Text("差额：¥\(StatsFormat.decimalGrouped(abs(diff)))")
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.dangerRed)
                }
            }
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .fill(Color.hoverBg.opacity(0.5))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // 点击整行 → 打开自定义分摊编辑器（替代原"高级模式"按钮）
            advancedRecord = r
        }
    }

    private func participatingMemberIds(for r: Record) -> Set<String> {
        Set(vm.shares
            .filter { $0.recordId == r.id && $0.deletedAt == nil }
            .map { $0.memberId })
    }

    private func toggleParticipant(record r: Record, memberId: String, currentlyOn: Bool) {
        let participating = participatingMemberIds(for: r)
        let next: Set<String> = currentlyOn
            ? participating.subtracting([memberId])
            : participating.union([memberId])

        // 先清掉该 record 现有的 share
        try? SQLiteAAShareRepository.shared.deleteByRecord(recordId: r.id)
        // 重新写入按新参与者均分
        if !next.isEmpty {
            let perHead = decimalDiv(r.amount, by: next.count)
            for mid in next {
                try? SQLiteAAShareRepository.shared.upsert(
                    recordId: r.id, memberId: mid, amount: perHead, isCustom: false
                )
            }
        }
        vm.reload()
    }

    private func decimalDiv(_ x: Decimal, by n: Int) -> Decimal {
        guard n > 0 else { return 0 }
        var dividend = x
        var divisor = Decimal(n)
        var result = Decimal()
        NSDecimalDivide(&result, &dividend, &divisor, .bankers)
        var rounded = Decimal()
        var src = result
        NSDecimalRound(&rounded, &src, 4, .bankers)
        return rounded
    }
}

// MARK: - 高级模式 Sheet：按成员设置自定义金额

private struct AdvancedShareSheet: View {

    @ObservedObject var vm: AASplitDetailViewModel
    let record: Record
    @Environment(\.dismiss) private var dismiss
    @State private var amountTexts: [String: String] = [:]

    private var totalEntered: Decimal {
        amountTexts.values
            .compactMap { Decimal(string: $0.trimmingCharacters(in: .whitespaces)) }
            .reduce(Decimal(0)) { $0 + $1 }
    }

    private var diff: Decimal { record.amount - totalEntered }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("流水")
                        Spacer()
                        Text(record.note ?? "未填备注")
                            .foregroundStyle(Color.inkSecondary)
                    }
                    HStack {
                        Text("总金额")
                        Spacer()
                        Text("¥" + StatsFormat.decimalGrouped(record.amount))
                            .foregroundStyle(Color.inkPrimary)
                    }
                }

                Section("按成员分摊") {
                    ForEach(vm.members) { m in
                        HStack {
                            Text(m.avatarEmoji ?? "👤")
                            Text(m.name)
                            Spacer()
                            TextField("0", text: binding(for: m.id))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("已分摊合计")
                        Spacer()
                        Text("¥" + StatsFormat.decimalGrouped(totalEntered))
                            .foregroundStyle(Color.inkSecondary)
                    }
                    HStack {
                        Text("差额")
                        Spacer()
                        Text("¥" + StatsFormat.decimalGrouped(abs(diff)))
                            .foregroundStyle(diff == 0 ? Color.statusSuccess : Color.dangerRed)
                    }
                } footer: {
                    if diff != 0 {
                        Text(diff > 0
                             ? "还差 ¥\(StatsFormat.decimalGrouped(diff)) 未分摊；提交时将阻塞结算完成。"
                             : "超出总金额 ¥\(StatsFormat.decimalGrouped(-diff))。")
                    }
                }
            }
            .navigationTitle("自定义分摊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { preload() }
        }
    }

    private func binding(for memberId: String) -> Binding<String> {
        Binding(
            get: { amountTexts[memberId] ?? "" },
            set: { amountTexts[memberId] = $0 }
        )
    }

    private func preload() {
        for m in vm.members {
            if let s = vm.shares.first(where: { $0.recordId == record.id && $0.memberId == m.id && $0.deletedAt == nil }) {
                amountTexts[m.id] = "\(s.amount)"
            } else {
                amountTexts[m.id] = ""
            }
        }
    }

    private func save() {
        // 先清掉该 record 的所有 share
        try? SQLiteAAShareRepository.shared.deleteByRecord(recordId: record.id)
        for m in vm.members {
            let raw = (amountTexts[m.id] ?? "").trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty, let v = Decimal(string: raw), v > 0 else { continue }
            try? SQLiteAAShareRepository.shared.upsert(
                recordId: record.id, memberId: m.id, amount: v, isCustom: true
            )
        }
        vm.reload()
        Haptics.success()
        dismiss()
    }
}
