//  Migrations.swift
//  CoinFlow · M1
//
//  数据库版本号管理：通过 PRAGMA user_version 持久化当前 schema 版本。
//  v1 = 初始建表（§3.1 全部 6 张表 + 索引）。
//
//  约定：
//  - 每个 Migration 必须幂等（包含 IF NOT EXISTS / 容错处理）
//  - 升级失败时整个 migrate() 抛错，DatabaseManager 决定降级策略

import Foundation

/// 一次升级所执行的 SQL 语句序列。
/// - `tolerateDuplicateColumn`：容忍 "duplicate column name" 错误。
///    用于 ALTER TABLE ADD COLUMN：物理列已存在但 user_version 滞后的脏环境（开发期模拟器
///    重装、测试环境状态污染）下可幂等跳过；不影响生产真实首次安装的行为。
struct Migration {
    let version: Int
    let description: String
    let statements: [String]
    let tolerateDuplicateColumn: Bool

    init(version: Int,
         description: String,
         statements: [String],
         tolerateDuplicateColumn: Bool = false) {
        self.version = version
        self.description = description
        self.statements = statements
        self.tolerateDuplicateColumn = tolerateDuplicateColumn
    }
}

enum Migrations {

    /// 当前最新版本号。每次新增表/字段时 +1，并新增对应 Migration。
    static let latestVersion: Int = 5

    /// 全部已知 migration（按版本号升序）。
    static let all: [Migration] = [
        Migration(
            version: 1,
            description: "Initial schema: ledger / category / record / quota_usage / user_settings / voice_session",
            statements: Schema.allV1Statements
        ),
        Migration(
            version: 2,
            description: "M9-Fix4: add attachment_local_path / attachment_remote_token to record (OCR 截图归档)",
            statements: [
                "ALTER TABLE record ADD COLUMN attachment_local_path TEXT;",
                "ALTER TABLE record ADD COLUMN attachment_remote_token TEXT;"
            ],
            tolerateDuplicateColumn: true
        ),
        Migration(
            version: 3,
            description: "M9-Fix5: add merchant_channel to record (OCR 渠道单独列：微信/支付宝/抖音/银行/其他)",
            statements: [
                "ALTER TABLE record ADD COLUMN merchant_channel TEXT;"
            ],
            tolerateDuplicateColumn: true
        ),
        Migration(
            version: 4,
            description: "M10: bills_summary 表（LLM 周/月/年情绪化总结归档 + 飞书文档同步状态）",
            statements: [
                Schema.createBillsSummary,
                Schema.createBillsSummaryUniqIndex
            ]
        ),
        Migration(
            version: 5,
            description: "M10-Fix1: 修复 bills_summary 唯一索引（partial → full）。"
                       + "原 partial 索引带 WHERE deleted_at IS NULL，"
                       + "SQLite ON CONFLICT 无法识别 partial 索引导致 upsert 失败。",
            statements: [
                "DROP INDEX IF EXISTS idx_bills_summary_period;",
                Schema.createBillsSummaryUniqIndex
            ]
        )
    ]

    /// 根据当前 user_version 返回需要执行的 migration 列表（已升序）。
    static func pending(currentVersion: Int) -> [Migration] {
        return all.filter { $0.version > currentVersion }
                  .sorted { $0.version < $1.version }
    }
}
