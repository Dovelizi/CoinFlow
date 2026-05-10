//  BillsLLMParser.swift
//  CoinFlow · M5 · §7.5.3 LLM 多笔解析协议（Mock 实现）
//
//  本文件是 M5 的占位实现：用确定性规则模拟 LLM 的切分 + 字段提取，
//  目的是让端到端链路（录音 → ASR → Parser → 向导）在 M5 全部跑通。
//  M6 会把 `parse(...)` 内部换成调用真 LLM（豆包/Qwen），Prompt 照抄文档 §7.5.3。
//
//  规则覆盖（常见中文记账口语）：
//  - 切分：分隔词 "还有 / 另外 / 接着 / 对了 / 然后"；句号 / 分号也切分
//  - 金额：
//      1. 阿拉伯数字 + "块/元/钱/毛/角/分"（含小数）
//      2. 中文数字 "一百二十五" → 125（最多到"千"级别）
//      3. "一百二十五块五" / "一百二十五块五毛" → 125.50
//  - direction 关键词：
//      支出：花 / 付 / 买 / 打车 / 吃 / 交 / 充 / 去 / 用 / 请
//      收入：收 / 赚 / 退 / 领 / 进账 / 还我 / 转给我
//  - 日期：
//      今天 / 今儿 → today
//      昨天 → today-1; 前天 → today-2; 大前天 → today-3
//      明天 / 后天 / 大后天 → +1/+2/+3（虽 MVP 不鼓励未来日期，但仍解析）
//      上周一 ~ 上周日 / 周一 ~ 周日（最近一次过去）
//      N 天前 / N 号
//      无匹配 → 使用 today
//  - category：LLM 在文档中"必须严格匹配用户已有分类"；这里用**关键词 → 分类名**的词典匹配
//    （如"打车/出租/地铁" → "交通"）。不确定则返回 nil。
//
//  未覆盖的场景（刻意）：
//  - 多货币、汇率换算：MVP 仅 CNY
//  - 参与人 / AA 付款人：本期语音不支持 AA（§7.5 范围明确）

import Foundation

// M7-Fix24：分类映射词典已删除 —— category 完全由 LLM 根据传入白名单决定；
// 规则引擎降级路径的 parseCategory 一律返回 nil，由 UI 提示用户手填。

final class BillsLLMParser {

    /// Parser 最终路由结果：包含解析后的 bills + 实际使用的 engine（用于 session 审计）
    struct ParseResult {
        let bills: [ParsedBill]
        let engine: ParserEngine
        /// LLM 原始响应（仅 LLM 路径有值；供 voice_session.parser_raw_json 审计）
        let rawJSON: String?
    }

    /// LLM 客户端（从 AppConfig 工厂获取）；可在测试时注入
    private let llmClient: LLMTextClient

    init(llmClient: LLMTextClient? = nil) {
        self.llmClient = llmClient ?? LLMTextClientFactory.make()
    }

    /// M6 主入口：LLM 优先，失败降级规则。
    /// - Parameter source: 文本来源（voice=口述 / ocr=截图文本），影响 LLM prompt 的 system 角色描述
    /// - Returns:
    ///   - LLM 成功且判断为"无账单" → `bills: []`（空数组是合法结果，上层据此提示用户重试）
    ///   - LLM 成功且解析出多笔 → `bills: [...]`
    ///   - LLM 失败 → 降级规则引擎；规则引擎无金额时也返回空
    ///   - 输入文本为空 → `bills: []`
    func parse(asrText: String,
               today: Date = Date(),
               tz: TimeZone = TimeZone.current,
               allowedCategories: [String],
               requiredFields: [String],
               source: BillsSourceHint = .voice) async -> ParseResult {
        let text = asrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return ParseResult(bills: [], engine: .ruleOnly, rawJSON: nil)
        }

