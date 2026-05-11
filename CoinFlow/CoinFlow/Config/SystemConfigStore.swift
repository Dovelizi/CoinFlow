//  SystemConfigStore.swift
//  CoinFlow
//
//  系统配置存储（用户在 App 内可配置的运行时参数）：
//  - 飞书：App ID（明文 UD）+ App Secret（Keychain）+ 4 项可选高级字段（明文 UD）
//  - 文本 LLM：provider / baseURL / model（明文 UD）+ apiKey（Keychain）
//  - 视觉 LLM：provider / baseURL / model（明文 UD）+ apiKey（Keychain）
//
//  完全无 plist 依赖；未配置时下游能力不可用，由 SystemConfigView 引导用户填写。

import Foundation
import Security

// MARK: - Provider 枚举（与 AppConfig 内部 enum 对齐，但暴露给 UI 使用）

enum SystemTextProvider: String, CaseIterable, Identifiable {
    case deepseek, openai, doubao, qwen, modelscope, stub

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .deepseek:   return "DeepSeek"
        case .openai:     return "OpenAI"
        case .doubao:     return "豆包（火山方舟）"
        case .qwen:       return "通义千问（DashScope）"
        case .modelscope: return "魔搭 ModelScope"
        case .stub:       return "未启用"
        }
    }

    /// 该 provider 的官方 BaseURL 默认值（用作 placeholder 和首次填充）
    var defaultBaseURL: String {
        switch self {
        case .deepseek:   return "https://api.deepseek.com/v1"
        case .openai:     return "https://api.openai.com/v1"
        case .doubao:     return "https://ark.cn-beijing.volces.com/api/v3"
        case .qwen:       return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .modelscope: return "https://api-inference.modelscope.cn/v1"
        case .stub:       return ""
        }
    }

    /// 该 provider 的默认模型（仅作 placeholder 提示，用户可改）
    var defaultModel: String {
        switch self {
        case .deepseek:   return "deepseek-v4-flash"
        case .openai:     return "gpt-4o-mini"
        case .doubao:     return "doubao-pro-128k"   // endpoint id
        case .qwen:       return "qwen-turbo"
        case .modelscope: return "moonshotai/Kimi-K2.5"
        case .stub:       return ""
        }
    }
}

enum SystemVisionProvider: String, CaseIterable, Identifiable {
    case qwen, doubao, openai, modelscope, stub

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .qwen:       return "通义千问 VL（DashScope）"
        case .doubao:     return "豆包视觉（火山方舟）"
        case .openai:     return "OpenAI（GPT-4 Vision）"
        case .modelscope: return "魔搭 ModelScope"
        case .stub:       return "未启用"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .qwen:       return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .doubao:     return "https://ark.cn-beijing.volces.com/api/v3"
        case .openai:     return "https://api.openai.com/v1"
        case .modelscope: return "https://api-inference.modelscope.cn/v1"
        case .stub:       return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .qwen:       return "qwen-vl-ocr-2025-11-20"
        case .doubao:     return "doubao-seed-2-0-lite-260215"
        case .openai:     return "gpt-4o"
        case .modelscope: return "Qwen/Qwen3-VL-235B-A22B-Instruct"
        case .stub:       return ""
        }
    }
}

// MARK: - Store

final class SystemConfigStore {

    static let shared = SystemConfigStore()

    /// 任何字段被保存后会发出此通知，AppConfig 用于刷新内部缓存
    static let didChangeNotification = Notification.Name("SystemConfigStore.didChange")

    // UserDefaults keys
    private enum UD {
        // 文本 LLM
        static let textProvider   = "syscfg.text.provider"
        static let textBaseURL    = "syscfg.text.baseURL"
        static let textModel      = "syscfg.text.model"
        // 视觉 LLM
        static let visionProvider = "syscfg.vision.provider"
        static let visionBaseURL  = "syscfg.vision.baseURL"
        static let visionModel    = "syscfg.vision.model"
        // 飞书
        static let feishuAppID    = "syscfg.feishu.app_id"
        static let feishuWiki     = "syscfg.feishu.wiki_node_token"
        static let feishuTable    = "syscfg.feishu.bills_table_id"
        static let feishuFolder   = "syscfg.feishu.folder_token"
        static let feishuOpenID   = "syscfg.feishu.owner_open_id"
    }

