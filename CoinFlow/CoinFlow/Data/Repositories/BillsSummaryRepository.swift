//  BillsSummaryRepository.swift
//  CoinFlow · M10
//
//  bills_summary 表 CRUD。SQL 全参数化（B 安全规则）。
//
//  关键约定：
//  - upsert(by: periodKind + periodStart)：用户主动"重新生成"时走 UPDATE 而不是建新条
//  - listRecent(kind:limit:)：用于 PromptBuilder 喂"历史摘要"
//  - listAll：SettingsView / DetailView 列表展示

import Foundation
import SQLCipher

protocol BillsSummaryRepository {
    /// 按 period_kind + period_start 唯一索引 upsert。
    func upsert(_ summary: BillsSummary) throws

    /// 按 id 查找单条。
    func find(id: String) throws -> BillsSummary?

    /// 查找指定周期是否已存在。返回非 nil = 已生成，UI 可直接展示无需再调 LLM。
    func find(kind: BillsSummaryPeriodKind, periodStart: Date) throws -> BillsSummary?

    /// 取同 kind 最近 N 条（按 period_start 降序），用于历史对比 prompt。
    func listRecent(kind: BillsSummaryPeriodKind, limit: Int) throws -> [BillsSummary]

    /// 取全部（按 period_start 降序）。UI 列表用。
    func listAll(includesDeleted: Bool) throws -> [BillsSummary]

    /// 软删（仅写 deleted_at）。
    func softDelete(id: String) throws

    /// 同步元数据更新（不改 summary_text）。
    func updateFeishuSync(id: String,
                         status: BillsSummaryFeishuStatus,
                         docToken: String?,
                         docURL: String?,
                         error: String?) throws
}

final class SQLiteBillsSummaryRepository: BillsSummaryRepository {

    static let shared = SQLiteBillsSummaryRepository()
    private init() {}

    private let db = DatabaseManager.shared

    /// 与 Schema.createBillsSummary DDL 严格一致。读列索引（0-based）按此顺序。
    private static let columns = """
    id, period_kind, period_start, period_end,
    total_expense, total_income, record_count,
    snapshot_json, summary_text, summary_digest, llm_provider,
    feishu_doc_token, feishu_doc_url, feishu_sync_status, feishu_last_error,
    created_at, updated_at, deleted_at
    """

    // MARK: - Upsert