        // 1. 尝试 LLM（若未配置会抛 notConfigured，直接降级）
        if !(llmClient is StubLLMTextClient) {
            do {
                let raw = try await callLLM(
                    asrText: text, today: today, tz: tz,
                    allowedCategories: allowedCategories,
                    requiredFields: requiredFields,
                    source: source
                )
                let bills = try decodeLLMResponse(
                    raw: raw,
                    today: today,
                    tz: tz,
                    allowedCategories: allowedCategories,
                    requiredFields: requiredFields
                )
                // M7-Fix12：LLM 返回空数组是合法结果（非账单 / 无金额），不兜底不走规则
                return ParseResult(
                    bills: bills,
                    engine: engineTag(for: llmClient.providerName),
                    rawJSON: raw
                )
            } catch {
                // M7-Fix19：区分超时 vs 其他失败，便于排查
                if case LLMTextError.timeout = error {
                    NSLog("[LLM] \(llmClient.providerName) 超时（含 1 次重试），已降级到规则引擎")
                } else {
                    NSLog("[LLM] \(llmClient.providerName) 失败，已降级到规则引擎：\(error.localizedDescription)")
                }
                // fallthrough to rule
            }
        }

        // 2. 规则引擎降级
        let bills = parseWithRules(
            text: text, today: today, tz: tz,
            allowedCategories: allowedCategories,
            requiredFields: requiredFields
        )
        // M7-Fix12：规则引擎返回的笔里如果没有任何金额，视为"无账单"返回空
        let validBills = bills.filter { ($0.amount ?? 0) > 0 }
        return ParseResult(bills: validBills, engine: .ruleOnly, rawJSON: nil)
    }

    /// 纯规则解析（M5 实现；LLM 失败时降级路径）。公开以便单测。
    func parseWithRules(text: String,
                        today: Date = Date(),
                        tz: TimeZone = TimeZone.current,
                        allowedCategories: [String],
                        requiredFields: [String]) -> [ParsedBill] {
        let segments = splitSegments(text)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz

        return segments.map { seg in
            let amount = parseAmount(in: seg)
            let direction = parseDirection(in: seg)
            let rawDate = parseDate(in: seg, today: today, calendar: cal)
            let date: Date? = {
                guard let d = rawDate else { return nil }
                let startOfToday = cal.startOfDay(for: today)
                return d > startOfToday ? nil : d
            }()
            let catName = parseCategory(in: seg)
            var missing: Set<String> = []
            if requiredFields.contains("amount"),      amount == nil || (amount ?? 0) <= 0 {
                missing.insert("amount")
            }
            if requiredFields.contains("occurred_at"), date == nil {
                missing.insert("occurred_at")
            }
            if requiredFields.contains("direction"),   direction == nil {
                missing.insert("direction")
            }
            if requiredFields.contains("category"),    catName == nil {
                missing.insert("category")
            }
            let catFinal = catName.flatMap { allowedCategories.contains($0) ? $0 : nil }
            if requiredFields.contains("category"), catFinal == nil {
                missing.insert("category")
            }
            return ParsedBill(
                id: UUID().uuidString,
                occurredAt: date,
                amount: amount,
                direction: direction,
                categoryName: catFinal,
                note: seg,
                missingFields: missing
            )
        }
    }

    // MARK: - LLM path

    private func callLLM(asrText: String,
                         today: Date,
                         tz: TimeZone,
                         allowedCategories: [String],
                         requiredFields: [String],
                         source: BillsSourceHint = .voice) async throws -> String {
        // M7-Fix19：OCR 路径截断 rawText 至 800 字符，降低 DeepSeek 负载、缩短首 token 时间。
        //   截图 OCR 全文常 500~2000 字符，含订单号 / 商家备注 / 大段冗余文本，
        //   实际有效字段（金额 / 商户 / 时间）通常在前 800 字以内。
        //   语音路径（voice）保持原文，因 ASR 文本通常远短于 800 字。
        let promptText: String = {
            guard source == .ocr, asrText.count > 800 else { return asrText }
            return String(asrText.prefix(800))
        }()
        let prompt = BillsPromptBuilder.build(
            asrText: promptText, today: today, tz: tz,
            allowedCategories: allowedCategories,
            requiredFields: requiredFields,
            source: source
        )
        return try await llmClient.completeJSON(prompt: prompt)
    }

    /// 解析 LLM 返回的 `{"bills": [...]}` 结构；失败抛错触发降级。
    /// - Parameter today: 用户时区下的"今天"参照；用于"未来日期"拦截（避免 LLM 返回 `2099-01-01` 通过）
    /// - Parameter tz:    用户时区；用于日期字符串 → Date 的解析
    ///
    /// M7-Fix8：字段名与内部 Swift 协议保持一致：occurred_at / amount / direction / category / note
    /// occurred_at 支持 `YYYY-MM-DD HH:mm:ss`（新 Prompt 要求）和 `YYYY-MM-DD`（兼容旧数据）
    /// M7-Fix21：暴露为 public，让视觉 LLM 客户端复用解析逻辑（schema 完全一致）
    func decodeBillsJSON(raw: String,
                         today: Date = Date(),
                         tz: TimeZone = TimeZone.current,
                         allowedCategories: [String],
                         requiredFields: [String]) throws -> [ParsedBill] {
        try decodeLLMResponse(raw: raw, today: today, tz: tz,
                              allowedCategories: allowedCategories,
                              requiredFields: requiredFields)
    }

    private func decodeLLMResponse(raw: String,
                                   today: Date,
                                   tz: TimeZone,
                                   allowedCategories: [String],
                                   requiredFields: [String]) throws -> [ParsedBill] {
        // LLM 偶尔会把 JSON 包在 markdown 里，做一次清理
        let cleaned = stripMarkdownFence(raw)
        guard let data = cleaned.data(using: .utf8) else {
            throw LLMTextError.invalidResponse("raw non-utf8")
        }

        struct Envelope: Decodable {
            let bills: [BillDTO]
        }
        struct BillDTO: Decodable {
            let occurred_at: String?
            let amount: Double?
            let direction: String?
            let category: String?
            let note: String?
            let merchant_type: String?   // M7-Fix23：枚举{微信,支付宝,抖音,银行,其他}
            let missing_fields: [String]?
        }

        let env: Envelope
        do {
            env = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            // 容错：LLM 偶尔违反 Prompt 直接返回顶层数组，再尝试一次
            if let arr = try? JSONDecoder().decode([BillDTO].self, from: data) {
                env = Envelope(bills: arr)
            } else {
                throw LLMTextError.jsonDecodeFailed(raw: cleaned, underlying: error)
            }
        }

        // 用 **用户时区** 构造两套日期解析器：带时间 + 仅日期
        let dtFormatter = DateFormatter()
        dtFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dtFormatter.locale = Locale(identifier: "en_US_POSIX")
        dtFormatter.timeZone = tz
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateOnlyFormatter.timeZone = tz

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let startOfToday = cal.startOfDay(for: today)
        // 未来日期拦截阈值："明日 00:00:00"（即允许今天任意时刻）
        let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? today

        return env.bills.map { dto in
            // occurred_at：优先解析 "YYYY-MM-DD HH:mm:ss"，回退到 "YYYY-MM-DD"
            var occurredAt: Date? = nil
            if let s = dto.occurred_at {
                if let d = dtFormatter.date(from: s), d < endOfToday {
                    occurredAt = d
                } else if let d = dateOnlyFormatter.date(from: s), d <= startOfToday {
                    occurredAt = d
                }
            }
            // 金额（M7-Fix13：范围 0 < a <= 1 亿）
            var amount: Decimal? = nil
            if let a = dto.amount, a > 0, a <= 100_000_000 {
                amount = Decimal(a)
            }
            // direction
            let direction: BillDirection? = {
                guard let d = dto.direction else { return nil }
                return BillDirection(rawValue: d)
            }()
            // category 白名单（"其他"是 LLM 兜底返回值，只有当用户白名单里确实有"其他"才保留）
            let catFinal = dto.category.flatMap { allowedCategories.contains($0) ? $0 : nil }

            // M7-Fix23：merchant_type 白名单校验，非枚举值归"其他"；nil 保持 nil（不强填）
            let allowedMerchants: Set<String> = ["微信", "支付宝", "抖音", "银行", "其他"]
            let merchantTypeFinal: String? = dto.merchant_type.map {
                allowedMerchants.contains($0) ? $0 : "其他"
            }

            // missing = LLM 给的 ∪ 客户端再校验
            var missing = Set(dto.missing_fields ?? [])
            if requiredFields.contains("amount"),      (amount ?? 0) <= 0         { missing.insert("amount") }
            if requiredFields.contains("occurred_at"), occurredAt == nil          { missing.insert("occurred_at") }
            if requiredFields.contains("direction"),   direction == nil           { missing.insert("direction") }
            if requiredFields.contains("category"),    catFinal == nil            { missing.insert("category") }

            return ParsedBill(
                id: UUID().uuidString,
                occurredAt: occurredAt,
                amount: amount,
                direction: direction,
                categoryName: catFinal,
                note: dto.note,
                merchantType: merchantTypeFinal,
                missingFields: missing
            )
        }
    }

    private func stripMarkdownFence(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // 去掉 ```json ... ``` 或 ``` ... ```
        if t.hasPrefix("```") {
            if let nl = t.firstIndex(of: "\n") {
                t = String(t[t.index(after: nl)...])
            }
            if t.hasSuffix("```") {
                t = String(t.dropLast(3))
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func engineTag(for providerName: String) -> ParserEngine {
        switch providerName {
        case "deepseek": return .llmDeepseek
        case "openai":   return .llmGPT4o
        case "doubao":   return .llmDoubao
        case "qwen":     return .llmQwen
        default:         return .ruleOnly
        }
    }

    // MARK: - 分句（切分）

    /// 切分：以分隔词 / 句号 / 分号 + 后续是"金额 / 金钱动词"作切点。
    /// 保守策略：切点后的段必须包含**数字 OR 中文数字 OR 金钱相关动词**，
    /// 否则合并回上一段（避免"还有一点钱"被错切成两段）。
    func splitSegments(_ text: String) -> [String] {
        var t = text
        let markers = ["还有", "另外", "接着", "对了", "然后", "；", ";", "。"]
        for m in markers { t = t.replacingOccurrences(of: m, with: "|") }
        let raw = t.split(separator: "|", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !raw.isEmpty else { return [] }

        // 合并规则：若某段不含数字/中文数字/金钱动词，合并到上一段尾部
        let digits: Set<Character> = ["零","一","二","三","四","五","六","七","八","九","十","百","千","万"]
        func looksLikeBill(_ s: String) -> Bool {
            if s.contains(where: { $0.isNumber }) { return true }
            if s.contains(where: { digits.contains($0) }) { return true }
            let moneyVerbs = ["花","付","买","吃","打车","收","赚","退","领","充","交"]
            return moneyVerbs.contains(where: { s.contains($0) })
        }
        var merged: [String] = []
        for seg in raw {
            if looksLikeBill(seg) {
                merged.append(seg)
            } else if var last = merged.last {
                last += " " + seg
                merged[merged.count - 1] = last
            } else {
                // 第一段就不像账单，保留让下游判为"全缺失"
                merged.append(seg)
            }
        }
        return merged
    }

    // MARK: - 金额解析

    private static let arabicAmountRegex = try! NSRegularExpression(
        pattern: #"(\d+(?:\.\d{1,2})?)\s*(块|元|钱|毛|角|分)?"#
    )

    /// 主函数：先找阿拉伯数字金额；失败再尝试中文数字。
    func parseAmount(in text: String) -> Decimal? {
        if let v = parseArabicAmount(in: text) { return v }
        return parseChineseAmount(in: text)
    }

    /// 阿拉伯数字金额：优先"X块Y毛"/"X元Y角"；否则取最大 number。
    private func parseArabicAmount(in text: String) -> Decimal? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = Self.arabicAmountRegex.matches(in: text, range: range)
        guard !matches.isEmpty else { return nil }

        // 收集 (value, unit)
        struct Hit { let value: Decimal; let unit: String }
        var hits: [Hit] = []
        for m in matches {
            guard let numR = Range(m.range(at: 1), in: text) else { continue }
            guard let num = Decimal(string: String(text[numR])) else { continue }
            let unit: String = {
                if m.numberOfRanges > 2, let uR = Range(m.range(at: 2), in: text) {
                    return String(text[uR])
                }
                return ""
            }()
            hits.append(Hit(value: num, unit: unit))
        }
        guard !hits.isEmpty else { return nil }

        // 组合 "X 块 Y 毛"：第一条 unit ∈ {块,元,钱}，紧跟第二条 unit ∈ {毛,角}
        var i = 0
        var best: Decimal = 0
        while i < hits.count {
            let h = hits[i]
            if ["块", "元", "钱", ""].contains(h.unit) {
                var acc = h.value
                // 后面紧邻 毛/角/分 → 加小数
                if i + 1 < hits.count {
                    let nxt = hits[i + 1]
                    if nxt.unit == "毛" || nxt.unit == "角" {
                        acc += nxt.value / 10
                        i += 1
                    } else if nxt.unit == "分" {
                        acc += nxt.value / 100
                        i += 1
                    }
                }
                if acc > best { best = acc }
            }
            i += 1
        }
        return best > 0 ? best : nil
    }

    /// 中文数字金额（精简版）：支持"一/二/三/四/五/六/七/八/九/零/十/百/千/万"
    /// 常见句式："一百二十块五"、"两百五"、"三十块钱"、"一万块"
    private func parseChineseAmount(in text: String) -> Decimal? {
        // 把"两"视作 2
        let t = text.replacingOccurrences(of: "两", with: "二")
        // 扫"中文数字团"（最多 12 个字符），遇到第一个即返回
        let digits: Set<Character> = ["零","一","二","三","四","五","六","七","八","九","十","百","千","万"]
        let chars = Array(t)
        var i = 0
        while i < chars.count {
            if digits.contains(chars[i]) {
                var j = i
                while j < chars.count, digits.contains(chars[j]) { j += 1 }
                let token = String(chars[i..<j])
                if let v = Self.chineseNumeralToDecimal(token), v > 0 {
                    // 判断是否紧跟"块/元/钱" + 可能的小数部分"X毛/X角"
                    var acc = v
                    var k = j
                    // 跳过可选的 "块/元/钱"
                    if k < chars.count, ["块","元","钱"].contains(chars[k]) { k += 1 }
                    // 后续继续是中文数字 + 毛/角/分 → 小数
                    if k < chars.count, digits.contains(chars[k]) {
                        var m = k
                        while m < chars.count, digits.contains(chars[m]) { m += 1 }
                        let frac = String(chars[k..<m])
                        if let f = Self.chineseNumeralToDecimal(frac) {
                            if m < chars.count, chars[m] == "毛" || chars[m] == "角" {
                                acc += f / 10
                            } else if m < chars.count, chars[m] == "分" {
                                acc += f / 100
                            }
                        }
                    }
                    return acc
                }
                i = j
            } else {
                i += 1
            }
        }
        return nil
    }

    /// 把"一百二十五"之类中文数字转 Decimal。支持到"万"。不严谨但够 MVP。
    static func chineseNumeralToDecimal(_ s: String) -> Decimal? {
        if s.isEmpty { return nil }
        // 纯"十" = 10
        if s == "十" { return 10 }
        let digit: [Character: Int] = [
            "零":0,"一":1,"二":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9
        ]
        let unit: [Character: Int] = ["十":10,"百":100,"千":1000,"万":10000]

        var total = 0
        var current = 0
        var lastUnit = 1
        for ch in s {
            if let d = digit[ch] {
                current = d
            } else if let u = unit[ch] {
                if u == 10_000 {
                    total = (total + max(current, 1)) * 10_000
                    current = 0
                    lastUnit = 1
                } else {
                    let base = current == 0 ? 1 : current
                    total += base * u
                    current = 0
                    lastUnit = u
                }
            } else {
                return nil
            }
        }
        // 尾部散位：省略了一级单位。
        //   "五十六"：lastUnit=10，尾 6 → 6 * 1 = 6 → 56
        //   "一千二"：lastUnit=1000，尾 2 → 2 * 100 = 200 → 1200
        //   "三百五"：lastUnit=100，尾 5 → 5 * 10 = 50 → 350
        //   "两万三"：lastUnit=1（"万"已清位），尾 3 → 3 * 1000 = 3000 → 23000
        // 规则：散位乘以 lastUnit/10（lastUnit>10 时）；万位处理后 lastUnit 重置为 1，
        // 此时尾部散位应代表"千"级 → 1000；所以用"万后"标记特殊处理。
        if current > 0 {
            let multiplier: Int
            if lastUnit > 1 {
                multiplier = lastUnit / 10
            } else {
                // lastUnit==1：要么没有单位词（如"五"=5），要么刚处理完"万"
                // 区分方式：total>0 说明前面有过单位 → 散位在"千"级
                multiplier = total > 0 ? 1000 : 1
            }
            total += current * multiplier
        }
        return total > 0 ? Decimal(total) : nil
    }

    // MARK: - direction

    /// 支出词典。注意：先匹配收入强语义词（"发工资"/"收到"/"还我"），再降级到支出。
    /// "还" "给" 本身歧义大，必须靠上下文前后缀区分：
    ///   - "还你/还他/还款" → 支出；"还我" → 收入（已在 incomeKeywords 命中）
    ///   - "给我/发给我" → 收入；"给你/给他/给老板" → 支出
    private static let expenseKeywords =
        ["花", "付", "买", "打车", "吃", "交", "充", "用", "请", "送"]
    /// 需要前后缀区分的歧义词：命中时做额外判断
    private static let ambiguousGiveExpense: [String] = ["给你", "给他", "给她", "给妈", "给爸", "给老板", "给朋友"]
    private static let ambiguousGiveIncome:  [String] = ["给我", "发给我", "转给我"]
    private static let ambiguousBackExpense: [String] = ["还你", "还他", "还她", "还款", "还房贷", "还花呗"]

    /// 收入词典。"发工资"/"工资"/"薪水"/"奖金"/"报销"/"退款" 是典型强语义收入。
    private static let incomeKeywords =
        ["收到", "收", "赚", "退", "领", "进账", "到账",
         "还我", "转给我", "发工资", "工资", "薪水", "发薪", "奖金", "报销", "退款"]

    func parseDirection(in text: String) -> BillDirection? {
        // 1. 收入强语义优先
        if Self.incomeKeywords.contains(where: { text.contains($0) }) { return .income }
        // 2. "给我/发给我/转给我" → 收入
        if Self.ambiguousGiveIncome.contains(where: { text.contains($0) }) { return .income }
        // 3. 歧义"给"/"还" 指向对方 → 支出
        if Self.ambiguousGiveExpense.contains(where: { text.contains($0) }) { return .expense }
        if Self.ambiguousBackExpense.contains(where: { text.contains($0) }) { return .expense }
        // 4. 通用支出关键词
        if Self.expenseKeywords.contains(where: { text.contains($0) }) { return .expense }
        return nil
    }

    // MARK: - 日期

    /// 简易自然语言日期解析。
    func parseDate(in text: String,
                   today: Date,
                   calendar: Calendar) -> Date? {
        // 把时间部分（HH:mm）丢掉，只返回日期的 00:00:00
        let startOfToday = calendar.startOfDay(for: today)

        // 绝对关键词
        if text.contains("大前天") { return calendar.date(byAdding: .day, value: -3, to: startOfToday) }
        if text.contains("前天")   { return calendar.date(byAdding: .day, value: -2, to: startOfToday) }
        if text.contains("昨天")   { return calendar.date(byAdding: .day, value: -1, to: startOfToday) }
        if text.contains("今天") || text.contains("今儿") { return startOfToday }
        if text.contains("大后天") { return calendar.date(byAdding: .day, value: 3, to: startOfToday) }
        if text.contains("后天")   { return calendar.date(byAdding: .day, value: 2, to: startOfToday) }
        if text.contains("明天")   { return calendar.date(byAdding: .day, value: 1, to: startOfToday) }

        // N 天前 / N 天后
        if let n = Self.extractChineseOrArabicNumber(after: "", before: "天前", in: text) {
            return calendar.date(byAdding: .day, value: -n, to: startOfToday)
        }
        if let n = Self.extractChineseOrArabicNumber(after: "", before: "天后", in: text) {
            return calendar.date(byAdding: .day, value: n, to: startOfToday)
        }

        // 上周 X / 周 X（取最近一次过去；Apple weekday: 1=Sun..7=Sat）
        // weekdayNames index 0..6 对应 周一..周日 → Apple weekday [2,3,4,5,6,7,1]
        let appleMapping = [2, 3, 4, 5, 6, 7, 1]
        let weekdayNames = ["一","二","三","四","五","六","日"]
        for (i, n) in weekdayNames.enumerated() {
            let apple = appleMapping[i]
            if text.contains("上周\(n)") {
                return lastWeekday(apple, from: startOfToday, calendar: calendar, weeksAgo: 1)
            }
            if text.contains("周\(n)") || text.contains("星期\(n)") {
                return lastWeekday(apple, from: startOfToday, calendar: calendar, weeksAgo: 0)
            }
        }

        return nil
    }

    /// 从 date 回推到上一次目标 weekday（Apple Calendar：1=Sun..7=Sat）。
    /// weeksAgo=0 取"最近一次过去"；weeksAgo=1 再多回一周（"上周 X"语义）。
    private func lastWeekday(_ appleTarget: Int,
                             from date: Date,
                             calendar: Calendar,
                             weeksAgo: Int) -> Date? {
        let current = calendar.component(.weekday, from: date)   // 1..7
        var diff = current - appleTarget                          // 往回几天
        if diff <= 0 { diff += 7 }                                // 保证严格过去
        let totalBack = diff + weeksAgo * 7
        return calendar.date(byAdding: .day, value: -totalBack, to: date)
    }

    private static func extractChineseOrArabicNumber(after prefix: String,
                                                     before suffix: String,
                                                     in text: String) -> Int? {
        // 简易：找到 suffix 位置，往前扫连续的中文/阿拉伯数字
        guard let r = text.range(of: suffix) else { return nil }
        let head = text[..<r.lowerBound]
        // 截末尾连续数字
        var buf = ""
        for ch in head.reversed() {
            if ch.isNumber || "零一二三四五六七八九十百千".contains(ch) {
                buf = String(ch) + buf
            } else {
                break
            }
        }
        guard !buf.isEmpty else { return nil }
        if let i = Int(buf) { return i }
        if let d = chineseNumeralToDecimal(buf) {
            return NSDecimalNumber(decimal: d).intValue
        }
        return nil
    }

    // MARK: - Category

    /// M7-Fix24：规则引擎降级路径不再做分类判定 —— 分类职责完全交给 LLM。
    /// 保留此函数只是为了维持 `parseWithRules` 的调用签名，永远返回 nil。
    /// 上层会因 category 缺失把它加入 missingFields，UI 会提示用户手填分类。
    func parseCategory(in text: String) -> String? {
        return nil
    }
}
