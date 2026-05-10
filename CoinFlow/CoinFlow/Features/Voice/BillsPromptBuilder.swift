//  BillsPromptBuilder.swift
//  CoinFlow · M6/M7 · §7.5.3 Prompt 模板
//
//  M7-Fix7/8：按用户规范"智能财务记账专家"身份 + 6 条处理规则；
//            字段名与 Swift 内部协议保持一致（occurred_at/amount/direction/category/note）。
//  - 顶层结构：`{"bills": [...]}`（符合 OpenAI/DeepSeek JSON mode 对"顶层必须对象"的约束）

import Foundation

enum BillsSourceHint: String {
    case voice    // 口述
    case ocr      // 截图 OCR
}

enum BillsPromptBuilder {

    /// 构造多笔解析 Prompt。
    /// 输出结构**必须**是 `{"bills": [...]}`（不是顶层数组——OpenAI JSON mode 要求对象）
    static func build(asrText: String,
                      today: Date,
                      tz: TimeZone,
                      allowedCategories: [String],
                      requiredFields: [String],
                      source: BillsSourceHint = .voice) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.timeZone = tz
        let currentDate = df.string(from: today)
        let categoriesLine = allowedCategories.isEmpty ? "（空）" : allowedCategories.joined(separator: " / ")

        // 来源描述
        let sourceLabel: String
        switch source {
        case .voice: sourceLabel = "语音（ASR）"
        case .ocr:   sourceLabel = "图片（OCR）"
        }

        return """
        你是一个智能财务记账专家。你的任务是处理用户的语音（ASR）或图片（OCR）原始文本，提取关键交易信息，并输出标准的 JSON 格式。

        ### 处理规则：
        1. **数据清洗**：忽略输入中的口语废话（如"哎"、"那个"、"呃"）、无意义的符号或 OCR 识别出的页眉页脚。
        2. **多笔拆分（重要）**：只要一段话中出现**多个独立消费/收入动作**，就必须拆成多笔。典型线索包括：
           - 显式连接词：`还有 / 又 / 另外 / 接着 / 然后 / 对了 / 顺便`；句号 `。` / 分号 `；`
           - **多个"动作+金额"组合紧邻出现，即使没有任何连接词或标点**，也算多笔。例如：
             · `吃饭花了20打车花了10块` → 2 笔：`{餐饮 20}` + `{交通 10}`
             · `早饭15午饭30晚饭50` → 3 笔
             · `买菜20买水果15` → 2 笔
           - 判断标准：若发现第二个金额，且该金额有独立的消费/收入语境（动词或品类词），就必须新起一笔。
           - 如果只是一笔账拆账（"A付了30B付了50我们一起吃的"），保持 1 笔。
        3. **时间推断**：
           - 如果文本包含"刚才"、"今天"，请基于当前日期（\(currentDate)）推算具体日期。
           - 如果未提及时间，默认为当前时间。
           - 格式统一为 `YYYY-MM-DD HH:mm:ss`。
        4. **分类匹配**：
           - `category` 字段必须严格从提供的【分类列表】中选择最匹配的一项。
           - 如果无法匹配，归为"其他"。
        5. **金额提取**：
           - 提取纯数字，不要包含货币符号。
           - 如果是中文数字（如"三十块"），请转换为阿拉伯数字（30）。
        6. **非账单判定（重要）**：
           - 如果输入内容**完全未提及金额**，或整体**与消费/收入/账单无关**（例如聊天对话、笑话、诗歌、广告文案、菜单图片、通讯录截图、系统通知等），必须返回空账单数组：`{"bills": []}`
           - **宁可返回空也不要编造金额**。如果仅仅因为不确定金额就生造一个数字，算严重错误。
        7. **输出格式**：
           - 顶层必须是一个 JSON 对象：`{"bills": [ ... ]}`（数组中每个元素代表一笔交易；无账单时数组为空）。
           - 不要使用 Markdown 代码块（即不要输出 ```json ... ```）。
           - 不要输出任何解释性文字。

        ### 字段定义：
        - `occurred_at`: 交易时间（字符串，格式 `YYYY-MM-DD HH:mm:ss`）
        - `amount`: 金额（Number，纯数字不含货币符号；**必须 > 0**）
        - `category`: 分类（String，必须来自【分类列表】；无法匹配时填 "其他"）
        - `direction`: 收支方向（String，只能是 `"expense"` 或 `"income"`）
        - `note`: 备注简述（String）

        ### 【分类列表】
        \(categoriesLine)

        ### 【用户原始文本 · 来源：\(sourceLabel)】
        \(asrText)

        ### 输出示例：
        - 单笔（含金额）：`{"bills":[{"occurred_at":"\(currentDate)","amount":30,"category":"餐饮","direction":"expense","note":"早餐"}]}`
        - 多笔无连接词："吃饭花了20打车花了10块" → `{"bills":[{"occurred_at":"\(currentDate)","amount":20,"category":"餐饮","direction":"expense","note":"吃饭"},{"occurred_at":"\(currentDate)","amount":10,"category":"交通","direction":"expense","note":"打车"}]}`
        - 非账单 / 无金额：`{"bills":[]}`
        """
    }
}
