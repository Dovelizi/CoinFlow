//  RecordRepositorySyncTests.swift
//  CoinFlowTests · M8
//
//  覆盖 SQLiteRecordRepository 的同步元数据语义：
//  - insert/update/delete 后的 sync_status 行为
//  - markSyncing/markSynced/markFailed **不写 updated_at**（B2 修复）
//  - reconcileSyncingOnLaunch 复活 syncing 滞留态（B1 修复）
//  - pendingSync 排序按 updated_at ASC（B4 修复）
//  - delete 重置 sync_status=pending、attempts=0（B3 软删可重推语义）
//
//  使用真实 SQLCipher DB（DatabaseManager.shared）；测试用例间通过删表+重建隔离。

import XCTest
@testable import CoinFlow

@MainActor
final class RecordRepositorySyncTests: XCTestCase {

    private let repo = SQLiteRecordRepository.shared
    private let ledgerId = "test-ledger"
    private let categoryId = "test-cat"

    override func setUp() async throws {
        try await super.setUp()
        // bootstrap DB（幂等）
        _ = try DatabaseManager.shared.bootstrap()
        try cleanRecordTable()
        try ensureLedgerAndCategory()
    }

    override func tearDown() async throws {
        try? cleanRecordTable()
        try await super.tearDown()
    }

    // MARK: - insert

    func test_insert_setsPendingByDefault() throws {
        let r = makeRecord(id: "r1", note: "a")
        try repo.insert(r)
        let got = try XCTUnwrap(try repo.find(id: "r1"))
        XCTAssertEqual(got.syncStatus, .pending)
        XCTAssertEqual(got.syncAttempts, 0)
        XCTAssertNil(got.lastSyncError)
        XCTAssertNil(got.deletedAt)
    }

    // MARK: - update

    /// 业务 update 必须保留传入的 syncStatus（VM 决定是否重置为 pending）。
    func test_update_preservesPassedSyncStatus() throws {
        var r = makeRecord(id: "r2")
        try repo.insert(r)
        // 模拟 ViewModel 在用户编辑后置 pending 重新触发同步
        r.syncStatus = .pending
        r.syncAttempts = 0
        r.lastSyncError = nil
        try repo.update(r)
        let got = try XCTUnwrap(try repo.find(id: "r2"))
        XCTAssertEqual(got.syncStatus, .pending)
    }

    // MARK: - delete (软删)

    func test_delete_softDelete_resetsSyncStatusForReplay() throws {
        // 插入后人工 mark synced，模拟"已同步过"的记录
        try repo.insert(makeRecord(id: "r3"))
        try repo.markSynced(id: "r3", remoteId: "r3")
        var got = try XCTUnwrap(try repo.find(id: "r3"))
        XCTAssertEqual(got.syncStatus, .synced)

        // 用户删除
        try repo.delete(id: "r3")
        got = try XCTUnwrap(try repo.find(id: "r3"))
        XCTAssertNotNil(got.deletedAt, "deletedAt 应被写入")
        XCTAssertEqual(got.syncStatus, .pending, "软删必须重置 pending 让 SyncQueue 推回云")
        XCTAssertEqual(got.syncAttempts, 0)
        XCTAssertNil(got.lastSyncError)
    }

    // MARK: - markSyncing / markSynced / markFailed 不动 updated_at

    func test_markSyncing_doesNotTouchUpdatedAt() throws {
        let r = makeRecord(id: "r4")
        try repo.insert(r)
        let originalUpdatedAt = try XCTUnwrap(try repo.find(id: "r4")).updatedAt
        // 拉开时间窗口，让任何"再写 now"都能被检测到
        try await_seconds(0.05)

        try repo.markSyncing(ids: ["r4"])
        let got = try XCTUnwrap(try repo.find(id: "r4"))
        XCTAssertEqual(got.syncStatus, .syncing)
        XCTAssertEqual(got.updatedAt.timeIntervalSinceReferenceDate,
                       originalUpdatedAt.timeIntervalSinceReferenceDate,
                       accuracy: 0.001,
                       "markSyncing 不应修改 updated_at")
    }

