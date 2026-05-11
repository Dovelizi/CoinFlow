//  BillsOCRPromptBuilder.swift
//  CoinFlow · OCR / 视觉账单识别专用 Prompt
//
//  使用场景：
//   1. 视觉 LLM 直识图（BillsVisionLLMClient）→ buildForImage(...)
//   2. 本地 Vision OCR 出文本回落到文本 LLM → buildForText(rawText:...)
//   两者共用同一主体规则，仅"输入类型"描述切换。
//
//  与语音 Prompt 的关键差异：
//   - 处理截图特有结构（顶部品牌 logo / 列表行 / ±号金额 / 商户列）
//   - merchant_type 必填（5 选 1）
//   - 防止订单号 / 流水号 / 卡号被误判为金额
//   - 抵扣行只取实付，不当 2 笔
//   - 分期账单只取「当前月份的那行」
//   - **不做按天展开**（截图场景不会出现"每天 X 块"的语义）

import Foundation

enum BillsOCRPromptBuilder {

    /// 入口 1：视觉 LLM 直识图。Prompt 不含 OCR 文本，由视觉模型直接看图片。
    static func buildForImage(today: Date,
                              tz: TimeZone,
                              allowedCategories: [String]) -> String {
        return buildBody(inputType: .image,
                         payload: nil,
                         today: today, tz: tz,
                         allowedCategories: allowedCategories)
    }

    /// 入口 2：纯文本 LLM。Vision 本地 OCR 出文本后用此入口。
    static func buildForText(rawText: String,
                             today: Date,
                             tz: TimeZone,
                             allowedCategories: [String]) -> String {
        return buildBody(inputType: .text,
                         payload: rawText,
                         today: today, tz: tz,
                         allowedCategories: allowedCategories)
    }

    // MARK: - Internal

    private enum InputKind {
        case image
        case text

        var label: String {
            switch self {
            case .image: return "账单截图图片"
            case .text:  return "账单截图的 OCR 文本"
            }
        }
    }

    private static func buildBody(inputType: InputKind,
                                  payload: String?,
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
        let curMonth: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM"
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = tz
            return f.string(from: today)
        }()

        let categoriesLine = allowedCategories.isEmpty
            ? "（用户尚未自定义分类，无法匹配时填 \"其他\"）"
            : allowedCategories.joined(separator: " / ")

        // 输入区块：image 模式不附 payload；text 模式附原始 OCR 文本
        let inputBlock: String = {
            switch inputType {
            case .image:
                return "（图片已通过 vision 模态附在本次请求中，请直接观察图片内容）"
            case .text:
                let safe = payload ?? ""
                return """
                以下是该截图的原始 OCR 文本（注意 OCR 可能存在换行错误、错别字、多列被拼成一行）：
                ----
                \(safe)
                ----
                """
            }
        }()

