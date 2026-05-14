//  BillsSummaryAggregator.swift
//  CoinFlow · M10
//
//  从本地 SQLite 聚合周/月/年统计快照，喂给 LLM。
//
//  关键设计：
//  - 周边界：周一 00:00 ~ 周日 23:59:59（ISO 8601；使用 Calendar(.gregorian).firstWeekday=2）
//  - 月边界：本月 1 日 00:00 ~ 月末 23:59:59
//  - 年边界：1/1 00:00 ~ 12/31 23:59:59
//  - 时区：使用用户设备当前时区（Locale.current 的 TimeZone）
//  - 金额：Decimal，禁止 Double 中转（B1）
//  - 不读 deleted record；不读 income 计入支出 / 反之亦然
//
//  快照内容（按"诉求 1"prompt 模板设计）：
//   - 时间范围 / 总收支 / 笔数
//   - TOP 5 分类（金额、占比、典型 note）
//   - 最大单笔（金额、分类、note、日期）
//   - 高频分类（笔数）
//   - 深夜消费（22:00~04:00）笔数与金额
//   - 工作日 vs 周末支出比
//   - 备注关键词词频（≥2 次）
//   - 环比变化（上一同 kind 周期）

import Foundation

/// LLM 输入快照。Codable，序列化后存 bills_summary.snapshot_json，并拼进 user prompt。
struct BillsSummarySnapshot: Codable, Equatable {
    let periodKind: String        // week / month / year
    let periodLabel: String       // "2026-W19" / "2026-05" / "2026"
    let startDate: String         // yyyy-MM-dd
    let endDate: String           // yyyy-MM-dd
    let totalExpense: String      // Decimal stringified
    let totalIncome: String
    let expenseCount: Int
    let incomeCount: Int
    let categoryBreakdown: [CategoryStat]
    let maxExpense: SingleStat?
    let mostFrequentCategory: FreqStat?
    let lateNightCount: Int       // 22:00 ~ 04:00 笔数
    let lateNightAmount: String   // Decimal
    let weekdayRatio: String      // "工作日/周末" 文案，如 "62 : 38"
    let frequentKeywords: [String]
    let deltaVsPrevPeriod: PeriodDelta?
    let historyDigests: [String]  // 历史摘要（喂给 LLM 做对比，可空）

    struct CategoryStat: Codable, Equatable {
        let name: String
        let amount: String        // Decimal
        let percent: Int          // 0-100
        let count: Int
    }

    struct SingleStat: Codable, Equatable {
        let amount: String
        let category: String
        let note: String
        let date: String          // yyyy-MM-dd
    }

    struct FreqStat: Codable, Equatable {
        let name: String
        let count: Int
    }

    struct PeriodDelta: Codable, Equatable {
        let expenseDeltaPercent: Int       // 可正可负
        let risingCategory: String?        // 增长最多类目
        let risingPercent: Int?
        let fallingCategory: String?
        let fallingPercent: Int?
    }
}

enum BillsSummaryAggregator {

    // MARK: - 周期边界

