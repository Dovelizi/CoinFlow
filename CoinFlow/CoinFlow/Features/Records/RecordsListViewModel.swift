//  RecordsListViewModel.swift
//  CoinFlow · M3.2 · M7-Fix2
//
//  流水列表 VM：
//  - 启动时从 Repository 拉本地数据
//  - 订阅 RecordChangeNotifier，本地写入/Firestore 推送都自动 reload
//  - 按日分组（DateGrouping）+ 计算 InlineStatsBar 三段汇总
//  - 提供 categoryName/icon/colorHex/kind 查询（缓存所有分类）
//  - M7-Fix2：支持月份过滤 + 关键词搜索（备注 / 金额 / 分类名）

import Foundation
import SwiftUI
import Combine

@MainActor
final class RecordsListViewModel: ObservableObject {

    // MARK: - Published

    @Published private(set) var groups: [DayGroup] = []
    @Published private(set) var totalExpense: Decimal = 0
    @Published private(set) var totalIncome: Decimal = 0
    @Published private(set) var loadError: String?

    /// M7-Fix2：当前筛选的年月。nil = 全部；默认设为当前月
    @Published var selectedYearMonth: YearMonth? = YearMonth.current {
        didSet { reload() }
    }
    /// M7-Fix2：搜索关键词（备注 / 金额字符串 / 分类名 都参与匹配）
    @Published var searchQuery: String = "" {
        didSet { reload() }
    }

    // MARK: - Cache

    private var categoryById: [String: Category] = [:]
    /// AA 账本 id → 状态。用于 RecordRow 渲染"AA · 待结算"徽标 + 跳转 AA 详情页。
    /// reload 时从 ledger 表刷新。
    private(set) var aaLedgerStatusById: [String: AAStatus] = [:]
    /// AA 账本 id → 名称。用于点击未结算 AA 流水时跳到对应详情页。
    private(set) var aaLedgerNameById: [String: String] = [:]

    // MARK: - State

    private let ledgerId: String
    private var observer: NSObjectProtocol?

