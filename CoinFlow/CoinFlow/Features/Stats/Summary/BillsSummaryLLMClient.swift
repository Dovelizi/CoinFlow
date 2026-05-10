//  BillsSummaryLLMClient.swift
//  CoinFlow · M10
//
//  专给账单总结用的 LLM 客户端薄封装。
//  - 复用 LLMTextClientFactory.make()（DeepSeek/Doubao/Qwen/OpenAI/ModelScope 自动选）
//  - 不强制 JSON mode：Part1 + Part2 是 markdown 文本，JSON mode 反而压制叙事性
//  - 单独走一个 client 实例：避免污染 voice/OCR 路径的 useJSONMode 设置
//  - timeout 30s（总结输出比 voice 解析长，给宽松超时）
//
//  设计考量：
//  - 不再做"超时立即重试 1 次"：总结是非阻塞后台任务，失败一次直接 fail，下次进 App 再触发
//  - 错误分类沿用 LLMTextError，便于上层 UI 文案一致

import Foundation

/// 账单总结 LLM 调用的薄封装。
struct BillsSummaryLLMClient {

    /// Provider 名称（用于审计写入 bills_summary.llm_provider）
    let providerName: String
    let baseURL: String
    let model: String
    let apiKey: String

    /// 从 AppConfig 选活跃 provider；保持与语音 / OCR 同一套配置入口。
    static func active() -> BillsSummaryLLMClient? {
        let cfg = AppConfig.shared
        guard cfg.isLLMTextConfigured else { return nil }
        switch cfg.llmTextProvider {
        case .stub:
            return nil
        case .deepseek:
            return .init(providerName: "deepseek",
                         baseURL: cfg.deepseekBaseURL,
                         model: cfg.deepseekModel,
                         apiKey: cfg.deepseekAPIKey)
        case .openai:
            return .init(providerName: "openai",
                         baseURL: cfg.openAIBaseURL,
                         model: cfg.openAIModel,
                         apiKey: cfg.openAIKey)
        case .doubao:
            return .init(providerName: "doubao",
                         baseURL: cfg.doubaoBaseURL,
                         model: cfg.doubaoEndpointID,
                         apiKey: cfg.doubaoAPIKey)
        case .qwen:
            return .init(providerName: "qwen",
                         baseURL: cfg.qwenBaseURL,
                         model: cfg.qwenModel,
                         apiKey: cfg.qwenAPIKey)
        case .modelscope:
            return .init(providerName: "modelscope",
                         baseURL: cfg.modelScopeBaseURL,
                         model: cfg.modelScopeTextModel,
                         apiKey: cfg.modelScopeToken)
        }
    }

    /// 发起一次 chat completion（system + user 双消息）。
    /// - Returns: LLM 返回的纯文本（应该是 JSON 字符串；调用方用 JSONDecoder 解析）
    func complete(system: String, user: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw LLMTextError.notConfigured(provider: providerName)
        }
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                            + "/chat/completions") else {
            throw LLMTextError.invalidResponse("bad base url")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        // 总结允许长 JSON 回复（含 part1 长文 + 多条 categories/insights）
        // 给 60s（魔搭 Kimi 等大模型偶尔首 token 较慢）
        req.timeoutInterval = 60
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // OpenAI 兼容协议：messages = [system, user]
        // - temperature 0.8：叙事要有人味同时控制幻觉
        // - max_tokens 4000：给 LLM 充足空间写完整 Markdown
        // - stream=false：显式关流式（部分模型如 Kimi-K2.5 默认走 SSE 会导致
        //   我们按整体 JSON 解析失败，报"数据缺失"）
        // - 关闭 response_format JSON mode（M10-Fix3 回到 markdown 链路）
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user",   "content": user]
            ],
            "temperature": 0.8,
            "max_tokens": 4000,
            "stream": false
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch let e as URLError where e.code == .timedOut {
            throw LLMTextError.timeout
        } catch {
            throw LLMTextError.networkFailure(underlying: error)
        }
        guard let http = resp as? HTTPURLResponse else {
            throw LLMTextError.invalidResponse("non-HTTP response")
        }
        if http.statusCode == 429 { throw LLMTextError.rateLimited }
        if http.statusCode != 200 {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw LLMTextError.httpError(status: http.statusCode, body: bodyStr)
        }

        // OpenAI 兼容响应壳。注意：
        //  - content 可能为 null（某些模型在 reasoning 模式下只填 reasoning_content）
        //  - 魔搭/DeepSeek 的 thinking 模型会把真正答案塞 reasoning_content
        //  - 所以两个字段都当可选读，优先 content，其次 reasoning_content
        struct ChatResp: Decodable {
            let choices: [Choice]
            struct Choice: Decodable { let message: Msg }
            struct Msg: Decodable {
                let content: String?
                let reasoning_content: String?
            }
        }
        do {
            let parsed = try JSONDecoder().decode(ChatResp.self, from: data)
            guard let msg = parsed.choices.first?.message else {
                let raw = String(data: data, encoding: .utf8) ?? ""
                NSLog("[BillsSummaryLLM] empty choices; raw=%@", raw.prefix(500) as NSString)
                throw LLMTextError.invalidResponse("empty choices")
            }
            // 主路径：content 非空
            if let c = msg.content, !c.isEmpty {
                return c
            }
            // 降级：thinking 模型可能只填 reasoning_content
            if let rc = msg.reasoning_content, !rc.isEmpty {
                NSLog("[BillsSummaryLLM] 使用 reasoning_content 作为主内容（content 为空）")
                return rc
            }
            // 两者都空：抛带原始响应的错误，方便诊断
            let raw = String(data: data, encoding: .utf8) ?? ""
            NSLog("[BillsSummaryLLM] content+reasoning_content 都为空; raw=%@",
                  raw.prefix(500) as NSString)
            throw LLMTextError.invalidResponse(
                "LLM 返回 content 为空（raw: \(raw.prefix(200)))"
            )
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? ""
            NSLog("[BillsSummaryLLM] decode 失败 err=%@ raw=%@",
                  String(describing: error),
                  raw.prefix(500) as NSString)
            throw LLMTextError.jsonDecodeFailed(raw: raw, underlying: error)
        }
    }
}