        return """
        你是一个账单识别专家。任务：从一张\(inputType.label)中提取所有独立交易，并以 JSON 格式返回。

        ### 当前时间参考
        - 现在：\(nowStr)（\(tz.identifier)）
        - 今天：\(todayStr)
        - 当前月份：\(curMonth)

        ### 用户已有分类白名单
        \(categoriesLine)

        ### 处理规则

        1. 来源识别（决定 merchant_type，必填字段）
           优先从顶部标题栏 / 状态栏文案 / 主色调 / logo 判断：
           - "微信支付 / WeChat Pay / 财付通 / 微信钱包 / 零钱"，绿色 #07C160 主色 → "微信"
           - "支付宝 / Alipay / 蚂蚁 / 芝麻 / 花呗 / 借呗"，蓝色 #1677FF 主色 → "支付宝"
           - "抖音 / 抖音月付 / 抖音支付 / DOU+"，黑色底 → "抖音"
           - "工商/建设/招商/农业/中国/交通/浦发/兴业/平安/民生/光大/邮政 银行 / 银行卡 / 信用卡账单 / 还款" → "银行"
           - 以上都不明显 → "其他"

        2. 多笔识别
           **核心判定**：只要图中存在下列任一"已发生付款"语义，就必须至少产生 1 笔账单：
               实付 / 实付金额 / 已付 / 已付金额 / 已支付 / 付款金额 / 支付金额
               订单金额 / 消费金额 / 交易金额 / 到账金额 / 入账金额
               合计支付 / 本单实付 / 需付款 / 应付款 / 待支付（已完成状态）
           即使 UI 是"团购待使用券 / 订单详情 / 费用明细弹层 / 电子发票"等非经典账单流水页，
           只要含实付一行，也**必须**当作一笔账单提取。

           典型布局：一张图常含多条独立记录，必须全部提取。线索：
           - 列表型：相同结构行重复（商家名 / 时间 / 金额 成组）→ 每行 1 笔
           - 汇总页："最近交易 / 账单明细 / 本月账单" 标题下的列表
           - 单笔详情页 / 订单详情 / 费用明细弹层 / 团购券详情：**只提取"实付 / 已付"那 1 笔**
           - "-XX.XX" / "+XX.XX" 混排：各自提取，direction 分开判断

           **不要重复或误拆**（同一笔只算 1 笔，以"实付/已付/付款金额"为准）：
           - "商品 ¥802 / 优惠 -¥571 / 实付 ¥230" → 只取**实付 230**，商品原价与各级优惠**都不算账单**
           - "参考价 / 原价 / 划线价 / 市场价" → 不是账单，忽略
           - "团购优惠 / 直降优惠 / 优惠券 / 支付优惠 / 立减 / 抵扣" → 不是账单，忽略
           - "券面额 / 红包金额 / 满减额"（营销装饰，如红色券 Banner 上的 ¥22 / ¥1 / ¥3）→ 不是账单，忽略
           - 分期账单"总额 3000 / 共 6 期 / 1 月 500 / 2 月 500 ..." → 只取**当前月份（\(curMonth)）的那行**；如果都没有匹配的月份则取首期或总额行（任选其一）
           - 页脚"累计 / 合计 / 本期待还"是聚合数 → 不提取

        3. amount 提取（核心）
           - 优先从以下"已发生付款"关键词附近的数字中选取（按优先级由高到低）：
               **实付 / 实付金额 / 已付 / 已付金额 / 已支付 / 合计支付 / 本单实付 / 需付款**
               付款金额 / 支付金额 / 订单金额 / 消费金额 / 交易金额 / 到账金额 / 入账金额
               应付 / 总计 / 合计 / 金额（仅当不存在上一级关键词时使用）
           - 若同一页同时出现"商品/原价/参考价"和"实付/已付"，**必须取后者**，前者视为原价展示
           - **绝不**把以下字段误判为 amount：
               · 订单号 / 交易号 / 流水号 / 商户号 / 卡号 / 手机号
               · 积分 / 里程 / 币种代码（CNY/USD）
               · 日期年月日数字
               · 分期"共 N 期 / 第 k 期"中的 N、k
               · 营销券面额（红/黄色 Banner 上的 ¥1 / ¥3 / ¥5 / ¥22 等装饰图）
               · "省 X 元 / 减 X 元 / 立减 X / 优惠 X" 等节省金额
           - amount **必须 > 0** 且 ≤ 100000000
           - 货币符号 / 千分位逗号丢弃
           - 同一笔的"-"前缀 = expense；"+"前缀 = income

        4. direction 判断
           - "+" 前缀 / "收款 / 退款 / 到账 / 转入" → "income"
           - "-" 前缀 / "付款 / 支出 / 转出 / 扣款 / 消费" → "expense"
           - 无符号但有"购买 / 订单 / 商家名" → "expense"
           - 信用卡"本期账单 / 待还款" → "expense"

        5. occurred_at 解析
           - 优先用行内显示的时间（"2026-05-08 12:34" / "昨天 18:30" / "5 月 8 日"）
           - "昨天 / 前天 / 今天" 按 \(todayStr) 推算
           - 仅有日期无时刻 → 补 "12:00:00"
           - 完全无时间 → \(nowStr)
           - 格式 "YYYY-MM-DD HH:mm:ss"，**不得晚于 \(nowStr)**

        6. category 判断（严格）
           - 只能从【白名单】选一个最贴切的
           - 商户名 → 分类映射线索（仅作提示，最终以白名单为准）：
               美团/饿了么/肯德基/麦当劳/瑞幸/星巴克/餐厅/饭店/食堂/奶茶 → 餐饮
               滴滴/高德/出租/地铁/公交/加油/12306/携程/航空                 → 交通
               京东/淘宝/拼多多/天猫/苏宁/超市/便利店/全家/罗森               → 购物 / 日用
               电信/移动/联通/宽带/话费/流量                                 → 通讯
               医院/药店/同仁堂/挂号                                         → 医疗
               房租/物业/水电/燃气/暖气                                      → 居家
               电影/KTV/演出/游戏/Steam/网易/腾讯视频                         → 娱乐
               学费/培训/学习/得到/知乎/极客                                 → 教育
               工资代发 / 退款 / 红包收款                                    → 工资 / 收入
           - 无法对应 → "其他"

        7. note 生成
           - 优先用商户名（≤ 20 字）；无商户则用"消费类目 + 关键词"
           - ≤ 30 字；不要复述金额或日期
           - OCR 不清的商户名取最可能拼写，避免乱码入库

        8. missing_fields
           - amount / occurred_at / direction / category 任一不可靠 → 放入数组
           - 全部补齐 → 空数组或省略

        9. 非账单兜底
           - 与账单无关（菜单图 / 通讯录 / 聊天 / 新闻 / 表情包 / 广告 / 单纯二维码页）→ {"bills":[]}
           - 是账单框架但金额看不清 / 被遮挡 → {"bills":[]}
           - **宁可返回空也不要瞎猜数字**

        10. 输出格式
            - 顶层必须是对象：{"bills":[ ... ]}
            - 每笔 **merchant_type 必填**："微信" / "支付宝" / "抖音" / "银行" / "其他" 之一
            - **不要** markdown 代码块包装
            - **不要** 解释文字

        ### 输入
        \(inputBlock)

        ### 输出示例

        示例 A（微信账单截图 · 3 笔列表）：
        {"bills":[
          {"occurred_at":"\(todayStr) 12:32:00","amount":38.5,"direction":"expense","category":"餐饮","note":"瑞幸咖啡","merchant_type":"微信","missing_fields":[]},
          {"occurred_at":"\(todayStr) 09:15:00","amount":12,"direction":"expense","category":"交通","note":"滴滴快车","merchant_type":"微信","missing_fields":[]},
          {"occurred_at":"\(todayStr) 08:00:00","amount":5000,"direction":"income","category":"工资","note":"工资代发","merchant_type":"微信","missing_fields":[]}
        ]}

        示例 B（非账单图 / 菜单图 / 聊天截图）：
        {"bills":[]}

        示例 C（单笔明细页）：
        {"bills":[
          {"occurred_at":"\(todayStr) 12:32:00","amount":38.5,"direction":"expense","category":"餐饮","note":"瑞幸咖啡 中杯拿铁","merchant_type":"微信","missing_fields":[]}
        ]}

        示例 D（团购券 / 订单费用明细 · 只取实付 1 笔）：
        输入线索：商品 ¥802 / 参考价 1件×¥802 / 优惠 -¥571.22（团购优惠 / 直降优惠 / 优惠券 / 支付优惠） / **实付 ¥230.78**
        输出（营销券面额 ¥22 / ¥1 / ¥3 与各级优惠**都不产生账单**）：
        {"bills":[
          {"occurred_at":"\(todayStr) 12:00:00","amount":230.78,"direction":"expense","category":"餐饮","note":"虾聚一堂 4-5人餐","merchant_type":"其他","missing_fields":[]}
        ]}
        """
    }
}
