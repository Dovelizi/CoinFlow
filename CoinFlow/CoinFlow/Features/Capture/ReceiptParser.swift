//  ReceiptParser.swift
//  CoinFlow · M4
//
//  从 OCR 全文用规则提取金额/商户/时间。MVP 版本：
//  - 金额：找形如 ¥12.50 / 12.5 元 / -12.50 / 总计 12.50 等中文/英文/符号包裹的最大金额
//  - 商户：取首行中文较长的非数字短语
//  - 时间：找 yyyy-MM-dd HH:mm / yyyy/MM/dd HH:mm / yyyy年MM月dd日 等格式
//
//  M6 阶段会接 LLM 二次校对，本规则解析作 fallback 仍保留。

import Foundation

enum ReceiptParser {

    static func parse(rawText: String, confidence: Double) -> ParsedReceipt {
        let amount = extractAmount(rawText)
        let merchant = extractMerchant(rawText)
        let occurredAt = extractDate(rawText)
        return ParsedReceipt(
            amount: amount,
            merchant: merchant,
            occurredAt: occurredAt,
            confidence: confidence,
            rawText: rawText
        )
    }

    // MARK: - Amount

    /// 优先匹配「合计 / 实付 / 应付 / 总计 / 总额」后跟的金额；
    /// 否则取整段中数值最大的金额。
    private static func extractAmount(_ text: String) -> Decimal? {
        let priorityKeywords = ["合计", "实付", "应付", "总计", "总额", "实收", "金额"]
        let amountPattern = #"[¥￥$]?\s*(\d{1,7}(?:[,\d]*)(?:\.\d{1,2})?)\s*(?:元|RMB|CNY)?"#
        guard let regex = try? NSRegularExpression(pattern: amountPattern) else { return nil }

        // 1. 优先关键字附近
        for keyword in priorityKeywords {
            if let range = text.range(of: keyword) {
                let after = String(text[range.upperBound...]).prefix(40)
                let nsText = String(after) as NSString
                let matches = regex.matches(in: nsText as String,
                                            range: NSRange(location: 0, length: nsText.length))
                if let m = matches.first, m.numberOfRanges > 1 {
                    let raw = nsText.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "")
                    if let d = Decimal(string: raw), d > 0 { return d }
                }
            }
        }

        // 2. 全文最大金额
        let nsText = text as NSString
        let allMatches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var max: Decimal = 0
        for m in allMatches where m.numberOfRanges > 1 {
            let raw = nsText.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "")
            if let d = Decimal(string: raw), d > max { max = d }
        }
        return max > 0 ? max : nil
    }

    // MARK: - Merchant

    /// 取第一行非纯数字、非时间格式的中文短语作为商户。
    private static func extractMerchant(_ text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for line in lines.prefix(5) {
            // 排除纯数字、纯日期、过短行
            let digitsOnly = line.allSatisfy { $0.isNumber || $0.isPunctuation }
            let isDate = line.range(of: #"\d{4}[-/年]"#, options: .regularExpression) != nil
            if !digitsOnly && !isDate && line.count >= 3 && line.count <= 25 {
                return String(line)
            }
        }
        return nil
    }

    // MARK: - Date

    private static func extractDate(_ text: String) -> Date? {
        let patterns: [(String, String)] = [
            (#"(\d{4})[-/](\d{1,2})[-/](\d{1,2})\s+(\d{1,2}):(\d{2})"#, "yyyy-MM-dd HH:mm"),
            (#"(\d{4})年(\d{1,2})月(\d{1,2})日\s*(\d{1,2}):(\d{2})"#,    "yyyy-MM-dd HH:mm"),
            (#"(\d{4})[-/](\d{1,2})[-/](\d{1,2})"#,                      "yyyy-MM-dd"),
            (#"(\d{4})年(\d{1,2})月(\d{1,2})日"#,                         "yyyy-MM-dd")
        ]
        for (pattern, _) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsText = text as NSString
            if let m = regex.firstMatch(in: text,
                                        range: NSRange(location: 0, length: nsText.length)),
               m.numberOfRanges >= 4 {
                let y = Int(nsText.substring(with: m.range(at: 1))) ?? 0
                let mo = Int(nsText.substring(with: m.range(at: 2))) ?? 0
                let d = Int(nsText.substring(with: m.range(at: 3))) ?? 0
                let hour: Int? = m.numberOfRanges > 4 ? Int(nsText.substring(with: m.range(at: 4))) : nil
                let min: Int? = m.numberOfRanges > 5 ? Int(nsText.substring(with: m.range(at: 5))) : nil
                var comp = DateComponents()
                comp.year = y
                comp.month = mo
                comp.day = d
                comp.hour = hour ?? 12
                comp.minute = min ?? 0
                if let date = Calendar.current.date(from: comp) {
                    return date
                }
            }
        }
        return nil
    }
}
