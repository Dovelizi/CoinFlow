//  LedgerRepository.swift
//  CoinFlow · M3

import Foundation
import SQLCipher

protocol LedgerRepository {
    func insert(_ ledger: Ledger) throws
    func update(_ ledger: Ledger) throws
    func archive(id: String) throws
    func delete(id: String) throws       // 软删除
    func find(id: String) throws -> Ledger?
    func list(includeArchived: Bool) throws -> [Ledger]
}

final class SQLiteLedgerRepository: LedgerRepository {

    static let shared = SQLiteLedgerRepository()
    private init() {}

    private let db = DatabaseManager.shared

    // MARK: - Columns order（与 SELECT / INSERT 保持一致）

    private static let columns = """
    id, name, type, firestore_path, created_at, timezone, archived_at, deleted_at
    """

    // MARK: - Insert

    func insert(_ ledger: Ledger) throws {
        let sql = """
        INSERT INTO ledger (\(Self.columns))
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
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
            try stmt.stepDone()
        }
    }

    // MARK: - Update

    func update(_ ledger: Ledger) throws {
        let sql = """
        UPDATE ledger SET
          name = ?, type = ?, firestore_path = ?, timezone = ?,
          archived_at = ?, deleted_at = ?
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
            stmt.bind(7, ledger.id)
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
            deletedAt: s.columnDateOrNil(7)
        )
    }
}
