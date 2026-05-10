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
struct Migration {
    let version: Int
    let description: String
    let statements: [String]
}

enum Migrations {

    /// 当前最新版本号。每次新增表/字段时 +1，并新增对应 Migration。
    static let latestVersion: Int = 3

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
            ]
        ),
        Migration(
            version: 3,
            description: "M9-Fix5: add merchant_channel to record (OCR 渠道单独列：微信/支付宝/抖音/银行/其他)",
            statements: [
                "ALTER TABLE record ADD COLUMN merchant_channel TEXT;"
            ]
        )
    ]

    /// 根据当前 user_version 返回需要执行的 migration 列表（已升序）。
    static func pending(currentVersion: Int) -> [Migration] {
        return all.filter { $0.version > currentVersion }
                  .sorted { $0.version < $1.version }
    }
}
