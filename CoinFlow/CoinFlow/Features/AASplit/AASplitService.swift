//  AASplitService.swift
//  CoinFlow · M11 — AA 分账业务核心服务
//
//  设计原则：
//  - 状态机：recording → settling → completed（支持 settling → recording 回退）
//  - 所有写操作通过 DatabaseManager.execute("BEGIN/COMMIT;") 显式事务包裹
//  - 金额一律 Decimal（B1）；时间一律 UTC（B2）；删除一律软删（B3）
//  - 单用户模型：当前用户 id 固定 "me"（与 Record.payerUserId 习惯一致）

import Foundation

/// 当前用户在 AA 分账内的恒定标识。本 App 单用户单设备，不引入登录系统。
enum AAOwner {
    /// "我"作为 record.payerUserId 写入流水时的恒定值（**不是**成员 id）。
    static let currentUserId = "me"

    /// "我"作为 AA 成员时的成员 id 前缀。
    /// 由于 aa_member.id 是全局主键（非 (ledger_id, id) 复合），不能跨账本复用同一个 id，
    /// 因此把"我"在每个账本下的成员 id 设计为 `me-<ledgerId>`，确保唯一。
    static let memberIdPrefix = "me-"

    /// 生成"我"在指定账本下的成员 id。
    static func memberId(in ledgerId: String) -> String {
        return memberIdPrefix + ledgerId
    }

    /// 判定一个成员 id 是否代表"我"。同时兼容历史数据里直接用 "me" 作为 id 的情况。
    static func isOwnerMemberId(_ id: String) -> Bool {
        return id == currentUserId || id.hasPrefix(memberIdPrefix)
    }

    /// 判定一个 AAMember 是否代表"我"。
    static func isOwnerMember(_ member: AAMember) -> Bool {
        return isOwnerMemberId(member.id)
    }
}

enum AASplitError: Error, LocalizedError {
    case ledgerNotFound
    case invalidStatus(expected: AAStatus, actual: AAStatus?)
    case nameRequired
    case noRecordsToSettle
    case noMembersForSettlement
    case customAmountMismatch(recordId: String, diff: Decimal)
    case writebackFailed(String)

    var errorDescription: String? {
        switch self {
        case .ledgerNotFound: return "找不到 AA 账本"
        case .invalidStatus(let expected, let actual):
            return "AA 账本状态不符（期望 \(expected.rawValue)，当前 \(actual?.rawValue ?? "nil")）"
        case .nameRequired: return "请输入分账名称"
        case .noRecordsToSettle: return "请先添加至少一笔流水再结算"
        case .noMembersForSettlement: return "请至少添加 1 位分账成员"
        case .customAmountMismatch(_, let diff):
            return "自定义金额合计不平，差额 \(diff)"
        case .writebackFailed(let msg): return "结算未完成：\(msg)"
        }
    }
}

@MainActor
final class AASplitService {

    static let shared = AASplitService()
    private init() {}

    private var ledgerRepo: LedgerRepository { SQLiteLedgerRepository.shared }
    private var memberRepo: AAMemberRepository { SQLiteAAMemberRepository.shared }
    private var shareRepo: AAShareRepository { SQLiteAAShareRepository.shared }
    private var recordRepo: RecordRepository { SQLiteRecordRepository.shared }
    private var db: DatabaseManager { DatabaseManager.shared }

    // MARK: - 1. 创建 AA 账本（需求 1）

