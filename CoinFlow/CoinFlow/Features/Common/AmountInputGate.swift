//  AmountInputGate.swift
//  CoinFlow · 全局金额输入校验
//
//  统一所有金额输入入口（NewRecord / RecordDetail / VoiceWizard / CaptureConfirm）
//  的合法性校验逻辑。任何写入 amountText 的代码都必须先经过 `evaluate(_:)`，
//  根据返回的 `Decision` 决定是接受写入还是触发拦截反馈。
//
//  设计原则：
//  - **接受 / 拒绝两态**：不修正用户输入，避免光标位置丢失
//  - **按 raw 字符串判定**：不去前导零，确保超长串（如全 0）能被长度闸门拦下
//  - **数值与位数双闸门**：长度防撑屏 + Decimal 数值防越界
//
//  规则（任一不通过即拒绝，按列表顺序短路）：
//   1. 字符白名单：仅允许数字 + 至多一个小数点
//   2. 整数部分长度 ≤ 9 位（最大合法值 100000000，9 位）
//   3. 小数部分长度 ≤ 2 位
//   4. Decimal 解析后数值 ≤ 1 亿（含等号）
//
//  允许的中间态（直接接受）：空串、单独 "."、末尾 "." 如 "100."

import Foundation

enum AmountInputGate {

    /// 业务硬上限：1 亿
    static let hardLimit: Decimal = 100_000_000

    /// 整数部分最大位数（与 hardLimit 对齐：100000000 = 9 位）
    static let maxIntegerDigits: Int = 9

    /// 小数部分最大位数
    static let maxFractionDigits: Int = 2

    /// 拦截原因（驱动 UI 红字 + Modal toast 文案分流）
    enum ClampReason: Equatable {
        /// 数值超过 1 亿
        case overLimit
        /// 小数位 > 2
        case tooManyFractionDigits
        /// 整数位 > 9
        case tooManyIntegerDigits
        /// 非法字符或多个小数点
        case invalidCharacter
    }

    /// 校验结果
    enum Decision: Equatable {
        /// 接受：写入这个清洗后的字符串（仅去逗号、空白）
        case accept(String)
        /// 拒绝：调用方应触发拦截反馈，amountText 保持旧值
        case reject(ClampReason)
    }

    /// 校验 raw 输入。**不修改任何状态**，调用方据 Decision 决定下一步。
    static func evaluate(_ raw: String) -> Decision {
        // 1) 仅清洗逗号和空白（OCR/粘贴可能带逗号；不算用户拦截事件）
        let s = raw
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)

        // 2) 空串、单独 "." 直接接受（中间态）
        if s.isEmpty || s == "." {
            return .accept(s)
        }

        // 3) 字符白名单 + 单点限制
        let dotCount = s.filter { $0 == "." }.count
        let onlyDigitOrDot = s.allSatisfy { $0.isNumber || $0 == "." }
        if !onlyDigitOrDot || dotCount > 1 {
            return .reject(.invalidCharacter)
        }

        // 4) 拆分整数/小数（按 raw 字符串切，不做去前导零）
        let dotIdx = s.firstIndex(of: ".")
        let intRaw: String
        let fracRaw: String
        if let dot = dotIdx {
            intRaw = String(s[..<dot])
            fracRaw = String(s[s.index(after: dot)...])
        } else {
            intRaw = s
            fracRaw = ""
        }

        // 5) 整数位数硬限：> 9 位 → 拒（堵住超长串撑屏，含全 0 串）
        if intRaw.count > maxIntegerDigits {
            return .reject(.tooManyIntegerDigits)
        }

        // 6) 小数位数限：> 2 位 → 拒
        if fracRaw.count > maxFractionDigits {
            return .reject(.tooManyFractionDigits)
        }

        // 7) 数值上限：> 1 亿 → 拒
        //    用整体串解析（含小数），覆盖 "100000000.5" 这种边界
        let parseSrc = s.hasSuffix(".") ? String(s.dropLast()) : s
        let numeric = Decimal(string: parseSrc.isEmpty ? "0" : parseSrc) ?? 0
        if numeric > hardLimit {
            return .reject(.overLimit)
        }

        return .accept(s)
    }

    /// 拦截原因 → 红字提示文案
    static func hintText(for reason: ClampReason) -> String {
        switch reason {
        case .tooManyFractionDigits:
            return "金额仅支持小数点后两位"
        case .tooManyIntegerDigits, .overLimit:
            return "已达上限（1 亿）"
        case .invalidCharacter:
            return "包含不支持的字符"
        }
    }

    /// 是否触发"小目标"彩蛋 toast（仅 overLimit）
    static func shouldShowDreamToast(for reason: ClampReason) -> Bool {
        reason == .overLimit
    }

    /// 彩蛋 toast 文案
    static let dreamToastText = "吹🐮🍺呢，你会有一个小目标？？？"
}
