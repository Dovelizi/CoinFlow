//  CategoryRepository.swift
//  CoinFlow · M3

import Foundation
import SQLCipher

protocol CategoryRepository {
    func insert(_ category: Category) throws
    func update(_ category: Category) throws
    func delete(id: String) throws
    func find(id: String) throws -> Category?
    func list(kind: CategoryKind?, includeDeleted: Bool) throws -> [Category]
}

final class SQLiteCategoryRepository: CategoryRepository {

    static let shared = SQLiteCategoryRepository()
    private init() {}

    private let db = DatabaseManager.shared

    private static let columns = """
    id, name, kind, icon, color_hex, parent_id, sort_order, is_preset, deleted_at
    """

    // MARK: - Insert

    func insert(_ category: Category) throws {
        let sql = """
        INSERT INTO category (\(Self.columns))
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, category.id)
            stmt.bind(2, category.name)
            stmt.bind(3, category.kind.rawValue)
            stmt.bind(4, category.icon)
            stmt.bind(5, category.colorHex)
            stmt.bind(6, category.parentId)
            stmt.bind(7, category.sortOrder)
            stmt.bind(8, category.isPreset)
            stmt.bind(9, category.deletedAt)
            try stmt.stepDone()
        }
    }

    // MARK: - Update

    func update(_ category: Category) throws {
        let sql = """
        UPDATE category SET
          name = ?, kind = ?, icon = ?, color_hex = ?, parent_id = ?,
          sort_order = ?, is_preset = ?, deleted_at = ?
        WHERE id = ?;
        """
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, category.name)
            stmt.bind(2, category.kind.rawValue)
            stmt.bind(3, category.icon)
            stmt.bind(4, category.colorHex)
            stmt.bind(5, category.parentId)
            stmt.bind(6, category.sortOrder)
            stmt.bind(7, category.isPreset)
            stmt.bind(8, category.deletedAt)
            stmt.bind(9, category.id)
            try stmt.stepDone()
        }
    }

    // MARK: - Delete（软删，预设分类不可删由业务层拦截）

    func delete(id: String) throws {
        try db.withHandle { handle in
            let stmt = try PreparedStatement(
                sql: "UPDATE category SET deleted_at = ? WHERE id = ? AND is_preset = 0;",
                handle: handle
            )
            stmt.bind(1, Date())
            stmt.bind(2, id)
            try stmt.stepDone()
        }
    }

    // MARK: - Read

    func find(id: String) throws -> Category? {
        let sql = "SELECT \(Self.columns) FROM category WHERE id = ? LIMIT 1;"
        return try db.withHandle { handle -> Category? in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, id)
            if try stmt.hasNext() {
                return Self.decode(stmt)
            }
            return nil
        }
    }

    func list(kind: CategoryKind?, includeDeleted: Bool) throws -> [Category] {
        // 改为参数化绑定，彻底消除字符串拼接（白名单 precondition 仍保留作为运行时防御）
        let kindClause = kind == nil ? "" : "AND kind = ?"
        let deletedClause = includeDeleted ? "" : "AND deleted_at IS NULL"
        let sql = """
        SELECT \(Self.columns) FROM category
        WHERE 1=1 \(kindClause) \(deletedClause)
        ORDER BY sort_order ASC, name ASC;
        """
        return try db.withHandle { handle -> [Category] in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            if let k = kind {
                let raw = k.rawValue
                precondition(raw == "income" || raw == "expense",
                             "CategoryKind raw value must be whitelisted")
                stmt.bind(1, raw)
            }
            var out: [Category] = []
            while try stmt.hasNext() {
                out.append(Self.decode(stmt))
            }
            return out
        }
    }

    // MARK: - Decode

    private static func decode(_ s: PreparedStatement) -> Category {
        Category(
            id: s.columnText(0),
            name: s.columnText(1),
            kind: CategoryKind(rawValue: s.columnText(2)) ?? .expense,
            icon: s.columnText(3),
            colorHex: s.columnText(4),
            parentId: s.columnTextOrNil(5),
            sortOrder: s.columnInt(6),
            isPreset: s.columnBool(7),
            deletedAt: s.columnDateOrNil(8)
        )
    }
}