    @discardableResult
    func createSplit(name: String, emoji: String? = nil, note: String? = nil) throws -> Ledger {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AASplitError.nameRequired }
        let now = Date()
        // emoji / note 暂存到 name 后缀的 v1 简化方案；未来 v2 增列再迁移。
        // 这里直接以名字落库，emoji 拼到 name 前缀（"💰 7月泰国"）。
        let displayName: String = {
            if let e = emoji, !e.isEmpty { return "\(e) \(trimmed)" }
            return trimmed
        }()
        let ledger = Ledger(
            id: UUID().uuidString,
            name: displayName,
            type: .aa,
            firestorePath: nil,
            createdAt: now,
            timezone: TimeZone.current.identifier,
            archivedAt: nil,
            deletedAt: nil,
            aaStatus: .recording,
            settlingStartedAt: nil,
            completedAt: nil
        )
        try ledgerRepo.insert(ledger)
        // 备注暂存到 user_settings 维度（v1 简化）
        if let n = note, !n.isEmpty {
            SQLiteUserSettingsRepository.shared.set(key: "aa.note.\(ledger.id)", value: n)
        }
        SyncTrigger.fire(reason: "aa.createSplit")
        return ledger
    }

    // MARK: - 2. 状态：recording → settling（M12 重构）

    /// 进入结算中阶段，同时在个人账本上生成/更新一条净额占位（sourceKind=.aaSettlement,
    /// settlementStatus=.settling）。该占位在个人账单里代表用户本次 AA 中的净损益。
    func startSettlement(ledgerId: String) throws {
        guard let ledger = try ledgerRepo.find(id: ledgerId) else {
            throw AASplitError.ledgerNotFound
        }
        guard ledger.aaStatus == .recording else {
            throw AASplitError.invalidStatus(expected: .recording, actual: ledger.aaStatus)
        }
        // 至少存在一笔流水（记录中阶段已加流水）
        let records = try recordRepo.list(RecordQuery(ledgerId: ledgerId, limit: 1))
        guard !records.isEmpty else { throw AASplitError.noRecordsToSettle }

        try execTransaction {
            try ledgerRepo.updateAAStatus(
                id: ledgerId, status: .settling,
                settlingStartedAt: Date(),
                completedAt: nil
            )
            // 进入结算中：生成/更新占位。金额随后续流水/分摊/成员变化由 Projector 实时维护。
            try self.recomputePlaceholder(ledgerId: ledgerId, status: .settling)
        }
        SyncTrigger.fire(reason: "aa.startSettlement")
    }

    // MARK: - 3. 状态：settling → recording 回退（M12 重构）

    /// 回退到记录中：切换 ledger 状态并软删个人账本上的占位。
    /// share / member / paidAt 保留不动，重新进结算中时会看到上次配置。
    func revertToRecording(ledgerId: String) throws {
        guard let ledger = try ledgerRepo.find(id: ledgerId) else {
            throw AASplitError.ledgerNotFound
        }
        guard ledger.aaStatus == .settling else {
            throw AASplitError.invalidStatus(expected: .settling, actual: ledger.aaStatus)
        }
        try execTransaction {
            try ledgerRepo.updateAAStatus(
                id: ledgerId, status: .recording,
                settlingStartedAt: nil,
                completedAt: nil
            )
            // 回退后个人账单不再展示这次分账的净额占位
            try self.softDeletePlaceholder(ledgerId: ledgerId)
        }
        SyncTrigger.fire(reason: "aa.revertToRecording")
    }

    // MARK: - 4. 重算分摊（均分模式，需求 7.1-7.3）

    /// 按"金额 / 参与者数"为账本下所有支出 record 重新生成 share 行。
    /// - 默认每位 member 都被视为参与者（AA 习惯：默认全员均分）。
    /// - 参与者数 = 0（账本内无成员）→ 不写任何 share，留给当前用户独自承担。
    /// - 已经 isCustom = true 的 record 跳过（保留用户高级模式输入）。
    func recomputeShares(ledgerId: String) throws {
        let members = try memberRepo.list(ledgerId: ledgerId)
        let memberCount = members.count
        let records = try recordRepo.list(
            RecordQuery(ledgerId: ledgerId, kind: .expense, limit: 5000)
        )
        try execTransaction {
            for r in records where r.deletedAt == nil {
                // 跳过 isCustom 的 record（其 share 已由用户手动设定）
                let existing = try shareRepo.list(recordId: r.id)
                let hasCustom = existing.contains(where: { $0.isCustom })
                if hasCustom { continue }
                // 清掉旧的均分 share
                try shareRepo.deleteByRecord(recordId: r.id)
                guard memberCount > 0 else { continue }
                let perHead = decimalDiv(r.amount, by: memberCount)
                for m in members {
                    try shareRepo.upsert(
                        recordId: r.id,
                        memberId: m.id,
                        amount: perHead,
                        isCustom: false
                    )
                }
            }
        }
    }

    // MARK: - 5. 自定义金额（高级模式，需求 7.4-7.5）

    func setCustomShare(recordId: String, memberId: String, amount: Decimal) throws {
        try execTransaction {
            try shareRepo.upsert(
                recordId: recordId,
                memberId: memberId,
                amount: amount,
                isCustom: true
            )
        }
    }

    /// 校验自定义模式下某 record 的 share 总和与 record.amount 的差额。
    /// - Returns: 差额（>0 表示用户分摊不足；<0 表示超额）。0 表示对账平。
    func validateCustomBalance(recordId: String) throws -> Decimal {
        guard let r = try recordRepo.find(id: recordId) else { return 0 }
        let shares = try shareRepo.list(recordId: recordId)
        let sum = shares.reduce(Decimal(0)) { $0 + $1.amount }
        return r.amount - sum
    }

    // MARK: - 6. 支付确认（需求 8.2-8.3）

    func markPaid(memberId: String) throws {
        guard let m = try memberRepo.find(id: memberId) else { return }
        var rev = m
        rev.status = .paid
        rev.paidAt = Date()
        try memberRepo.update(rev)
    }

    func unmarkPaid(memberId: String) throws {
        guard let m = try memberRepo.find(id: memberId) else { return }
        var rev = m
        rev.status = .pending
        rev.paidAt = nil
        try memberRepo.update(rev)
    }

    // MARK: - 6.5 删除整个 AA 账本（M12：级联软删 + 占位清理）

    /// 删除一个 AA 账本：在事务内级联软删本账本下的 record / member / share 以及 ledger 自身。
    ///
    /// 注意：**保留**个人账本上的占位（sourceKind=.aaSettlement，aaSettlementId=本账本）。
    /// 占位代表用户已经发生过的一笔历史消费（已回写到个人账单），删除 AA 账本本身
    /// 不应连带抹掉用户的个人账单流水。删除后占位仍以 aaSettlementId 指向已被软删
    /// 的 ledger，UI 端在 RecordDetailSheet 已有"该分账已删除"兜底文案。
    ///
    /// - 仅写 deleted_at；同步队列会把这些"带 deletedAt 的行"推到云端达成软删。
    func deleteSplit(ledgerId: String) throws {
        guard let ledger = try ledgerRepo.find(id: ledgerId) else {
            throw AASplitError.ledgerNotFound
        }
        guard ledger.type == .aa else {
            // 防御：仅允许删 AA 账本，普通账本走别的入口
            throw AASplitError.ledgerNotFound
        }

        // 收集要删除的 AA 内部流水（含未删行）
        let aaRecords = try recordRepo.list(RecordQuery(ledgerId: ledgerId, limit: 5000))
        let members = try memberRepo.list(ledgerId: ledgerId)

        try execTransaction {
            // 1) 删 share
            for r in aaRecords {
                try shareRepo.deleteByRecord(recordId: r.id)
            }
            // 2) 软删 member
            for m in members {
                try memberRepo.softDelete(id: m.id)
            }
            // 3) 软删 AA 内部 record
            for r in aaRecords where r.deletedAt == nil {
                try recordRepo.delete(id: r.id)
            }
            // 4) 软删 ledger 自身（占位流水保留，不动）
            try ledgerRepo.delete(id: ledgerId)
        }

        // 通知列表 / 账单 / 统计页刷新（仅含 AA 内部 record id；占位本次未变）
        let allIds = aaRecords.map { $0.id }
        RecordChangeNotifier.broadcast(recordIds: allIds)
        SyncTrigger.fire(reason: "aa.deleteSplit")
    }

    // MARK: - 7. 完成结算（M12 重构）

    /// 完成结算：把 ledger 状态置 completed，并把对应的占位 settlementStatus 改为 .settled。
    /// 不再写"双向应收应付"——所有 AA 数据都封装在 AA 账本内，
    /// 个人账本只见到 1 条净额占位（"AA 分账·已结算"）。
    /// - Returns: 兼容签名：返回更新后的占位（如有），上层用作 toast/jump 的引用。
    @discardableResult
    func completeSettlement(ledgerId: String) throws -> [Record] {
        guard let ledger = try ledgerRepo.find(id: ledgerId) else {
            throw AASplitError.ledgerNotFound
        }
        guard ledger.aaStatus == .settling else {
            throw AASplitError.invalidStatus(expected: .settling, actual: ledger.aaStatus)
        }
        let members = try memberRepo.list(ledgerId: ledgerId)
        guard !members.isEmpty else { throw AASplitError.noMembersForSettlement }

        // 校验所有 record 的 custom share 平衡
        let aaRecords = try recordRepo.list(
            RecordQuery(ledgerId: ledgerId, kind: .expense, limit: 5000)
        )
        for r in aaRecords where r.deletedAt == nil {
            let shares = try shareRepo.list(recordId: r.id)
            if shares.contains(where: { $0.isCustom }) {
                let diff = try validateCustomBalance(recordId: r.id)
                if diff != 0 {
                    throw AASplitError.customAmountMismatch(recordId: r.id, diff: diff)
                }
            }
        }

        // 诊断：进入 completeSettlement 时的状态快照
        #if DEBUG
        let activeMembers = members.filter { $0.deletedAt == nil }
        let hasMe = activeMembers.contains(where: { AAOwner.isOwnerMember($0) })
        print("[AA-Complete] BEGIN ledgerId=\(ledgerId) name=\(ledger.name) members=\(activeMembers.count) hasMe=\(hasMe)")
        #endif

        let now = Date()
        do {
            try execTransaction {
                try ledgerRepo.updateAAStatus(
                    id: ledgerId, status: .completed,
                    settlingStartedAt: ledger.settlingStartedAt ?? now,
                    completedAt: now
                )
                // 把占位状态改为 .settled（金额按当前最终态算一遍）
                try self.recomputePlaceholder(ledgerId: ledgerId, status: .settled)
            }
        } catch {
            throw AASplitError.writebackFailed(error.localizedDescription)
        }

        // 兜底校验：事务结束后重新查占位状态。
        // 若 mineShareSum>0 但占位丢失（理论上不应发生），强制补写一条，
        // 避免 UI 端"看不到分账流水"的回归。
        let postPlaceholders = try recordRepo.findByAASettlementId(ledgerId)
            .filter { $0.deletedAt == nil && $0.sourceKind == .aaSettlement }
        let postRecords = try recordRepo.list(
            RecordQuery(ledgerId: ledgerId, kind: .expense, limit: 5000)
        ).filter { $0.deletedAt == nil }
        var postMineShareSum: Decimal = 0
        for r in postRecords {
            let shares = try shareRepo.list(recordId: r.id)
            postMineShareSum += shares
                .filter { AAOwner.isOwnerMemberId($0.memberId) && $0.deletedAt == nil }
                .reduce(Decimal(0)) { $0 + $1.amount }
        }
        #if DEBUG
        print("[AA-Complete] END ledgerId=\(ledgerId) mineShareSum=\(postMineShareSum) placeholders.count=\(postPlaceholders.count)")
        for p in postPlaceholders {
            print("[AA-Complete]   placeholder id=\(p.id) ledger=\(p.ledgerId) amount=\(p.amount) status=\(p.settlementStatus?.rawValue ?? "nil") note=\(p.note ?? "")")
        }
        #endif
        if postPlaceholders.isEmpty && postMineShareSum > 0 {
            // 兜底补写：极端情况下事务内 recomputePlaceholder 没生效，强制再写一条。
            #if DEBUG
            print("[AA-Complete] ⚠️ FALLBACK insert placeholder mineShareSum=\(postMineShareSum)")
            #endif
            let placeholder = Record(
                id: UUID().uuidString,
                ledgerId: DefaultSeeder.defaultLedgerId,
                categoryId: "preset-expense-other",
                amount: postMineShareSum,
                currency: "CNY",
                occurredAt: now,
                timezone: TimeZone.current.identifier,
                note: "AA 分账·已结算 · \(ledger.name)",
                payerUserId: nil,
                participants: nil,
                source: .manual,
                ocrConfidence: nil,
                voiceSessionId: nil,
                missingFields: nil,
                merchantChannel: nil,
                aaSettlementId: ledgerId,
                sourceKind: .aaSettlement,
                settlementStatus: .settled,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil
            )
            try recordRepo.insert(placeholder)
        }

        SyncTrigger.fire(reason: "aa.completeSettlement")
        // 显式再广播一次，确保 RecordsListViewModel 收到刷新通知。
        RecordChangeNotifier.broadcast(recordIds: [])
        // 返回当前 ledger 对应的占位
        let finalPlaceholders = try recordRepo.findByAASettlementId(ledgerId)
            .filter { $0.deletedAt == nil && $0.sourceKind == .aaSettlement }
        return finalPlaceholders
    }

    // MARK: - 工具

    /// Decimal 除法（B1：不走 Double）。SQLite 内部全程用 String 表示 Decimal。
    private func decimalDiv(_ x: Decimal, by n: Int) -> Decimal {
        guard n > 0 else { return 0 }
        var dividend = x
        var divisor = Decimal(n)
        var result = Decimal()
        NSDecimalDivide(&result, &dividend, &divisor, .bankers)
        // 保留 4 位小数避免循环小数累积误差
        var rounded = Decimal()
        var src = result
        NSDecimalRound(&rounded, &src, 4, .bankers)
        return rounded
    }

    private func execTransaction(_ block: () throws -> Void) throws {
        try db.execute("BEGIN TRANSACTION;")
        do {
            try block()
            try db.execute("COMMIT;")
        } catch {
            try? db.execute("ROLLBACK;")
            throw error
        }
    }

    // MARK: - M12 占位（AASettlementProjector）

    /// 重算并写入"我"在某 AA 账本下的应分摊占位。
    ///
    /// 占位语义（"我"视角，单一规则）：
    /// - 当且仅当"我"作为成员参与了这次 AA（创建时勾选"包含我自己"，即 members 里有 id="me"），
    ///   在我的个人账单上记一条**支出**，金额 = 我应分摊的份额总和。
    /// - 与"谁垫付/我是不是付款人"完全无关：垫付/应收应付只在 AA 内部成员页里体现。
    ///
    /// 公式：
    ///   mineShareSum = Σ(share.amount where share.memberId == AAOwner.currentUserId)
    /// - mineShareSum > 0：写/更新一条支出占位
    /// - mineShareSum == 0：我没参与这次 AA（或参与但应分摊为 0）→ 不写占位；
    ///   若历史已有占位则软删。
    ///
    /// 注：此方法**必须在事务内调用**（startSettlement / completeSettlement 已包裹）；
    /// AASettlementProjector 通知触发时会自己包裹一层事务。
    /// - Parameters:
    ///   - ledgerId: AA 账本 id
    ///   - status: 当前结算阶段（决定占位 note 显示"结算中"或"已结算"）
    fileprivate func recomputePlaceholder(ledgerId: String,
                                          status: AASettlementStatus) throws {
        guard let ledger = try ledgerRepo.find(id: ledgerId) else { return }

        let records = try recordRepo.list(
            RecordQuery(ledgerId: ledgerId, kind: .expense, limit: 5000)
        ).filter { $0.deletedAt == nil }

        // 聚合"我"作为成员在所有流水里的应分摊金额（"我"未加入成员则恒为 0）
        var mineShareSum: Decimal = 0
        for r in records {
            let shares = try shareRepo.list(recordId: r.id)
            let mineShare = shares
                .filter { AAOwner.isOwnerMemberId($0.memberId) }
                .reduce(Decimal(0)) { $0 + $1.amount }
            mineShareSum += mineShare
        }

        // 找现有占位
        let existing = try recordRepo.findByAASettlementId(ledgerId)
            .filter { $0.deletedAt == nil && $0.sourceKind == .aaSettlement }
        let now = Date()

        if mineShareSum <= 0 {
            // 我没参与（或应分摊为 0）：清掉占位，个人账单不出现该 AA 的任何痕迹
            for p in existing {
                try recordRepo.delete(id: p.id)
            }
            return
        }

        // 占位永远是支出（与垫付/付款人无关）
        let absAmount: Decimal = mineShareSum
        let categoryId = "preset-expense-other"
        let statusLabel = (status == .settling) ? "结算中" : "已结算"
        let note = "AA 分账·\(statusLabel) · \(ledger.name)"

        if let p = existing.first {
            // 已存在：更新金额/分类/note/status
            var updated = p
            updated.amount = absAmount
            updated.categoryId = categoryId
            updated.note = note
            updated.settlementStatus = status
            updated.updatedAt = now
            // 重置同步元数据，保证软删/数据变化同步推到云端（与 RecordRepository.delete 同思路）
            updated.syncStatus = .pending
            updated.syncAttempts = 0
            updated.lastSyncError = nil
            try recordRepo.update(updated)
            // 若旧占位已被同步过，update 内部 broadcast 即可触发 UI 刷新
        } else {
            let placeholder = Record(
                id: UUID().uuidString,
                ledgerId: DefaultSeeder.defaultLedgerId,
                categoryId: categoryId,
                amount: absAmount,
                currency: "CNY",
                occurredAt: now,
                timezone: TimeZone.current.identifier,
                note: note,
                payerUserId: nil,
                participants: nil,
                source: .manual,
                ocrConfidence: nil,
                voiceSessionId: nil,
                missingFields: nil,
                merchantChannel: nil,
                aaSettlementId: ledgerId,
                sourceKind: .aaSettlement,
                settlementStatus: status,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil
            )
            try recordRepo.insert(placeholder)
        }
    }

    /// 软删某 AA 账本对应的占位（revertToRecording / deleteSplit 路径用）。
    fileprivate func softDeletePlaceholder(ledgerId: String) throws {
        let existing = try recordRepo.findByAASettlementId(ledgerId)
            .filter { $0.deletedAt == nil && $0.sourceKind == .aaSettlement }
        for p in existing {
            try recordRepo.delete(id: p.id)
        }
    }

    /// AASettlementProjector：监听 AA 账本流水变化，对处于 settling 状态的账本实时重算占位。
    /// 由 AAShareEditSection / NewRecordModal 等 UI 写完流水后，通过 .recordsDidChange 间接触发。
    /// 也可由 ViewModel 在用户改完 share/member 后显式调用。
    func recomputePlaceholderIfSettling(ledgerId: String) {
        do {
            guard let ledger = try ledgerRepo.find(id: ledgerId),
                  ledger.aaStatus == .settling else { return }
            try execTransaction {
                try self.recomputePlaceholder(ledgerId: ledgerId, status: .settling)
            }
        } catch {
            // 静默失败：占位重算不应阻塞主流程
        }
    }
}

// MARK: - AAShareRepository 便捷扩展（清空整个账本的 share）

extension AAShareRepository {
    /// 删除账本下所有 share（按 record join 实现）。
    /// 由 AASplitService.revertToRecording 使用。
    func deleteByLedger(ledgerId: String) throws {
        let shares = try listByLedger(ledgerId: ledgerId)
        for s in shares {
            try deleteByRecord(recordId: s.recordId)
        }
    }
}