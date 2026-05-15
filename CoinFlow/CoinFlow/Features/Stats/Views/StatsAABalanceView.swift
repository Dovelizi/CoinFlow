//  StatsAABalanceView.swift
//  CoinFlow · Stats · AA 账本数据统计
//
//  M11+ 重写：从原"等待 V2"占位升级为真正的 AA 数据统计页。
//  所有统计均按 StatsHubView 顶部月份选择器联动（"最近活跃"除外）：
//  - Hero：当月 AA 金额 + 当月活跃账本数 + 当月流水数
//  - 状态分组：当月活跃账本中，记录中 / 结算中 / 已完成 各自数量与金额
//  - 已结算 · 本月：当月已结算账本数 + "我"在本月被分摊的金额（回写流水合计）
//  - 最近活跃：前 5 个 AA 账本卡片（跨月，按 lastRecordAt 倒序），点击跳详情

import SwiftUI

struct StatsAABalanceView: View {

    /// 由 StatsHubView 顶部月份选择器传入；用于驱动"已结算 · YYYY-M月"卡片的本月口径。
    let month: YearMonth

    @StateObject private var vm: StatsAABalanceViewModel

    init(month: YearMonth = .current) {
        self.month = month
        _vm = StateObject(wrappedValue: StatsAABalanceViewModel(month: month))
    }

    var body: some View {
        VStack(spacing: 0) {
            StatsSubNavBar(title: "AA 账本",
                           subtitle: vm.subtitle)
            ScrollView {
                VStack(spacing: NotionTheme.space6) {
                    if !vm.hasAnyLedger {
                        emptyContent
                    } else if vm.totalLedgerCount == 0 {
                        monthEmptyContent
                    } else {
                        heroCard
                        statusBreakdown
                        balanceCard
                        if !vm.recentLedgers.isEmpty {
                            recentSection
                        }
                    }
                    if let err = vm.loadError {
                        Text(err)
                            .font(NotionFont.small())
                            .foregroundStyle(Color.dangerRed)
                            .padding()
                    }
                }
                .padding(.horizontal, NotionTheme.space5)
                .padding(.top, NotionTheme.space6)
                .padding(.bottom, NotionTheme.space9)
            }
        }
        .background(ThemedBackgroundLayer(kind: .stats))
        .navigationBarHidden(true)
        .hideTabBar()
        .onAppear { vm.reload() }
    }

    // MARK: - Hero（当月金额 + 账本数）

