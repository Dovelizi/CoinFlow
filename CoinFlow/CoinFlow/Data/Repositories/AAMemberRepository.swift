//  AAMemberRepository.swift
//  CoinFlow · M11 — AA 分账成员仓库

import Foundation
import SQLCipher

protocol AAMemberRepository {
    func insert(_ member: AAMember) throws
    func update(_ member: AAMember) throws
    func softDelete(id: String) throws
    func find(id: String) throws -> AAMember?
    func list(ledgerId: String) throws -> [AAMember]
    /// 计某账本下处于 status 的成员数（不含软删行）。
    func count(ledgerId: String, status: AAMemberStatus) throws -> Int
}

final class SQLiteAAMemberRepository: AAMemberRepository {

    static let shared = SQLiteAAMemberRepository()
    private init() {}

    private let db = DatabaseManager.shared

    private static let columns = """
    id, ledger_id, name, avatar_emoji, status, paid_at, sort_order,
    created_at, updated_at, deleted_at
    """

    func insert(_ member: AAMember) throws {
        let sql = """
        INSERT INTO aa_member (\(Self.columns))
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, member.id)
            stmt.bind(2, member.ledgerId)
            stmt.bind(3, member.name)
            stmt.bind(4, member.avatarEmoji)
            stmt.bind(5, member.status.rawValue)
            stmt.bind(6, member.paidAt)
            stmt.bind(7, member.sortOrder)
            stmt.bind(8, member.createdAt)
            stmt.bind(9, member.updatedAt)
            stmt.bind(10, member.deletedAt)
            try stmt.stepDone()
        }
    }

    func update(_ member: AAMember) throws {
        let sql = """
        UPDATE aa_member SET
          name = ?, avatar_emoji = ?, status = ?, paid_at = ?,
          sort_order = ?, updated_at = ?, deleted_at = ?
        WHERE id = ?;
        """
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, member.name)
            stmt.bind(2, member.avatarEmoji)
            stmt.bind(3, member.status.rawValue)
            stmt.bind(4, member.paidAt)
            stmt.bind(5, member.sortOrder)
            stmt.bind(6, Date())
            stmt.bind(7, member.deletedAt)
            stmt.bind(8, member.id)
            try stmt.stepDone()
        }
    }

    func softDelete(id: String) throws {
        try db.withHandle { handle in
            let stmt = try PreparedStatement(
                sql: "UPDATE aa_member SET deleted_at = ?, updated_at = ? WHERE id = ?;",
                handle: handle
            )
            let now = Date()
            stmt.bind(1, now)
            stmt.bind(2, now)
            stmt.bind(3, id)
            try stmt.stepDone()
        }
    }

    func find(id: String) throws -> AAMember? {
        let sql = "SELECT \(Self.columns) FROM aa_member WHERE id = ? LIMIT 1;"
        return try db.withHandle { handle -> AAMember? in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, id)
            if try stmt.hasNext() {
                return Self.decode(stmt)
            }
            return nil
        }
    }

    func list(ledgerId: String) throws -> [AAMember] {
        let sql = """
        SELECT \(Self.columns) FROM aa_member
        WHERE ledger_id = ? AND deleted_at IS NULL
        ORDER BY sort_order ASC, created_at ASC;
        """
        return try db.withHandle { handle -> [AAMember] in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, ledgerId)
            var out: [AAMember] = []
            while try stmt.hasNext() {
                out.append(Self.decode(stmt))
            }
            return out
        }
    }

    func count(ledgerId: String, status: AAMemberStatus) throws -> Int {
        let sql = """
        SELECT COUNT(*) FROM aa_member
        WHERE ledger_id = ? AND status = ? AND deleted_at IS NULL;
        """
        return try db.withHandle { handle -> Int in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, ledgerId)
            stmt.bind(2, status.rawValue)
            return try stmt.hasNext() ? stmt.columnInt(0) : 0
        }
    }

    private static func decode(_ s: PreparedStatement) -> AAMember {
        AAMember(
            id: s.columnText(0),
            ledgerId: s.columnText(1),
            name: s.columnText(2),
            avatarEmoji: s.columnTextOrNil(3),
            status: AAMemberStatus(rawValue: s.columnText(4)) ?? .pending,
            paidAt: s.columnDateOrNil(5),
            sortOrder: s.columnInt(6),
            createdAt: s.columnDate(7),
            updatedAt: s.columnDate(8),
            deletedAt: s.columnDateOrNil(9)
        )
    }
}
