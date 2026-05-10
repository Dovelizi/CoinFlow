//  UserSettingsRepository.swift
//  CoinFlow · M6 · §3.1 user_settings
//
//  键值表 CRUD：(key TEXT PK, value TEXT, updated_at INTEGER)
//
//  典型 key（约定，不需要 schema 约束）：
//    security.biometric_enabled       = "true" / "false"
//    voice.required_fields            = JSON 数组 (e.g. ["amount","occurred_at","direction"])
//    privacy.shield_on_inactive       = "true" / "false"
//    asr.preferred_engine             = "local" / "cloud"
//
//  设计：
//  - 无业务实体语义 → 不带软删除
//  - value 一律 TEXT，调用方负责类型转换（JSON 用 Codable 帮手）
//  - SQL 全参数化

import Foundation
import SQLCipher

protocol UserSettingsRepository {
    func get(key: String) -> String?
    func set(key: String, value: String)
    func remove(key: String)
    /// JSON 帮手：编/解码 Codable 类型
    func getJSON<T: Decodable>(key: String, as type: T.Type) -> T?
    func setJSON<T: Encodable>(key: String, value: T)
}

final class SQLiteUserSettingsRepository: UserSettingsRepository {

    static let shared = SQLiteUserSettingsRepository()
    private init() {}

    private let db = DatabaseManager.shared

    // MARK: - Get / Set

    func get(key: String) -> String? {
        let sql = "SELECT value FROM user_settings WHERE key = ? LIMIT 1;"
        return (try? db.withHandle { handle -> String? in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, key)
            return try stmt.hasNext() ? stmt.columnTextOrNil(0) : nil
        }) ?? nil
    }

    func set(key: String, value: String) {
        let upsert = """
        INSERT INTO user_settings (key, value, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;
        """
        try? db.withHandle { handle in
            let stmt = try PreparedStatement(sql: upsert, handle: handle)
            stmt.bind(1, key)
            stmt.bind(2, value)
            stmt.bind(3, Date())
            try stmt.stepDone()
        }
    }

    func remove(key: String) {
        try? db.withHandle { handle in
            let stmt = try PreparedStatement(
                sql: "DELETE FROM user_settings WHERE key = ?;",
                handle: handle
            )
            stmt.bind(1, key)
            try stmt.stepDone()
        }
    }

    // MARK: - JSON helpers

    func getJSON<T: Decodable>(key: String, as type: T.Type) -> T? {
        guard let s = get(key: key), let data = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func setJSON<T: Encodable>(key: String, value: T) {
        guard let data = try? JSONEncoder().encode(value),
              let s = String(data: data, encoding: .utf8) else { return }
        set(key: key, value: s)
    }
}

// MARK: - 类型化键访问器（避免拼写错误）

enum SettingsKey {
    static let biometricEnabled    = "security.biometric_enabled"
    static let voiceRequiredFields = "voice.required_fields"
    static let privacyShieldOnInactive = "privacy.shield_on_inactive"
    static let asrPreferredEngine  = "asr.preferred_engine"
    static let backTapEnabled      = "record.back_tap_enabled"
    /// 流水列表布局：list / stack / grid（统一全页一种布局，从段头切换器迁移而来）
    static let recordsListLayout   = "records.list_layout"
    /// M7 [13-1]：首次启动引导完成标志。UserDefaults 镜像 `onboarding.completed_mirror`。
    static let onboardingCompleted = "onboarding.completed"
    /// Dark Glass 设置页"加入 N 天"副标题数据源。
    /// AppState.bootstrap() 在首次启动时写入 UTC 毫秒时间戳；SettingsView 读取计算天数差。
    static let firstLaunchDate     = "profile.first_launch_date"
}

// MARK: - 便捷 API（Bool / String 常用值）

extension SQLiteUserSettingsRepository {
    /// 兼容性解码：true / 1 / yes（大小写不敏感）都视作 true，其他视作 false。
    /// 历史数据回滚 / 手工编辑场景更鲁棒。
    func bool(_ key: String, default defaultValue: Bool = false) -> Bool {
        guard let s = get(key: key)?.lowercased() else { return defaultValue }
        return ["true", "1", "yes"].contains(s)
    }

    func setBool(_ key: String, _ value: Bool) {
        set(key: key, value: value ? "true" : "false")
    }
}
