//  AppConfig.swift
//  CoinFlow
//
//  全 App 配置访问入口。内部数据源为 `SystemConfigStore`（Keychain + UserDefaults）。
//
//  关键约束：本类对外暴露的 API（如 `cfg.deepseekAPIKey` / `cfg.llmTextProvider`
//  / `cfg.isLLMTextConfigured` 等）签名与语义保持不变，所以下游调用方零改动。
//  内部把"当前激活的文本/视觉 LLM 一组配置"映射到对应 provider 的字段上：
//  例如 `cfg.deepseekAPIKey` 在 textProvider==deepseek 时返回用户填的 textAPIKey，
//  其他 provider 时返回空字符串。

import Foundation

final class AppConfig {

    // MARK: - Singleton
    static let shared = AppConfig()

    enum LLMTextProvider: String {
        case deepseek, openai, doubao, qwen, modelscope, stub
    }
    enum LLMVisionProvider: String {
        case qwen, doubao, openai, modelscope, stub
    }

    // MARK: - Storage（指向新的 SystemConfigStore）
    private let store = SystemConfigStore.shared

    private init() {
        // 监听 store 变更（保留扩展点；当前类无可变缓存，无需特别动作）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStoreDidChange),
            name: SystemConfigStore.didChangeNotification,
            object: nil
        )
    }

    @objc private func handleStoreDidChange() {
        // no-op: 所有 getter 都直接走 store 实时读取
    }

    // MARK: - LLM Text provider

    var llmTextProvider: LLMTextProvider {
        LLMTextProvider(rawValue: store.textProvider.rawValue) ?? .stub
    }

    var isLLMTextConfigured: Bool {
        store.isTextConfigured
    }

    var llmVisionProvider: LLMVisionProvider {
        LLMVisionProvider(rawValue: store.visionProvider.rawValue) ?? .stub
    }

    var isLLMVisionConfigured: Bool {
        store.isVisionConfigured
    }

    // MARK: - DeepSeek
    /// 仅当当前 textProvider == .deepseek 时返回用户填值；否则返回空，避免误用。
    var deepseekAPIKey: String  { textKey(for: .deepseek) }
    var deepseekBaseURL: String { textBase(for: .deepseek, fallback: "https://api.deepseek.com/v1") }
    var deepseekModel: String   { textModel(for: .deepseek, fallback: "deepseek-v4-flash") }

    // MARK: - OpenAI
    var openAIKey: String     { textKey(for: .openai) }
    var openAIBaseURL: String { textBase(for: .openai, fallback: "https://api.openai.com/v1") }
    var openAIModel: String   { textModel(for: .openai, fallback: "gpt-4o-mini") }

    // MARK: - Doubao
    /// 文本：API Key + Endpoint ID（豆包在 OpenAI 兼容协议里 model 字段填 endpoint id）
    var doubaoAPIKey: String     { textKey(for: .doubao) }
    var doubaoBaseURL: String    { textBase(for: .doubao, fallback: "https://ark.cn-beijing.volces.com/api/v3") }
    var doubaoEndpointID: String { textModel(for: .doubao, fallback: "") }
    /// 视觉 Endpoint ID：当 visionProvider==.doubao 时来自用户填的 visionModel
    var doubaoVisionEndpointID: String {
        guard store.visionProvider == .doubao else { return "doubao-seed-2-0-lite-260215" }
        let v = store.visionModel
        return v.isEmpty ? "doubao-seed-2-0-lite-260215" : v
    }

    // MARK: - Qwen
    /// 文本与视觉共享同一份 API Key；但本属性映射到"哪一组当前激活"。
    /// `qwenAPIKey` 用作文本路径；`qwenVisionModel` 用作视觉路径，单独走 store.visionAPIKey。
    var qwenAPIKey: String   { textKey(for: .qwen) }
    var qwenBaseURL: String  { textBase(for: .qwen, fallback: "https://dashscope.aliyuncs.com/compatible-mode/v1") }
    var qwenModel: String    { textModel(for: .qwen, fallback: "qwen-turbo") }
    /// 视觉模型 ID（仅 visionProvider==.qwen 时返回用户值）
    var qwenVisionModel: String {
        guard store.visionProvider == .qwen else { return "qwen-vl-ocr-2025-11-20" }
        let v = store.visionModel
        return v.isEmpty ? "qwen-vl-ocr-2025-11-20" : v
    }

    // MARK: - ModelScope（魔搭）
    var modelScopeToken: String   { textKey(for: .modelscope) }
    var modelScopeBaseURL: String { textBase(for: .modelscope, fallback: "https://api-inference.modelscope.cn/v1") }
    var modelScopeTextModel: String {
        textModel(for: .modelscope, fallback: "moonshotai/Kimi-K2.5")
    }
    var modelScopeVisionModel: String {
        guard store.visionProvider == .modelscope else { return "Qwen/Qwen3-VL-235B-A22B-Instruct" }
        let v = store.visionModel
        return v.isEmpty ? "Qwen/Qwen3-VL-235B-A22B-Instruct" : v
    }

    // MARK: - 视觉 LLM 直接访问入口（供 BillsVisionLLMClient 等使用）
    /// 当前激活的视觉 LLM 凭据（由 SystemConfigStore.visionProvider 决定）
    var visionLLMBaseURL: String { resolveVisionBaseURL() }
    var visionLLMAPIKey: String  { store.visionAPIKey }
    var visionLLMModel: String   { resolveVisionModel() }

    // MARK: - Debug
    var sourceDescription: String { "SystemConfigStore（用户配置）" }

    func configurationSummary() -> [(name: String, ok: Bool)] {
        [
            ("LLM 文本 (\(llmTextProvider.rawValue))", isLLMTextConfigured),
            ("LLM 视觉 (\(llmVisionProvider.rawValue))", isLLMVisionConfigured)
        ]
    }

    // MARK: - Private helpers

    /// 当当前 textProvider 等于参数 provider 时返回用户填的 apiKey；否则返回空。
    private func textKey(for provider: LLMTextProvider) -> String {
        guard llmTextProvider == provider else { return "" }
        return store.textAPIKey
    }

    private func textBase(for provider: LLMTextProvider, fallback: String) -> String {
        guard llmTextProvider == provider else { return fallback }
        let v = store.textBaseURL
        return v.isEmpty ? fallback : v
    }

    private func textModel(for provider: LLMTextProvider, fallback: String) -> String {
        guard llmTextProvider == provider else { return fallback }
        let v = store.textModel
        return v.isEmpty ? fallback : v
    }

    private func resolveVisionBaseURL() -> String {
        let v = store.visionBaseURL
        if !v.isEmpty { return v }
        switch store.visionProvider {
        case .qwen:       return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .doubao:     return "https://ark.cn-beijing.volces.com/api/v3"
        case .openai:     return "https://api.openai.com/v1"
        case .modelscope: return "https://api-inference.modelscope.cn/v1"
        case .stub:       return ""
        }
    }

    private func resolveVisionModel() -> String {
        let v = store.visionModel
        if !v.isEmpty { return v }
        switch store.visionProvider {
        case .qwen:       return "qwen-vl-ocr-2025-11-20"
        case .doubao:     return "doubao-seed-2-0-lite-260215"
        case .openai:     return "gpt-4o"
        case .modelscope: return "Qwen/Qwen3-VL-235B-A22B-Instruct"
        case .stub:       return ""
        }
    }
}