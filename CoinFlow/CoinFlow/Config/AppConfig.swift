//  AppConfig.swift
//  CoinFlow · M1 → M6
//
//  单例配置访问器：从 Bundle 内的 Config.plist 读取 API Key / Base URL 等。
//  缺失文件 / 缺失 key → 返回空字符串（不崩溃），让 App 在未配置情况下也能启动到主页面，
//  仅当真正调用对应能力（LLM / OCR / ASR）时由调用方报错。

import Foundation

final class AppConfig {

    // MARK: - Singleton
    static let shared = AppConfig()

    // MARK: - Keys
    enum Key: String {
        // LLM 选型
        case llmTextProvider      = "LLM_Text_Provider"
        case llmVisionProvider    = "LLM_Vision_Provider"
        // DeepSeek
        case deepseekAPIKey       = "DeepSeek_API_Key"
        case deepseekBaseURL      = "DeepSeek_BaseURL"
        case deepseekModel        = "DeepSeek_Model"
        // OpenAI
        case openAIKey            = "OpenAI_API_Key"
        case openAIBaseURL        = "OpenAI_BaseURL"
        case openAIModel          = "OpenAI_Model"
        // Doubao
        case doubaoAPIKey         = "Doubao_API_Key"
        case doubaoBaseURL        = "Doubao_BaseURL"
        case doubaoEndpointID     = "Doubao_Endpoint_ID"
        case doubaoVisionEndpointID = "Doubao_Vision_Endpoint_ID"
        // Qwen
        case qwenAPIKey           = "Qwen_API_Key"
        case qwenBaseURL          = "Qwen_BaseURL"
        case qwenModel            = "Qwen_Model"
        case qwenVisionModel      = "Qwen_Vision_Model"
        // ModelScope（魔搭）
        case modelScopeToken      = "ModelScope_AccessToken"
        case modelScopeBaseURL    = "ModelScope_BaseURL"
        case modelScopeVisionModel = "ModelScope_Vision_Model"
        case modelScopeTextModel  = "ModelScope_Text_Model"
    }

    enum LLMTextProvider: String {
        case deepseek, openai, doubao, qwen, modelscope, stub
    }
    enum LLMVisionProvider: String {
        case qwen, doubao, openai, modelscope, stub
    }

    // MARK: - Storage
    private let dict: [String: Any]
    let plistURL: URL?

    private init() {
        let bundle = Bundle.main
        if let realURL = bundle.url(forResource: "Config", withExtension: "plist"),
           let data = try? Data(contentsOf: realURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            self.dict = plist
            self.plistURL = realURL
        } else if let exampleURL = bundle.url(forResource: "Config.example", withExtension: "plist"),
                  let data = try? Data(contentsOf: exampleURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            self.dict = plist
            self.plistURL = exampleURL
        } else {
            self.dict = [:]
            self.plistURL = nil
        }
    }

    // MARK: - Typed accessors
    func string(_ key: Key) -> String { (dict[key.rawValue] as? String) ?? "" }
    func isConfigured(_ key: Key) -> Bool { !string(key).isEmpty }

    // MARK: - LLM Text provider

    var llmTextProvider: LLMTextProvider {
        LLMTextProvider(rawValue: string(.llmTextProvider).lowercased()) ?? .stub
    }

    var isLLMTextConfigured: Bool {
        switch llmTextProvider {
        case .stub:       return false
        case .deepseek:   return isConfigured(.deepseekAPIKey)
        case .openai:     return isConfigured(.openAIKey)
        case .doubao:     return isConfigured(.doubaoAPIKey) && isConfigured(.doubaoEndpointID)
        case .qwen:       return isConfigured(.qwenAPIKey)
        case .modelscope: return isConfigured(.modelScopeToken)
        }
    }

    var llmVisionProvider: LLMVisionProvider {
        LLMVisionProvider(rawValue: string(.llmVisionProvider).lowercased()) ?? .stub
    }

    var isLLMVisionConfigured: Bool {
        switch llmVisionProvider {
        case .stub:       return false
        case .qwen:       return isConfigured(.qwenAPIKey)
        case .doubao:     return isConfigured(.doubaoAPIKey)
        case .openai:     return isConfigured(.openAIKey)
        case .modelscope: return isConfigured(.modelScopeToken)
        }
    }

