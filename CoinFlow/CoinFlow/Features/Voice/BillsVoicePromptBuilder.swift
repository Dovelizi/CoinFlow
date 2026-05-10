//  BillsVoicePromptBuilder.swift
//  CoinFlow · 语音多笔解析专用 Prompt
//
//  特性：
//  - 针对 ASR 口语化文本设计：废话词清洗、同音容错
//  - 紧邻"动作+金额"组合切多笔
//  - 「按天展开」：用户说"最近一周每天吃饭 10 块" → 展开为 N 笔
//      上限 14 笔；超过的部分截断
//  - merchant_type 不输出（语音通常缺商户线索）
//
//  输出 schema 与 OCR Prompt 完全一致：
//      {"bills":[{occurred_at, amount, direction, category, note, missing_fields?}]}

import Foundation

enum BillsVoicePromptBuilder {

    /// 按天展开上限（用户决策：14）
    static let dailyExpansionMaxBills: Int = 14

    static func build(asrText: String,
                      today: Date,
                      tz: TimeZone,
                      allowedCategories: [String]) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = tz
        let nowStr = df.string(from: today)

        let dayDF = DateFormatter()
        dayDF.dateFormat = "yyyy-MM-dd"
        dayDF.locale = Locale(identifier: "en_US_POSIX")
        dayDF.timeZone = tz
        let todayStr = dayDF.string(from: today)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let weekdayCN = ["日", "一", "二", "三", "四", "五", "六"]
        let weekdayIdx = cal.component(.weekday, from: today) - 1   // 1..7 → 0..6
        let todayWeekday = "周" + (weekdayCN.indices.contains(weekdayIdx) ? weekdayCN[weekdayIdx] : "?")

        let categoriesLine = allowedCategories.isEmpty
            ? "（用户尚未自定义分类，无法匹配时填 \"其他\"）"
            : allowedCategories.joined(separator: " / ")

