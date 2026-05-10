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
            let all = try SQLiteRecordRepository.shared.list(.init(
                ledgerId: ledgerId,
                includesDeleted: false,
                limit: 2000
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
            let split = AmountFormatter.split(filtered) { [weak self] cid in
                self?.categoryById[cid]?.kind ?? .expense
            }
            totalExpense = split.expense
            totalIncome  = split.income
            loadError = nil
        } catch {
            loadError = error.localizedDescription
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
