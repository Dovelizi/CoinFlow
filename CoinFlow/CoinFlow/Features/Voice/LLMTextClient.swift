//  LLMTextClient.swift
//  CoinFlow · M6 · §7.5.3 LLM 多笔解析
//
//  抽象出 LLM 文本客户端接口，让 BillsLLMParser 只关心 prompt→JSON，具体 provider
//  可在 `AppConfig.llmTextProvider` 切换（deepseek / openai / doubao / qwen / stub）。
//
//  所有真 provider 均走 OpenAI 兼容协议 `/chat/completions`，仅 BaseURL / Model / Key 不同。
//  DeepSeek V4 支持 `response_format: {"type": "json_object"}`（文档页明确），因此
//  强制 JSON mode 时 prompt 中必须含"json"字样（OpenAI 规范硬性要求）。

import Foundation

/// LLM 文本调用错误。
enum LLMTextError: Error, LocalizedError {
    case notConfigured(provider: String)
    case httpError(status: Int, body: String)
    case invalidResponse(String)
    case jsonDecodeFailed(raw: String, underlying: Error)
    case timeout
    case networkFailure(underlying: Error)
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .notConfigured(let p):       return "\(p) 未配置 API Key"
        case .httpError(let s, let b):    return "LLM HTTP \(s)：\(b.prefix(200))"
        case .invalidResponse(let s):     return "LLM 响应格式异常：\(s.prefix(200))"
        case .jsonDecodeFailed(_, let e): return "LLM JSON 解析失败：\(e.localizedDescription)"
        case .timeout:                    return "LLM 请求超时"
        case .networkFailure(let e):      return "LLM 网络失败：\(e.localizedDescription)"
        case .rateLimited:                return "LLM 请求被限流，请稍后再试"
        }
    }
}

/// LLM 文本客户端抽象。
protocol LLMTextClient {
    /// Provider 标识（用于审计写入 voice_session.parser_engine）
    var providerName: String { get }
    /// 发送 prompt 并**强制要求**返回严格 JSON。
    /// - Returns: 原始 JSON 文本（由调用方用 JSONDecoder 解码）
    func completeJSON(prompt: String) async throws -> String
}

/// Stub：M5 规则模式使用；永远抛 `notConfigured`，由 BillsLLMParser 捕获后降级到规则引擎。
struct StubLLMTextClient: LLMTextClient {
    let providerName = "stub"
    func completeJSON(prompt: String) async throws -> String {
        throw LLMTextError.notConfigured(provider: "stub")
    }
}

// MARK: - OpenAI 兼容请求/响应模型

private struct OAChatRequest: Encodable {
    let model: String
    let messages: [Msg]
    let temperature: Double
    let response_format: [String: String]?
    struct Msg: Encodable { let role: String; let content: String }
}

private struct OAChatResponse: Decodable {
    let choices: [Choice]
    struct Choice: Decodable { let message: Msg }
    struct Msg: Decodable { let content: String }
}

private struct OAErrorResponse: Decodable {
    let error: ErrorDetail?
    struct ErrorDetail: Decodable { let message: String?; let type: String? }
}

/// OpenAI 兼容协议的通用客户端：DeepSeek / OpenAI / 豆包（ARK） / Qwen 共用。
/// 子类/实例只需注入 `baseURL / model / apiKey / providerName`。
struct OpenAICompatibleLLMClient: LLMTextClient {
    let providerName: String
    let baseURL: String            // 形如 "https://api.deepseek.com/v1"
    let model: String
    let apiKey: String
    /// 是否启用 JSON mode（DeepSeek V4 / GPT-4o 支持；豆包部分 endpoint 支持）
    let useJSONMode: Bool

    init(providerName: String,
         baseURL: String,
         model: String,
         apiKey: String,
         useJSONMode: Bool = true) {
        self.providerName = providerName
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.useJSONMode = useJSONMode
    }

