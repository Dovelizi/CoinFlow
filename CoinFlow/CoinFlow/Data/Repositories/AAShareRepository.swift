//  AAShareRepository.swift
//  CoinFlow · M11 — AA 分账：单笔流水按成员维度的应付明细仓库

import Foundation
import SQLCipher

protocol AAShareRepository {
    func insert(_ share: AAShare) throws
    func update(_ share: AAShare) throws
    /// 根据 (record_id, member_id) upsert：存在则更新 amount/is_custom，
    /// 不存在则新建一条。Decimal 全程不做 Double 中转。
    func upsert(recordId: String, memberId: String, amount: Decimal, isCustom: Bool) throws
    /// 物理删除（按 record / member 维度清理）。
    func deleteByRecord(recordId: String) throws
    func deleteByMember(memberId: String) throws
    /// 列出某条 record 下的所有未删除分摊。
    func list(recordId: String) throws -> [AAShare]
    /// 列出某账本下所有 record 的所有未删除分摊（用于结算页一次拉全）。
    func listByLedger(ledgerId: String) throws -> [AAShare]
    /// 求某成员在指定账本下的应付总额（自动跳过 deleted_at 不为空的 share）。
    func sumByMember(ledgerId: String, memberId: String) throws -> Decimal
}

final class SQLiteAAShareRepository: AAShareRepository {

    static let shared = SQLiteAAShareRepository()
    private init() {}

    private let db = DatabaseManager.shared

    private static let columns = """
    id, record_id, member_id, amount, is_custom,
    created_at, updated_at, deleted_at
    """

    func insert(_ share: AAShare) throws {
        let sql = """
        INSERT INTO aa_share (\(Self.columns))
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, share.id)
            stmt.bind(2, share.recordId)
            stmt.bind(3, share.memberId)
            stmt.bind(4, share.amount)
            stmt.bind(5, share.isCustom)
            stmt.bind(6, share.createdAt)
            stmt.bind(7, share.updatedAt)
            stmt.bind(8, share.deletedAt)
            try stmt.stepDone()
        }
    }

    func update(_ share: AAShare) throws {
        let sql = """
        UPDATE aa_share SET
          amount = ?, is_custom = ?, updated_at = ?, deleted_at = ?
        WHERE id = ?;
        """
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, share.amount)
            stmt.bind(2, share.isCustom)
            stmt.bind(3, Date())
            stmt.bind(4, share.deletedAt)
            stmt.bind(5, share.id)
            try stmt.stepDone()
        }
    }

    func upsert(recordId: String, memberId: String, amount: Decimal, isCustom: Bool) throws {
        // 先查现有未删除行
        let findSQL = """
        SELECT id FROM aa_share
        WHERE record_id = ? AND member_id = ? AND deleted_at IS NULL
        LIMIT 1;
        """
        let existingId: String? = try db.withHandle { handle -> String? in
            let stmt = try PreparedStatement(sql: findSQL, handle: handle)
            stmt.bind(1, recordId)
            stmt.bind(2, memberId)
            return try stmt.hasNext() ? stmt.columnText(0) : nil
        }

        if let id = existingId {
            let updateSQL = """
            UPDATE aa_share SET amount = ?, is_custom = ?, updated_at = ?
            WHERE id = ?;
            """
            try db.withHandle { handle in
                let stmt = try PreparedStatement(sql: updateSQL, handle: handle)
                stmt.bind(1, amount)
                stmt.bind(2, isCustom)
                stmt.bind(3, Date())
                stmt.bind(4, id)
                try stmt.stepDone()
            }
        } else {
            let now = Date()
            let share = AAShare(
                id: UUID().uuidString,
                recordId: recordId,
                memberId: memberId,
                amount: amount,
                isCustom: isCustom,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil
            )
            try insert(share)
        }
    }

    func deleteByRecord(recordId: String) throws {
        try db.withHandle { handle in
            let stmt = try PreparedStatement(
                sql: """
                UPDATE aa_share SET deleted_at = ?, updated_at = ?
                WHERE record_id = ? AND deleted_at IS NULL;
                """,
                handle: handle
            )
            let now = Date()
            stmt.bind(1, now)
            stmt.bind(2, now)
            stmt.bind(3, recordId)
            try stmt.stepDone()
        }
    }

    func deleteByMember(memberId: String) throws {
        try db.withHandle { handle in
            let stmt = try PreparedStatement(
                sql: """
                UPDATE aa_share SET deleted_at = ?, updated_at = ?
                WHERE member_id = ? AND deleted_at IS NULL;
                """,
                handle: handle
            )
            let now = Date()
            stmt.bind(1, now)
            stmt.bind(2, now)
            stmt.bind(3, memberId)
            try stmt.stepDone()
        }
    }

    func list(recordId: String) throws -> [AAShare] {
        let sql = """
        SELECT \(Self.columns) FROM aa_share
        WHERE record_id = ? AND deleted_at IS NULL
        ORDER BY created_at ASC;
        """
        return try db.withHandle { handle -> [AAShare] in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, recordId)
            var out: [AAShare] = []
            while try stmt.hasNext() {
                out.append(Self.decode(stmt))
            }
            return out
        }
    }

    func listByLedger(ledgerId: String) throws -> [AAShare] {
        // JOIN record 表过滤 ledger_id
        let sql = """
        SELECT s.id, s.record_id, s.member_id, s.amount, s.is_custom,
               s.created_at, s.updated_at, s.deleted_at
        FROM aa_share s
        INNER JOIN record r ON r.id = s.record_id
        WHERE r.ledger_id = ?
          AND s.deleted_at IS NULL
          AND r.deleted_at IS NULL
        ORDER BY s.created_at ASC;
        """
        return try db.withHandle { handle -> [AAShare] in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, ledgerId)
            var out: [AAShare] = []
            while try stmt.hasNext() {
                out.append(Self.decode(stmt))
            }
            return out
        }
    }

    func sumByMember(ledgerId: String, memberId: String) throws -> Decimal {
        // SQLite 没有 Decimal 聚合，TEXT 列 SUM 会被强转 Double 失真。
        // 因此先把候选 amount 字符串拉到内存层再用 Decimal 累加（B1）。
        let sql = """
        SELECT s.amount FROM aa_share s
        INNER JOIN record r ON r.id = s.record_id
        WHERE r.ledger_id = ?
          AND s.member_id = ?
          AND s.deleted_at IS NULL
          AND r.deleted_at IS NULL;
        """
        return try db.withHandle { handle -> Decimal in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, ledgerId)
            stmt.bind(2, memberId)
            var total: Decimal = 0
            while try stmt.hasNext() {
                total += stmt.columnDecimal(0)
            }
            return total
        }
    }

    private static func decode(_ s: PreparedStatement) -> AAShare {
        AAShare(
            id: s.columnText(0),
            recordId: s.columnText(1),
            memberId: s.columnText(2),
            amount: s.columnDecimal(3),
            isCustom: s.columnBool(4),
            createdAt: s.columnDate(5),
            updatedAt: s.columnDate(6),
            deletedAt: s.columnDateOrNil(7)
        )
    }
}