    // MARK: - DeepSeek
    var deepseekAPIKey: String { string(.deepseekAPIKey) }
    var deepseekBaseURL: String {
        let v = string(.deepseekBaseURL)
        return v.isEmpty ? "https://api.deepseek.com/v1" : v
    }
    var deepseekModel: String {
        let v = string(.deepseekModel)
        return v.isEmpty ? "deepseek-v4-flash" : v
    }

    // MARK: - OpenAI
    var openAIKey: String { string(.openAIKey) }
    var openAIBaseURL: String {
        let v = string(.openAIBaseURL)
        return v.isEmpty ? "https://api.openai.com/v1" : v
    }
    var openAIModel: String {
        let v = string(.openAIModel)
        return v.isEmpty ? "gpt-4o-mini" : v
    }

    // MARK: - Doubao
    var doubaoAPIKey: String { string(.doubaoAPIKey) }
    var doubaoBaseURL: String {
        let v = string(.doubaoBaseURL)
        return v.isEmpty ? "https://ark.cn-beijing.volces.com/api/v3" : v
    }
    var doubaoEndpointID: String       { string(.doubaoEndpointID) }
    /// 视觉模型 ID：优先用用户在 plist 配置的 `Doubao_Vision_Endpoint_ID`
    /// （可填火山控制台创建的 ep-xxx 推理接入点，或带版本日期的官方模型 ID）；
    /// 空则使用官方推荐默认值 doubao-seed-2-0-lite-260215（Seed 2.0 lite 多模态旗舰，
    /// 需先在火山控制台「开通管理」中激活该模型）
    var doubaoVisionEndpointID: String {
        let v = string(.doubaoVisionEndpointID)
        return v.isEmpty ? "doubao-seed-2-0-lite-260215" : v
    }

    // MARK: - Qwen
    var qwenAPIKey: String { string(.qwenAPIKey) }
    var qwenBaseURL: String {
        let v = string(.qwenBaseURL)
        return v.isEmpty ? "https://dashscope.aliyuncs.com/compatible-mode/v1" : v
    }
    var qwenModel: String {
        let v = string(.qwenModel)
        return v.isEmpty ? "qwen-turbo" : v
    }
    var qwenVisionModel: String {
        let v = string(.qwenVisionModel)
        return v.isEmpty ? "qwen-vl-ocr-2025-11-20" : v
    }

    // MARK: - ModelScope（魔搭 API-Inference，OpenAI 兼容）
    var modelScopeToken: String { string(.modelScopeToken) }
    var modelScopeBaseURL: String {
        let v = string(.modelScopeBaseURL)
        return v.isEmpty ? "https://api-inference.modelscope.cn/v1" : v
    }
    var modelScopeVisionModel: String {
        let v = string(.modelScopeVisionModel)
        return v.isEmpty ? "Qwen/Qwen3-VL-235B-A22B-Instruct" : v
    }
    /// 文本 LLM 模型：默认 moonshotai/Kimi-K2.5（实测 0.24s 最快）；
    /// 可独立改为 Qwen/Qwen3-Next-80B-A3B-Instruct / Qwen/Qwen3-VL-235B-A22B-Instruct 等
    var modelScopeTextModel: String {
        let v = string(.modelScopeTextModel)
        return v.isEmpty ? "moonshotai/Kimi-K2.5" : v
    }

    // MARK: - Tencent OCR / Aliyun ASR
    //
    // 已于 2026-05-10 用户反馈中整体移除（删除 backend + 配置）。
    // 历史 Record / VoiceSession 数据中残留的 ocr_api / aliyun engine 值仍可被
    // 模型 enum 反序列化，但运行时不再有对应路径。

    // MARK: - Debug
    var sourceDescription: String {
        guard let url = plistURL else { return "未注入（缺失 Config.plist 与 Config.example.plist）" }
        return url.lastPathComponent
    }

    func configurationSummary() -> [(name: String, ok: Bool)] {
        [
            ("LLM 文本 (\(llmTextProvider.rawValue))", isLLMTextConfigured),
            ("LLM 视觉 (\(llmVisionProvider.rawValue))", isLLMVisionConfigured)
        ]
    }
}
