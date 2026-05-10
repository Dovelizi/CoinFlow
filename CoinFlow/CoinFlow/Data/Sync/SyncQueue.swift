//  SyncQueue.swift
//  CoinFlow · M9 · 飞书多维表格同步队列
//
//  把本地 SQLite record 表的 pending/failed 行同步到飞书多维表格。
//  - 状态机：pending → syncing → synced / failed
//    failed 且 isTransient → 等下次 tick 重试（attempts 累积）
//    failed 且 !isTransient → 立即"死亡"（attempts 强制 = maxAttempts）
//    用户在 UI 点「全部重试」走 `resetDeadRetries()` 复活
//    attempts ≥ 5 → 视为"已放弃"，pendingSync 仍 SELECT 出来但 SyncQueue 内存层跳过
//  - 退避：指数 1/2/4/8/16/32s 上限 60s，±20% 抖动
//  - 启动 reconcile：tick 入口处先把上次 crash 滞留在 `syncing` 的记录复活为 pending
//
//  与 Firebase 版（M8）的差异（M9 切换）：
//  - 鉴权：FeishuTokenManager 维护 tenant_access_token，过期前 5min 刷新
//  - 字段映射：RecordBitableMapper（明文，不加密）
//  - 写云：FeishuBitableClient.createRecord / updateRecord
//    * record.remoteId == nil → createRecord，飞书返回 record_id 写回 remoteId
//    * record.remoteId != nil → updateRecord(remoteId)，含软删（"已删除"打勾）
//
//  调度：由 ViewModel 在 insert/update/delete 后通过 SyncTrigger.fire() 触发；
//        同步状态页"立即同步/全部重试"按钮也会触发。

import Foundation