    func test_markSynced_doesNotTouchUpdatedAt_andClearsAttempts() throws {
        var r = makeRecord(id: "r5")
        r.syncAttempts = 3
        r.lastSyncError = "previous error"
        try repo.insert(r)
        let original = try XCTUnwrap(try repo.find(id: "r5")).updatedAt
        try await_seconds(0.05)

        try repo.markSynced(id: "r5", remoteId: "remote-r5")
        let got = try XCTUnwrap(try repo.find(id: "r5"))
        XCTAssertEqual(got.syncStatus, .synced)
        XCTAssertEqual(got.remoteId, "remote-r5")
        XCTAssertEqual(got.syncAttempts, 0)
        XCTAssertNil(got.lastSyncError)
        XCTAssertEqual(got.updatedAt.timeIntervalSinceReferenceDate,
                       original.timeIntervalSinceReferenceDate,
                       accuracy: 0.001)
    }

    func test_markFailed_doesNotTouchUpdatedAt() throws {
        try repo.insert(makeRecord(id: "r6"))
        let original = try XCTUnwrap(try repo.find(id: "r6")).updatedAt
        try await_seconds(0.05)

        try repo.markFailed(id: "r6", error: "network", attempts: 2)
        let got = try XCTUnwrap(try repo.find(id: "r6"))
        XCTAssertEqual(got.syncStatus, .failed)
        XCTAssertEqual(got.lastSyncError, "network")
        XCTAssertEqual(got.syncAttempts, 2)
        XCTAssertEqual(got.updatedAt.timeIntervalSinceReferenceDate,
                       original.timeIntervalSinceReferenceDate,
                       accuracy: 0.001)
    }

    // MARK: - reconcileSyncingOnLaunch

    func test_reconcileSyncingOnLaunch_revivesStuckSyncing() throws {
        try repo.insert(makeRecord(id: "r7-a"))
        try repo.insert(makeRecord(id: "r7-b"))
        try repo.markSyncing(ids: ["r7-a", "r7-b"])
        // 模拟 crash：现在两条都卡在 syncing
        XCTAssertEqual(try repo.find(id: "r7-a")?.syncStatus, .syncing)

        let revived = try repo.reconcileSyncingOnLaunch()
        XCTAssertEqual(revived, 2)
        XCTAssertEqual(try repo.find(id: "r7-a")?.syncStatus, .pending)
        XCTAssertEqual(try repo.find(id: "r7-b")?.syncStatus, .pending)
    }

    func test_reconcileSyncingOnLaunch_zeroWhenNothingStuck() throws {
        try repo.insert(makeRecord(id: "r7c"))
        let revived = try repo.reconcileSyncingOnLaunch()
        XCTAssertEqual(revived, 0)
    }

    // MARK: - pendingSync FIFO by updated_at

    func test_pendingSync_returnsByUpdatedAtAscending() throws {
        // 顺序 insert，但人工修改 updated_at 让顺序与 created_at 相反
        let now = Date()
        var newest = makeRecord(id: "r-new"); newest.createdAt = now.addingTimeInterval(-100); newest.updatedAt = now
        var middle = makeRecord(id: "r-mid"); middle.createdAt = now.addingTimeInterval(-50);  middle.updatedAt = now.addingTimeInterval(-30)
        var oldest = makeRecord(id: "r-old"); oldest.createdAt = now;                          oldest.updatedAt = now.addingTimeInterval(-60)
        try repo.insert(newest)
        try repo.insert(middle)
        try repo.insert(oldest)

        let pending = try repo.pendingSync(limit: 10)
        let ids = pending.map { $0.id }
        XCTAssertEqual(ids, ["r-old", "r-mid", "r-new"],
                       "pendingSync 必须按 updated_at ASC 排序（最早被业务修改的先发）")
    }