    // Keychain accounts
    private enum KC {
        static let service          = "com.lemolli.coinflow.syscfg"
        static let textAPIKey       = "text_api_key"
        static let visionAPIKey     = "vision_api_key"
        static let feishuAppSecret  = "feishu_app_secret"
    }

    private let ud = UserDefaults.standard

    private init() {}

    // MARK: - 文本 LLM

    var textProvider: SystemTextProvider {
        get { SystemTextProvider(rawValue: ud.string(forKey: UD.textProvider) ?? "") ?? .stub }
        set { ud.set(newValue.rawValue, forKey: UD.textProvider) }
    }
    var textBaseURL: String {
        get { ud.string(forKey: UD.textBaseURL) ?? "" }
        set { ud.set(newValue, forKey: UD.textBaseURL) }
    }
    var textModel: String {
        get { ud.string(forKey: UD.textModel) ?? "" }
        set { ud.set(newValue, forKey: UD.textModel) }
    }
    var textAPIKey: String {
        get { Self.kcRead(KC.textAPIKey) ?? "" }
        set { Self.kcWrite(KC.textAPIKey, value: newValue) }
    }

    /// 文本 LLM 是否已配置完整（provider 非 stub + baseURL/model/key 非空）
    var isTextConfigured: Bool {
        textProvider != .stub
            && !textBaseURL.isEmpty
            && !textModel.isEmpty
            && !textAPIKey.isEmpty
    }

    // MARK: - 视觉 LLM

    var visionProvider: SystemVisionProvider {
        get { SystemVisionProvider(rawValue: ud.string(forKey: UD.visionProvider) ?? "") ?? .stub }
        set { ud.set(newValue.rawValue, forKey: UD.visionProvider) }
    }
    var visionBaseURL: String {
        get { ud.string(forKey: UD.visionBaseURL) ?? "" }
        set { ud.set(newValue, forKey: UD.visionBaseURL) }
    }
    var visionModel: String {
        get { ud.string(forKey: UD.visionModel) ?? "" }
        set { ud.set(newValue, forKey: UD.visionModel) }
    }
    var visionAPIKey: String {
        get { Self.kcRead(KC.visionAPIKey) ?? "" }
        set { Self.kcWrite(KC.visionAPIKey, value: newValue) }
    }

    var isVisionConfigured: Bool {
        visionProvider != .stub
            && !visionBaseURL.isEmpty
            && !visionModel.isEmpty
            && !visionAPIKey.isEmpty
    }

    // MARK: - 飞书

    var feishuAppID: String {
        get { ud.string(forKey: UD.feishuAppID) ?? "" }
        set { ud.set(newValue, forKey: UD.feishuAppID) }
    }
    var feishuAppSecret: String {
        get { Self.kcRead(KC.feishuAppSecret) ?? "" }
        set { Self.kcWrite(KC.feishuAppSecret, value: newValue) }
    }

    /// 高级（默认空）：Wiki 模式 + 自动建表回调位置 + 协作者开放
    var feishuWikiNodeToken: String {
        get { ud.string(forKey: UD.feishuWiki) ?? "" }
        set { ud.set(newValue, forKey: UD.feishuWiki) }
    }
    var feishuBillsTableId: String {
        get { ud.string(forKey: UD.feishuTable) ?? "" }
        set { ud.set(newValue, forKey: UD.feishuTable) }
    }
    var feishuFolderToken: String {
        get { ud.string(forKey: UD.feishuFolder) ?? "" }
        set { ud.set(newValue, forKey: UD.feishuFolder) }
    }
    var feishuOwnerOpenID: String {
        get { ud.string(forKey: UD.feishuOpenID) ?? "" }
        set { ud.set(newValue, forKey: UD.feishuOpenID) }
    }

    var isFeishuConfigured: Bool {
        !feishuAppID.isEmpty && !feishuAppSecret.isEmpty
    }

    // MARK: - 通知

    /// UI 保存后调用一次，让监听方刷新缓存
    func notifyDidChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    // MARK: - Keychain

    private static func kcRead(_ account: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KC.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        _ = query  // silence unused-mutated warning
        return str
    }

    private static func kcWrite(_ account: String, value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KC.service,
            kSecAttrAccount as String: account,
        ]
        if value.isEmpty {
            SecItemDelete(query as CFDictionary)
            return
        }
        let data = value.data(using: .utf8) ?? Data()
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}
