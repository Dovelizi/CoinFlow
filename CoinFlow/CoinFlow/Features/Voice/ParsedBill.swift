//  ParsedBill.swift
//  CoinFlow · M5 · §7.5.3
//
//  LLM 多笔解析协议的 Swift 表达。字段设计严格跟随文档 Prompt 的 JSON 结构：
//    occurred_at / amount / direction / category / note / missing_fields
//  客户端 normalizedMissing() 再校验 amount/occurred_at/direction/category 合法性，
//  与 LLM 给的 missing_fields 取并集。

import Foundation

enum BillDirection: String, Codable {
    case expense
    case income
}

/// 解析后的单笔账（可变：向导里用户逐字段补齐 / 修改）
struct ParsedBill: Identifiable, Equatable {
    let id: String                      // 本地生成；非 LLM 字段，不参与 JSON 协议
    var occurredAt: Date?
    var amount: Decimal?
    var direction: BillDirection?
    /// 分类名（必须 ∈ 用户已有分类名）；向导里最终绑回 Category.id
    var categoryName: String?
    var note: String?
    /// M7-Fix23：商户类型（LLM 从截图识别：微信 / 支付宝 / 抖音 / 银行 / 其他）；
    /// 仅视觉流程使用，语音流程保持 nil。UI 用它覆盖 MerchantBrand 的启发式猜测。
    var merchantType: String?
    var missingFields: Set<String>      // {"amount","occurred_at","direction","category"}

    /// Router 传回的 engine（审计用）
    var parserEngine: ParserEngine = .ruleOnly

    /// 客户端再校验，把失败项合并入 missingFields。
    /// Fix：字段现已有合法值时必须从 missingFields 中移除，否则 LLM 首次标记缺失、
    ///      用户补齐后 `canProceed` 仍为 false（按钮永远灰着）。
    /// - Parameter required: 用户配置的必填集合
    /// - Parameter allowedCategories: 当前分类白名单（按方向过滤后的）
    func normalizedMissing(required: [String],
                           allowedCategories: [String]) -> ParsedBill {
        var missing = missingFields
        // amount
        if (amount ?? 0) > 0 {
            missing.remove("amount")
        } else if required.contains("amount") {
            missing.insert("amount")
        }
        // occurred_at
        if occurredAt != nil {
            missing.remove("occurred_at")
        } else if required.contains("occurred_at") {
            missing.insert("occurred_at")
        }
        // direction
        if direction != nil {
            missing.remove("direction")
        } else if required.contains("direction") {
            missing.insert("direction")
        }
        // category：如果 LLM 给的 name 不在白名单就清掉让用户重选
        var copy = self
        if let n = categoryName, !allowedCategories.contains(n) {
            copy.categoryName = nil
            if required.contains("category") { missing.insert("category") }
        } else if copy.categoryName != nil {
            missing.remove("category")
        } else if required.contains("category") {
            missing.insert("category")
        }
        copy.missingFields = missing
        return copy
    }
}

extension ParsedBill {
    /// 一个空笔（"全缺失"）工厂，兜底 UI 显示用
    static func empty(required: [String]) -> ParsedBill {
        ParsedBill(
            id: UUID().uuidString,
            occurredAt: nil,
            amount: nil,
            direction: nil,
            categoryName: nil,
            note: nil,
            missingFields: Set(required)
        )
    }
}
