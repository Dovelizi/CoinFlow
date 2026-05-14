//  AASplitListViewModel.swift
//  CoinFlow · M11 — AA 分账主页 VM

import Foundation
import Combine
import SwiftUI

/// 一行展示用的聚合数据。
struct AASplitListItem: Identifiable, Equatable {
    let ledger: Ledger
    let totalAmount: Decimal      // 累计金额（该 Ledger 下所有未删除流水合计）
    let recordCount: Int          // 流水数
    let lastRecordAt: Date?       // 最近一笔时间
    let memberCount: Int          // 成员数（结算阶段用）

    var id: String { ledger.id }
    var status: AAStatus { ledger.aaStatus ?? .recording }
}

/// 列表过滤 Tab。
enum AASplitListFilter: String, CaseIterable, Identifiable {
    case all
    case recording
    case settling
    case completed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部"
        case .recording: return "记录中"
        case .settling: return "结算中"
        case .completed: return "已完成"
        }
    }

    fileprivate var statusFilter: AAStatus? {
        switch self {
        case .all: return nil
        case .recording: return .recording
        case .settling: return .settling
        case .completed: return .completed
        }
    }
}

@MainActor
final class AASplitListViewModel: ObservableObject {

    @Published private(set) var items: [AASplitListItem] = []
    @Published private(set) var loadError: String?
    @Published var filter: AASplitListFilter = .all

    private var cancellables: Set<AnyCancellable> = []

    init() {
        // 监听 record 变化以刷新累计金额
        NotificationCenter.default
            .publisher(for: .recordsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellables)
    }

    var filteredItems: [AASplitListItem] {
        guard let status = filter.statusFilter else { return items }
        return items.filter { $0.status == status }
    }

    func reload() {
        do {
            let ledgers = try SQLiteLedgerRepository.shared
                .listAA(status: nil, includeArchived: false)
            var aggregated: [AASplitListItem] = []
            for l in ledgers {
                let records = try SQLiteRecordRepository.shared.list(
                    RecordQuery(ledgerId: l.id, limit: 5000)
                )
                let visible = records.filter { $0.deletedAt == nil }
                let total = visible.reduce(Decimal(0)) { $0 + $1.amount }
                let last = visible.map(\.occurredAt).max()
                let members = (try? SQLiteAAMemberRepository.shared.list(ledgerId: l.id)) ?? []
                aggregated.append(AASplitListItem(
                    ledger: l,
                    totalAmount: total,
                    recordCount: visible.count,
                    lastRecordAt: last,
                    memberCount: members.count
                ))
            }
            self.items = aggregated
            self.loadError = nil
        } catch {
            self.loadError = "加载失败：\(error.localizedDescription)"
        }
    }

    /// 删除一个 AA 账本：直接委托给 AASplitService.deleteSplit，
    /// 由 Service 在事务内级联软删 share / member / 内部 record / 个人账单占位 / ledger 本身，
    /// 并广播 RecordChangeNotifier 触发账单列表 / 统计 / 详情刷新。
    ///
    /// 设计：占位流水是 AA 账本在个人账单上的"投影"，与 AA 账本同生命周期；
    /// 删除 AA 账本必须联动软删占位，避免出现指向已删账本的孤儿流水。
    /// 联动逻辑只在 AASplitService.deleteSplit 中维护一份，本入口只做委托。
    func softDelete(id: String) {
        do {
            try AASplitService.shared.deleteSplit(ledgerId: id)
        } catch {
            self.loadError = "删除失败：\(error.localizedDescription)"
        }
        reload()
    }
}
