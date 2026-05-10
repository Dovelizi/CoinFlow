//  RecordRepository.swift
//  CoinFlow · M3

import Foundation
import SQLCipher

/// 流水查询条件。
struct RecordQuery {
    var ledgerId: String?
    var categoryId: String?
    var kind: CategoryKind?
    var fromDate: Date?
    var toDate: Date?
    var includesDeleted: Bool = false
    var limit: Int? = 200
}

protocol RecordRepository {
    func insert(_ record: Record) throws
    func update(_ record: Record) throws
    func delete(id: String) throws       // 软删除：仅写 deleted_at
    /// 物理删除：DELETE FROM record。
    /// 用于"仅删除本地"语义：飞书行不动，本地彻底抹掉该 id。
    /// ⚠️ 语义副作用：下次 `RemoteRecordPuller.pullAll` 时该 id 会被视为 remote-only
    /// 重新 INSERT 回本地；用户需在点击"仅删除本地"时自行接受此行为。
    func hardDelete(id: String) throws
    func find(id: String) throws -> Record?
    func list(_ query: RecordQuery) throws -> [Record]
    func pendingSync(limit: Int) throws -> [Record]

    /// 同步队列用：记录一次同步尝试结果。
    func markSyncing(ids: [String]) throws
    func markSynced(id: String, remoteId: String) throws
    func markFailed(id: String, error: String, attempts: Int) throws

    /// 用户在 UI 上点击「全部重试」时调用：把 attempts 已达上限的死记录重置为 pending，
    /// 让 SyncQueue.tick 能再次拾起它们。返回被重置的条数。
    func resetDeadRetries() throws -> Int

    /// 启动时调用：把因 App 强杀 / crash 滞留在 `syncing` 的记录复活为 `pending`。
    /// 不复活也不会数据损坏，但会让该记录"卡住"直到下次业务编辑触发 update→pending。
    /// - Returns: 被复活的记录条数（用于日志）
    @discardableResult
    func reconcileSyncingOnLaunch() throws -> Int

    /// M9-Fix4：把所有 record 的同步元数据完全 reset 到 pending（清 remoteId / attempts /
    /// lastSyncError / attachment_remote_token）。用于飞书表被外部删除/迁移后强制重推。
    /// - Returns: 被 reset 的记录条数
    @discardableResult
    func resetAllSyncMetadata() throws -> Int
}

final class SQLiteRecordRepository: RecordRepository {

    static let shared = SQLiteRecordRepository()
    private init() {}

    private let db = DatabaseManager.shared

    /// 与 Schema.createRecord DDL 严格一致。每次修改 schema 都要同步。
    /// 读列索引（0-based）按此顺序。
    private static let columns = """
    id, ledger_id, category_id, amount, currency, occurred_at, timezone,
    note, payer_user_id, participants, source, ocr_confidence,
    voice_session_id, missing_fields, merchant_channel,
    sync_status, remote_id, last_sync_error, sync_attempts,
    attachment_local_path, attachment_remote_token,
    created_at, updated_at, deleted_at
    """

    // MARK: - Insert

