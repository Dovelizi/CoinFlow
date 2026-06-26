//  BillGroupRepository.swift
//  CoinFlow · M13 · 账单分组

import Foundation
import SQLCipher

protocol BillGroupRepository {
    func insert(_ group: BillGroup) throws
    func update(_ group: BillGroup) throws
    func delete(id: String) throws
    func find(id: String) throws -> BillGroup?
    func list(includeDeleted: Bool) throws -> [BillGroup]
}

final class SQLiteBillGroupRepository: BillGroupRepository {

    static let shared = SQLiteBillGroupRepository()
    private init() {}

    private let db = DatabaseManager.shared

    private static let columns = """
    id, name, emoji, note, sort_order, is_default, created_at, updated_at, deleted_at
    """

    func insert(_ group: BillGroup) throws {
        let sql = """
        INSERT INTO bill_group (\(Self.columns))
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, group.id)
            stmt.bind(2, group.name)
            stmt.bind(3, group.emoji)
            stmt.bind(4, group.note)
            stmt.bind(5, group.sortOrder)
            stmt.bind(6, group.isDefault ? 1 : 0)
            stmt.bind(7, group.createdAt)
            stmt.bind(8, group.updatedAt)
            stmt.bind(9, group.deletedAt)
            try stmt.stepDone()
        }
    }

    func update(_ group: BillGroup) throws {
        let sql = """
        UPDATE bill_group SET
          name = ?, emoji = ?, note = ?, sort_order = ?, is_default = ?,
          updated_at = ?, deleted_at = ?
        WHERE id = ?;
        """
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, group.name)
            stmt.bind(2, group.emoji)
            stmt.bind(3, group.note)
            stmt.bind(4, group.sortOrder)
            stmt.bind(5, group.isDefault ? 1 : 0)
            stmt.bind(6, Date())
            stmt.bind(7, group.deletedAt)
            stmt.bind(8, group.id)
            try stmt.stepDone()
        }
    }

    func delete(id: String) throws {
        try db.withHandle { handle in
            let stmt = try PreparedStatement(
                sql: "UPDATE bill_group SET deleted_at = ?, updated_at = ? WHERE id = ?;",
                handle: handle
            )
            let now = Date()
            stmt.bind(1, now)
            stmt.bind(2, now)
            stmt.bind(3, id)
            try stmt.stepDone()
        }
    }

    func find(id: String) throws -> BillGroup? {
        let sql = "SELECT \(Self.columns) FROM bill_group WHERE id = ? LIMIT 1;"
        return try db.withHandle { handle -> BillGroup? in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, id)
            if try stmt.hasNext() {
                return Self.decode(stmt)
            }
            return nil
        }
    }

    func list(includeDeleted: Bool) throws -> [BillGroup] {
        var sql = "SELECT \(Self.columns) FROM bill_group"
        if !includeDeleted { sql += " WHERE deleted_at IS NULL" }
        sql += " ORDER BY sort_order ASC, name ASC;"
        return try db.withHandle { handle -> [BillGroup] in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            var out: [BillGroup] = []
            while try stmt.hasNext() {
                out.append(Self.decode(stmt))
            }
            return out
        }
    }

    private static func decode(_ s: PreparedStatement) -> BillGroup {
        BillGroup(
            id: s.columnText(0),
            name: s.columnText(1),
            emoji: s.columnText(2),
            note: s.columnTextOrNil(3),
            sortOrder: s.columnInt(4),
            isDefault: s.columnInt(5) != 0,
            createdAt: s.columnDate(6),
            updatedAt: s.columnDate(7),
            deletedAt: s.columnDateOrNil(8)
        )
    }
}
