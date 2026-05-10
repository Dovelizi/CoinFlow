//  DatabaseManager.swift
//  CoinFlow · M3（SQLCipher 接入完成）
//
//  历程：
//  - M1：用 iOS 内建 `libsqlite3`，schema 就绪但**未加密**，密钥已生成存 Keychain；
//  - M3：接入官方 `sqlcipher/SQLCipher.swift` 4.10.0 SPM 包，`import SQLCipher` 后
//    所有 `sqlite3_*` 符号由 SQLCipher 提供，`PRAGMA key` 即可启用 256-bit AES。
//
//  约定：
//  - 密钥从 Keychain 读取（`AfterFirstUnlockThisDeviceOnly`，本地不跨设备）
//  - PRAGMA key 必须在 **任何其他 SQL** 之前执行（包括 journal_mode/foreign_keys）
//  - PRAGMA cipher_page_size 保持默认 4096（SQLCipher 4 的默认值，兼容历史库）
//
//  ⚠️ M1 产生的未加密 DB 文件如果存在，需要 M3 启动时检测并迁移。
//  **当前 MVP 尚无线上用户**，直接在首次检测到旧 DB 时删除重建即可；
//  方法：若第一次 `PRAGMA key` 后 `SELECT count(*) FROM sqlite_master` 失败
//  （SQLCipher 会报 "file is not a database"），则删掉文件重建空库。

import Foundation
import SQLCipher

/// SQLite 操作错误。
enum DatabaseError: Error, LocalizedError {
    case openFailed(code: Int32, message: String)
    case prepareFailed(sql: String, message: String)
    case stepFailed(sql: String, message: String)
    case keyGenerationFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .openFailed(let c, let m):       return "openFailed(\(c)): \(m)"
        case .prepareFailed(let sql, let m):  return "prepareFailed: \(m) | SQL=\(sql.prefix(120))…"
        case .stepFailed(let sql, let m):     return "stepFailed: \(m) | SQL=\(sql.prefix(120))…"
        case .keyGenerationFailed(let s):     return "keyGenerationFailed(OSStatus=\(s))"
        }
    }
}

final class DatabaseManager {

    // MARK: - Singleton

    static let shared = DatabaseManager()

    // MARK: - 文件路径

    /// DB 文件路径（Application Support 内）。public 便于启动页展示。
    let databaseURL: URL

    // MARK: - SQLite 句柄

    private var handle: OpaquePointer?

    /// 启动后已加载的 user_version（schema 版本号）。
    private(set) var currentSchemaVersion: Int = 0

    /// 所有表名（启动后查 sqlite_master 得到，用于自检与启动页展示）。
    private(set) var existingTableNames: [String] = []

    /// DB 句柄是否已就绪。HomeViewModel 等可读取以在 bootstrap 前避免抛错。
    /// - Note: 不代表 migration / seed 是否完成；更严格的"完全可用"信号由
    ///   `AppState.database == .ready` 提供。
    var isHandleOpen: Bool { handle != nil }

    // MARK: - Init

    private init() {
        // 1. 解析 DB 路径
        let fm = FileManager.default
        let appSupport = (try? fm.url(for: .applicationSupportDirectory,
                                      in: .userDomainMask,
                                      appropriateFor: nil,
                                      create: true))
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("CoinFlow", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.databaseURL = dir.appendingPathComponent("coinflow.sqlite")
    }

    // MARK: - Public API

    /// App 启动时调用一次：打开 DB → 应用密钥 → 跑 migration。
    /// 失败抛错由调用方决定 UX（M1 启动页直接展示错误信息）。
    @discardableResult
    func bootstrap() throws -> BootstrapResult {
        try openEncryptedOrMigrate()
        try migrateIfNeeded()
        try refreshTableSnapshot()
        return BootstrapResult(
            databasePath: databaseURL.path,
            schemaVersion: currentSchemaVersion,
            tableCount: existingTableNames.count,
            tableNames: existingTableNames
        )
    }

    struct BootstrapResult: Equatable {
        let databasePath: String
        let schemaVersion: Int
        let tableCount: Int
        let tableNames: [String]
    }

    // MARK: - SQLite 内部操作

    /// 打开加密 DB。策略：
    /// 1. 打开 sqlite 句柄
    /// 2. 立即执行 `PRAGMA key`（必须是第一条 SQL）
    /// 3. 探测 DB 是否可读：`SELECT count(*) FROM sqlite_master`
    /// 4. 若探测失败且文件存在 → 视为 M1 旧未加密 DB，删除重建（当前 MVP 无线上用户）
    /// 5. 可读则设置其他 PRAGMA（foreign_keys / journal_mode）
    private func openEncryptedOrMigrate() throws {
        guard handle == nil else { return }
        try openAndApplyKey()
        if !isKeyedDatabaseReadable() {
            // 旧的 M1 未加密 DB 或密钥不匹配；删除文件重建
            try closeHandle()
            try FileManager.default.removeItem(at: databaseURL)
            // WAL / SHM 伴生文件也要清理
            let wal = databaseURL.appendingPathExtension("wal")
            let shm = databaseURL.appendingPathExtension("shm")
            try? FileManager.default.removeItem(at: wal)
            try? FileManager.default.removeItem(at: shm)
            try openAndApplyKey()
        }
        // 主动读取 user_version 验证句柄可用；失败会抛
        _ = try readUserVersion()
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA journal_mode = WAL;")
    }

    private func openAndApplyKey() throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(databaseURL.path, &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let msg = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw DatabaseError.openFailed(code: rc, message: msg)
        }
        self.handle = db
        try applyEncryptionKey()
    }