    func insert(_ record: Record) throws {
        let sql = """
        INSERT INTO record (\(Self.columns))
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            try Self.bindAll(stmt, record)
            try stmt.stepDone()
        }
        RecordChangeNotifier.broadcast(recordIds: [record.id])
    }

    // MARK: - Update

    func update(_ record: Record) throws {
        let sql = """
        UPDATE record SET
          ledger_id = ?, category_id = ?, amount = ?, currency = ?,
          occurred_at = ?, timezone = ?, note = ?, payer_user_id = ?,
          participants = ?, source = ?, ocr_confidence = ?,
          voice_session_id = ?, missing_fields = ?, merchant_channel = ?,
          sync_status = ?, remote_id = ?, last_sync_error = ?, sync_attempts = ?,
          attachment_local_path = ?, attachment_remote_token = ?,
          updated_at = ?, deleted_at = ?
        WHERE id = ?;
        """
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, record.ledgerId)
            stmt.bind(2, record.categoryId)
            stmt.bind(3, record.amount)
            stmt.bind(4, record.currency)
            stmt.bind(5, record.occurredAt)
            stmt.bind(6, record.timezone)
            stmt.bind(7, record.note)
            stmt.bind(8, record.payerUserId)
            try stmt.bindJSON(9, record.participants)
            stmt.bind(10, record.source.rawValue)
            stmt.bind(11, record.ocrConfidence)
            stmt.bind(12, record.voiceSessionId)
            try stmt.bindJSON(13, record.missingFields)
            stmt.bind(14, record.merchantChannel)
            stmt.bind(15, record.syncStatus.rawValue)
            stmt.bind(16, record.remoteId)
            stmt.bind(17, record.lastSyncError)
            stmt.bind(18, record.syncAttempts)
            stmt.bind(19, record.attachmentLocalPath)
            stmt.bind(20, record.attachmentRemoteToken)
            stmt.bind(21, Date())             // updated_at = now
            stmt.bind(22, record.deletedAt)
            stmt.bind(23, record.id)
            try stmt.stepDone()
        }
        RecordChangeNotifier.broadcast(recordIds: [record.id])
    }

    // MARK: - Delete（软删）

    /// 软删一条流水。
    /// - 标记 `deleted_at = now`、`updated_at = now`
    /// - **同时把 `sync_status` 重置为 `pending`、`sync_attempts = 0`、`last_sync_error = NULL`**：
    ///   云端清理需要靠 SyncQueue 把这条「带 deletedAt 的 record」推上去（writeRecord
    ///   会把 deletedAt 编码进 Firestore doc，达成云端软删）。如果不重置，记录仍是
    ///   `synced` 态，永远不会进入 `pendingSync()` 候选集。
    func delete(id: String) throws {
        try db.withHandle { handle in
            let stmt = try PreparedStatement(
                sql: """
                UPDATE record SET
                  deleted_at = ?, updated_at = ?,
                  sync_status = 'pending', sync_attempts = 0, last_sync_error = NULL
                WHERE id = ?;
                """,
                handle: handle
            )
            let now = Date()
            stmt.bind(1, now)
            stmt.bind(2, now)
            stmt.bind(3, id)
            try stmt.stepDone()
        }
        RecordChangeNotifier.broadcast(recordIds: [id])
    }

    // MARK: - Hard Delete（物理删除 · "仅删除本地"）

    /// 物理删除一行。不触发 SyncQueue（飞书行保持原样）。
    /// 语义：用户选择了"仅删除本地"——只想把本地这条抹掉，飞书上那条与我无关。
    /// 代价：下次从飞书手动拉取时，该 id 本地 `find` 不命中 → 会被当 remote-only 再 INSERT 回来。
    func hardDelete(id: String) throws {
        try db.withHandle { handle in
            let stmt = try PreparedStatement(
                sql: "DELETE FROM record WHERE id = ?;",
                handle: handle
            )
            stmt.bind(1, id)
            try stmt.stepDone()
        }
        RecordChangeNotifier.broadcast(recordIds: [id])
    }

    // MARK: - Find / List

    func find(id: String) throws -> Record? {
        let sql = "SELECT \(Self.columns) FROM record WHERE id = ? LIMIT 1;"
        return try db.withHandle { handle -> Record? in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, id)
            if try stmt.hasNext() {
                return Self.decode(stmt)
            }
            return nil
        }
    }

    func list(_ query: RecordQuery) throws -> [Record] {
        // 白名单校验防止 SQL 注入
        if let k = query.kind {
            let raw = k.rawValue
            precondition(raw == "income" || raw == "expense",
                         "CategoryKind raw value must be whitelisted")
        }

        var where_: [String] = []
        if !query.includesDeleted { where_.append("deleted_at IS NULL") }
        if query.ledgerId != nil   { where_.append("ledger_id = ?") }
        if query.categoryId != nil { where_.append("category_id = ?") }
        if query.fromDate != nil   { where_.append("occurred_at >= ?") }
        if query.toDate != nil     { where_.append("occurred_at <= ?") }
        // kind 需要 JOIN category 表，M3 简化：放到内存层过滤（list 返回后再 filter）

        let whereClause = where_.isEmpty ? "1=1" : where_.joined(separator: " AND ")
        let limitClause = query.limit.map { "LIMIT \($0)" } ?? ""
        let sql = """
        SELECT \(Self.columns) FROM record
        WHERE \(whereClause)
        ORDER BY occurred_at DESC
        \(limitClause);
        """
        return try db.withHandle { handle -> [Record] in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            var idx: Int32 = 1
            if let lid = query.ledgerId   { stmt.bind(idx, lid); idx += 1 }
            if let cid = query.categoryId { stmt.bind(idx, cid); idx += 1 }
            if let f = query.fromDate     { stmt.bind(idx, f);   idx += 1 }
            if let t = query.toDate       { stmt.bind(idx, t);   idx += 1 }
            var out: [Record] = []
            while try stmt.hasNext() {
                out.append(Self.decode(stmt))
            }
            return out
        }
    }

    // MARK: - Sync queue helpers

    func pendingSync(limit: Int) throws -> [Record] {
        // 含 deleted_at 不为空的软删记录：它们也需要把"软删"事件推到云端
        // （writeRecord 会把 deletedAt 编码进 Firestore doc）。
        //
        // 状态过滤：
        //   - `pending`：待首次同步 / 业务编辑后重置 / `delete()` 重置
        //   - `failed`：上次失败可重试（attempts < maxAttempts）；attempts ≥ max 由
        //     `SyncQueue.shouldRetry` 在内存层过滤跳过，避免反复占用候选名额
        //   - `syncing` 不在此处选中：reconcileSyncingOnLaunch() 启动时已统一打回 pending
        //
        // 排序：按 `updated_at ASC`（最早被业务修改的先发）。
        // 旧实现用 `created_at ASC` 的问题：同一记录被多次编辑后 created_at 不变，
        // 老旧但已同步的"骨骸"会一直占位；软删事件的实际触发时间是 updated_at，
        // 用 created_at 排序会让软删被排在新增之后。`updated_at ASC` 同时满足
        // FIFO 与"最新一次业务变更优先"两个语义（B4 修复）。
        let sql = """
        SELECT \(Self.columns) FROM record
        WHERE sync_status IN ('pending', 'failed')
        ORDER BY updated_at ASC
        LIMIT ?;
        """
        return try db.withHandle { handle -> [Record] in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, limit)
            var out: [Record] = []
            while try stmt.hasNext() {
                out.append(Self.decode(stmt))
            }
            return out
        }
    }

    /// 标记为 syncing。
    ///
    /// ⚠️ **不写 updated_at**：updated_at 表达的是"业务最后修改时间"，被 ViewModel
    /// 用作排序/冲突解决依据；同步元事件不应污染该字段（B2 修复）。
    func markSyncing(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        let sql = """
        UPDATE record SET sync_status = 'syncing'
        WHERE id IN (\(placeholders));
        """
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            for (i, id) in ids.enumerated() {
                stmt.bind(Int32(1 + i), id)
            }
            try stmt.stepDone()
        }
    }

    /// 标记同步成功。同样不写 `updated_at`（理由同 markSyncing）。
    /// 重置 `sync_attempts = 0`、清错误。
    func markSynced(id: String, remoteId: String) throws {
        let sql = """
        UPDATE record SET
          sync_status = 'synced', remote_id = ?, last_sync_error = NULL,
          sync_attempts = 0
        WHERE id = ?;
        """
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, remoteId)
            stmt.bind(2, id)
            try stmt.stepDone()
        }
        RecordChangeNotifier.broadcast(recordIds: [id])
    }

    /// 标记同步失败。不写 `updated_at`（理由同 markSyncing）。
    /// - Note: 调用方决定 attempts 累计语义（transient 才递增）；本方法只做存储。
    func markFailed(id: String, error: String, attempts: Int) throws {
        let sql = """
        UPDATE record SET
          sync_status = 'failed', last_sync_error = ?, sync_attempts = ?
        WHERE id = ?;
        """
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, error)
            stmt.bind(2, attempts)
            stmt.bind(3, id)
            try stmt.stepDone()
        }
        RecordChangeNotifier.broadcast(recordIds: [id])
    }

    /// **启动时 reconcile**：把上次未完成（停留在 `syncing`）的记录复活为 `pending`。
    /// 场景：tick 期间 App 被强杀或 crash → record 卡在 syncing 永远不会再被 pendingSync 选中。
    /// - Returns: 被复活的条数
    @discardableResult
    func reconcileSyncingOnLaunch() throws -> Int {
        let countSQL = "SELECT COUNT(*) FROM record WHERE sync_status = 'syncing';"
        let updateSQL = "UPDATE record SET sync_status = 'pending' WHERE sync_status = 'syncing';"
        let count: Int = try db.withHandle { handle -> Int in
            let stmt = try PreparedStatement(sql: countSQL, handle: handle)
            return try stmt.hasNext() ? stmt.columnInt(0) : 0
        }
        guard count > 0 else { return 0 }
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: updateSQL, handle: handle)
            try stmt.stepDone()
        }
        return count
    }

    /// 把 attempts 达到上限（永久失败）的记录重置为 pending、attempts=0、清错误，
    /// 让 SyncQueue.tick 重新拾起。仅用于用户在 UI 上点击「全部重试」时。
    /// - Returns: 被重置的记录数
    func resetDeadRetries() throws -> Int {
        // SQLite 不支持 RETURNING（旧版本），分两步：先 SELECT count，再 UPDATE
        let countSQL = """
        SELECT COUNT(*) FROM record
        WHERE sync_status = 'failed' AND sync_attempts >= ?;
        """
        let updateSQL = """
        UPDATE record SET
          sync_status = 'pending', sync_attempts = 0, last_sync_error = NULL,
          updated_at = ?
        WHERE sync_status = 'failed' AND sync_attempts >= ?;
        """
        let cap = SyncQueue.maxAttempts
        let count: Int = try db.withHandle { handle -> Int in
            let stmt = try PreparedStatement(sql: countSQL, handle: handle)
            stmt.bind(1, cap)
            return try stmt.hasNext() ? stmt.columnInt(0) : 0
        }
        guard count > 0 else { return 0 }
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: updateSQL, handle: handle)
            stmt.bind(1, Date())
            stmt.bind(2, cap)
            try stmt.stepDone()
        }
        RecordChangeNotifier.broadcast(recordIds: [])  // 群发刷新（id 列表此处不重要）
        return count
    }

    /// 把所有 record 的同步元数据完全 reset。用于飞书表被外部清空/迁移时全量重推。
    /// 改动：sync_status='pending', remote_id=NULL, attempts=0, last_sync_error=NULL,
    /// attachment_remote_token=NULL（飞书 file_token 也失效，需重新上传）
    @discardableResult
    func resetAllSyncMetadata() throws -> Int {
        let sql = """
        UPDATE record SET
          sync_status = 'pending',
          remote_id = NULL,
          sync_attempts = 0,
          last_sync_error = NULL,
          attachment_remote_token = NULL
        WHERE deleted_at IS NULL;
        """
        let count: Int = try db.withHandle { handle -> Int in
            let countStmt = try PreparedStatement(
                sql: "SELECT COUNT(*) FROM record WHERE deleted_at IS NULL;",
                handle: handle
            )
            return try countStmt.hasNext() ? countStmt.columnInt(0) : 0
        }
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            try stmt.stepDone()
        }
        RecordChangeNotifier.broadcast(recordIds: [])
        return count
    }

    // MARK: - Bind & Decode

    private static func bindAll(_ stmt: PreparedStatement, _ r: Record) throws {
        stmt.bind(1, r.id)
        stmt.bind(2, r.ledgerId)
        stmt.bind(3, r.categoryId)
        stmt.bind(4, r.amount)
        stmt.bind(5, r.currency)
        stmt.bind(6, r.occurredAt)
        stmt.bind(7, r.timezone)
        stmt.bind(8, r.note)
        stmt.bind(9, r.payerUserId)
        try stmt.bindJSON(10, r.participants)
        stmt.bind(11, r.source.rawValue)
        stmt.bind(12, r.ocrConfidence)
        stmt.bind(13, r.voiceSessionId)
        try stmt.bindJSON(14, r.missingFields)
        stmt.bind(15, r.merchantChannel)
        stmt.bind(16, r.syncStatus.rawValue)
        stmt.bind(17, r.remoteId)
        stmt.bind(18, r.lastSyncError)
        stmt.bind(19, r.syncAttempts)
        stmt.bind(20, r.attachmentLocalPath)
        stmt.bind(21, r.attachmentRemoteToken)
        stmt.bind(22, r.createdAt)
        stmt.bind(23, r.updatedAt)
        stmt.bind(24, r.deletedAt)
    }

    private static func decode(_ s: PreparedStatement) -> Record {
        Record(
            id: s.columnText(0),
            ledgerId: s.columnText(1),
            categoryId: s.columnText(2),
            amount: s.columnDecimal(3),
            currency: s.columnText(4),
            occurredAt: s.columnDate(5),
            timezone: s.columnText(6),
            note: s.columnTextOrNil(7),
            payerUserId: s.columnTextOrNil(8),
            participants: s.columnJSON(9, as: [String].self),
            source: RecordSource(rawValue: s.columnText(10)) ?? .manual,
            ocrConfidence: s.columnDoubleOrNil(11),
            voiceSessionId: s.columnTextOrNil(12),
            missingFields: s.columnJSON(13, as: [String].self),
            merchantChannel: s.columnTextOrNil(14),
            syncStatus: SyncStatus(rawValue: s.columnText(15)) ?? .pending,
            remoteId: s.columnTextOrNil(16),
            lastSyncError: s.columnTextOrNil(17),
            syncAttempts: s.columnInt(18),
            attachmentLocalPath: s.columnTextOrNil(19),
            attachmentRemoteToken: s.columnTextOrNil(20),
            createdAt: s.columnDate(21),
            updatedAt: s.columnDate(22),
            deletedAt: s.columnDateOrNil(23)
        )
    }
}