    private var heroCard: some View {
        VStack(spacing: NotionTheme.space3) {
            Text("\(vm.monthLabel) AA 金额")
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
            Text("¥" + StatsFormat.decimalGrouped(vm.totalAmount))
                .font(.system(size: 38, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.inkPrimary)
            Text("\(vm.totalLedgerCount) 个活跃 AA 账本 · \(vm.totalRecordCount) 笔流水")
                .font(NotionFont.small())
                .foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(NotionTheme.space6)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .fill(Color.hoverBg.opacity(0.5))
        )
    }

    // MARK: - 状态分组（3 个统计卡）

    private var statusBreakdown: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            Text("按状态")
                .font(NotionFont.bodyBold())
                .foregroundStyle(Color.inkPrimary)
            HStack(spacing: NotionTheme.space3) {
                statusPill(title: "记录中",
                           count: vm.recordingCount,
                           amount: vm.recordingAmount,
                           color: Color.accentBlue)
                statusPill(title: "结算中",
                           count: vm.settlingCount,
                           amount: vm.settlingAmount,
                           color: Color.statusWarning)
                statusPill(title: "已完成",
                           count: vm.completedCount,
                           amount: vm.completedAmount,
                           color: Color.statusSuccess)
            }
        }
    }

    private func statusPill(title: String,
                            count: Int,
                            amount: Decimal,
                            color: Color) -> some View {
        VStack(alignment: .leading, spacing: NotionTheme.space2) {
            Text(title)
                .font(NotionFont.micro())
                .foregroundStyle(color)
            Text("\(count)")
                .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.inkPrimary)
            Text("¥" + StatsFormat.compactK(amount))
                .font(NotionFont.micro().monospacedDigit())
                .foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NotionTheme.space4)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .fill(color.opacity(0.10))
        )
    }

    // MARK: - 已结算 · 本月（账单数 + 个人分账支付金额）

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            Text("已结算 · \(vm.monthLabel)")
                .font(NotionFont.bodyBold())
                .foregroundStyle(Color.inkPrimary)
            HStack(spacing: NotionTheme.space5) {
                balanceColumn(title: "已结算账单",
                              value: "\(vm.completedCount) 个",
                              color: Color.statusSuccess)
                Divider().frame(height: 36)
                balanceColumn(title: "本月个人支付",
                              value: "¥" + StatsFormat.decimalGrouped(vm.monthlySettledPaid),
                              color: Color.dangerRed)
            }
            .padding(NotionTheme.space5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                    .fill(Color.hoverBg.opacity(0.5))
            )
            Text("数据来源：已完成 AA 账本回写到个人账单的流水（本月 occurredAt）")
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
        }
    }

    private func balanceColumn(title: String,
                               value: String,
                               color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 最近活跃（前 5）

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            Text("最近活跃")
                .font(NotionFont.bodyBold())
                .foregroundStyle(Color.inkPrimary)
            VStack(spacing: NotionTheme.space3) {
                ForEach(vm.recentLedgers) { item in
                    NavigationLink(value: AASplitListDestination(ledgerId: item.ledger.id)) {
                        recentRow(item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func recentRow(_ item: AASplitListItem) -> some View {
        HStack(spacing: NotionTheme.space4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.ledger.name)
                    .font(NotionFont.body())
                    .foregroundStyle(Color.inkPrimary)
                    .lineLimit(1)
                if let last = item.lastRecordAt {
                    Text("最近 \(formatRelative(last)) · \(item.recordCount) 笔")
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.inkTertiary)
                } else {
                    Text("尚无流水")
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.inkTertiary)
                }
            }
            Spacer()
            Text("¥" + StatsFormat.decimalGrouped(item.totalAmount))
                .font(NotionFont.body().monospacedDigit())
                .foregroundStyle(Color.inkPrimary)
            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundStyle(Color.inkTertiary)
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .fill(Color.hoverBg.opacity(0.5))
        )
    }

    // “从未启用 AA”的空态：全量不存在任何 AA 账本
    private var emptyContent: some View {
        StatsEmptyState(
            title: "还没有 AA 账本",
            subtitle: "在「账单」Tab 切到 AA 视图即可创建分账，旅游、聚餐等场景的账目会在这里聚合显示"
        )
        .frame(height: 360)
    }

    // “选中月无活动”的空态：用户有 AA 账本，但该月未产生任何流水
    private var monthEmptyContent: some View {
        StatsEmptyState(
            title: "\(vm.monthLabel)无 AA 活动",
            subtitle: "该月份没有产生任何 AA 账本流水，可在顶部切换其他月份查看"
        )
        .frame(height: 360)
    }

    // MARK: - 工具

    private func formatRelative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}

// MARK: - ViewModel

@MainActor
final class StatsAABalanceViewModel: ObservableObject {

    @Published private(set) var totalAmount: Decimal = 0
    @Published private(set) var totalLedgerCount: Int = 0
    @Published private(set) var totalRecordCount: Int = 0
    /// 区分两种空态：“从未启用 AA” vs “本月无活动”。
    /// 为 true 表示用户的确存在 AA 账本（不论哪个月），仅可能选中月不活跃。
    @Published private(set) var hasAnyLedger: Bool = false

    @Published private(set) var recordingCount: Int = 0
    @Published private(set) var recordingAmount: Decimal = 0
    @Published private(set) var settlingCount: Int = 0
    @Published private(set) var settlingAmount: Decimal = 0
    @Published private(set) var completedCount: Int = 0
    @Published private(set) var completedAmount: Decimal = 0