actor SyncQueue {

    // MARK: - Config

    /// 单批最大条数。
    static let batchSize: Int = 100

    /// 最大重试次数。
    static let maxAttempts: Int = 5

    /// 退避基数上限（秒）。
    static let backoffCap: TimeInterval = 60

    // MARK: - Singleton

    static let shared = SyncQueue()

    // MARK: - State

    private var isRunning = false

    // MARK: - Public API

    /// 触发一次队列调度。线程安全（actor）。
    /// 默认 ledgerId：M3 仅支持单一「默认账本」；多账本在 M4/M5 扩展。
    func tick(defaultLedgerId: String) async {
        guard !isRunning else {
            SyncLogger.info(phase: "tick", "skip: already running")
            return
        }
        isRunning = true
        defer { isRunning = false }

        SyncLogger.info(phase: "tick", "begin")

        // 1. 配置检查 + token 预取
        guard FeishuConfig.isConfigured else {
            SyncLogger.warn(phase: "auth",
                            "skip tick: 飞书未配置（缺 App ID / Secret）")
            return
        }
        do {
            _ = try await FeishuTokenManager.shared.getToken()
            SyncLogger.info(phase: "auth", "feishu token ok")
        } catch let e as FeishuAuthError where e.isTransient {
            SyncLogger.warn(phase: "auth",
                            "feishu token transient err, skip without consuming attempts: \(e.localizedDescription)")
            return
        } catch {
            SyncLogger.failure(phase: "auth", error: error,
                               extra: "feishu token failed; abort tick")
            return
        }

        // 2. 多维表格存在性确认（首次会自动创建）
        do {
            try await FeishuBitableClient.shared.ensureBitableExists()
            SyncLogger.info(phase: "feishu.bootstrap", "table ready")
        } catch let e as FeishuBitableError where e.isTransient {
            SyncLogger.warn(phase: "feishu.bootstrap",
                            "transient err, skip: \(e.localizedDescription)")
            return
        } catch {
            SyncLogger.failure(phase: "feishu.bootstrap", error: error,
                               extra: "abort tick")
            return
        }

        // 3. 启动 reconcile：把 syncing 滞留态复活为 pending
        let repo = SQLiteRecordRepository.shared
        do {
            let revived = try repo.reconcileSyncingOnLaunch()
            if revived > 0 {
                SyncLogger.info(phase: "reconcile", "revived \(revived) syncing→pending")
            }
        } catch {
            SyncLogger.failure(phase: "reconcile", error: error)
        }

        // 4. 拉 pending/failed
        let pending: [Record]
        do {
            pending = try repo.pendingSync(limit: Self.batchSize)
        } catch {
            SyncLogger.failure(phase: "fetch", error: error)
            return
        }
        guard !pending.isEmpty else {
            SyncLogger.info(phase: "tick", "empty queue, end")
            return
        }
        SyncLogger.info(phase: "fetch", "pending=\(pending.count)")

        // 5. 过滤死记录
        let candidates = pending.filter { $0.syncAttempts < Self.maxAttempts }
        let dead = pending.count - candidates.count
        if dead > 0 {
            SyncLogger.info(phase: "fetch",
                            "dead=\(dead) (attempts >= \(Self.maxAttempts), need user retry)")
        }
        guard !candidates.isEmpty else {
            SyncLogger.info(phase: "tick", "all candidates dead, end")
            return
        }

        // 6. markSyncing
        let ids = candidates.map { $0.id }
        do {
            try repo.markSyncing(ids: ids)
        } catch {
            SyncLogger.failure(phase: "markSyncing", error: error)
            return
        }

        // 7. 串行 dispatch
        var ok = 0
        var fail = 0
        for record in candidates {
            let success = await syncOne(record)
            if success { ok += 1 } else { fail += 1 }
        }
        SyncLogger.info(phase: "tick", "end ok=\(ok) fail=\(fail)")
    }

    // MARK: - Private

    /// 单条同步。
    /// - Returns: true = markSynced 成功；false = 进入 failed 分支
    private func syncOne(_ record: Record) async -> Bool {
        let phase: String
        if record.deletedAt != nil {
            phase = "softDelete"
        } else if let rid = record.remoteId, !rid.isEmpty {
            phase = "update"
        } else {
            phase = "create"
        }

        let repo = SQLiteRecordRepository.shared
        do {
            // 软删 + 从未推过云端 → 直接 markSynced 跳过（避免在飞书生成无主孤儿行）
            if record.deletedAt != nil && (record.remoteId?.isEmpty ?? true) {
                try repo.markSynced(id: record.id, remoteId: record.id)
                SyncLogger.info(phase: phase, recordId: record.id,
                                "skip: never synced before, mark local synced")
                return true
            }
            // M9-Fix4：写飞书前先确保附件已上传（若有本地截图 + 还没拿到 file_token）
            let recordWithAttachment = try await ensureAttachmentUploaded(record: record, phase: phase)
            let newRemoteId = try await writeWithFallbacks(record: recordWithAttachment, phase: phase)
            try repo.markSynced(id: recordWithAttachment.id, remoteId: newRemoteId)
            SyncLogger.info(phase: phase, recordId: record.id, "ok remoteId=\(newRemoteId)")
            return true
        } catch let e as FeishuBitableError {
            let attempts: Int
            if e.isTransient {
                attempts = record.syncAttempts + 1
            } else {
                attempts = Self.maxAttempts
            }
            SyncLogger.failure(phase: phase, recordId: record.id,
                               attempts: attempts, error: e,
                               extra: e.isTransient ? "transient, will retry"
                                                    : "permanent, marked dead")
            markFailedSafe(id: record.id, msg: e.localizedDescription, attempts: attempts)
            return false
        } catch let e as RecordBitableMapperError {
            let attempts = Self.maxAttempts
            SyncLogger.failure(phase: phase, recordId: record.id,
                               attempts: attempts, error: e,
                               extra: "mapper error, marked dead")
            markFailedSafe(id: record.id, msg: e.localizedDescription, attempts: attempts)
            return false
        } catch {
            // 未知错误：保守按 transient 处理
            let attempts = record.syncAttempts + 1
            SyncLogger.failure(phase: phase, recordId: record.id,
                               attempts: attempts, error: error,
                               extra: "unclassified, treat as transient")
            markFailedSafe(id: record.id, msg: error.localizedDescription, attempts: attempts)
            return false
        }
    }

    /// M9-Fix4 · 写飞书前确保附件已上传。
    /// - 无本地截图（attachmentLocalPath 为空 / 文件已被系统清）→ 直接返回原 record
    /// - 已有 attachmentRemoteToken → 直接返回（不重复上传）
    /// - 否则：读 jpeg → 调 uploadAttachment → 拿 file_token → 写回 SQLite + 返回更新后的 record
    /// 上传失败：仅打 WARN 不阻塞同步（带文字字段照常写飞书；下次 tick 再尝试上传）
    private func ensureAttachmentUploaded(record: Record, phase: String) async throws -> Record {
        if let token = record.attachmentRemoteToken, !token.isEmpty {
            return record  // 已有 token
        }
        guard let localPath = record.attachmentLocalPath, !localPath.isEmpty,
              let data = ScreenshotStore.read(path: localPath) else {
            return record  // 无本地截图
        }
        SyncLogger.info(phase: "attachment", recordId: record.id,
                        "uploading \(data.count) bytes")
        do {
            let fileToken = try await FeishuBitableClient.shared.uploadAttachment(
                data: data, recordId: record.id
            )
            // 写回本地（仅更 attachmentRemoteToken 字段；用 update 整行，updated_at 会被刷新但
            // 这是同步元事件不算业务编辑——可接受副作用）
            var updated = record
            updated.attachmentRemoteToken = fileToken
            try SQLiteRecordRepository.shared.update(updated)
            SyncLogger.info(phase: "attachment", recordId: record.id,
                            "uploaded file_token=\(fileToken.prefix(15))...")
            return updated
        } catch {
            SyncLogger.warn(phase: "attachment", recordId: record.id,
                            "upload failed (will retry next tick): \(error.localizedDescription)")
            return record  // 不阻塞同步，无附件继续走
        }
    }

    /// 单条写入（含 2 层失效防御）。
    /// - Returns: 实际写入飞书后的 record_id（用于 markSynced 写回 remoteId）
    /// - Throws: FeishuBitableError；调用方按 isTransient 决定 attempts 策略
    ///
    /// 防御 1（remoteId 失效）：本地 record.remoteId 指向的飞书行已被删/迁移
    ///   → 飞书返回 `1254043 RecordIdNotFound` → 降级 createRecord
    ///
    /// 防御 2（app_token 失效）：本地缓存的多维表格被删（场景：旧版本 App 自动建过表后表被人手删，
    ///   或我们清掉旧测试表）→ 飞书返回 `1002 note has been deleted` 或 `91402 NOTEXIST`
    ///   → 清 UserDefaults 缓存 → ensureBitableExists 自动建一张新表 → 整体重试一次
    private func writeWithFallbacks(record: Record, phase: String) async throws -> String {
        let fields = try RecordBitableMapper.encode(record)
        do {
            return try await writeOnce(record: record, fields: fields, phase: phase)
        } catch FeishuBitableError.apiError(let code, _, _) where code == 1002 || code == 91402 {
            // app_token 失效：清缓存 + 重建表 + 重试一次
            SyncLogger.warn(phase: phase, recordId: record.id,
                            "app_token stale (\(code)), reset cache and rebuild bitable")
            FeishuConfig.resetBitableCache()
            try await FeishuBitableClient.shared.ensureBitableExists()
            // 旧 remoteId 失效；旧 file_token 也失效（飞书素材跟着旧表走），全部清
            var rebuiltRecord = record
            rebuiltRecord.remoteId = nil
            rebuiltRecord.attachmentRemoteToken = nil
            // 重建后再上传一次附件到新表（若有本地截图）
            let withFreshAttachment = try await ensureAttachmentUploaded(record: rebuiltRecord, phase: phase)
            let rebuiltFields = try RecordBitableMapper.encode(withFreshAttachment)
            return try await writeOnce(record: withFreshAttachment, fields: rebuiltFields, phase: phase)
        }
    }

    /// writeWithFallbacks 内部用：执行一次实际写入（仍含 1254043 → create 降级）。
    private func writeOnce(record: Record, fields: [String: Any], phase: String) async throws -> String {
        if let existingId = record.remoteId, !existingId.isEmpty {
            do {
                try await FeishuBitableClient.shared.updateRecord(
                    recordId: existingId, fields: fields
                )
                return existingId
            } catch FeishuBitableError.apiError(let code, _, _) where code == 1254043 {
                SyncLogger.warn(phase: phase, recordId: record.id,
                                "remoteId stale (1254043), fallback to create")
                return try await FeishuBitableClient.shared.createRecord(fields: fields)
            }
        } else {
            return try await FeishuBitableClient.shared.createRecord(fields: fields)
        }
    }

    private func markFailedSafe(id: String, msg: String, attempts: Int) {
        do {
            try SQLiteRecordRepository.shared.markFailed(
                id: id, error: msg, attempts: attempts
            )
        } catch {
            SyncLogger.failure(phase: "markFailed", recordId: id, error: error)
        }
    }

    // MARK: - Backoff (pure, unit-testable)

    /// 计算指数退避时长。
    /// - attempt 从 0 开始；0 → 1s，1 → 2s …
    /// - 加 ±20% 抖动避免雪崩。
    /// - 上限 60s。
    /// - 最小 100ms 保护。
    static func backoff(attempt: Int,
                        randomSource: () -> Double = { Double.random(in: 0..<1) }) -> TimeInterval {
        let base = min(pow(2.0, Double(attempt)), backoffCap)
        let jitterPct = (randomSource() - 0.5) * 0.4     // [-0.2, +0.2]
        let delay = base * (1.0 + jitterPct)
        return max(0.1, delay)
    }

    /// 给定错误是否应重试。
    static func shouldRetry(_ error: FeishuBitableError, attempts: Int) -> Bool {
        guard attempts < maxAttempts else { return false }
        return error.isTransient
    }
}
