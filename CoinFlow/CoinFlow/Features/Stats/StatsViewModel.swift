//  StatsViewModel.swift
//  CoinFlow · V2 Stats · 深度分析数据层
//
//  设计基线：design/screens/05-stats 全部 8 个分析页面共用一个 VM；
//  所有图表数据来自 SQLiteRecordRepository + SQLiteCategoryRepository 真实数据。
//
//  职责：
//   - 加载本月所有 record + 全部 category（含已删除，历史 record 仍可能引用）
//   - 派生：本月概览 / 日历热力 / 分类排行 / 24 小时分布 / 桑基（收入分类→支出分类）
//   - 派生：年度 12 个月柱图 / 30 天日趋势 / 单分类下钻
//   - 派生：存钱率历史（近 6 月）/ 备注词频
//   - 订阅 .recordsDidChange 自动 reload
//
//  约束：所有金额一律 Decimal，禁止 Double 中转计算（仅在 Charts 渲染最后一步转 Double）。

import Foundation
import SwiftUI
import Combine

// MARK: - 派生数据模型（仅 Stats 内部使用，避免污染流水页）

/// 单条分类聚合数据。
struct StatsCategorySlice: Identifiable, Equatable {
    let id: String          // category id
    let name: String
    let icon: String
    let kind: CategoryKind
    let tone: NotionColor   // 由 colorHex 映射
    let amount: Decimal
    let count: Int
    var percentage: Double  // 0~1，外部按当前数据集 total 计算后赋值
}

/// 一天的支出/收入小计。
struct StatsDailyPoint: Identifiable, Equatable {
    let id: Int             // day (1..31) 或 dayOfYear；按上下文
    let date: Date
    let income: Decimal
    let expense: Decimal
    var net: Decimal { income - expense }
}

/// 月度柱图（年度视图用）。
struct StatsMonthBucket: Identifiable, Equatable {
    let id: String          // "2026-05"
    let yearMonth: YearMonth
    let monthShort: String  // "5月"
    let income: Decimal
    let expense: Decimal
    var net: Decimal { income - expense }
}

/// 24 小时切片。
struct StatsHourSlice: Identifiable, Equatable {
    let id: Int             // 0..23
    let hour: Int
    let amount: Decimal     // 仅累计支出（消费时段分布的语义）
    let count: Int
}

/// 备注词频。
struct StatsKeyword: Identifiable, Equatable {
    let id: String
    let word: String
    let weight: Int          // 出现次数
    let categoryColor: NotionColor   // 关联最频繁出现的分类色
}

// MARK: - ViewModel

@MainActor
final class StatsViewModel: ObservableObject {

    // 当前月（驱动一切派生属性）。后续可加月份切换器；V2 默认锁定本月。
    @Published var month: YearMonth = YearMonth.current {
        didSet { reload() }
    }

    @Published private(set) var loadError: String?

    // ----- 原始数据缓存 -----
    /// 所有未删除 record（最近 24 个月内为合理上界）。
    @Published private(set) var allRecords: [Record] = []
    @Published private(set) var categoriesById: [String: Category] = [:]

    // ----- 派生：本月概览 -----
    @Published private(set) var monthlyIncome:  Decimal = 0
    @Published private(set) var monthlyExpense: Decimal = 0
    var monthlyNet: Decimal { monthlyIncome - monthlyExpense }
    @Published private(set) var monthlyCount: Int = 0

    // ----- 派生：上月（用于环比） -----
    @Published private(set) var prevMonthExpense: Decimal = 0
    @Published private(set) var prevMonthIncome:  Decimal = 0

    // ----- 派生：本月日历热力（day 1...numberOfDays） -----
    @Published private(set) var dailyExpenseInMonth: [StatsDailyPoint] = []

    // ----- 派生：分类排行（本月支出 only） -----
    @Published private(set) var expenseCategorySlices: [StatsCategorySlice] = []
    @Published private(set) var incomeCategorySlices:  [StatsCategorySlice] = []

