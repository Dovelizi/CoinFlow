//  AAMigrationsM12.swift
//  CoinFlow · M12 — AA 重构一次性数据迁移
//
//  方案 B（M11）期间会把 AA 已结算账本的应收/应付分别回写为多条 default-ledger
//  上的 income/expense 流水（aaSettlementId 非空，sourceKind 为旧默认 .normal）。
//  方案 C（M12）改为"净额单条占位"，旧的多条回写会与新占位重复。
//
//  本迁移：扫描所有 sourceKind == .normal 且 aaSettlementId 非空的 default-ledger
//  上的记录，把它们物理删除。仅运行一次（user_settings 写 flag 防重）。

import Foundation

enum AAMigrationsM12 {

    private static let didRunKey = "migration.m12.aaCleanup.didRun"

    /// 启动时调用一次：清理 M11 方案 B 的双向回写残留。
    /// 幂等：完成后写 flag，下次启动直接跳过。
    @discardableResult
    static func cleanupLegacyWritebacksIfNeeded() -> Int {
        let settings = SQLiteUserSettingsRepository.shared
        if settings.get(key: didRunKey) == "1" {
            return 0
        }

        var removed = 0
        do {
            // 扫所有"挂了 aaSettlementId 但 sourceKind 不是 aaSettlement 的"流水
            let candidates = try SQLiteRecordRepository.shared.list(.init(
                ledgerId: nil,
                includesDeleted: true,
                limit: 10000
            )).filter { r in
                guard let id = r.aaSettlementId, !id.isEmpty else { return false }
                return r.sourceKind != .aaSettlement
            }
            for r in candidates {
                try? SQLiteRecordRepository.shared.hardDelete(id: r.id)
                removed += 1
            }
        } catch {
            // 静默失败：迁移失败不应阻塞启动
            return 0
        }

        settings.set(key: didRunKey, value: "1")
        return removed
    }
}
