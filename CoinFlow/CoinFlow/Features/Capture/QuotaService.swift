//  QuotaService.swift
//  CoinFlow · M4 · §7.2
//
//  配额管理：
//  - 月度计数 quota_usage(month, engine, count, cost_cny)
//  - canUse(engine): 如果未达月度上限返回 true
//  - increment(engine): +1 计数
//
//  上限默认值（M4 mock）：
//  - ocr_api: 100/月
//  - ocr_llm: 30/月
//  - asr_cloud: 200/月
//  - llm_parser: 50/月

import Foundation
import SQLCipher

enum QuotaEngine: String {
    case ocrAPI     = "ocr_api"
    case ocrLLM     = "ocr_llm"
    case asrCloud   = "asr_cloud"
    case llmParser  = "llm_parser"

    var monthlyLimit: Int {
        switch self {
        case .ocrAPI:    return 100
        case .ocrLLM:    return 30
        case .asrCloud:  return 200
        case .llmParser: return 50
        }
    }
}

final class QuotaService {

    static let shared = QuotaService()
    private init() {}

    private let db = DatabaseManager.shared

    private static var currentMonthKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }

    /// 当月计数。无记录则 0。
    func currentCount(_ engine: QuotaEngine) -> Int {
        let sql = "SELECT count FROM quota_usage WHERE month = ? AND engine = ?;"
        return (try? db.withHandle { handle -> Int in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, Self.currentMonthKey)
            stmt.bind(2, engine.rawValue)
            return try stmt.hasNext() ? stmt.columnInt(0) : 0
        }) ?? 0
    }

    func canUse(_ engine: QuotaEngine) -> Bool {
        currentCount(engine) < engine.monthlyLimit
    }

    /// +1。如不存在则插入；存在则 UPDATE count = count + 1，cost_cny 用 Decimal 字符串累加。
    /// （M6: 移除原 ON CONFLICT 中 CAST AS REAL 的精度损失；改为 BEGIN IMMEDIATE 事务保护的 RMW）
    func increment(_ engine: QuotaEngine, costCny: Decimal = 0) {
        try? db.withHandle { handle in
            // 用 BEGIN IMMEDIATE 防止并发 RMW 丢增量（SyncQueue / 后台任务场景）
            guard sqlite3_exec(handle, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else {
                return
            }
            defer {
                // 默认 COMMIT；任何一步出错 goto rollback
            }
            do {
                // 1. 读当前 cost
                let selectSQL = "SELECT cost_cny FROM quota_usage WHERE month = ? AND engine = ?;"
                let sel = try PreparedStatement(sql: selectSQL, handle: handle)
                sel.bind(1, Self.currentMonthKey)
                sel.bind(2, engine.rawValue)
                let existingCost: Decimal = (try sel.hasNext())
                    ? (Decimal(string: sel.columnText(0)) ?? 0)
                    : 0
                let newCost = existingCost + costCny

                // 2. UPSERT（cost 已经在 Swift 层算好，避免 SQL 浮点累加）
                let upsertSQL = """
                INSERT INTO quota_usage (month, engine, count, cost_cny)
                VALUES (?, ?, 1, ?)
                ON CONFLICT(month, engine) DO UPDATE SET
                  count = count + 1,
                  cost_cny = ?;
                """
                let stmt = try PreparedStatement(sql: upsertSQL, handle: handle)
                stmt.bind(1, Self.currentMonthKey)
                stmt.bind(2, engine.rawValue)
                stmt.bind(3, "\(costCny)")
                stmt.bind(4, "\(newCost)")
                try stmt.stepDone()

                sqlite3_exec(handle, "COMMIT;", nil, nil, nil)
            } catch {
                sqlite3_exec(handle, "ROLLBACK;", nil, nil, nil)
                throw error
            }
        }
    }

    /// 当月累计成本（CNY）；用于设置页"本月配额"展示。
    func currentCost(_ engine: QuotaEngine) -> Decimal {
        let sql = "SELECT cost_cny FROM quota_usage WHERE month = ? AND engine = ?;"
        return (try? db.withHandle { handle -> Decimal in
            let stmt = try PreparedStatement(sql: sql, handle: handle)
            stmt.bind(1, Self.currentMonthKey)
            stmt.bind(2, engine.rawValue)
            return try stmt.hasNext() ? (Decimal(string: stmt.columnText(0)) ?? 0) : 0
        }) ?? 0
    }
}
