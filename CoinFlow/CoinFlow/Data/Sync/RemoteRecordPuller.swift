//  RemoteRecordPuller.swift
//  CoinFlow · M9 · 从飞书多维表格手动拉取（Q5 = L 手动按钮）
//
//  设计策略（B 端业务规则，与 M8 pullFromCloud 对齐）：
//  - 一次性 searchAllRecords，不订阅
//  - 飞书 row 在本地**不存在** → INSERT（`sync_status = synced`，避免再被推回云）
//  - 飞书 row 在本地**已存在**（含软删） → **跳过，不覆盖任何字段**（保护未推送的本地编辑）
//  - 飞书 row 解码失败的计入 `decodeFailures`，仅展示，不写本地

import Foundation

@MainActor
enum RemoteRecordPuller {

    struct PullResult: Equatable {
        var inserted: Int          // 本地原本不存在、本次 INSERT
        var skippedExisting: Int   // 本地已有同 id（按规则不覆盖）
        var decodeFailures: Int    // 飞书行解码失败 / 字段缺失，被跳过
    }

    /// 手动从飞书拉取并写入本地。
    /// - Returns: 拉取结果摘要；调用方负责展示
    static func pullAll(defaultLedgerId: String) async throws -> PullResult {
        let rows = try await FeishuBitableClient.shared.searchAllRecords()
        let repo = SQLiteRecordRepository.shared
        var inserted = 0
        var skipped = 0
        var decFail = 0

        for row in rows {
            do {
                var record = try RecordBitableMapper.decode(
                    fields: row.fields, remoteRecordId: row.recordId
                )
                record.ledgerId = defaultLedgerId
                if try repo.find(id: record.id) != nil {
                    skipped += 1
                    continue
                }
                record.syncStatus = .synced
                record.syncAttempts = 0
                record.lastSyncError = nil
                try repo.insert(record)
                inserted += 1
                SyncLogger.info(phase: "pull", recordId: record.id,
                                "remote-only → local INSERT")
            } catch {
                decFail += 1
                SyncLogger.failure(phase: "pull.decode",
                                   recordId: row.recordId,
                                   error: error)
            }
        }
        SyncLogger.info(phase: "pull",
                        "done inserted=\(inserted) skipped=\(skipped) decodeFail=\(decFail) total=\(rows.count)")
        return PullResult(inserted: inserted,
                          skippedExisting: skipped,
                          decodeFailures: decFail)
    }
}
