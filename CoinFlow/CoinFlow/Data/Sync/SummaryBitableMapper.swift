//  SummaryBitableMapper.swift
//  CoinFlow · M10-Fix2
//
//  BillsSummary ↔ 飞书总结表 fields dict 的双向映射。
//
//  飞书表字段类型对应（与 FeishuSummaryFieldName 一致）：
//  - 周期标签 (Text 主键)        : "2026-W19"
//  - 总结ID  (Text)               : UUID
//  - 周期类型 (SingleSelect)      : "周报" / "月报" / "年报"
//  - 起始日期 / 结束日期 / 生成时间 (DateTime) : Int64 毫秒
//  - 总收入 / 总支出 / 笔数 (Number)            : Decimal/Int → Double
//  - 一句话洞察 / 完整总结 / LLM模型 (Text)
//
//  设计：
//  - encode 失败抛 SummaryBitableMapperError；service 层归类到 feishuLastError
//  - 飞书 Number 字段不接受 Decimal 字符串，必须转 Double（金额范围在 Double 安全区）

import Foundation

enum SummaryBitableMapperError: Error, LocalizedError {
    case invalidValue(field: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidValue(let f, let r): return "\(f) 字段非法：\(r)"
        }
    }
}

enum SummaryBitableMapper {

    /// 周期标签：与本地 BillsSummaryAggregator.periodLabel() 同语义。
    /// 直接复用 aggregator 计算结果以保持一致；如未来分离需小心同步。
    static func periodLabel(kind: BillsSummaryPeriodKind, start: Date) -> String {
        BillsSummaryAggregator.periodLabel(kind: kind, start: start)
    }

    /// BillsSummary → 飞书 fields dict
    static func encode(_ s: BillsSummary) throws -> [String: Any] {
        let kindCN: String = {
            switch s.periodKind {
            case .week:  return "周报"
            case .month: return "月报"
            case .year:  return "年报"
            }
        }()

        // Decimal → Double（金额，飞书 Number 字段约束）
        let expenseDouble = NSDecimalNumber(decimal: s.totalExpense).doubleValue
        let incomeDouble  = NSDecimalNumber(decimal: s.totalIncome).doubleValue
        guard expenseDouble.isFinite, incomeDouble.isFinite else {
            throw SummaryBitableMapperError.invalidValue(
                field: "amount", reason: "non-finite double"
            )
        }

        let label = periodLabel(kind: s.periodKind, start: s.periodStart)

        return [
            FeishuSummaryFieldName.periodLabel:  label,
            FeishuSummaryFieldName.summaryId:    s.id,
            FeishuSummaryFieldName.periodKind:   kindCN,
            FeishuSummaryFieldName.startDate:    Int64(s.periodStart.timeIntervalSince1970 * 1000),
            FeishuSummaryFieldName.endDate:      Int64(s.periodEnd.timeIntervalSince1970 * 1000),
            FeishuSummaryFieldName.totalIncome:  incomeDouble,
            FeishuSummaryFieldName.totalExpense: expenseDouble,
            FeishuSummaryFieldName.recordCount:  s.recordCount,
            FeishuSummaryFieldName.digest:       s.summaryDigest,
            FeishuSummaryFieldName.fullJSON:     s.summaryText,
            FeishuSummaryFieldName.llmProvider:  s.llmProvider,
            FeishuSummaryFieldName.generatedAt:  Int64(s.updatedAt.timeIntervalSince1970 * 1000)
        ]
    }
}
