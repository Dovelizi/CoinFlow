//  BillsVisionLLMClient.swift
//  CoinFlow · M7-Fix21 视觉 LLM 直识图
//
//  职责：把用户截图 + prompt 发给视觉 LLM，拿回结构化 bills JSON。
//
//  接入：火山方舟 OpenAI 兼容协议（/chat/completions），
//        messages.content 为 [text, image_url] 数组（OpenAI Vision 规范）。
//  默认 provider = doubao；模型 ID 从 AppConfig.doubaoVisionEndpointID 读取
//  （为空时降级到 "Doubao-1.5-vision-lite" 模型名直调）。
//
//  设计要点：
//  - 图片压缩到长边 1024px / JPEG 0.7（约 200KB），减小请求体与 LLM token 消耗
//  - response_format: json_object 强制 JSON 输出（火山方舟 vision 模型支持）
//  - 复用 BillsLLMParser 的 decodeLLMResponse 解析路径（结构与文本 LLM 完全一致）
//  - 超时 30s（视觉模型首 token 比文本慢）

import Foundation
import UIKit

/// 视觉 LLM 错误（对齐 LLMTextError 风格）
enum LLMVisionError: Error, LocalizedError {
    case notConfigured
    case imageEncodingFailed
    case httpError(status: Int, body: String)
    case invalidResponse(String)
    case timeout
    case networkFailure(underlying: Error)
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .notConfigured:           return "视觉 LLM 未配置"
        case .imageEncodingFailed:     return "图片编码失败"
        case .httpError(let s, let b): return "视觉 LLM HTTP \(s)：\(b.prefix(200))"
        case .invalidResponse(let s):  return "视觉 LLM 响应异常：\(s.prefix(200))"
        case .timeout:                 return "视觉 LLM 请求超时"
        case .networkFailure(let e):   return "视觉 LLM 网络失败：\(e.localizedDescription)"
        case .rateLimited:             return "视觉 LLM 被限流"
        }
    }
}

final class BillsVisionLLMClient {

    /// 配置（默认从 AppConfig 读取；测试可注入）
    struct Config {
        let baseURL: String
        let apiKey: String
        let model: String         // 模型 ID 或 endpoint ID
        let providerName: String  // 用于日志

        static var doubao: Config {
            let cfg = AppConfig.shared
            return Config(
                baseURL: cfg.doubaoBaseURL,
                apiKey:  cfg.doubaoAPIKey,
                model:   cfg.doubaoVisionEndpointID,
                providerName: "doubao-vision"
            )
        }

        /// Qwen-VL：阿里 DashScope OpenAI 兼容入口
        /// baseURL 已内建 `/compatible-mode/v1`；model 从 AppConfig.qwenVisionModel 读取
        static var qwen: Config {
            let cfg = AppConfig.shared
            return Config(
                baseURL: cfg.qwenBaseURL,
                apiKey:  cfg.qwenAPIKey,
                model:   cfg.qwenVisionModel,
                providerName: "qwen-vl"
            )
        }

        /// ModelScope 魔搭：API-Inference OpenAI 兼容入口
        /// 模型 ID 形如 "Qwen/Qwen2.5-VL-7B-Instruct"（带组织前缀）
        static var modelscope: Config {
            let cfg = AppConfig.shared
            return Config(
                baseURL: cfg.modelScopeBaseURL,
                apiKey:  cfg.modelScopeToken,
                model:   cfg.modelScopeVisionModel,
                providerName: "modelscope-vlm"
            )
        }

        /// M7-Fix22：按 AppConfig.llmVisionProvider 自动选
        static var active: Config {
            switch AppConfig.shared.llmVisionProvider {
            case .qwen:       return .qwen
            case .doubao:     return .doubao
            case .modelscope: return .modelscope
            case .openai:     return .doubao   // openai 暂未落地
            case .stub:       return .doubao
            }
        }
    }

    private let config: Config

    init(config: Config = .active) {
        self.config = config
    }

    /// 主入口：图片 → bills JSON 文本
    /// - Returns: LLM 返回的原始 JSON 字符串（由 BillsLLMParser.decodeLLMResponse 后续解码）
    func recognizeBills(image: UIImage,
                        allowedCategories: [String],
                        today: Date = Date(),
                        tz: TimeZone = TimeZone.current) async throws -> String {
        guard !config.apiKey.isEmpty else {
            throw LLMVisionError.notConfigured
        }

        // 1. 图片压缩并 base64 编码
        guard let imageData = compressToJPEG(image: image, maxDimension: 1024, quality: 0.7) else {
            throw LLMVisionError.imageEncodingFailed
        }
        let base64 = imageData.base64EncodedString()

        // 2. 拼 Prompt（统一走 BillsOCRPromptBuilder.buildForImage；与文本回落路径共用规则主体）
        let prompt = BillsOCRPromptBuilder.buildForImage(
            today: today,
            tz: tz,
            allowedCategories: allowedCategories
        )

        // 3. 构造请求
        let url = URL(string: config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30   // 视觉模型首 token 较慢
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // OpenAI Vision 兼容规范（火山方舟 Chat API 官方示例顺序：image_url 在前 + text 在后 + detail=high）
        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "image_url",
                         "image_url": [
                            "url": "data:image/jpeg;base64,\(base64)",
                            "detail": "high"
                         ]],
                        ["type": "text", "text": prompt]
                    ]
                ]
            ],
            "temperature": 0,
            "response_format": ["type": "json_object"]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        // 4. 发起请求 + 错误分类
        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch let e as URLError where e.code == .timedOut {
            throw LLMVisionError.timeout
        } catch let e as URLError where e.code == .cancelled {
            // M7-Fix25：URLError.cancelled 绝大多数来自：
            //  1. SwiftUI `.task` 宿主视图销毁/重建 → Swift Task.cancel() → URLSession 取消
            //  2. 服务端主动关断连接（偶发）
            // 两种情况都不是"真的识别失败"。向上抛 timeout，由调用方判断 Task.isCancelled
            // 决定是静默退出还是切 llmFailed
            throw LLMVisionError.timeout
        } catch {
            throw LLMVisionError.networkFailure(underlying: error)
        }

        guard let http = resp as? HTTPURLResponse else {
            throw LLMVisionError.invalidResponse("non-HTTP response")
        }
        if http.statusCode == 429 { throw LLMVisionError.rateLimited }
        if http.statusCode != 200 {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw LLMVisionError.httpError(status: http.statusCode, body: bodyStr)
        }

        // 5. 解析 OpenAI 兼容响应
        struct ChatResp: Decodable {
            let choices: [Choice]
            struct Choice: Decodable { let message: Msg }
            struct Msg: Decodable { let content: String }
        }
        do {
            let parsed = try JSONDecoder().decode(ChatResp.self, from: data)
            guard let content = parsed.choices.first?.message.content else {
                throw LLMVisionError.invalidResponse("empty choices")
            }
            return content
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw LLMVisionError.invalidResponse("decode failed: \(error.localizedDescription); raw=\(raw.prefix(200))")
        }
    }

    // MARK: - Helpers

    /// 长边压缩 + JPEG 编码
    private func compressToJPEG(image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1.0
        let target = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true   // JPEG 不需透明通道，加速渲染
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
