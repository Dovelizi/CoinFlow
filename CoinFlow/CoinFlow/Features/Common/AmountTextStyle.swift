//  AmountTextStyle.swift
//  CoinFlow · 全局金额字号自适应
//
//  统一规则（2026-05-10 用户决策 v3 · 温和缩放）：
//  金额字号根据**数值大小**分档缩放，避免按字符数动态算法导致
//  "每输入一位字号就抖一下"的不稳定体验。
//
//  数值档位（金额绝对值，含合法上限 1 亿与超额兜底）：
//   < 100,000              → ×1.00（base 原始大小）
//   100,000 ~ 9,999,999    → ×0.85
//   10,000,000 ~ 99,999,999 → ×0.70
//   100,000,000 ~ 999,999,999 → ×0.60   （含 vm 上限 1 亿合法值）
//   ≥ 1,000,000,000        → ×0.50      （vm 校验阻拦后的兜底）
//
//  说明：
//   - vm 业务上限 1 亿（NewRecordViewModel.parsedAmount）；1 亿临界值在 ×0.60 档，
//     base 36 → 21.6pt，base 44 → 26.4pt，仍清晰可读。
//   - ≥ 10 亿 仅为编辑态超额输入兜底（用户疯狂打字时），保证布局不被撑开。
//
//  字符兜底：
//   编辑态用户可能输入 16 位以上的数字串（vm 红字提示但不阻断），
//   此时数值档位与字符兜底取较小者，确保字段始终不溢出父容器。
//
//  Text vs TextField：
//   - Text：用 `.amountAutoFit(scaleFloor:)` 让 SwiftUI 内置缩放，
//     scaleFloor 兜底极端宽度（字体度量误差）。
//   - TextField：SwiftUI 不响应 minimumScaleFactor，必须用
//     `AmountFontScale.scaledSize(base:, forText:)` 手算字号。

import SwiftUI

// MARK: - 数值档位计算

enum AmountFontScale {

    /// 根据金额数值返回字号缩放倍数（1.00 / 0.85 / 0.70 / 0.60 / 0.50）。
    static func scale(forValue value: Decimal) -> CGFloat {
        let abs = value < 0 ? -value : value
        if abs < Decimal(100_000)       { return 1.00 }
        if abs < Decimal(10_000_000)    { return 0.85 }
        if abs < Decimal(100_000_000)   { return 0.70 }
        if abs < Decimal(1_000_000_000) { return 0.60 }
        return 0.50
    }

    /// 直接返回缩放后的字号（base × 数值档位倍数）。
    /// - Parameter base: 视觉基准字号（如 44 / 36 / 30 / 17）
    /// - Parameter value: 金额数值
    static func scaledSize(base: CGFloat, forValue value: Decimal) -> CGFloat {
        base * scale(forValue: value)
    }

    /// 根据金额**字符串**返回缩放后的字号。
    /// 用于 TextField 编辑态：把 amountText 解析成 Decimal 走数值档位；
    /// 解析失败（空串/非法字符）按 base 原始大小返回。
    ///
    /// 设计：仅按数值档位缩放，不再做字符数兜底。
    /// 因为 vm 已经将金额硬上限锁定在 1 亿（`NewRecordViewModel.amountHardLimit`），
    /// 最长合法字符串 `100000000.00`（12 字符）在最低档 0.60 倍下的渲染宽度
    /// 远小于卡片可用宽度，不会撑开父容器。
    static func scaledSize(base: CGFloat, forText text: String) -> CGFloat {
        let cleaned = text.replacingOccurrences(of: ",", with: "")
        guard let d = Decimal(string: cleaned), d > 0 else { return base }
        return scaledSize(base: base, forValue: d)
    }
}

// MARK: - View 修饰器（Text 自适应）
//
// 用于 SwiftUI Text 显示金额（非编辑态）。
// 内部用 `minimumScaleFactor` 让 SwiftUI 在父容器宽度不够时自动缩小。
//
// 设计取舍：
// - 用 `View` 扩展（非 `Text` 扩展）：避免编译器在 `.foregroundStyle(...).amountAutoFit(...)`
//   链路上做返回类型回填时把整段错配为 iOS 17+ API。
extension View {
    /// 金额视图统一自适应：单行 + 可缩放至 base × scaleFloor
    /// - Parameter scaleFloor: 最小字号比例（默认 0.50，与数值最低档一致）
    func amountAutoFit(base _: CGFloat = 44, scaleFloor: CGFloat = 0.50) -> some View {
        self
            .lineLimit(1)
            .minimumScaleFactor(scaleFloor)
            .allowsTightening(true)
    }

    /// 金额组（含 ¥ 与数字混排）的统一自适应。语义同 amountAutoFit，单独命名仅为可读性。
    func amountGroupAutoFit(scaleFloor: CGFloat = 0.50) -> some View {
        self
            .lineLimit(1)
            .minimumScaleFactor(scaleFloor)
            .allowsTightening(true)
    }
}
