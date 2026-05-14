//  AASplitDetailViewModel.swift
//  CoinFlow · M11 — AA 分账详情页 VM（任务 6/7/8 持续填充）

import Foundation
import Combine
import SwiftUI

@MainActor
final class AASplitDetailViewModel: ObservableObject {

    @Published private(set) var ledger: Ledger?
    @Published private(set) var records: [Record] = []
    @Published private(set) var members: [AAMember] = []
    @Published private(set) var shares: [AAShare] = []
    @Published private(set) var loadError: String?

    let ledgerId: String
    private var cancellables: Set<AnyCancellable> = []

    init(ledgerId: String) {
        self.ledgerId = ledgerId
        // 监听 record 变化以刷新累计金额、流水列表
        NotificationCenter.default
            .publisher(for: .recordsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    var totalAmount: Decimal {
        records.filter { $0.deletedAt == nil }
               .reduce(Decimal(0)) { $0 + $1.amount }
    }

    var visibleRecords: [Record] {
        records.filter { $0.deletedAt == nil }
    }

    var status: AAStatus { ledger?.aaStatus ?? .recording }

    var canStartSettlement: Bool {
        status == .recording && !visibleRecords.isEmpty
    }

    func reload() {
        do {
            ledger = try SQLiteLedgerRepository.shared.find(id: ledgerId)
            records = try SQLiteRecordRepository.shared.list(
                RecordQuery(ledgerId: ledgerId, limit: 5000)
            )
            members = try SQLiteAAMemberRepository.shared.list(ledgerId: ledgerId)
            shares = try SQLiteAAShareRepository.shared.listByLedger(ledgerId: ledgerId)
            loadError = nil
            // M12 AASettlementProjector：当账本处于"结算中"时，每次数据变化后实时重算占位金额。
            // recordsDidChange 触发 reload；reload 结束时保证占位与 share/record/member 同步。
            // service 内部对非 settling 状态会自动 no-op。
            AASplitService.shared.recomputePlaceholderIfSettling(ledgerId: ledgerId)
        } catch {
            loadError = "加载失败：\(error.localizedDescription)"
        }
    }

    /// 计算某成员在本账本下的应付总额（用 share 累加；用于成员卡片小计与支付确认进度）
    func owe(of memberId: String) -> Decimal {
        shares
            .filter { $0.memberId == memberId && $0.deletedAt == nil }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// 当前用户在该账本下的应付总额（= Σ record.amount - Σ 所有成员 share）。
    /// 仅在结算阶段有意义（用于"对称回写"差额计算）。
    var ownerOwe: Decimal {
        let memberSum = shares
            .filter { $0.deletedAt == nil }
            .reduce(Decimal(0)) { $0 + $1.amount }
        return totalAmount - memberSum
    }

    // MARK: - 业务动作（直接转发到 AASplitService）

    func startSettlement() throws {
        try AASplitService.shared.startSettlement(ledgerId: ledgerId)
        reload()
    }

    func revertToRecording() throws {
        try AASplitService.shared.revertToRecording(ledgerId: ledgerId)
        reload()
    }

    func recomputeShares() throws {
        try AASplitService.shared.recomputeShares(ledgerId: ledgerId)
        reload()
    }

    func setCustomShare(recordId: String, memberId: String, amount: Decimal) throws {
        try AASplitService.shared.setCustomShare(
            recordId: recordId, memberId: memberId, amount: amount
        )
        reload()
    }

    func validateCustomBalance(recordId: String) throws -> Decimal {
        try AASplitService.shared.validateCustomBalance(recordId: recordId)
    }

    func markPaid(memberId: String) throws {
        try AASplitService.shared.markPaid(memberId: memberId)
        reload()
    }

    func unmarkPaid(memberId: String) throws {
        try AASplitService.shared.unmarkPaid(memberId: memberId)
        reload()
    }

    @discardableResult
    func completeSettlement() throws -> [Record] {
        let generated = try AASplitService.shared.completeSettlement(ledgerId: ledgerId)
        reload()
        return generated
    }

    /// 删除整个 AA 账本（级联软删 ledger / record / member / share）。
    /// 已回写到个人账本的流水保留，不在此处理。
    func deleteSplit() throws {
        try AASplitService.shared.deleteSplit(ledgerId: ledgerId)
    }

    // MARK: - 成员管理

    func addMember(name: String, emoji: String? = nil) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 20 else { return }
        // 同账本去重（active 行）
        if members.contains(where: { $0.deletedAt == nil && $0.name == trimmed }) {
            return
        }
        let now = Date()
        let m = AAMember(
            id: UUID().uuidString,
            ledgerId: ledgerId,
            name: trimmed,
            avatarEmoji: emoji,
            status: .pending,
            paidAt: nil,
            sortOrder: members.count,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        try SQLiteAAMemberRepository.shared.insert(m)
        // 持久化到常用昵称列表（与 StatsAABalanceView 占位页一致）
        appendNicknameSuggestion(trimmed)
        reload()
    }

    /// 把当前用户作为成员加入到本账本。
    ///
    /// 重要：成员 id 形如 `me-<ledgerId>`（见 `AAOwner.memberId(in:)`），
    /// 不再用全局常量 "me"。原因：`aa_member.id` 是全局主键，跨账本沿用同一 id 会触发主键冲突。
    /// 已存在则跳过；新增后立即重算分摊（与普通 addMember 路径行为一致），
    /// 这样 settling 阶段会即时把"我应分摊的份额"反映到个人账单的占位流水上。
    func addCurrentUserAsMember() throws {
        let myId = AAOwner.memberId(in: ledgerId)
        // 同账本内已存在则跳过
        if members.contains(where: { $0.id == myId && $0.deletedAt == nil }) { return }
        // 兼容：若同账本下还存在历史"裸 me"成员，也跳过
        if members.contains(where: { $0.id == AAOwner.currentUserId && $0.deletedAt == nil }) { return }
        let now = Date()
        let m = AAMember(
            id: myId,
            ledgerId: ledgerId,
            name: "我",
            avatarEmoji: "🙋",
            status: .pending,
            paidAt: nil,
            sortOrder: members.count,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        try SQLiteAAMemberRepository.shared.insert(m)
        // 与 AAMemberManageSection 的 addMemberDirectly 行为一致：
        // 加完成员立刻把所有非自定义流水按新成员人数重算 share。
        // 否则个人账单上的"AA 应分摊占位"会一直按 mineShareSum=0 不写出来。
        try AASplitService.shared.recomputeShares(ledgerId: ledgerId)
        reload()
    }

    func renameMember(id: String, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 20 else { return }
        guard var m = members.first(where: { $0.id == id }) else { return }
        m.name = trimmed
        m.updatedAt = Date()
        try SQLiteAAMemberRepository.shared.update(m)
        reload()
    }

    /// 删除成员；若该成员被任何 share 引用，先清掉 share 再软删 member。
    /// 返回该成员被引用的 share 数（供 UI 二次确认提示）。
    @discardableResult
    func deleteMember(id: String) throws -> Int {
        let usedShares = shares.filter { $0.memberId == id && $0.deletedAt == nil }
        try SQLiteAAShareRepository.shared.deleteByMember(memberId: id)
        try SQLiteAAMemberRepository.shared.softDelete(id: id)
        reload()
        return usedShares.count
    }

    private func appendNicknameSuggestion(_ name: String) {
        let key = "aa.preview.nicknames"
        let existing = UserDefaults.standard.string(forKey: key) ?? ""
        var arr = existing.split(separator: ",").map(String.init).map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        if !arr.contains(name) {
            arr.append(name)
            UserDefaults.standard.set(arr.joined(separator: ","), forKey: key)
        }
    }
}