    func test_pendingSync_excludesSyncedAndSyncing() throws {
        try repo.insert(makeRecord(id: "p1"))
        try repo.insert(makeRecord(id: "p2"))
        try repo.markSynced(id: "p1", remoteId: "p1")
        try repo.markSyncing(ids: ["p2"])
        let pending = try repo.pendingSync(limit: 10)
        XCTAssertEqual(pending.count, 0, "synced + syncing 都不在候选名单里")
    }

    func test_pendingSync_includesFailed() throws {
        try repo.insert(makeRecord(id: "f1"))
        try repo.markFailed(id: "f1", error: "x", attempts: 1)
        let pending = try repo.pendingSync(limit: 10)
        XCTAssertEqual(pending.map { $0.id }, ["f1"])
    }

    // MARK: - resetDeadRetries

    func test_resetDeadRetries_revivesCappedFailed() throws {
        try repo.insert(makeRecord(id: "d1"))
        try repo.markFailed(id: "d1", error: "perm", attempts: SyncQueue.maxAttempts)
        try repo.insert(makeRecord(id: "d2"))
        try repo.markFailed(id: "d2", error: "transient", attempts: 2)

        let revived = try repo.resetDeadRetries()
        XCTAssertEqual(revived, 1, "只复活 attempts >= max 的死记录")
        XCTAssertEqual(try repo.find(id: "d1")?.syncStatus, .pending)
        XCTAssertEqual(try repo.find(id: "d1")?.syncAttempts, 0)
        XCTAssertEqual(try repo.find(id: "d2")?.syncStatus, .failed,
                       "未到上限的 failed 不被复活（仍然能继续重试）")
    }

    // MARK: - Helpers

    private func makeRecord(id: String, note: String? = nil) -> Record {
        let now = Date()
        return Record(
            id: id,
            ledgerId: ledgerId,
            categoryId: categoryId,
            amount: Decimal(string: "12.34")!,
            currency: "CNY",
            occurredAt: now,
            timezone: "Asia/Shanghai",
            note: note,
            payerUserId: nil,
            participants: nil,
            source: .manual,
            ocrConfidence: nil,
            voiceSessionId: nil,
            missingFields: nil,
            merchantChannel: nil,
            syncStatus: .pending,
            remoteId: nil,
            lastSyncError: nil,
            syncAttempts: 0,
            attachmentLocalPath: nil,
            attachmentRemoteToken: nil,
            aaSettlementId: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
    }

    private func cleanRecordTable() throws {
        try DatabaseManager.shared.withHandle { handle in
            let stmt = try PreparedStatement(
                sql: "DELETE FROM record;",
                handle: handle
            )
            try stmt.stepDone()
        }
    }

    /// 确保 ledger / category 存在以满足 record 表的外键。
    private func ensureLedgerAndCategory() throws {
        try DatabaseManager.shared.withHandle { handle in
            // ledger
            let l = try PreparedStatement(
                sql: """
                INSERT OR IGNORE INTO ledger (id, name, type, firestore_path, created_at, timezone, archived_at, deleted_at)
                VALUES (?, ?, ?, NULL, ?, ?, NULL, NULL);
                """,
                handle: handle
            )
            l.bind(1, ledgerId)
            l.bind(2, "Test Ledger")
            l.bind(3, "personal")
            l.bind(4, Date())
            l.bind(5, "Asia/Shanghai")
            try l.stepDone()
            // category
            let c = try PreparedStatement(
                sql: """
                INSERT OR IGNORE INTO category (id, name, kind, icon, color_hex, parent_id, sort_order, is_preset, deleted_at)
                VALUES (?, ?, ?, ?, ?, NULL, 0, 1, NULL);
                """,
                handle: handle
            )
            c.bind(1, categoryId)
            c.bind(2, "测试分类")
            c.bind(3, "expense")
            c.bind(4, "circle")
            c.bind(5, "#888888")
            try c.stepDone()
        }
    }

    private func await_seconds(_ s: TimeInterval) throws {
        // 短延时；用 RunLoop 而非 Task.sleep 避免 async 测试方法转换
        let deadline = Date().addingTimeInterval(s)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: deadline)
        }
    }
}
