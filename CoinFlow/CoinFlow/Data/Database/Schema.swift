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
        source_kind       TEXT NOT NULL DEFAULT 'normal',
        settlement_status TEXT,
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

    // MARK: - v4 bills_summary（M10 LLM 周/月/年总结）

    /// 周/月/年 LLM 情绪化总结归档。
    /// - period_kind：week / month / year
    /// - period_start/end：UTC 秒（与 record.occurred_at 同语义），周/月/年起止
    /// - snapshot_json：喂给 LLM 的统计快照（用于"重新生成"）
    /// - summary_text：LLM 返回的完整 markdown
    /// - summary_digest：从 summary_text 抽出的 ≤30 字核心洞察（喂给历史对比）
    /// - feishu_doc_token / feishu_doc_url：飞书文档 token 与可访问 URL
    /// - feishu_sync_status：pending / synced / failed
    static let createBillsSummary = """
    CREATE TABLE IF NOT EXISTS bills_summary (
        id                  TEXT PRIMARY KEY,
        period_kind         TEXT NOT NULL,
        period_start        INTEGER NOT NULL,
        period_end          INTEGER NOT NULL,
        total_expense       TEXT NOT NULL,
        total_income        TEXT NOT NULL,
        record_count        INTEGER NOT NULL DEFAULT 0,
        snapshot_json       TEXT NOT NULL,
        summary_text        TEXT NOT NULL,
        summary_digest      TEXT NOT NULL DEFAULT '',
        llm_provider        TEXT NOT NULL,
        feishu_doc_token    TEXT,
        feishu_doc_url      TEXT,
        feishu_sync_status  TEXT NOT NULL DEFAULT 'pending',
        feishu_last_error   TEXT,
        created_at          INTEGER NOT NULL,
        updated_at          INTEGER NOT NULL,
        deleted_at          INTEGER
    );
    """

    /// 唯一索引：同 kind + 同周期起点全局唯一（含软删行）。
    ///
    /// **不使用 partial index**（去掉 `WHERE deleted_at IS NULL`）：
    /// SQLite 的 `ON CONFLICT(...) DO UPDATE` 子句要求目标必须匹配**完整**的
    /// 唯一约束，partial unique index 不被识别 → 抛 "ON CONFLICT clause does not
    /// match any PRIMARY KEY or UNIQUE constraint"。
    ///
    /// 语义：用户软删 summary 后再次生成同周期总结时，upsert 会**复活同行**
    /// （把 `deleted_at` 重置为 NULL），不再产生孤儿堆积。
    static let createBillsSummaryUniqIndex = """
    CREATE UNIQUE INDEX IF NOT EXISTS idx_bills_summary_period
        ON bills_summary(period_kind, period_start);
    """

    // MARK: - v6 AA 分账（M11）

    /// AA 分账成员表。每个成员归属一个 `type=aa` 的 ledger，承载昵称 / emoji 头像 /
    /// 支付状态。`status`：`pending`（默认）/ `paid`（用户已勾选"该成员已把钱给我了"）。
    static let createAAMember = """
    CREATE TABLE IF NOT EXISTS aa_member (
        id              TEXT PRIMARY KEY,
        ledger_id       TEXT NOT NULL REFERENCES ledger(id),
        name            TEXT NOT NULL,
        avatar_emoji    TEXT,
        status          TEXT NOT NULL DEFAULT 'pending',
        paid_at         INTEGER,
        sort_order      INTEGER NOT NULL DEFAULT 0,
        created_at      INTEGER NOT NULL,
        updated_at      INTEGER NOT NULL,
        deleted_at      INTEGER
    );
    """

    /// AA 分账：流水到成员的应付明细。一笔流水有 N 行，每行表示某成员对该笔的应付金额。
    /// `is_custom = 1` 表示用户在高级模式手动设置的金额（非平均分摊计算结果）。
    static let createAAShare = """
    CREATE TABLE IF NOT EXISTS aa_share (
        id              TEXT PRIMARY KEY,
        record_id       TEXT NOT NULL REFERENCES record(id),
        member_id       TEXT NOT NULL REFERENCES aa_member(id),
        amount          TEXT NOT NULL,
        is_custom       INTEGER NOT NULL DEFAULT 0,
        created_at      INTEGER NOT NULL,
        updated_at      INTEGER NOT NULL,
        deleted_at      INTEGER
    );
    """

    /// AA 成员名 + ledger 唯一（不含软删行：用 partial index）。
    /// 不参与 ON CONFLICT upsert，仅作为读取/校验防重复使用。
    static let createAAMemberUniqIndex = """
    CREATE UNIQUE INDEX IF NOT EXISTS idx_aa_member_ledger_name
        ON aa_member(ledger_id, name)
        WHERE deleted_at IS NULL;
    """

    /// 按 ledger 拉成员列表。
    static let createAAMemberLedgerIndex = """
    CREATE INDEX IF NOT EXISTS idx_aa_member_ledger
        ON aa_member(ledger_id)
        WHERE deleted_at IS NULL;
    """

    /// 按 record 拉分摊明细（流水分摊视图主查询路径）。
    static let createAAShareRecordIndex = """
    CREATE INDEX IF NOT EXISTS idx_aa_share_record
        ON aa_share(record_id)
        WHERE deleted_at IS NULL;
    """

    /// 按 member 聚合应付总额。
    static let createAAShareMemberIndex = """
    CREATE INDEX IF NOT EXISTS idx_aa_share_member
        ON aa_share(member_id)
        WHERE deleted_at IS NULL;
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
        "record", "quota_usage", "user_settings",
        "bills_summary",
        "aa_member", "aa_share"
    ]
}
