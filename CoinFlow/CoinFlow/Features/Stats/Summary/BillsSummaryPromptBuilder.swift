//  BillsSummaryPromptBuilder.swift
//  CoinFlow · M10
//
//  把 BillsSummarySnapshot 渲染成喂给 LLM 的 user prompt。
//  - system prompt 由 PromptResource.billsSummarySystem 加载（Resources/Prompts/BillsSummary.system.md）
//  - 历史摘要拼在 user prompt 末尾，section 标题 "历史摘要"，可空
//
//  与 OCR/ASR PromptBuilder 的对齐：
//  - 同样用 enum + static func 单入口
//  - 同样穿透 today / tz 显式参数（避免单测受系统时区影响）
//  - 同样不在 builder 内部读 Bundle（资源加载交给 PromptResource）

import Foundation

enum BillsSummaryPromptBuilder {

    /// 完整产物：(system, user) 两段 prompt 文本。
    /// LLM 调用方负责拼成 OpenAI 格式 messages 数组。
    static func build(snapshot: BillsSummarySnapshot,
                      systemPromptOverride: String? = nil) -> (system: String, user: String) {
        let system = systemPromptOverride ?? loadSystem()
        let user = renderUser(snapshot: snapshot)
        return (system, user)
    }

    /// 仅供单测访问：渲染 user 部分。
    static func renderUser(snapshot s: BillsSummarySnapshot) -> String {
        var lines: [String] = []
        lines.append("这是用户【\(periodKindCN(s.periodKind))】的账单数据：")
        lines.append("")
        lines.append("时间范围：\(s.startDate) 到 \(s.endDate)（\(s.periodLabel)）")
        lines.append("总支出：¥\(formatAmount(s.totalExpense)) 元（共 \(s.expenseCount) 笔）")
        lines.append("总收入：¥\(formatAmount(s.totalIncome)) 元（共 \(s.incomeCount) 笔）")
        lines.append("")

        // 分类 TOP
        if !s.categoryBreakdown.isEmpty {
            lines.append("分类支出 TOP \(s.categoryBreakdown.count)（金额 | 占比 | 笔数）：")
            for c in s.categoryBreakdown {
                lines.append("  - \(c.name)：¥\(formatAmount(c.amount)) | \(c.percent)% | \(c.count) 笔")
            }
            lines.append("")
        }

        // 关注点
        lines.append("值得关注的记录：")
        if let m = s.maxExpense {
            let note = m.note.isEmpty ? "（无备注）" : m.note
            lines.append("  - 最大单笔支出：¥\(formatAmount(m.amount))（\(m.category)，备注：\(note)，\(m.date)）")
        } else {
            lines.append("  - 最大单笔支出：（无）")
        }
        if let f = s.mostFrequentCategory {
            lines.append("  - 最高频分类：\(f.name)（\(f.count) 次）")
        }
        lines.append("  - 深夜消费（22:00-04:00）：\(s.lateNightCount) 笔，共 ¥\(formatAmount(s.lateNightAmount)) 元")
        lines.append("  - 工作日 vs 周末支出比：\(s.weekdayRatio)")
        lines.append("")

        // 环比
        if let d = s.deltaVsPrevPeriod {
            lines.append("环比变化（vs 上一\(periodKindCN(s.periodKind))）：")
            let sign = d.expenseDeltaPercent >= 0 ? "+" : ""
            lines.append("  - 总支出变化：\(sign)\(d.expenseDeltaPercent)%")
            if let rc = d.risingCategory, let rp = d.risingPercent {
                lines.append("  - 增长最多的分类：\(rc)（+\(rp)%）")
            }
            if let fc = d.fallingCategory, let fp = d.fallingPercent {
                lines.append("  - 减少最多的分类：\(fc)（\(fp)%）")
            }
            lines.append("")
        }

        // 备注关键词
        if !s.frequentKeywords.isEmpty {
            lines.append("用户备注关键词（出现≥2次）：\(s.frequentKeywords.joined(separator: " / "))")
            lines.append("")
        }

        // 历史摘要
        if !s.historyDigests.isEmpty {
            lines.append("历史摘要（如发现明显变化可在 Part 2 末尾用一句话点出，不强制）：")
            for (i, h) in s.historyDigests.enumerated() {
                lines.append("  \(i + 1). \(h)")
            }
            lines.append("")
        }

        lines.append("现在，按 system 规则给 TA 写这一\(periodKindCN(s.periodKind))的复盘报告（Part 1 + Part 2）。")
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private static func loadSystem() -> String {
        if let s = try? PromptResource.billsSummarySystem.load() { return s }
        return PromptResource.billsSummarySystem.fallback()
    }

    /// "week" → "本周"；"month" → "本月"；"year" → "本年度"
    private static func periodKindCN(_ raw: String) -> String {
        switch raw {
        case "week":  return "本周"
        case "month": return "本月"
        case "year":  return "本年度"
        default:      return "本期"
        }
    }

    /// Decimal 字符串 → 千分位 + 最多 2 位小数（用户阅读友好）。
    private static func formatAmount(_ s: String) -> String {
        guard let d = Decimal(string: s) else { return s }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        f.groupingSeparator = ","
        return f.string(from: NSDecimalNumber(decimal: d)) ?? s
    }
}
