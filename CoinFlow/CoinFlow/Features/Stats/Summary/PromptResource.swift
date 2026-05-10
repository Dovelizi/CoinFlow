//  PromptResource.swift
//  CoinFlow · M10
//
//  通用 prompt 资源加载器。
//  约定：所有 prompt .md 文件统一放在 `Resources/Prompts/`，文件名作为 case rawValue。
//
//  设计取舍：
//  - 不在加载时做模板渲染（该职责交给上层 PromptBuilder），本类仅负责"读 bundle 字节"
//  - 加载失败 → 抛 LocalizedError，上层捕获后用兜底字符串（避免崩溃）
//  - 进程内缓存：同一 .md 不重复读盘（资源稳定，进程级缓存安全）

import Foundation

enum PromptResourceError: Error, LocalizedError {
    case notFound(name: String)
    case decodeFailed(name: String)

    var errorDescription: String? {
        switch self {
        case .notFound(let n):     return "Prompt 资源未找到：\(n)"
        case .decodeFailed(let n): return "Prompt 资源解码失败：\(n)"
        }
    }
}

enum PromptResource: String {
    case billsSummarySystem = "BillsSummary.system"

    /// 文件扩展名（不含点）。
    var ext: String { "md" }

    /// 同步加载：读 bundle 内 .md 文件原始字符串。
    /// 失败时上层应捕获并使用 builder 内置兜底（不要让总结链路因 .md 缺失而崩溃）。
    func load() throws -> String {
        if let cached = Self.cache[self.rawValue] { return cached }
        guard let url = Bundle.main.url(forResource: self.rawValue, withExtension: self.ext) else {
            throw PromptResourceError.notFound(name: "\(self.rawValue).\(self.ext)")
        }
        guard let data = try? Data(contentsOf: url),
              let s = String(data: data, encoding: .utf8) else {
            throw PromptResourceError.decodeFailed(name: self.rawValue)
        }
        Self.cache[self.rawValue] = s
        return s
    }

    /// 兼容性兜底：bundle 加载失败时调用方可用此方法拿到一个最小可用的 system prompt
    /// 保证 LLM 链路即使资源丢失也不会硬崩。
    func fallback() -> String {
        switch self {
        case .billsSummarySystem:
            return Self.billsSummaryFallback
        }
    }

    // MARK: - Private

    private static var cache: [String: String] = [:]

    /// 极简兜底；正式版本永远应从 .md 加载。
    private static let billsSummaryFallback = """
    你是一个温暖、幽默的中文记账助手。
    基于 user 提供的账单数据，输出 Part 1（情绪叙事 120-200 字）+ Part 2（核心财务体检 / 消费地图 / 行为显微镜 三个 markdown 表格小节）。
    禁止官方话术、说教、虚构用户没有的消费细节。直接输出结果，不要任何前后缀。
    """
}