        return """
        你是一个中文记账助手。任务：把用户的一段口述（ASR 原文）解析成一笔或多笔账单，按 JSON 输出。

        ### 当前时间参考
        - 现在：\(nowStr)（\(tz.identifier)）
        - 今天：\(todayStr) \(todayWeekday)

        ### 用户已有分类白名单
        \(categoriesLine)

        ### 处理规则

        1. 数据清洗
           - 忽略口语废话："哎 / 那个 / 呃 / 就是 / 嗯 / 啊 / 这个"
           - 同一金额前后重复说出时只算一笔（ASR 修正）
           - 同音容错："打车" ≈ "打的 / 滴滴 / 打车车"；"外卖" ≈ "外买"

        2. 多笔拆分
           出现以下任一线索即新起一笔：
           - 显式连接词：还有 / 又 / 另外 / 接着 / 然后 / 对了 / 顺便
           - 句号 "。" / 分号 "；"
           - 紧邻"动作+金额"组合（即使无连接词）：
               · "吃饭 20 打车 10" → 2 笔
               · "早饭 15 午饭 30 晚饭 50" → 3 笔
           - 同一次消费拆账（"A 付了 30 B 付了 50 一起吃的"）→ 仍是 1 笔

        3. 时间按天展开（语音 Prompt 的核心）
           用户口述常隐含"按天/按次重复"语义，必须展开为多笔，每笔独立 occurred_at。

           触发与规则：
           3.1 "最近 N 天每天 X" / "这 N 天每天 X" / "过去 N 天每天 X"
               → 展开 N 笔，日期从「今天-(N-1)」到「今天」
               · "最近一周每天吃饭花 10 块" → 7 笔
               · "这三天每天打车 15" → 3 笔

           3.2 "本周每天 X" / "这周每天 X"
               → 从本周一到今天，展开 K 笔（K = 今天是周几，周日记 7）
               · 今天周四说"本周每天 10" → 4 笔（周一/二/三/四）

           3.3 "上周每天 X"
               → 上周一到上周日，7 笔

           3.4 "上个月每天 X" / "这个月每天 X"
               → 上个月：全月每一天；这个月：1 号到今天

           3.5 "每天 X 连续 N 天" / "连续 N 天每天 X"
               → 展开 N 笔，日期从「今天-(N-1)」到「今天」

           3.6 "周一到周五每天 X"
               → 按本周该区间展开

           3.7 不展开（保持 1 笔）：
               · "每周 X 块"（无"每天"）
               · "每月 X 块"（无"每天"）
               · "一天 X 块"（孤立用法，无"连续 N 天"）

           展开上限：
           - 单次展开最多 \(dailyExpansionMaxBills) 笔；超出按 \(dailyExpansionMaxBills) 笔封顶（取最近 \(dailyExpansionMaxBills) 天）
           - "最近一年每天 10 块" 也只展开 \(dailyExpansionMaxBills) 笔

           展开后每笔字段：
           - occurred_at = "对应日期 12:00:00"（统一中午 12 点，避免 0 点被判未来时间）
           - amount / direction / category / note 全部复制主笔
           - **note 直接复制主笔，不要追加"（第 k 天）"等后缀**

        4. 单笔时间推断（未触发 §3 展开时）
           - "刚才 / 刚刚 / 今天 / 今儿" → 今天 + 当前时刻
           - "昨天" → 今天-1；"前天" → 今天-2；"大前天" → 今天-3
           - "上周X / 周X"（X ∈ 一~日）→ 最近一次过去的该 weekday
           - "N 天前 / N 号" → 对应日期
           - 无任何时间线索 → \(nowStr)
           - 统一格式 "YYYY-MM-DD HH:mm:ss"，**不得晚于 \(nowStr)**

        5. 金额解析
           - 阿拉伯数字直接取：10 / 10.5 / 10.50
           - 中文数字转阿拉伯：三十 = 30；一百二十 = 120；一千二 = 1200；两万三 = 23000
           - "X 块 Y 毛 / X 元 Y 角" = X + Y/10；"X 块 Y 分" = X + Y/100
           - 不含货币符号；amount **必须 > 0**

        6. 方向判断（direction）
           - 收入词：发工资 / 工资 / 薪水 / 奖金 / 报销 / 退款 / 退我 / 收到 / 到账 / 还我 / 转给我 / 领 / 赚 / 进账
           - 支出词：花 / 付 / 买 / 打车 / 吃 / 交 / 充 / 请 / 送 / 还款 / 还房贷 / 还花呗
           - 歧义"给"：给我 = 收入；给你/他/她/老板 = 支出
           - 歧义"还"：还我 = 收入；还你/他/款 = 支出
           - 全部未命中：默认 "expense"

        7. 分类匹配（category）
           - 严格从【白名单】选一个最贴切的
           - 常见映射线索（仅作提示，最终以白名单为准）：
               餐饮/吃饭/早饭/午饭/晚饭/外卖/奶茶/咖啡 → 餐饮
               打车/滴滴/地铁/公交/高铁/火车/机票    → 交通
               买菜/超市/日用品                       → 日用
               工资/奖金/报销                         → 工资 / 收入
               房租/水电/燃气                         → 居家
           - 无法对应 → "其他"（若白名单无"其他"，由客户端处理）

        8. note 生成
           - 简短可读：餐饮 → "吃饭 / 早餐 / 外卖"；交通 → "打车 / 地铁"
           - ≤ 30 字；不要复述金额或日期
           - 展开的多笔保持相同 note

        9. missing_fields
           - amount / occurred_at / direction / category 任一不可靠 → 放入数组
           - 全部补齐 → 空数组或省略

        10. 非账单兜底
            - 用户只是在聊天、讲故事、读诗、无任何金额与消费动作 → {"bills": []}
            - **宁可返回空也不要编造金额**

        11. 输出格式
            - 顶层必须是对象：{"bills":[ ... ]}
            - **不要** markdown 代码块包装
            - **不要** 解释文字
            - 语音场景**不要**输出 merchant_type 字段（缺省即可）

        ### 用户原始 ASR 文本
        \(asrText)

        ### 输出示例

        示例 A（单笔）：
        输入："刚才打车花了 28 块"
        输出：{"bills":[{"occurred_at":"\(nowStr)","amount":28,"direction":"expense","category":"交通","note":"打车","missing_fields":[]}]}

        示例 B（紧邻多笔）：
        输入："吃饭 20 打车 10"
        输出：{"bills":[{"occurred_at":"\(nowStr)","amount":20,"direction":"expense","category":"餐饮","note":"吃饭","missing_fields":[]},{"occurred_at":"\(nowStr)","amount":10,"direction":"expense","category":"交通","note":"打车","missing_fields":[]}]}

        示例 C（按天展开 · 核心）：
        输入："最近一周每天吃饭花 10 块"
        输出：以「今天」为锚点反推 7 天，每天一笔，时间统一 12:00:00；note 都是 "吃饭"；超过 \(dailyExpansionMaxBills) 笔时按上限截断。

        示例 D（非账单 / 无金额）：
        输入："今天天气真好"
        输出：{"bills":[]}
        """
    }
}