    func completeJSON(prompt: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw LLMTextError.notConfigured(provider: providerName)
        }
        // M7-Fix19：首次超时立即重试 1 次（仅超时错误重试；HTTP 错误/限流/解码失败不重试）
        do {
            return try await sendOnce(prompt: prompt)
        } catch LLMTextError.timeout {
            NSLog("[LLM] \(providerName) 首次请求超时（15s），立即重试 1 次")
            do {
                return try await sendOnce(prompt: prompt)
            } catch LLMTextError.timeout {
                NSLog("[LLM] \(providerName) 重试仍超时，已降级到规则引擎")
                throw LLMTextError.timeout
            }
        }
    }

    /// 单次 HTTP 请求（不含重试逻辑）
    private func sendOnce(prompt: String) async throws -> String {
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                            + "/chat/completions") else {
            throw LLMTextError.invalidResponse("bad base url")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        // 15s timeout：LLM 路径作为 voice 流程的关键阶段，超过此值用户体验已显著下降，
        // 应快速降级到规则引擎；DeepSeek V4 Pro 普通短输入实测 < 5s，足够。
        req.timeoutInterval = 15
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = OAChatRequest(
            model: model,
            messages: [.init(role: "user", content: prompt)],
            temperature: 0,   // JSON 任务用 0 最稳
            response_format: useJSONMode ? ["type": "json_object"] : nil
        )
        req.httpBody = try JSONEncoder().encode(body)

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
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMTextError.httpError(status: http.statusCode, body: body)
        }

        do {
            let parsed = try JSONDecoder().decode(OAChatResponse.self, from: data)
            guard let first = parsed.choices.first else {
                throw LLMTextError.invalidResponse("empty choices")
            }
            return first.message.content
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw LLMTextError.jsonDecodeFailed(raw: raw, underlying: error)
        }
    }
}

// MARK: - Factory

enum LLMTextClientFactory {
    /// 根据 AppConfig 选择客户端。未配置时返回 Stub。
    static func make() -> LLMTextClient {
        let cfg = AppConfig.shared
        guard cfg.isLLMTextConfigured else { return StubLLMTextClient() }
        switch cfg.llmTextProvider {
        case .stub:
            return StubLLMTextClient()
        case .deepseek:
            return OpenAICompatibleLLMClient(
                providerName: "deepseek",
                baseURL: cfg.deepseekBaseURL,
                model: cfg.deepseekModel,
                apiKey: cfg.deepseekAPIKey,
                useJSONMode: true  // V4 支持
            )
        case .openai:
            return OpenAICompatibleLLMClient(
                providerName: "openai",
                baseURL: cfg.openAIBaseURL,
                model: cfg.openAIModel,
                apiKey: cfg.openAIKey,
                useJSONMode: true
            )
        case .doubao:
            // 豆包 / 火山方舟 model 字段传 endpoint ID
            return OpenAICompatibleLLMClient(
                providerName: "doubao",
                baseURL: cfg.doubaoBaseURL,
                model: cfg.doubaoEndpointID,
                apiKey: cfg.doubaoAPIKey,
                useJSONMode: true
            )
        case .qwen:
            // DashScope 的 OpenAI 兼容模式支持 response_format json
            return OpenAICompatibleLLMClient(
                providerName: "qwen",
                baseURL: cfg.qwenBaseURL,
                model: cfg.qwenModel,
                apiKey: cfg.qwenAPIKey,
                useJSONMode: true
            )
        case .modelscope:
            // M7-Fix27：魔搭 API-Inference OpenAI 兼容入口
            // 默认 model = ModelScope_Text_Model（与视觉同款 Qwen3-VL-235B，可独立改）
            return OpenAICompatibleLLMClient(
                providerName: "modelscope",
                baseURL: cfg.modelScopeBaseURL,
                model: cfg.modelScopeTextModel,
                apiKey: cfg.modelScopeToken,
                useJSONMode: true
            )
        }
    }
}