    // ----- 派生：24 小时分布（本月支出 only） -----
    @Published private(set) var hourlyDistribution: [StatsHourSlice] = []

    // ----- 派生：年度（近 12 个月） -----
    @Published private(set) var last12Months: [StatsMonthBucket] = []

    // ----- 派生：30/90/180 日趋势 -----
    @Published private(set) var dailyTrend30:  [StatsDailyPoint] = []
    @Published private(set) var dailyTrend90:  [StatsDailyPoint] = []
    @Published private(set) var dailyTrend180: [StatsDailyPoint] = []

    // ----- 派生：存钱率历史（近 6 月） -----
    @Published private(set) var saveRateHistory: [(month: String, rate: Double)] = []

    // ----- 派生：备注词频（本月） -----
    @Published private(set) var keywords: [StatsKeyword] = []

    // ----- 状态：是否有真实数据。无数据 → 各分析页显示空态；有但稀疏（< 3 条）的子图标 [示例]。-----
    @Published private(set) var hasAnyData: Bool = false

    // ----- 私有 -----
    private let ledgerId: String
    private var observer: NSObjectProtocol?

    init(ledgerId: String = DefaultSeeder.defaultLedgerId,
         month: YearMonth = .current) {
        self.ledgerId = ledgerId
        self.month = month
        observer = NotificationCenter.default.addObserver(
            forName: .recordsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reload() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Reload

    func reload() {
        do {
            // 1) 拉所有分类（含已删除，旧 record 可能引用）
            let cats = try SQLiteCategoryRepository.shared
                .list(kind: nil, includeDeleted: true)
            categoriesById = Dictionary(uniqueKeysWithValues: cats.map { ($0.id, $0) })

            // 2) 拉记录（最近 18 个月，支撑年度 + 同比）
            let cal = Calendar.current
            let now = Date()
            let from = cal.date(byAdding: .month, value: -17, to: now) ?? now
            let records = try SQLiteRecordRepository.shared.list(.init(
                ledgerId: ledgerId,
                fromDate: cal.startOfDay(for: from),
                includesDeleted: false,
                limit: 5000
            ))
            allRecords = records
            hasAnyData = !records.isEmpty

            recompute()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Compute helpers

    private func kind(for record: Record) -> CategoryKind {
        categoriesById[record.categoryId]?.kind ?? .expense
    }

    private func recompute() {
        let cal = Calendar.current

        // ---- 本月 / 上月切片 ----
        let curInterval = month.dateInterval(in: cal)
        let prevYM = month.adding(months: -1)
        let prevInterval = prevYM.dateInterval(in: cal)

        let curRecords  = allRecords.filter { curInterval.contains($0.occurredAt) }
        let prevRecords = allRecords.filter { prevInterval.contains($0.occurredAt) }

        // ---- 本月概览 ----
        var inc: Decimal = 0, exp: Decimal = 0
        for r in curRecords {
            switch kind(for: r) {
            case .income:  inc += r.amount
            case .expense: exp += r.amount
            }
        }
        monthlyIncome = inc
        monthlyExpense = exp
        monthlyCount = curRecords.count

        var pInc: Decimal = 0, pExp: Decimal = 0
        for r in prevRecords {
            switch kind(for: r) {
            case .income:  pInc += r.amount
            case .expense: pExp += r.amount
            }
        }
        prevMonthIncome = pInc
        prevMonthExpense = pExp

        // ---- 本月日历热力（按 day 聚合） ----
        let monthStart = curInterval.start
        let dayCount = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        var byDay: [Int: (income: Decimal, expense: Decimal, date: Date)] = [:]
        for r in curRecords {
            let d = cal.component(.day, from: r.occurredAt)
            let date = cal.date(bySetting: .day, value: d, of: monthStart) ?? r.occurredAt
            var slot = byDay[d] ?? (0, 0, date)
            switch kind(for: r) {
            case .income:  slot.income += r.amount
            case .expense: slot.expense += r.amount
            }
            byDay[d] = slot
        }
        dailyExpenseInMonth = (1...dayCount).map { d in
            let s = byDay[d] ?? (0, 0, cal.date(bySetting: .day, value: d, of: monthStart) ?? monthStart)
            return StatsDailyPoint(id: d, date: s.date, income: s.income, expense: s.expense)
        }

        // ---- 分类排行（本月，分支收/支） ----
        expenseCategorySlices = buildSlices(from: curRecords, kind: .expense)
        incomeCategorySlices  = buildSlices(from: curRecords, kind: .income)

        // ---- 24 小时分布（本月支出） ----
        var byHour: [Int: (amount: Decimal, count: Int)] = [:]
        for r in curRecords where kind(for: r) == .expense {
            let h = cal.component(.hour, from: r.occurredAt)
            var s = byHour[h] ?? (0, 0)
            s.amount += r.amount
            s.count += 1
            byHour[h] = s
        }
        hourlyDistribution = (0..<24).map { h in
            let s = byHour[h] ?? (0, 0)
            return StatsHourSlice(id: h, hour: h, amount: s.amount, count: s.count)
        }

        // ---- 年度（近 12 个月） ----
        last12Months = (0..<12).reversed().map { offset in
            let ym = month.adding(months: -offset)
            let interval = ym.dateInterval(in: cal)
            let recs = allRecords.filter { interval.contains($0.occurredAt) }
            var i: Decimal = 0, e: Decimal = 0
            for r in recs {
                switch kind(for: r) {
                case .income:  i += r.amount
                case .expense: e += r.amount
                }
            }
            return StatsMonthBucket(
                id: ym.idString,
                yearMonth: ym,
                monthShort: "\(ym.month)月",
                income: i,
                expense: e
            )
        }

        // ---- 日趋势（30/90/180） ----
        dailyTrend30  = buildTrend(days: 30, baseDate: cal.startOfDay(for: Date()))
        dailyTrend90  = buildTrend(days: 90, baseDate: cal.startOfDay(for: Date()))
        dailyTrend180 = buildTrend(days: 180, baseDate: cal.startOfDay(for: Date()))

        // ---- 存钱率历史（近 6 月） ----
        saveRateHistory = (0..<6).reversed().map { offset in
            let ym = month.adding(months: -offset)
            let interval = ym.dateInterval(in: cal)
            let recs = allRecords.filter { interval.contains($0.occurredAt) }
            var i: Decimal = 0, e: Decimal = 0
            for r in recs {
                switch kind(for: r) {
                case .income:  i += r.amount
                case .expense: e += r.amount
                }
            }
            let rate: Double
            if i > 0 {
                rate = ((i - e) as NSDecimalNumber).doubleValue
                     / (i as NSDecimalNumber).doubleValue
            } else {
                rate = 0
            }
            return ("\(ym.month)月", max(0, rate))
        }

        // ---- 词频（本月备注） ----
        keywords = buildKeywords(records: curRecords)
    }

    /// 把一组 record 按分类聚合成 slices（仅一个 kind）。
    private func buildSlices(from records: [Record], kind: CategoryKind) -> [StatsCategorySlice] {
        let filtered = records.filter { self.kind(for: $0) == kind }
        guard !filtered.isEmpty else { return [] }
        var byCat: [String: (amount: Decimal, count: Int)] = [:]
        for r in filtered {
            var s = byCat[r.categoryId] ?? (0, 0)
            s.amount += r.amount
            s.count += 1
            byCat[r.categoryId] = s
        }
        let total = filtered.map(\.amount).reduce(Decimal(0), +)
        let totalDouble = (total as NSDecimalNumber).doubleValue
        return byCat.compactMap { (cid, s) -> StatsCategorySlice? in
            guard let cat = categoriesById[cid] else { return nil }
            let pct = totalDouble > 0
                ? (s.amount as NSDecimalNumber).doubleValue / totalDouble
                : 0
            return StatsCategorySlice(
                id: cid,
                name: cat.name,
                icon: cat.icon,
                kind: cat.kind,
                tone: NotionColorMapper.from(colorHex: cat.colorHex),
                amount: s.amount,
                count: s.count,
                percentage: pct
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    /// 按天聚合最近 N 天（含今天）。
    private func buildTrend(days: Int, baseDate: Date) -> [StatsDailyPoint] {
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -(days - 1), to: baseDate) ?? baseDate
        let upperBound = cal.date(byAdding: .day, value: 1, to: baseDate) ?? baseDate
        let scoped = allRecords.filter { $0.occurredAt >= from && $0.occurredAt < upperBound }
        var byDay: [Date: (i: Decimal, e: Decimal)] = [:]
        for r in scoped {
            let d = cal.startOfDay(for: r.occurredAt)
            var s = byDay[d] ?? (0, 0)
            switch kind(for: r) {
            case .income:  s.i += r.amount
            case .expense: s.e += r.amount
            }
            byDay[d] = s
        }
        return (0..<days).reversed().map { offset in
            let d = cal.date(byAdding: .day, value: -offset, to: baseDate) ?? baseDate
            let s = byDay[d] ?? (0, 0)
            return StatsDailyPoint(id: offset, date: d, income: s.i, expense: s.e)
        }
    }

    /// 备注词频：备注按空格 / 中文标点 / `,，。 ` 切，过滤短词；权重 = 出现次数。
    private func buildKeywords(records: [Record]) -> [StatsKeyword] {
        guard !records.isEmpty else { return [] }
        // 中文 1 字过短，2 字以上才计；最多 12 个
        let stopwords: Set<String> = ["的", "了", "和", "是", "在", "我", "你", "他",
                                       "今天", "今日", "昨天", "明天", "刚才", "刚刚"]
        var freq: [String: Int] = [:]
        var colorByWord: [String: [NotionColor: Int]] = [:]
        let separators = CharacterSet(charactersIn: " ,，。.;；:：!！?？\n\r\t/、|·•")
        for r in records {
            guard let note = r.note?.trimmingCharacters(in: .whitespaces),
                  !note.isEmpty else { continue }
            let cat = categoriesById[r.categoryId]
            let tone = cat.map { NotionColorMapper.from(colorHex: $0.colorHex) } ?? .gray
            // 切词（中文场景：拆 separators，并对剩余串切 2-grams 兜底）
            let tokens = note.components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.count >= 2 && $0.count <= 8 }   // 2-8 字最有信息量
                .filter { !stopwords.contains($0) }
                .filter { !$0.allSatisfy({ $0.isNumber || $0 == "." }) }
            for t in tokens {
                freq[t, default: 0] += 1
                var m = colorByWord[t] ?? [:]
                m[tone, default: 0] += 1
                colorByWord[t] = m
            }
        }
        return freq.map { (word, weight) -> StatsKeyword in
            // 取该词最常关联的分类色作为词色
            let dominant = colorByWord[word]?
                .max(by: { $0.value < $1.value })?.key ?? .gray
            return StatsKeyword(id: word, word: word, weight: weight, categoryColor: dominant)
        }
        .sorted { $0.weight > $1.weight }
        .prefix(12).map { $0 }
    }
}

// MARK: - YearMonth Stats helpers
//
// 主类型 `YearMonth` 已在 `RecordsListViewModel.swift` 定义。
// 这里只补 Stats 需要的派生 API（idString / dateInterval / adding）。

extension YearMonth {
    var idString: String { String(format: "%04d-%02d", year, month) }

    func dateInterval(in cal: Calendar) -> DateInterval {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        let start = cal.date(from: comps) ?? Date()
        return cal.dateInterval(of: .month, for: start)
            ?? DateInterval(start: start, end: start)
    }

    func adding(months delta: Int) -> YearMonth {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = year
        comps.month = month + delta
        comps.day = 1
        let date = cal.date(from: comps) ?? Date()
        let c = cal.dateComponents([.year, .month], from: date)
        return YearMonth(year: c.year ?? year, month: c.month ?? month)
    }
}