    func upsert(_ s: BillsSummary) throws {
        // 走 (period_kind, period_start) 唯一索引（非 partial，含已软删行）。
        // 软删记录撞键时 ON CONFLICT 会复活该行（重置 deleted_at = NULL）；
        // 与"用户软删后再次生成同周期不应堆积新行"的语义一致。
        let sql = """
        INSERT INTO bills_summary (\(Self.columns))
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(period_kind, period_start) DO UPDATE SET
            period_end         = excluded.period_end,
            total_expense      = excluded.total_expense,
            total_income       = excluded.total_income,
            record_count       = excluded.record_count,
            snapshot_json      = excluded.snapshot_json,
            summary_text       = excluded.summary_text,
            summary_digest     = excluded.summary_digest,
            llm_provider       = excluded.llm_provider,
            feishu_doc_token   = excluded.feishu_doc_token,
            feishu_doc_url     = excluded.feishu_doc_url,
            feishu_sync_status = excluded.feishu_sync_status,
            feishu_last_error  = excluded.feishu_last_error,
            updated_at         = excluded.updated_at,
            deleted_at         = NULL;
        """
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            try Self.bindAll(stmt, s)
            try stmt.stepDone()
        }
    }

    // MARK: - Find

    func find(id: String) throws -> BillsSummary? {
        let sql = """
        SELECT \(Self.columns) FROM bills_summary
        WHERE id = ? AND deleted_at IS NULL LIMIT 1;
        """
        return try db.withHandle { handle -> BillsSummary? in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, id)
            return try stmt.hasNext() ? Self.decode(stmt) : nil
        }
    }

    func find(kind: BillsSummaryPeriodKind, periodStart: Date) throws -> BillsSummary? {
        let sql = """
        SELECT \(Self.columns) FROM bills_summary
        WHERE period_kind = ? AND period_start = ? AND deleted_at IS NULL LIMIT 1;
        """
        return try db.withHandle { handle -> BillsSummary? in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, kind.rawValue)
            stmt.bind(2, periodStart)
            return try stmt.hasNext() ? Self.decode(stmt) : nil
        }
    }

    // MARK: - List

    func listRecent(kind: BillsSummaryPeriodKind, limit: Int) throws -> [BillsSummary] {
        precondition(limit > 0 && limit <= 50, "limit out of safe range")
        let sql = """
        SELECT \(Self.columns) FROM bills_summary
        WHERE period_kind = ? AND deleted_at IS NULL
        ORDER BY period_start DESC LIMIT ?;
        """
        return try db.withHandle { handle -> [BillsSummary] in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, kind.rawValue)
            stmt.bind(2, limit)
            var out: [BillsSummary] = []
            while try stmt.hasNext() { out.append(Self.decode(stmt)) }
            return out
        }
    }

    func listAll(includesDeleted: Bool) throws -> [BillsSummary] {
        let whereClause = includesDeleted ? "1=1" : "deleted_at IS NULL"
        let sql = """
        SELECT \(Self.columns) FROM bills_summary
        WHERE \(whereClause)
        ORDER BY period_start DESC;
        """
        return try db.withHandle { handle -> [BillsSummary] in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            var out: [BillsSummary] = []
            while try stmt.hasNext() { out.append(Self.decode(stmt)) }
            return out
        }
    }

    // MARK: - Mutations

    func softDelete(id: String) throws {
        let sql = "UPDATE bills_summary SET deleted_at = ?, updated_at = ? WHERE id = ?;"
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, Date())
            stmt.bind(2, Date())
            stmt.bind(3, id)
            try stmt.stepDone()
        }
    }

    func updateFeishuSync(id: String,
                         status: BillsSummaryFeishuStatus,
                         docToken: String?,
                         docURL: String?,
                         error: String?) throws {
        let sql = """
        UPDATE bills_summary SET
            feishu_sync_status = ?,
            feishu_doc_token   = ?,
            feishu_doc_url     = ?,
            feishu_last_error  = ?,
            updated_at         = ?
        WHERE id = ?;
        """
        try db.withHandle { handle in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, status.rawValue)
            stmt.bind(2, docToken)
            stmt.bind(3, docURL)
            stmt.bind(4, error)
            stmt.bind(5, Date())
            stmt.bind(6, id)
            try stmt.stepDone()
        }
    }

    // MARK: - Bind / Decode

    private static func bindAll(_ stmt: PreparedStatement, _ s: BillsSummary) throws {
        stmt.bind(1, s.id)
        stmt.bind(2, s.periodKind.rawValue)
        stmt.bind(3, s.periodStart)
        stmt.bind(4, s.periodEnd)
        stmt.bind(5, s.totalExpense)
        stmt.bind(6, s.totalIncome)
        stmt.bind(7, s.recordCount)
        stmt.bind(8, s.snapshotJSON)
        stmt.bind(9, s.summaryText)
        stmt.bind(10, s.summaryDigest)
        stmt.bind(11, s.llmProvider)
        stmt.bind(12, s.feishuDocToken)
        stmt.bind(13, s.feishuDocURL)
        stmt.bind(14, s.feishuSyncStatus.rawValue)
        stmt.bind(15, s.feishuLastError)
        stmt.bind(16, s.createdAt)
        stmt.bind(17, s.updatedAt)
        stmt.bind(18, s.deletedAt)
    }

    private static func decode(_ stmt: PreparedStatement) -> BillsSummary {
        let kindRaw = stmt.columnText(1)
        let kind = BillsSummaryPeriodKind(rawValue: kindRaw) ?? .week
        let statusRaw = stmt.columnText(13)
        let status = BillsSummaryFeishuStatus(rawValue: statusRaw) ?? .pending
        return BillsSummary(
            id: stmt.columnText(0),
            periodKind: kind,
            periodStart: stmt.columnDate(2),
            periodEnd: stmt.columnDate(3),
            totalExpense: stmt.columnDecimal(4),
            totalIncome: stmt.columnDecimal(5),
            recordCount: stmt.columnInt(6),
            snapshotJSON: stmt.columnText(7),
            summaryText: stmt.columnText(8),
            summaryDigest: stmt.columnText(9),
            llmProvider: stmt.columnText(10),
            feishuDocToken: stmt.columnTextOrNil(11),
            feishuDocURL: stmt.columnTextOrNil(12),
            feishuSyncStatus: status,
            feishuLastError: stmt.columnTextOrNil(14),
            createdAt: stmt.columnDate(15),
            updatedAt: stmt.columnDate(16),
            deletedAt: stmt.columnDateOrNil(17)
        )
    }
}