    /// 由外部（StatsHubView 顶部月份选择器）注入，用于驱动"已结算 · YYYY-M月"卡片的月份口径。
    private let month: YearMonth
    /// 当月所有已完成 AA 账本回写到个人账本的占位流水中、kind=expense、
    /// 且 occurredAt 落在所选月的金额合计（= "我"在该月各次结算中的应分摊总和）。
    @Published private(set) var monthlySettledPaid: Decimal = 0

    init(month: YearMonth = .current) {
        self.month = month
    }

    /// 卡片标题用："YYYY-M月"（与系统 Calendar 当前月一致）
    var monthLabel: String { "\(month.year)-\(month.month)月" }

    @Published private(set) var recentLedgers: [AASplitListItem] = []
    @Published private(set) var loadError: String?

    var subtitle: String {
        if !hasAnyLedger { return "等待启用" }
        if totalLedgerCount == 0 { return "\(monthLabel) 无活动" }
        return "\(totalLedgerCount) 个活跃账本 · 已结算 \(completedCount)"
    }

    func reload() {
        do {
            let ledgers = try SQLiteLedgerRepository.shared
                .listAA(status: nil, includeArchived: false)

            // 月口径区间：用于过滤每个 AA 账本下的流水
            let curInterval = month.dateInterval(in: Calendar.current)

            // monthlyAmounts[ledgerId] = 该账本在选中月内未删流水的金额合计
            // monthlyCounts [ledgerId] = 该账本在选中月内未删流水的笔数
            // 同时构建全量 items（供"最近活跃"使用，要保留 lastRecordAt 全量倒序语义）
            var items: [AASplitListItem] = []
            var monthlyAmounts: [String: Decimal] = [:]
            var monthlyCounts: [String: Int] = [:]
            for l in ledgers {
                let records = try SQLiteRecordRepository.shared.list(
                    RecordQuery(ledgerId: l.id, limit: 5000)
                )
                let visible = records.filter { $0.deletedAt == nil }
                let total = visible.reduce(Decimal(0)) { $0 + $1.amount }
                let last = visible.map(\.occurredAt).max()
                let memberCount = (try? SQLiteAAMemberRepository.shared
                    .list(ledgerId: l.id).count) ?? 0
                items.append(AASplitListItem(
                    ledger: l,
                    totalAmount: total,
                    recordCount: visible.count,
                    lastRecordAt: last,
                    memberCount: memberCount
                ))
                let monthVisible = visible.filter { curInterval.contains($0.occurredAt) }
                if !monthVisible.isEmpty {
                    monthlyAmounts[l.id] = monthVisible.reduce(Decimal(0)) { $0 + $1.amount }
                    monthlyCounts[l.id] = monthVisible.count
                }
            }

            // 月活跃子集：选中月内至少有 1 笔未删流水的账本
            // 总览/状态分组/已结算账单数全部基于此子集，金额改用月内流水合计
            // （与 StatsHubView AA 卡片"X 个 / 记录中 X · 当月 Y 笔"口径一致）
            let monthlyItems = items.filter { monthlyCounts[$0.ledger.id] != nil }

            hasAnyLedger = !items.isEmpty
            totalLedgerCount = monthlyItems.count
            totalAmount = monthlyItems.reduce(Decimal(0)) {
                $0 + (monthlyAmounts[$1.ledger.id] ?? 0)
            }
            totalRecordCount = monthlyItems.reduce(0) {
                $0 + (monthlyCounts[$1.ledger.id] ?? 0)
            }

            // 状态分组（在月活跃子集内按状态拆）
            let recording = monthlyItems.filter { $0.status == .recording }
            let settling  = monthlyItems.filter { $0.status == .settling }
            let completed = monthlyItems.filter { $0.status == .completed }
            recordingCount  = recording.count
            recordingAmount = recording.reduce(Decimal(0)) {
                $0 + (monthlyAmounts[$1.ledger.id] ?? 0)
            }
            settlingCount   = settling.count
            settlingAmount  = settling.reduce(Decimal(0)) {
                $0 + (monthlyAmounts[$1.ledger.id] ?? 0)
            }
            completedCount  = completed.count
            completedAmount = completed.reduce(Decimal(0)) {
                $0 + (monthlyAmounts[$1.ledger.id] ?? 0)
            }

            // 本月个人支付：扫所有已 completed 账本（注意此处仍需用全量 completed 集合，
            // 因为"我"在 X 月的回写支付可能落到"非 X 月活跃"的老账本上 —— 占位流水的 occurredAt
            // 由结算时间决定，与原始流水所在月不必一致），对应 default ledger 上带 aaSettlementId
            // 的回写流水，仅统计 kind=expense 且 occurredAt 落在所选月的金额。
            let allCompleted = items.filter { $0.status == .completed }
            let categories = (try? SQLiteCategoryRepository.shared
                .list(kind: nil, includeDeleted: true)) ?? []
            let catKindById: [String: CategoryKind] = Dictionary(
                uniqueKeysWithValues: categories.map { ($0.id, $0.kind) }
            )
            var monthlyPaid: Decimal = 0
            for c in allCompleted {
                let writebacks = (try? SQLiteRecordRepository.shared
                    .findByAASettlementId(c.ledger.id)) ?? []
                for r in writebacks
                where r.deletedAt == nil
                   && catKindById[r.categoryId] == .expense
                   && curInterval.contains(r.occurredAt) {
                    monthlyPaid += r.amount
                }
            }
            monthlySettledPaid = monthlyPaid

            // 最近活跃前 5（按最后流水时间倒序，没有流水的排后面）
            // 此处仍用全量 items —— "最近活跃"语义本就跨月，不应被月切换裁剪
            recentLedgers = items.sorted { a, b in
                switch (a.lastRecordAt, b.lastRecordAt) {
                case let (la?, lb?): return la > lb
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return a.ledger.createdAt > b.ledger.createdAt
                }
            }.prefix(5).map { $0 }

            loadError = nil
        } catch {
            loadError = "加载失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 添加 AA 成员 Sheet
//
// 当前阶段（M1-M7）AA 账本字段虽建表但无完整数据流，无法真正"添加成员"并落库。
// "简洁优先"：sheet 内只做"V2 内测预约"占位 + 演示性输入框，避免假数据/假交互。
// 用户填了昵称会被保存到 UserDefaults 作为下次默认值，等 V2 上线时无缝迁移。

private struct AAMemberAddSheet: View {
    @AppStorage("aa.preview.nicknames") private var nicknames: String = ""
    @State private var input: String = ""
    @Environment(\.dismiss) private var dismiss

    private var savedList: [String] {
        nicknames
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.accentBlue)
                        Text("AA 账本将在 V2 开放：创建账本 / 邀请成员 / 自动结算。先收集您的常用 AA 伙伴，V2 上线后会自动同步。")
                            .font(NotionFont.small())
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("V2 即将上线")
                }

                Section("添加常用 AA 伙伴") {
                    HStack {
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundStyle(Color.inkTertiary)
                        TextField("输入昵称", text: $input)
                            .submitLabel(.done)
                            .onSubmit { addNickname() }
                        Button {
                            addNickname()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(input.trimmingCharacters(in: .whitespaces).isEmpty
                                                 ? Color.inkTertiary
                                                 : Color.accentBlue)
                        }
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if !savedList.isEmpty {
                    Section("已添加（\(savedList.count) 人）") {
                        ForEach(savedList, id: \.self) { name in
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(Color.accentPurple)
                                Text(name)
                                Spacer()
                                Button {
                                    remove(name)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(Color.inkTertiary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("AA 成员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func addNickname() {
        let name = input.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var arr = savedList
        guard !arr.contains(name) else {
            input = ""
            return
        }
        arr.append(name)
        nicknames = arr.joined(separator: ",")
        input = ""
    }

    private func remove(_ name: String) {
        let arr = savedList.filter { $0 != name }
        nicknames = arr.joined(separator: ",")
    }
}
