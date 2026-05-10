//  Schema.swift
//  CoinFlow · M1
//
//  按技术设计文档 §3.1 完整定义所有表的 DDL（ledger / category / record /
//  quota_usage / user_settings / voice_session）。
//
//  字段约束依据：
//  - B1 金额用 Decimal → SQLite TEXT 存 Decimal 字符串
//  - B2 时间存 UTC + IANA 时区
//  - B3 软删除：**所有业务表**带 deleted_at
//
//  关于 voice_session 不带 deleted_at 的说明：
//    voice_session 是**临时会话日志表**（非用户可见业务实体），一次录音 →
//    识别 → 完成/取消即结束，其 `status` 字段已含 `cancelled` 表达"终止"语义；
//    产品上不存在"恢复已删除会话"的场景，30 天回收站只对 record 这种用户
//    直接可见的业务数据有意义。因此 voice_session 采用 `status = cancelled`
//    替代软删除，不在本表引入 deleted_at 列。（设计决策：team-lead 同意，M1 验收）

import Foundation

/// 集中存放所有表 DDL；`Migrations` 按版本号串成升级序列。
enum Schema {

    // MARK: - v1 表定义

    static let createLedger = """
    CREATE TABLE IF NOT EXISTS ledger (
        id              TEXT PRIMARY KEY,
        name            TEXT NOT NULL,
        type            TEXT NOT NULL,
        firestore_path  TEXT,
        created_at      INTEGER NOT NULL,
        timezone        TEXT NOT NULL,
        archived_at     INTEGER,
        deleted_at      INTEGER
    );
    """

    static let createCategory = """
    CREATE TABLE IF NOT EXISTS category (
        id              TEXT PRIMARY KEY,
        name            TEXT NOT NULL,
        kind            TEXT NOT NULL,
        icon            TEXT NOT NULL,
        color_hex       TEXT NOT NULL,
        parent_id       TEXT,
        sort_order      INTEGER NOT NULL DEFAULT 0,
        is_preset       INTEGER NOT NULL DEFAULT 0,
        deleted_at      INTEGER
    );
    """

    static let createRecord = """
    CREATE TABLE IF NOT EXISTS record (
        id                TEXT PRIMARY KEY,
        ledger_id         TEXT NOT NULL REFERENCES ledger(id),
        category_id       TEXT NOT NULL REFERENCES category(id),
        amount            TEXT NOT NULL,
        currency          TEXT NOT NULL DEFAULT 'CNY',
        occurred_at       INTEGER NOT NULL,
        timezone          TEXT NOT NULL,
        note              TEXT,
        payer_user_id     TEXT,
        participants      TEXT,
        source            TEXT NOT NULL,
        ocr_confidence    REAL,
        voice_session_id  TEXT REFERENCES voice_session(id),
        missing_fields    TEXT,
        merchant_channel  TEXT,
        sync_status       TEXT NOT NULL DEFAULT 'pending',
        remote_id         TEXT,
        last_sync_error   TEXT,
        sync_attempts     INTEGER NOT NULL DEFAULT 0,
        attachment_local_path   TEXT,
        attachment_remote_token TEXT,
        created_at        INTEGER NOT NULL,
        updated_at        INTEGER NOT NULL,
        deleted_at        INTEGER
    );
    """

    static let createQuotaUsage = """
    CREATE TABLE IF NOT EXISTS quota_usage (
        month       TEXT NOT NULL,
        engine      TEXT NOT NULL,
        count       INTEGER NOT NULL DEFAULT 0,
        cost_cny    TEXT NOT NULL DEFAULT '0',
        PRIMARY KEY (month, engine)
    );
    """

    static let createUserSettings = """
    CREATE TABLE IF NOT EXISTS user_settings (
        key         TEXT PRIMARY KEY,
        value       TEXT NOT NULL,
        updated_at  INTEGER NOT NULL
    );
    """

    static let createVoiceSession = """
    CREATE TABLE IF NOT EXISTS voice_session (
        id              TEXT PRIMARY KEY,
        started_at      INTEGER NOT NULL,
        duration_sec    REAL NOT NULL,
        audio_path      TEXT,
        asr_engine      TEXT NOT NULL,
        asr_text        TEXT NOT NULL,
        asr_confidence  REAL,
        parser_engine   TEXT,
        parser_raw_json TEXT,
        parsed_count    INTEGER NOT NULL DEFAULT 0,
        confirmed_count INTEGER NOT NULL DEFAULT 0,
        status          TEXT NOT NULL,
        error           TEXT,
        created_at      INTEGER NOT NULL
    );
    """

    // MARK: - 索引

    static let createRecordLedgerTimeIndex = """
    CREATE INDEX IF NOT EXISTS idx_record_ledger_time
        ON record(ledger_id, occurred_at DESC)
        WHERE deleted_at IS NULL;
    """

    static let createRecordSyncStatusIndex = """
    CREATE INDEX IF NOT EXISTS idx_record_sync_status
        ON record(sync_status)
        WHERE sync_status IN ('pending','failed');
    """

    static let createVoiceSessionStatusIndex = """
    CREATE INDEX IF NOT EXISTS idx_voice_session_status
        ON voice_session(status, started_at DESC);
    """

    // MARK: - 聚合：v1 全部建表 + 索引语句

    /// 按依赖顺序排列：voice_session 必须先于 record（record 引用其 id）。
    static let allV1Statements: [String] = [
        createLedger,
        createCategory,
        createVoiceSession,
        createRecord,
        createQuotaUsage,
        createUserSettings,
        createRecordLedgerTimeIndex,
        createRecordSyncStatusIndex,
        createVoiceSessionStatusIndex
    ]

    /// 表名（按建表顺序，便于 `Schema.tableNames.count` 在启动页展示数量）。
    static let tableNames: [String] = [
        "ledger", "category", "voice_session",
        "record", "quota_usage", "user_settings"
    ]
}
