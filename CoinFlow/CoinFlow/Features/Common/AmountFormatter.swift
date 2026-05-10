//  AmountFormatter.swift
//  CoinFlow · M3.2
//
//  金额展示统一规则（§5.5.8 InlineStatsBar / §5.5.9 详情）：
//  - 千分位
//  - 去尾零（12500.00 → 12,500；38.50 → 38.5）
//  - **不带方向符号**（全 App 统一去掉 +/-，方向只由颜色表达；
//    旧 `signed(_:kind:)` 已废弃于 2026-05-10 用户反馈）

import Foundation

enum AmountFormatter {

    /// 显示用：「12,500」「38.5」，不带货币符。
    static func display(_ amount: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = true
        return f.string(from: amount as NSDecimalNumber) ?? "0"
    }

    /// 计算总额：批量 record 的 expense / income 拆分小计。
    static func split(_ records: [Record], categoryKindLookup: (String) -> CategoryKind) -> (expense: Decimal, income: Decimal) {
        var exp: Decimal = 0
        var inc: Decimal = 0
        for r in records {
            let k = categoryKindLookup(r.categoryId)
            switch k {
            case .expense: exp += r.amount
            case .income:  inc += r.amount
            }
        }
        return (exp, inc)
    }
}
