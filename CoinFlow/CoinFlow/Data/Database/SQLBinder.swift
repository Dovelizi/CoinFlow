//  SQLBinder.swift
//  CoinFlow · M3
//
//  sqlite3 C API 的 Swift 语义包装。Repository 层通过 `DatabaseManager.shared.withHandle`
//  拿到 handle 后用本类 bind / step / read。
//
//  设计约束：
//  - 所有 bind 使用参数化（SQL injection 零容忍；文档安全规则）
//  - Decimal ↔ TEXT：借 `String(describing:)` 与 `Decimal(string:)`，严格零 Double 中转
//  - Date ↔ INTEGER：Unix 秒（UTC），符合 B2

import Foundation
import SQLCipher

/// `sqlite3_bind_text` 需要一个在 bind 期间仍然有效的字节缓冲。
/// 推荐传 `SQLITE_TRANSIENT` 让 SQLite 自己 copy，避免 Swift String 生命周期问题。
let SQLITE_TRANSIENT_DESTRUCTOR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 预编译的 SQLite statement 封装。用 defer { finalize() } 确保释放。
final class PreparedStatement {
    private let handle: OpaquePointer
    private(set) var stmt: OpaquePointer?
    let sql: String

    init(sql: String, handle: OpaquePointer) throws {
        self.handle = handle
        self.sql = sql
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &s, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(sql: sql, message: msg)
        }
        self.stmt = s
    }

    deinit {
        if let stmt { sqlite3_finalize(stmt) }
    }

    // MARK: - Bind (1-indexed per SQLite spec)

    func bind(_ index: Int32, _ value: String?) {
        guard let stmt else { return }
        if let v = value {
            sqlite3_bind_text(stmt, index, v, -1, SQLITE_TRANSIENT_DESTRUCTOR)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    func bind(_ index: Int32, _ value: Int?) {
        guard let stmt else { return }
        if let v = value {
            sqlite3_bind_int64(stmt, index, sqlite3_int64(v))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    func bind(_ index: Int32, _ value: Double?) {
        guard let stmt else { return }
        if let v = value {
            sqlite3_bind_double(stmt, index, v)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    /// Bool → INTEGER (0/1)
    func bind(_ index: Int32, _ value: Bool) {
        guard let stmt else { return }
        sqlite3_bind_int(stmt, index, value ? 1 : 0)
    }

    /// Date → Unix 秒（UTC）
    func bind(_ index: Int32, _ value: Date?) {
        bind(index, value.map { Int($0.timeIntervalSince1970) })
    }

    /// Decimal → TEXT（禁止 Double 中转，B1）
    func bind(_ index: Int32, _ value: Decimal?) {
        bind(index, value.map { "\($0)" })
    }

    /// 任意 Encodable → JSON TEXT（用于 `participants`, `missing_fields` 等数组列）
    func bindJSON<T: Encodable>(_ index: Int32, _ value: T?) throws {
        guard let v = value else { bind(index, nil as String?); return }
        let data = try JSONEncoder().encode(v)
        guard let json = String(data: data, encoding: .utf8) else {
            bind(index, nil as String?); return
        }
        bind(index, json)
    }

    // MARK: - Step

    /// 执行 DML，不返回行。
    @discardableResult
    func stepDone() throws -> Int32 {
        guard let stmt else { throw DatabaseError.stepFailed(sql: sql, message: "stmt nil") }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.stepFailed(sql: sql, message: msg)
        }
        return rc
    }

    /// 读一行，回调消费 row reader；返回是否还有下一行。
    func hasNext() throws -> Bool {
        guard let stmt else { throw DatabaseError.stepFailed(sql: sql, message: "stmt nil") }
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_ROW { return true }
        if rc == SQLITE_DONE { return false }
        let msg = String(cString: sqlite3_errmsg(handle))
        throw DatabaseError.stepFailed(sql: sql, message: msg)
    }

    // MARK: - Column reads (0-indexed)

    func columnInt(_ col: Int32) -> Int {
        guard let stmt else { return 0 }
        return Int(sqlite3_column_int64(stmt, col))
    }

    func columnIntOrNil(_ col: Int32) -> Int? {
        guard let stmt else { return nil }
        if sqlite3_column_type(stmt, col) == SQLITE_NULL { return nil }
        return Int(sqlite3_column_int64(stmt, col))
    }

    func columnText(_ col: Int32) -> String {
        guard let stmt, let c = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: c)
    }

    func columnTextOrNil(_ col: Int32) -> String? {
        guard let stmt else { return nil }
        if sqlite3_column_type(stmt, col) == SQLITE_NULL { return nil }
        guard let c = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: c)
    }

    func columnDouble(_ col: Int32) -> Double {
        guard let stmt else { return 0 }
        return sqlite3_column_double(stmt, col)
    }

    func columnDoubleOrNil(_ col: Int32) -> Double? {
        guard let stmt else { return nil }
        if sqlite3_column_type(stmt, col) == SQLITE_NULL { return nil }
        return sqlite3_column_double(stmt, col)
    }

    func columnBool(_ col: Int32) -> Bool { columnInt(col) != 0 }

    func columnDate(_ col: Int32) -> Date {
        Date(timeIntervalSince1970: TimeInterval(columnInt(col)))
    }

    func columnDateOrNil(_ col: Int32) -> Date? {
        columnIntOrNil(col).map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    /// TEXT → Decimal（B1：永不 Double 中转）
    func columnDecimal(_ col: Int32) -> Decimal {
        let s = columnText(col)
        return Decimal(string: s) ?? 0
    }

    /// JSON TEXT → Decodable
    func columnJSON<T: Decodable>(_ col: Int32, as type: T.Type) -> T? {
        guard let s = columnTextOrNil(col), !s.isEmpty,
              let data = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