    /// 当前 Calendar（中国大陆周一作为一周开始）。
    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.firstWeekday = 2 // 周一
        cal.minimumDaysInFirstWeek = 4 // ISO 8601
        return cal
    }

    /// 计算"包含 reference 时点的周期"起止（含端点）。
    /// 默认 reference = now()。
    static func periodBounds(kind: BillsSummaryPeriodKind,
                             reference: Date = Date(),
                             timeZone: TimeZone = .current) -> (start: Date, end: Date) {
        let cal = calendar(timeZone: timeZone)
        let start: Date
        let end: Date
        switch kind {
        case .week:
            // 当周周一 00:00 ~ 当周周日 23:59:59
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: reference)
            start = cal.date(from: comps) ?? reference
            end = cal.date(byAdding: .second, value: 7 * 86400 - 1, to: start) ?? reference
        case .month:
            let comps = cal.dateComponents([.year, .month], from: reference)
            start = cal.date(from: comps) ?? reference
            let nextMonth = cal.date(byAdding: .month, value: 1, to: start) ?? reference
            end = cal.date(byAdding: .second, value: -1, to: nextMonth) ?? reference
        case .year:
            let comps = cal.dateComponents([.year], from: reference)
            start = cal.date(from: comps) ?? reference
            let nextYear = cal.date(byAdding: .year, value: 1, to: start) ?? reference
            end = cal.date(byAdding: .second, value: -1, to: nextYear) ?? reference
        }
        return (start, end)
    }

    /// 取"上一同 kind 周期"边界（周→上周；月→上月；年→去年）。
    static func previousPeriodBounds(kind: BillsSummaryPeriodKind,
                                     currentStart: Date,
                                     timeZone: TimeZone = .current) -> (start: Date, end: Date) {
        let cal = calendar(timeZone: timeZone)
        let prevStart: Date
        switch kind {
        case .week:  prevStart = cal.date(byAdding: .day, value: -7, to: currentStart) ?? currentStart
        case .month: prevStart = cal.date(byAdding: .month, value: -1, to: currentStart) ?? currentStart
        case .year:  prevStart = cal.date(byAdding: .year, value: -1, to: currentStart) ?? currentStart
        }
        let bounds = periodBounds(kind: kind, reference: prevStart, timeZone: timeZone)
        return bounds
    }

    /// 周期标签（喂给 LLM 显示用）。
    static func periodLabel(kind: BillsSummaryPeriodKind,
                            start: Date,
                            timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        switch kind {
        case .week:
            f.dateFormat = "YYYY-'W'ww"
            return f.string(from: start)
        case .month:
            f.dateFormat = "yyyy-MM"
            return f.string(from: start)
        case .year:
            f.dateFormat = "yyyy"
            return f.string(from: start)
        }
    }

    // MARK: - 主聚合入口

    /// 聚合一个完整快照。
    /// - Parameters:
    ///   - kind: 周/月/年
    ///   - reference: 决定"哪一周/月/年"；默认 now()
    ///   - history: 历史摘要列表（最近 N 条），喂给 LLM 做对比
    static func aggregate(kind: BillsSummaryPeriodKind,
                          reference: Date = Date(),
                          history: [String] = [],
                          timeZone: TimeZone = .current,
                          recordRepo: RecordRepository = SQLiteRecordRepository.shared,
                          categoryRepo: CategoryRepository = SQLiteCategoryRepository.shared
    ) throws -> BillsSummarySnapshot {

        let cur = periodBounds(kind: kind, reference: reference, timeZone: timeZone)
        let prev = previousPeriodBounds(kind: kind, currentStart: cur.start, timeZone: timeZone)

        // 方案 C1：仅统计个人账本（ledgerId == default，含 AA 净额占位）。
        // AA 账本原始流水（ledgerId=AA）属于该 AA 账本，不进个人统计；
        // 占位（sourceKind=.aaSettlement）位于 default-ledger 上，自然纳入。
        let defaultLedgerId = DefaultSeeder.defaultLedgerId

        // 当前期个人账本未删除记录
        let curRecords = try recordRepo.list(.init(
            ledgerId: defaultLedgerId,
            fromDate: cur.start, toDate: cur.end,
            includesDeleted: false, limit: nil
        ))
        // 上一期个人账本记录（仅用于环比）
        let prevRecords = try recordRepo.list(.init(
            ledgerId: defaultLedgerId,
            fromDate: prev.start, toDate: prev.end,
            includesDeleted: false, limit: nil
        ))

        // 分类映射（id → (name, kind)）
        let allCats = try categoryRepo.list(kind: nil, includeDeleted: true)
        let catMap: [String: (name: String, kind: CategoryKind)] = allCats.reduce(into: [:]) {
            $0[$1.id] = ($1.name, $1.kind)
        }

        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: "en_US_POSIX")
        dayFmt.timeZone = timeZone
        dayFmt.dateFormat = "yyyy-MM-dd"

        // 拆分支出 / 收入
        var expenseRecords: [Record] = []
        var incomeRecords: [Record] = []
        for r in curRecords {
            let cat = catMap[r.categoryId]
            // 优先用 category 表的 kind；查不到则按 amount 正负兜底（理论不应发生）
            if let k = cat?.kind {
                if k == .expense { expenseRecords.append(r) } else { incomeRecords.append(r) }
            }
        }

        let totalExpense: Decimal = expenseRecords.reduce(0) { $0 + $1.amount }
        let totalIncome: Decimal = incomeRecords.reduce(0) { $0 + $1.amount }

        // 分类聚合（仅支出，收入分类对"消费地图"无意义）
        var byCategory: [String: (amount: Decimal, count: Int)] = [:]
        for r in expenseRecords {
            let name = catMap[r.categoryId]?.name ?? "其他"
            var v = byCategory[name] ?? (0, 0)
            v.amount += r.amount; v.count += 1
            byCategory[name] = v
        }
        let topCats: [BillsSummarySnapshot.CategoryStat] = byCategory
            .map { (name, v) -> BillsSummarySnapshot.CategoryStat in
                let pct = totalExpense > 0
                    ? Int(NSDecimalNumber(decimal: v.amount / totalExpense * 100).doubleValue.rounded())
                    : 0
                return .init(name: name, amount: "\(v.amount)", percent: pct, count: v.count)
            }
            .sorted { (a, b) in
                guard let da = Decimal(string: a.amount), let db = Decimal(string: b.amount) else { return false }
                return da > db
            }
            .prefix(5)
            .map { $0 }

        // 最大单笔（仅支出）
        let maxExpense: BillsSummarySnapshot.SingleStat? = expenseRecords
            .max { $0.amount < $1.amount }
            .map {
                .init(
                    amount: "\($0.amount)",
                    category: catMap[$0.categoryId]?.name ?? "其他",
                    note: $0.note ?? "",
                    date: dayFmt.string(from: $0.occurredAt)
                )
            }

        // 高频分类（按笔数）
        let mostFreq: BillsSummarySnapshot.FreqStat? = byCategory
            .max { $0.value.count < $1.value.count }
            .map { .init(name: $0.key, count: $0.value.count) }

        // 深夜消费（22:00 ~ 次日 04:00）
        let cal = calendar(timeZone: timeZone)
        var lateNightCount = 0
        var lateNightAmount: Decimal = 0
        for r in expenseRecords {
            let hour = cal.component(.hour, from: r.occurredAt)
            if hour >= 22 || hour < 4 {
                lateNightCount += 1
                lateNightAmount += r.amount
            }
        }

        // 工作日 vs 周末支出
        var weekdayAmt: Decimal = 0
        var weekendAmt: Decimal = 0
        for r in expenseRecords {
            let wd = cal.component(.weekday, from: r.occurredAt) // 1=Sun, 7=Sat
            if wd == 1 || wd == 7 { weekendAmt += r.amount } else { weekdayAmt += r.amount }
        }
        let total = weekdayAmt + weekendAmt
        let weekdayRatio: String
        if total > 0 {
            let wp = Int(NSDecimalNumber(decimal: weekdayAmt / total * 100).doubleValue.rounded())
            weekdayRatio = "\(wp) : \(100 - wp)"
        } else {
            weekdayRatio = "0 : 0"
        }

        // 备注关键词词频（仅支出，分词简化为"按 2-4 字滑窗 + 空白切分"）
        let kw = topKeywords(notes: expenseRecords.compactMap { $0.note }, minCount: 2, top: 5)

        // 环比
        let delta = computeDelta(
            curRecords: expenseRecords,
            prevRecords: prevRecords.filter { catMap[$0.categoryId]?.kind == .expense },
            catMap: catMap
        )

        return BillsSummarySnapshot(
            periodKind: kind.rawValue,
            periodLabel: periodLabel(kind: kind, start: cur.start, timeZone: timeZone),
            startDate: dayFmt.string(from: cur.start),
            endDate: dayFmt.string(from: cur.end),
            totalExpense: "\(totalExpense)",
            totalIncome: "\(totalIncome)",
            expenseCount: expenseRecords.count,
            incomeCount: incomeRecords.count,
            categoryBreakdown: topCats,
            maxExpense: maxExpense,
            mostFrequentCategory: mostFreq,
            lateNightCount: lateNightCount,
            lateNightAmount: "\(lateNightAmount)",
            weekdayRatio: weekdayRatio,
            frequentKeywords: kw,
            deltaVsPrevPeriod: delta,
            historyDigests: history
        )
    }

    // MARK: - Helpers

    /// 简易关键词词频：按非中英文数字字符切分，长度 2-6 的 token 计数。
    /// 简化策略：不引入分词库；中文连续片段直接整体当 token（用户备注一般已足够短，足够支持高频检测）。
    private static func topKeywords(notes: [String], minCount: Int, top: Int) -> [String] {
        var freq: [String: Int] = [:]
        let separators = CharacterSet(charactersIn: " ,.，。/、|·:;()()[]【】{}！!?？\n\t\r")
            .union(.decimalDigits)
            .union(.symbols)
        for note in notes {
            let parts = note.components(separatedBy: separators).filter { !$0.isEmpty }
            for p in parts where p.count >= 2 && p.count <= 6 {
                freq[p, default: 0] += 1
            }
        }
        return freq
            .filter { $0.value >= minCount }
            .sorted { $0.value > $1.value }
            .prefix(top)
            .map { $0.key }
    }

    private static func computeDelta(curRecords: [Record],
                                     prevRecords: [Record],
                                     catMap: [String: (name: String, kind: CategoryKind)]
    ) -> BillsSummarySnapshot.PeriodDelta? {
        guard !prevRecords.isEmpty else { return nil }
        let curTotal = curRecords.reduce(Decimal(0)) { $0 + $1.amount }
        let prevTotal = prevRecords.reduce(Decimal(0)) { $0 + $1.amount }
        guard prevTotal > 0 else { return nil }
        let pct = Int(NSDecimalNumber(
            decimal: (curTotal - prevTotal) / prevTotal * 100
        ).doubleValue.rounded())

        // 分类级别变化
        func byCat(_ rs: [Record]) -> [String: Decimal] {
            var m: [String: Decimal] = [:]
            for r in rs {
                let n = catMap[r.categoryId]?.name ?? "其他"
                m[n, default: 0] += r.amount
            }
            return m
        }
        let curByCat = byCat(curRecords)
        let prevByCat = byCat(prevRecords)
        var deltas: [(String, Int)] = []
        let allNames = Set(curByCat.keys).union(prevByCat.keys)
        for n in allNames {
            let c = curByCat[n] ?? 0
            let p = prevByCat[n] ?? 0
            guard p > 0 else { continue }
            let d = Int(NSDecimalNumber(decimal: (c - p) / p * 100).doubleValue.rounded())
            deltas.append((n, d))
        }
        deltas.sort { $0.1 > $1.1 }
        let rising = deltas.first.flatMap { $0.1 > 0 ? $0 : nil }
        let falling = deltas.last.flatMap { $0.1 < 0 ? $0 : nil }
        return .init(
            expenseDeltaPercent: pct,
            risingCategory: rising?.0,
            risingPercent: rising?.1,
            fallingCategory: falling?.0,
            fallingPercent: falling?.1
        )
    }
}
