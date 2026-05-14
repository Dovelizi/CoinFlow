//  LedgerRepository.swift
//  CoinFlow · M3 / M11 (AA 分账扩展)

import Foundation
import SQLCipher

protocol LedgerRepository {
    func insert(_ ledger: Ledger) throws
    func update(_ ledger: Ledger) throws
    func archive(id: String) throws
    func delete(id: String) throws       // 软删除
    func find(id: String) throws -> Ledger?
    func list(includeArchived: Bool) throws -> [Ledger]
    /// M11：列出 AA 类型账本（按 created_at DESC）。
    /// - status: nil 表示全部 AA（含 nil 状态的兼容旧行）；具体状态值表示精确过滤。
    /// - includeArchived: 是否包含已归档行。
    func listAA(status: AAStatus?, includeArchived: Bool) throws -> [Ledger]
    /// M11：仅更新 AA 状态机字段（aa_status / settling_started_at / completed_at）。
    /// 其他字段保持不变；事务由调用方包裹（AASplitService 内统一处理）。
    func updateAAStatus(id: String,
                        status: AAStatus,
                        settlingStartedAt: Date?,
                        completedAt: Date?) throws
}

final class SQLiteLedgerRepository: LedgerRepository {

    static let shared = SQLiteLedgerRepository()
    private init() {}

    private let db = DatabaseManager.shared

    // MARK: - Columns order（与 SELECT / INSERT 保持一致）

    private static let columns = """
    id, name, type, firestore_path, created_at, timezone, archived_at, deleted_at,
    aa_status, settling_started_at, completed_at
    """

    // MARK: - Insert

    func insert(_ ledger: Ledger) throws {
        let sql = """
        INSERT INTO ledger (\(Self.columns))
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, ledger.id)
            stmt.bind(2, ledger.name)
            stmt.bind(3, ledger.type.rawValue)
            stmt.bind(4, ledger.firestorePath)
            stmt.bind(5, ledger.createdAt)
            stmt.bind(6, ledger.timezone)
            stmt.bind(7, ledger.archivedAt)
            stmt.bind(8, ledger.deletedAt)
            stmt.bind(9, ledger.aaStatus?.rawValue)
            stmt.bind(10, ledger.settlingStartedAt)
            stmt.bind(11, ledger.completedAt)
            try stmt.stepDone()
        }
    }

    // MARK: - Update

    func update(_ ledger: Ledger) throws {
        let sql = """
        UPDATE ledger SET
          name = ?, type = ?, firestore_path = ?, timezone = ?,
          archived_at = ?, deleted_at = ?,
          aa_status = ?, settling_started_at = ?, completed_at = ?
        WHERE id = ?;
        """
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, ledger.name)
            stmt.bind(2, ledger.type.rawValue)
            stmt.bind(3, ledger.firestorePath)
            stmt.bind(4, ledger.timezone)
            stmt.bind(5, ledger.archivedAt)
            stmt.bind(6, ledger.deletedAt)
            stmt.bind(7, ledger.aaStatus?.rawValue)
            stmt.bind(8, ledger.settlingStartedAt)
            stmt.bind(9, ledger.completedAt)
            stmt.bind(10, ledger.id)
            try stmt.stepDone()
        }
    }

    // MARK: - Archive / soft delete

    func archive(id: String) throws {
        try db.withHandle { handle in
            let stmt = try PreparedStatement(
                sql: "UPDATE ledger SET archived_at = ? WHERE id = ?;",
                handle: handle
            )
            stmt.bind(1, Date())
            stmt.bind(2, id)
            try stmt.stepDone()
        }
    }

    func delete(id: String) throws {
        try db.withHandle { handle in
            let stmt = try PreparedStatement(
                sql: "UPDATE ledger SET deleted_at = ? WHERE id = ?;",
                handle: handle
            )
            stmt.bind(1, Date())
            stmt.bind(2, id)
            try stmt.stepDone()
        }
    }

    // MARK: - Read

    func find(id: String) throws -> Ledger? {
        let sql = "SELECT \(Self.columns) FROM ledger WHERE id = ? AND deleted_at IS NULL LIMIT 1;"
        return try db.withHandle { handle -> Ledger? in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, id)
            if try stmt.hasNext() {
                return Self.decode(stmt)
            }
            return nil
        }
    }

    func list(includeArchived: Bool) throws -> [Ledger] {
        let archivedClause = includeArchived ? "" : "AND archived_at IS NULL"
        let sql = """
        SELECT \(Self.columns) FROM ledger
        WHERE deleted_at IS NULL \(archivedClause)
        ORDER BY created_at DESC;
        """
        return try db.withHandle { handle -> [Ledger] in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            var out: [Ledger] = []
            while try stmt.hasNext() {
                out.append(Self.decode(stmt))
            }
            return out
        }
    }

    // MARK: - AA 扩展（M11）

    func listAA(status: AAStatus?, includeArchived: Bool) throws -> [Ledger] {
        var where_: [String] = ["deleted_at IS NULL", "type = 'aa'"]
        if !includeArchived { where_.append("archived_at IS NULL") }
        if status != nil    { where_.append("aa_status = ?") }
        let whereClause = where_.joined(separator: " AND ")
        // 已完成态按 completed_at DESC 排，其他统一按 created_at DESC
        let orderClause = (status == .completed)
            ? "ORDER BY completed_at DESC"
            : "ORDER BY created_at DESC"
        let sql = """
        SELECT \(Self.columns) FROM ledger
        WHERE \(whereClause)
        \(orderClause);
        """
        return try db.withHandle { handle -> [Ledger] in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            if let s = status { stmt.bind(1, s.rawValue) }
            var out: [Ledger] = []
            while try stmt.hasNext() {
                out.append(Self.decode(stmt))
            }
            return out
        }
    }

    func updateAAStatus(id: String,
                        status: AAStatus,
                        settlingStartedAt: Date?,
                        completedAt: Date?) throws {
        let sql = """
        UPDATE ledger SET
          aa_status = ?, settling_started_at = ?, completed_at = ?
        WHERE id = ?;
        """
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, status.rawValue)
            stmt.bind(2, settlingStartedAt)
            stmt.bind(3, completedAt)
            stmt.bind(4, id)
            try stmt.stepDone()
        }
    }

    // MARK: - Decode

    private static func decode(_ s: PreparedStatement) -> Ledger {
        Ledger(
            id: s.columnText(0),
            name: s.columnText(1),
            type: LedgerType(rawValue: s.columnText(2)) ?? .personal,
            firestorePath: s.columnTextOrNil(3),
            createdAt: s.columnDate(4),
            timezone: s.columnText(5),
            archivedAt: s.columnDateOrNil(6),
            deletedAt: s.columnDateOrNil(7),
            aaStatus: s.columnTextOrNil(8).flatMap { AAStatus(rawValue: $0) },
            settlingStartedAt: s.columnDateOrNil(9),
            completedAt: s.columnDateOrNil(10)
        )
    }
}
