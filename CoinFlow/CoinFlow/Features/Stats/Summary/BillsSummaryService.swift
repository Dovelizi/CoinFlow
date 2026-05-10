//  BillsSummaryService.swift
//  CoinFlow · M10
//
//  编排：聚合数据 → 拼 prompt → 调 LLM → 落本地 → 推飞书文档。
//
//  调用入口：
//   - generate(kind:reference:force:) — 主入口（被 Scheduler 触发，或用户在 UI 主动点"重新生成"）
//   - syncToFeishu(summaryId:) — 单独把本地已存在的 summary 推到飞书（重试入口）
//
//  错误策略：
//   - LLM 失败 → 整个 generate 失败抛出；本地不落库（避免脏数据）
//   - 飞书失败 → 本地已落库，仅 summary.feishuSyncStatus = failed；
//     用户主动调 syncToFeishu 重试；冷启动调度器**不会**重试飞书（避免反复打权限失败）
//   - 飞书权限不足（docx scope 未开） → status = .skipped，不视为失败
//
//  并发控制：actor 隔离，避免同一 kind 并发触发多次 LLM 调用

import Foundation

enum BillsSummaryServiceError: Error, LocalizedError {
    case llmNotConfigured
    case noData(reason: String)
    case llmFailed(underlying: Error)
    case llmEmptyOutput

    var errorDescription: String? {
        switch self {
        case .llmNotConfigured: return "LLM 未配置，无法生成总结"
        case .noData(let r):    return "数据不足：\(r)"
        case .llmFailed(let e): return "LLM 调用失败：\(e.localizedDescription)"
        case .llmEmptyOutput:   return "LLM 返回内容为空"
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// "账单总结已生成"全局事件。
    /// userInfo["summary"] = BillsSummary（刚生成的那条）。
    /// 订阅方：HomeMainView 首页 banner。
    static let billsSummaryDidGenerate = Notification.Name("CoinFlow.billsSummary.didGenerate")
}

actor BillsSummaryService {

    static let shared = BillsSummaryService()
    private init() {}

    /// 单 kind 的进行中任务，防止同一 kind 重复触发（用户疯狂点"重新生成"）
    private var inflight: [BillsSummaryPeriodKind: Task<BillsSummary, Error>] = [:]

    /// 触发阈值（用户决策默认值）。
    /// 周 ≥3 / 月 ≥5 / 年 ≥12
    static func minRecordCount(for kind: BillsSummaryPeriodKind) -> Int {
        switch kind {
        case .week:  return 3
        case .month: return 5
        case .year:  return 12
        }
    }

    /// 历史摘要喂入条数（用户决策默认值）
    static let historyDigestCount: Int = 3

    // MARK: - Generate

    /// 主入口：生成（或重新生成）指定 kind 的总结。
    /// - Parameters:
    ///   - reference: 决定是哪一周/月/年；默认 now()
    ///   - force: true = 即使 record 数 < 阈值也强制生成（用户主动点"立即生成"时用）
    /// - Returns: 已落库的 BillsSummary
    func generate(kind: BillsSummaryPeriodKind,
                  reference: Date = Date(),
                  force: Bool = false) async throws -> BillsSummary {
        // 串行化同 kind 的请求
        if let task = inflight[kind] {
            return try await task.value
        }
        let task = Task<BillsSummary, Error> {
            try await self.doGenerate(kind: kind, reference: reference, force: force)
        }
        inflight[kind] = task
        defer { inflight[kind] = nil }
        return try await task.value
    }

    private func doGenerate(kind: BillsSummaryPeriodKind,
                            reference: Date,
                            force: Bool) async throws -> BillsSummary {
        // 1. 历史摘要
        let history: [String] = (try? SQLiteBillsSummaryRepository.shared
            .listRecent(kind: kind, limit: Self.historyDigestCount))?
            .map { $0.summaryDigest }
            .filter { !$0.isEmpty }
            ?? []

        // 2. 聚合快照
        let snapshot = try BillsSummaryAggregator.aggregate(
            kind: kind, reference: reference, history: history
        )

        // 3. 阈值检查（force=false 时）
        let totalRecords = snapshot.expenseCount + snapshot.incomeCount
        if !force && totalRecords < Self.minRecordCount(for: kind) {
            throw BillsSummaryServiceError.noData(
                reason: "笔数 \(totalRecords) < 阈值 \(Self.minRecordCount(for: kind))"
            )
        }

        // 4. LLM
        guard let llm = BillsSummaryLLMClient.active() else {
            throw BillsSummaryServiceError.llmNotConfigured
        }
        let (system, user) = BillsSummaryPromptBuilder.build(snapshot: snapshot)
        let rawMarkdown: String
        do {
            rawMarkdown = try await llm.complete(system: system, user: user)
        } catch {
            throw BillsSummaryServiceError.llmFailed(underlying: error)
        }

        // 4.5 清理 LLM 偶尔会包的 ```markdown ... ``` 外层 code fence
        let summaryText = stripMarkdownCodeFence(rawMarkdown)
        guard !summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BillsSummaryServiceError.llmEmptyOutput
        }

        // 5. 抽 digest：markdown 首个非标题/表格/列表的自然段落，截 30 字
        let digest = extractDigestFromMarkdown(summaryText)

        // 6. 序列化 snapshot 存入 snapshotJSON
        let snapshotJSON: String = (try? String(data:
            JSONEncoder().encode(snapshot), encoding: .utf8)) ?? "{}"

        // 7. 计算周期边界（与聚合一致）
        let bounds = BillsSummaryAggregator.periodBounds(kind: kind, reference: reference)

        let now = Date()
        let bounds_start = bounds.start
        let bounds_end   = bounds.end

        // 8. 复用已有 id（如该周期已存在），保证 upsert 走 update 而不是新增 row
        let existing = try? SQLiteBillsSummaryRepository.shared
            .find(kind: kind, periodStart: bounds_start)

        let summary = BillsSummary(
            id: existing?.id ?? UUID().uuidString,
            periodKind: kind,
            periodStart: bounds_start,
            periodEnd: bounds_end,
            totalExpense: Decimal(string: snapshot.totalExpense) ?? 0,
            totalIncome: Decimal(string: snapshot.totalIncome) ?? 0,
            recordCount: totalRecords,
            snapshotJSON: snapshotJSON,
            summaryText: summaryText,
            summaryDigest: digest,
            llmProvider: llm.providerName,
            feishuDocToken: existing?.feishuDocToken,
            feishuDocURL: existing?.feishuDocURL,
            feishuSyncStatus: .pending,
            feishuLastError: nil,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            deletedAt: nil
        )

        try SQLiteBillsSummaryRepository.shared.upsert(summary)
        SyncLogger.info(phase: "summary.generate",
                        "kind=\(kind.rawValue) records=\(totalRecords) provider=\(llm.providerName)")

        // 9. 广播"账单总结已生成"通知 → AppState.pendingSummaryPush → 首页 banner
        // 必须在 main 线程 post，确保 AppState observer (queue: .main) 立刻投递；
        // 此处 self 处于 actor 上下文，用 Task { @MainActor } 桥到主线程。
        let generated = summary
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .billsSummaryDidGenerate,
                object: nil,
                userInfo: ["summary": generated]
            )
        }

