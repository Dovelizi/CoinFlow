//  FeishuTokenManager.swift
//  CoinFlow · M9
//
//  飞书 tenant_access_token 获取 + 自动刷新。
//  - 飞书 token 默认有效期 ~2 小时
//  - 我们提前 5 分钟主动刷新，避免边界过期导致请求失败
//  - 失败分类：网络错误（transient）/ 凭据错误（permanent）
//
//  API: https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal
//  Body: {"app_id": "...", "app_secret": "..."}
//  Resp: {"code": 0, "msg": "ok", "tenant_access_token": "t-xxx", "expire": 7200}

import Foundation

enum FeishuAuthError: Error, LocalizedError {
    case notConfigured
    case network(underlying: Error)
    case httpStatus(code: Int, body: String)
    case apiError(code: Int, msg: String)
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:           return "飞书未配置（缺 App ID / Secret）"
        case .network(let e):          return "飞书鉴权网络异常：\(e.localizedDescription)"
        case .httpStatus(let c, _):    return "飞书鉴权 HTTP \(c)"
        case .apiError(let c, let m):  return "飞书鉴权失败 code=\(c) msg=\(m)"
        case .decodeFailed:            return "飞书鉴权响应解析失败"
        }
    }

    /// 网络/HTTP 5xx 视为可重试；凭据/参数错误为永久失败
    var isTransient: Bool {
        switch self {
        case .network:                  return true
        case .httpStatus(let code, _):  return code >= 500
        case .apiError, .notConfigured, .decodeFailed: return false
        }
    }
}

actor FeishuTokenManager {

    static let shared = FeishuTokenManager()
    private init() {}

    // MARK: - State

    private var cachedToken: String?
    private var expiresAt: Date?

    /// 提前刷新窗口：到期前 5 分钟视为已过期
    private static let earlyRefreshWindow: TimeInterval = 5 * 60

    // MARK: - Public API

    /// 取一个有效的 tenant_access_token，必要时刷新。
    func getToken() async throws -> String {
        if let t = cachedToken, let exp = expiresAt,
           Date() < exp.addingTimeInterval(-Self.earlyRefreshWindow) {
            return t
        }
        return try await refresh()
    }

    /// 强制刷新（用于 401/403 后的重试）。
    func invalidateAndRefresh() async throws -> String {
        cachedToken = nil
        expiresAt = nil
        return try await refresh()
    }

    /// 仅用于测试：清缓存
    func reset() {
        cachedToken = nil
        expiresAt = nil
    }

    // MARK: - Private

    private func refresh() async throws -> String {
        let appID = FeishuConfig.appID
        let appSecret = FeishuConfig.appSecret
        guard !appID.isEmpty, !appSecret.isEmpty else {
            throw FeishuAuthError.notConfigured
        }

        let url = URL(string: "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["app_id": appID, "app_secret": appSecret]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 10

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw FeishuAuthError.network(underlying: error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw FeishuAuthError.decodeFailed
        }
        if http.statusCode < 200 || http.statusCode >= 300 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw FeishuAuthError.httpStatus(code: http.statusCode, body: body)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FeishuAuthError.decodeFailed
        }
        let code = (obj["code"] as? Int) ?? -1
        if code != 0 {
            let msg = (obj["msg"] as? String) ?? "unknown"
            throw FeishuAuthError.apiError(code: code, msg: msg)
        }
        guard let token = obj["tenant_access_token"] as? String, !token.isEmpty else {
            throw FeishuAuthError.decodeFailed
        }
        let expireSeconds = (obj["expire"] as? Double) ?? 7200
        cachedToken = token
        expiresAt = Date().addingTimeInterval(expireSeconds)
        return token
    }
}