    init(ledgerId: String = DefaultSeeder.defaultLedgerId) {
        self.ledgerId = ledgerId
        startObserving()
        reload()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Reload

    /// 主动 reload：拉所有未删除 record + 所有分类（含已删除 — 历史 record 可能引用）
    func reload() {
        do {
            categoryById = Dictionary(
                uniqueKeysWithValues: try SQLiteCategoryRepository.shared
                    .list(kind: nil, includeDeleted: true)
                    .map { ($0.id, $0) }
            )
            // 方案 C1：账单 Tab 个人模式只展示 default-ledger 流水（含 AA 净额占位）。
            // - AA 原始流水属于 AA 账本（ledgerId != default），不在此处出现，
            //   只在 AA 详情页内可见、可改。
            // - 占位 = sourceKind == .aaSettlement，由 AASplitService 在 settling/completed
            //   时自动写入个人账本，承载"我"在该 AA 账本下的净额。
            // 同时缓存所有 AA 账本的 id→name 映射，供占位卡渲染"AA 分账·xxx 名称"。
            let aaLedgers = (try? SQLiteLedgerRepository.shared
                .listAA(status: nil, includeArchived: true)) ?? []
            aaLedgerStatusById = Dictionary(uniqueKeysWithValues: aaLedgers.compactMap { ledger in
                ledger.aaStatus.map { st in (ledger.id, st) }
            })
            aaLedgerNameById = Dictionary(uniqueKeysWithValues: aaLedgers.map { ($0.id, $0.name) })

            // 仅拉 default-ledger 流水
            let all = try SQLiteRecordRepository.shared.list(.init(
                ledgerId: ledgerId,
                includesDeleted: false,
                limit: 5000
            ))
            // M7-Fix2：按月过滤
            var filtered = all
            if let ym = selectedYearMonth {
                let cal = Calendar.current
                filtered = all.filter {
                    let c = cal.dateComponents([.year, .month], from: $0.occurredAt)
                    return c.year == ym.year && c.month == ym.month
                }
            }
            // M7-Fix2：关键词搜索
            let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
            if !q.isEmpty {
                filtered = filtered.filter { r in
                    let note = (r.note ?? "").lowercased()
                    if note.contains(q) { return true }
                    let amountStr = AmountFormatter.display(r.amount).lowercased()
                    if amountStr.contains(q) { return true }
                    if let cat = categoryById[r.categoryId], cat.name.lowercased().contains(q) {
                        return true
                    }
                    return false
                }
            }
            groups = DateGrouping.group(filtered)
            // 汇总：default-ledger 全集（普通流水 + AA 占位）。
            // 占位 categoryId = preset-income-transfer / preset-expense-other，
            // 走分类原本的 kind，不需要特殊处理。
            let split = AmountFormatter.split(filtered) { [weak self] cid in
                self?.categoryById[cid]?.kind ?? .expense
            }
            totalExpense = split.expense
            totalIncome  = split.income
            loadError = nil
            #if DEBUG
            let aaPlaceholderCount = filtered.filter { $0.sourceKind == .aaSettlement }.count
            print("[Records-Reload] ledgerId=\(ledgerId) all=\(all.count) filtered=\(filtered.count) groups=\(groups.count) aaPlaceholders=\(aaPlaceholderCount) ym=\(selectedYearMonth.map { "\($0.year)-\($0.month)" } ?? "nil")")
            for r in filtered where r.sourceKind == .aaSettlement {
                print("[Records-Reload]   aaPH id=\(r.id) amount=\(r.amount) note=\(r.note ?? "") occurredAt=\(r.occurredAt) status=\(r.settlementStatus?.rawValue ?? "nil")")
            }
            #endif
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// 行级标识：用于 RecordRow 渲染左侧"AA"徽标 + RecordsListView 决定点击行为
    /// 方案 C1：个人账单只可能见到"占位"流水，不再有 AA 原始流水。
    func aaInfo(for record: Record) -> RecordAABadge? {
        // 仅占位记录会有 badge。普通流水 (sourceKind == .normal) 一律 nil。
        guard record.sourceKind == .aaSettlement,
              let aaId = record.aaSettlementId, !aaId.isEmpty else {
            return nil
        }
        let name = aaLedgerNameById[aaId] ?? "AA"
        // settlementStatus 在写入时一定有值；为兜底兼容老数据，nil 视为 settled
        let status = record.settlementStatus ?? .settled
        switch status {
        case .settled:  return .settledPlaceholder(ledgerId: aaId, ledgerName: name)
        case .settling: return .settlingPlaceholder(ledgerId: aaId, ledgerName: name)
        }
    }

    // MARK: - Lookup（行视图用）

    func category(for record: Record) -> Category? {
        categoryById[record.categoryId]
    }

    var balance: Decimal { totalIncome - totalExpense }

    /// 当日净额（收入 - 支出），用于段头右侧的"¥xxx 当日合计"展示。
    /// 设计基线：design/screens/01-records-list/main-light.png 段头右侧。
    func dayNet(for group: DayGroup) -> Decimal {
        var inc: Decimal = 0
        var exp: Decimal = 0
        for r in group.records {
            let kind = categoryById[r.categoryId]?.kind ?? .expense
            switch kind {
            case .income:  inc += r.amount
            case .expense: exp += r.amount
            }
        }
        return inc - exp
    }

    // MARK: - Actions

    /// 删除。
    /// - Parameter localOnly:
    ///   - `false`（默认 · "都删除"）：软删 → SyncQueue 推送飞书行 `deleted=true`
    ///   - `true`（"仅删除本地"）：物理删除本地行，飞书不动；下次从飞书拉取时会被复活回来
    func delete(_ record: Record, localOnly: Bool = false) {
        do {
            if localOnly {
                try SQLiteRecordRepository.shared.hardDelete(id: record.id)
                // 不触发 SyncTrigger：飞书那条保持原样
            } else {
                try SQLiteRecordRepository.shared.delete(id: record.id)
                // delete 内部已 broadcast，监听回调会触发 reload
                // 触发一次 sync tick + 启动 listener，把软删事件推到云端（异步，不阻塞 UI）
                SyncTrigger.fire(reason: "recordsList.delete")
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Observation

    private func startObserving() {
        observer = NotificationCenter.default.addObserver(
            forName: .recordsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // hop 到 main actor（用 Task 保险）
            Task { @MainActor [weak self] in
                self?.reload()
            }
        }
    }
}

// MARK: - YearMonth

/// M7-Fix2：年月筛选值
struct YearMonth: Equatable, Hashable {
    let year: Int
    let month: Int   // 1...12

    static var current: YearMonth {
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        return YearMonth(year: c.year ?? 2026, month: c.month ?? 1)
    }
}

// MARK: - RecordAABadge

/// 单条流水的 AA 状态标记（方案 C1）：仅用于"个人账本上的 AA 占位"渲染与点击跳转。
/// AA 原始流水现在只存在于对应的 AA 账本里，不会出现在账单 Tab 个人模式列表中。
/// - settledPlaceholder：sourceKind == .aaSettlement 且 settlementStatus == .settled
///   → 紫色"AA·已结算"徽标
/// - settlingPlaceholder：sourceKind == .aaSettlement 且 settlementStatus == .settling
///   → 橙色"AA·结算中"徽标
/// 两者点击都跳转到对应 AA 账本详情页（只读语义；编辑要去 AA 详情页内对原始流水操作）。
enum RecordAABadge: Equatable {
    case settledPlaceholder(ledgerId: String, ledgerName: String)
    case settlingPlaceholder(ledgerId: String, ledgerName: String)

    /// 跳转目标 ledgerId（两种 case 都带）。
    var jumpLedgerId: String {
        switch self {
        case .settledPlaceholder(let id, _): return id
        case .settlingPlaceholder(let id, _): return id
        }
    }
}
