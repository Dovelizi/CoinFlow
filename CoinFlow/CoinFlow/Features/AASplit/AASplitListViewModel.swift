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

    /// 删除一个 AA 账本，级联清理与之关联的所有数据：
    /// 1. AA 账本本体（ledger 软删）
    /// 2. 该账本下所有内部流水（record.ledgerId == ledgerId）
    /// 3. 该账本下所有分账成员（aa_member）
    ///
    /// 注意：**保留**已经回写到个人账单的占位流水（record.aaSettlementId == ledgerId
    /// 且 sourceKind == .aaSettlement）。从用户视角来看，这条占位代表了一笔已经
    /// 完成的历史消费，删除分账账本本身不应连带抹掉用户在个人账单里的支出记录。
    ///
    /// 全部走"软删"语义，与既有 delete 接口保持一致；同步层据 deleted_at 做 tombstone。
    func softDelete(id: String) {
        do {
            // 1) 收集 AA 账本内部流水（仅删这些，不动占位）
            var recordIdsToDelete: Set<String> = []
            let internalRecords = try SQLiteRecordRepository.shared
                .list(RecordQuery(ledgerId: id, limit: 5000))
            for r in internalRecords where r.deletedAt == nil {
                recordIdsToDelete.insert(r.id)
            }

            for rid in recordIdsToDelete {
                try? SQLiteRecordRepository.shared.delete(id: rid)
            }

            // 2) 成员
            let members = try SQLiteAAMemberRepository.shared.list(ledgerId: id)
            for m in members {
                try? SQLiteAAMemberRepository.shared.softDelete(id: m.id)
            }

            // 3) 账本本体
            try SQLiteLedgerRepository.shared.delete(id: id)

            // 兜底广播：确保订阅 .recordsDidChange 的 VM（账单列表 / 统计 / 详情）立即刷新
            RecordChangeNotifier.broadcast(recordIds: Array(recordIdsToDelete))
        } catch {
            self.loadError = "删除失败：\(error.localizedDescription)"
        }
        reload()
    }
}