        // 10. 异步推飞书（不阻塞调用方；失败不影响 summary 已落库）
        Task.detached { [weak self] in
            await self?.syncToFeishu(summaryId: summary.id)
        }
        return summary
    }

    // MARK: - Sync to Feishu Summary Bitable

    /// 把本地已存在的 summary 推到飞书"账单总结"独立 bitable。
    /// - 飞书未配置 → 写 .skipped
    /// - 已有 docToken（实际是 record_id） → updateRecord；如命中"远端行不存在/表不存在"类
    ///   错误（飞书 1254043 / 1254004 / 1254001 / 1254002），自动清缓存后降级到 createRecord
    /// - 无 → createRecord，把返回的 record_id 存到 feishuDocToken
    /// - 其它失败 → status = .failed（用户在 UI 主动重试）
    func syncToFeishu(summaryId: String) async {
        guard let s = try? SQLiteBillsSummaryRepository.shared.find(id: summaryId) else {
            return
        }
        guard FeishuConfig.isConfigured else {
            try? SQLiteBillsSummaryRepository.shared.updateFeishuSync(
                id: summaryId, status: .skipped,
                docToken: nil, docURL: nil,
                error: "飞书未配置"
            )
            return
        }

        do {
            let fields = try SummaryBitableMapper.encode(s)
            let recordId = try await upsertToFeishu(summary: s, fields: fields)
            let url = await summaryBitableURL(recordId: recordId)
            try? SQLiteBillsSummaryRepository.shared.updateFeishuSync(
                id: summaryId, status: .synced,
                docToken: recordId, docURL: url, error: nil
            )
        } catch {
            try? SQLiteBillsSummaryRepository.shared.updateFeishuSync(
                id: summaryId, status: .failed,
                docToken: s.feishuDocToken, docURL: s.feishuDocURL,
                error: error.localizedDescription
            )
            SyncLogger.failure(phase: "summary.feishu", error: error,
                               extra: "summaryId=\(summaryId)")
        }
    }

    /// 内部：执行 update 或 create，带"远端失效自动重建"语义。
    /// - Returns: 最终生效的 record_id（写回本地 feishuDocToken）
    private func upsertToFeishu(summary s: BillsSummary,
                                fields: [String: Any]) async throws -> String {
        if let existingRecordId = s.feishuDocToken, !existingRecordId.isEmpty {
            do {
                try await FeishuBitableClient.shared.updateSummaryRecord(
                    recordId: existingRecordId, fields: fields
                )
                SyncLogger.info(phase: "summary.feishu", "updated row \(existingRecordId)")
                return existingRecordId
            } catch FeishuBitableError.apiError(let code, let msg, _)
                where isRemoteObjectGone(code: code) {
                // 远端行/表/App 已不存在：清相应缓存后走 create 路径
                SyncLogger.warn(phase: "summary.feishu",
                                "remote object gone (code=\(code) msg=\(msg))，清缓存重建")
                if code == 1254043 {
                    // 仅行丢失：保留表，不清 summary bitable 缓存
                    // （createSummaryRecord 会在同一张表里建新行）
                } else {
                    // 表/App 级问题：连表缓存一起清，让下一轮 ensure 时自动重建新表
                    FeishuConfig.resetSummaryBitableCache()
                }
                // fallthrough 到下面 create
            }
        }
        // create 路径（首次同步 / 远端行失效）
        let newRecordId = try await FeishuBitableClient.shared.createSummaryRecord(fields: fields)
        SyncLogger.info(phase: "summary.feishu",
                        "created row \(newRecordId) (fallback=\(s.feishuDocToken != nil))")
        return newRecordId
    }

    /// 判断飞书错误码是否属于"远端对象已不存在，应当降级重建"。
    /// - 1254043: RecordIdNotFound（行被手动删了）
    /// - 1254004: TableIdNotFound（表被手动删了）
    /// - 1254001 / 1254002: App/请求参数异常（通常是 app_token 失效）
    private func isRemoteObjectGone(code: Int) -> Bool {
        return code == 1254043 || code == 1254004
            || code == 1254001 || code == 1254002
    }

    /// 拼接到飞书具体行的 URL（如果可拼）。
    /// 飞书 bitable URL 格式：`<base_url>?table=<tid>&view=...`，单条行无独立 URL，
    /// 这里返回 base url，UI 显示"在飞书中打开"即可。
    private func summaryBitableURL(recordId: String) async -> String? {
        return FeishuConfig.summaryBitableURL
    }

    // MARK: - Helpers

    /// 剥离 LLM 偶尔输出的整体 code fence（```markdown ... ``` / ```md ... ```）。
    /// 也兼容不带语言标识的 ``` ```。
    private func stripMarkdownCodeFence(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("```") else { return t }
        // 去掉首行 ```xxx
        if let firstNewline = t.firstIndex(of: "\n") {
            t = String(t[t.index(after: firstNewline)...])
        } else {
            return s  // 单行 fence 异常情况，原样返回
        }
        // 去掉末尾 ```
        if t.hasSuffix("```") {
            t = String(t.dropLast(3))
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 从 markdown 中抽取"一句话核心洞察"作为 digest（≤30 字）。
    /// 跳过标题（#）、表格（|）、列表（-）、引用（>）、代码块（```）、分割线（---）。
    private func extractDigestFromMarkdown(_ md: String) -> String {
        let lines = md.split(separator: "\n", omittingEmptySubsequences: false)
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") || line.hasPrefix("|") || line.hasPrefix(">")
                || line.hasPrefix("-") || line.hasPrefix("```")
                || line.hasPrefix("*") || line.hasPrefix("1.") {
                continue
            }
            // 去除开头的粗体/斜体符号，防止截断的 digest 里遗留半个 **
            let cleaned = line
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "*", with: "")
            return String(cleaned.prefix(30))
        }
        return ""
    }

    private func periodTitleCN(_ s: BillsSummary) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        switch s.periodKind {
        case .week:
            f.dateFormat = "YYYY-'W'ww"
            return f.string(from: s.periodStart) + " 周报"
        case .month:
            f.dateFormat = "yyyy-MM"
            return f.string(from: s.periodStart) + " 月报"
        case .year:
            f.dateFormat = "yyyy"
            return f.string(from: s.periodStart) + " 年报"
        }
    }
}