    /// 执行 `PRAGMA key` 注入 256-bit 主密钥（SQLCipher）。
    /// 必须在**任何其他 SQL 之前**执行，否则 SQLCipher 会把库当未加密处理。
    private func applyEncryptionKey() throws {
        let key = try KeychainKeyStore.shared.databaseEncryptionKey()
        // SQLCipher `PRAGMA key = "x'<hex>'";` 是推荐的 raw-key 形式，避免 KDF
        // 二次派生；hex 长度应为 64（32 字节 * 2）。
        let hex = key.map { String(format: "%02x", $0) }.joined()
        // 注意：这里拼字符串是 SAFE 的 —— hex 来自 Keychain 随机二进制，字符集严格 [0-9a-f]，
        // 无用户可控输入路径；不适用参数化（PRAGMA 本身不支持 bind）。
        try execute("PRAGMA key = \"x'\(hex)'\";")
        try execute("PRAGMA cipher_page_size = 4096;")
    }

    /// 通过一次 `sqlite_master` 查询确认 PRAGMA key 是否匹配本 DB。
    private func isKeyedDatabaseReadable() -> Bool {
        guard let db = handle else { return false }
        var stmt: OpaquePointer?
        let sql = "SELECT count(*) FROM sqlite_master;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private func closeHandle() throws {
        if let db = handle {
            sqlite3_close(db)
            handle = nil
        }
    }

    private func migrateIfNeeded() throws {
        currentSchemaVersion = try readUserVersion()
        let pending = Migrations.pending(currentVersion: currentSchemaVersion)
        guard !pending.isEmpty else { return }
        for m in pending {
            try execute("BEGIN TRANSACTION;")
            do {
                for stmt in m.statements {
                    try execute(stmt)
                }
                try execute("PRAGMA user_version = \(m.version);")
                try execute("COMMIT;")
                currentSchemaVersion = m.version
            } catch {
                try? execute("ROLLBACK;")
                throw error
            }
        }
    }

    private func refreshTableSnapshot() throws {
        existingTableNames = try queryStringColumn(
            sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;",
            column: 0
        )
    }

    // MARK: - 低层执行助手（Repository 层共享）

    /// 无参执行 SQL（DDL / 无 bind 的语句）。Repository 用于 BEGIN / COMMIT / 清空等。
    func execute(_ sql: String) throws {
        guard let db = handle else {
            throw DatabaseError.openFailed(code: -1, message: "DB handle nil")
        }
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw DatabaseError.stepFailed(sql: sql, message: msg)
        }
    }

    /// 借用 sqlite3 handle 做 prepare/step/bind。保证 Repository 无需自己管理单例。
    /// 调用方必须在 block 内完成所有 sqlite3_* 调用，不得把 OpaquePointer 逃出作用域。
    func withHandle<T>(_ block: (OpaquePointer) throws -> T) throws -> T {
        guard let db = handle else {
            throw DatabaseError.openFailed(code: -1, message: "DB handle nil")
        }
        return try block(db)
    }

    private func readUserVersion() throws -> Int {
        guard let db = handle else { return 0 }
        var stmt: OpaquePointer?
        let sql = "PRAGMA user_version;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(sql: sql, message: msg)
        }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    private func queryStringColumn(sql: String, column: Int32) throws -> [String] {
        guard let db = handle else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(sql: sql, message: msg)
        }
        defer { sqlite3_finalize(stmt) }
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cstr = sqlite3_column_text(stmt, column) {
                out.append(String(cString: cstr))
            }
        }
        return out
    }
}

// MARK: - Keychain 密钥存储

/// 256-bit 随机数据库密钥的 Keychain 存取。
/// 访问性：`AfterFirstUnlockThisDeviceOnly`（文档 §11 要求；本地库密钥不跨设备）。
final class KeychainKeyStore {

    static let shared = KeychainKeyStore()
    private init() {}

    private let service = "com.lemolli.coinflow.app.dbkey"
    private let account = "default"

    /// 读取已有密钥；若不存在则生成新密钥并写入 Keychain。
    func databaseEncryptionKey() throws -> Data {
        if let existing = try readKey() {
            return existing
        }
        let new = try generateRandomKey(byteCount: 32) // 256-bit
        try writeKey(new)
        return new
    }

    private func readKey() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw DatabaseError.keyGenerationFailed(status: status)
        }
    }

    private func writeKey(_ data: Data) throws {
        let attrs: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
            kSecValueData as String:    data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = SecItemAdd(attrs as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // 可能因 App 卸载时 Keychain 未清理残留。兜底用 SecItemUpdate 覆盖写入。
            let query: [String: Any] = [
                kSecClass as String:        kSecClassGenericPassword,
                kSecAttrService as String:  service,
                kSecAttrAccount as String:  account
            ]
            let update: [String: Any] = [
                kSecValueData as String:    data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        }
        guard status == errSecSuccess else {
            throw DatabaseError.keyGenerationFailed(status: status)
        }
    }

    private func generateRandomKey(byteCount: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            throw DatabaseError.keyGenerationFailed(status: status)
        }
        return Data(bytes)
    }
}
