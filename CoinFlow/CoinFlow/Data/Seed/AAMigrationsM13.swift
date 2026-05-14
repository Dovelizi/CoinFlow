//  AAMigrationsM13.swift
//  CoinFlow · M13 — AA 占位流水"孤儿"清理一次性迁移
//
//  背景：M12 把 AA 账本删除策略改为"联动软删占位流水"，但 AASplitListViewModel.softDelete
//  在更早版本中绕过了 AASplitService.deleteSplit，导致历史上通过列表页左划/长按删除
//  AA 账本时，对应的占位流水（sourceKind=.aaSettlement）被遗留在 default-ledger，
//  形成"指向已删账本的孤儿占位"。用户截图里的 A15 ¥67.5 就是这种孤儿。
//
//  本迁移：扫描所有未删除的 .aaSettlement 占位 → 反查其 aaSettlementId 对应账本
//  → 若账本不存在或已软删，则把这条占位也软删。仅运行一次（user_settings 写 flag 防重）。
//
//  幂等：完成后写 flag；即使 flag 误失，重跑也仅会把"剩余孤儿"再清一次，无副作用。

import Foundation

enum AAMigrationsM13 {

    private static let didRunKey = "migration.m13.aaOrphanPlaceholderCleanup.didRun"

    /// 启动时调用一次：清理孤儿占位流水。
    /// - Returns: 本次清理的占位条数（0 表示无孤儿或已运行过）。
    @discardableResult
    static func cleanupOrphanPlaceholdersIfNeeded() -> Int {
        let settings = SQLiteUserSettingsRepository.shared
        if settings.get(key: didRunKey) == "1" {
            return 0
        }

        var removed = 0
        do {
            // 扫所有未删除的 .aaSettlement 占位
            let candidates = try SQLiteRecordRepository.shared.list(.init(
                ledgerId: nil,
                limit: 10000
            )).filter { r in
                guard r.sourceKind == .aaSettlement,
                      let id = r.aaSettlementId, !id.isEmpty else { return false }
                return true
            }
            for r in candidates {
                guard let aaId = r.aaSettlementId else { continue }
                // LedgerRepository.find 已对 deleted_at IS NULL 过滤：
                // 返回 nil ⇒ 账本不存在 或 已被软删 ⇒ 占位是孤儿
                let ledger = try? SQLiteLedgerRepository.shared.find(id: aaId)
                if ledger == nil {
                    try? SQLiteRecordRepository.shared.delete(id: r.id)
                    removed += 1
                }
            }
        } catch {
            // 静默失败：迁移失败不应阻塞启动
            return 0
        }

        settings.set(key: didRunKey, value: "1")
        return removed
    }
}
