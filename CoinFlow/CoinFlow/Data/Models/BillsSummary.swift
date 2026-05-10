//  BillsSummary.swift
//  CoinFlow · M10 · 周/月/年 LLM 情绪化总结归档
//
//  对应 SQLite `bills_summary` 表（Schema.createBillsSummary）。
//  - period_kind：week / month / year
//  - period_start/end：UTC 秒（含端点）；周 = 周一 00:00:00 起 ~ 周日 23:59:59 止
//  - summary_text：LLM 返回的完整 markdown（Part1 + Part2）
//  - summary_digest：从 summary_text 抽取的 ≤30 字核心洞察，喂给历史对比省 token
//  - feishuSyncStatus：和 Record.syncStatus 同语义，但独立字段（不复用 SyncStatus 枚举
//    避免和 record 表的状态机交叉污染；这里只关心成功 / 失败 / 待推三态）

import Foundation

/// 总结周期类型。
enum BillsSummaryPeriodKind: String, Codable, CaseIterable {
    case week
    case month
    case year

    /// UI 标题。
    var displayName: String {
        switch self {
        case .week:  return "周"
        case .month: return "月"
        case .year:  return "年"
        }
    }
}

/// 飞书文档同步状态（独立于 record 表的 SyncStatus）。
enum BillsSummaryFeishuStatus: String, Codable {
    case pending
    case synced
    case failed
    /// 飞书未配置或 docx scope 未授予 → 跳过推送，不视为失败
    case skipped
}

/// 周/月/年 LLM 情绪化总结。
struct BillsSummary: Identifiable, Codable, Equatable, Hashable {
    let id: String              // UUID
    var periodKind: BillsSummaryPeriodKind
    var periodStart: Date       // UTC，周/月/年起点 00:00:00
    var periodEnd: Date         // UTC，周/月/年终点 23:59:59
    var totalExpense: Decimal   // 永远不要换成 Double（B1）
    var totalIncome: Decimal
    var recordCount: Int
    /// 喂给 LLM 的统计快照 JSON 字符串（用于"重新生成"时复用而无需再扫表）
    var snapshotJSON: String
    /// LLM 返回的完整 markdown
    var summaryText: String
    /// ≤30 字核心洞察（用于喂下次 LLM 做历史对比）
    var summaryDigest: String
    var llmProvider: String
    var feishuDocToken: String?
    var feishuDocURL: String?
    var feishuSyncStatus: BillsSummaryFeishuStatus
    var feishuLastError: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
}
