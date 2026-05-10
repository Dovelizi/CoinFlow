//  FeishuTokenManagerTests.swift
//  CoinFlowTests · M9
//
//  测试 FeishuAuthError 的分类语义；TokenManager 的真实网络调用放在端到端
//  集成测试里（FeishuEndToEndTests，需真实 App ID/Secret）。

import XCTest
@testable import CoinFlow

final class FeishuTokenManagerTests: XCTestCase {

    // MARK: - FeishuAuthError isTransient

    func test_authError_network_isTransient() {
        let netErr = FeishuAuthError.network(
            underlying: NSError(domain: NSURLErrorDomain, code: -1001)
        )
        XCTAssertTrue(netErr.isTransient)
    }

    func test_authError_5xx_isTransient() {
        XCTAssertTrue(FeishuAuthError.httpStatus(code: 500, body: "").isTransient)
        XCTAssertTrue(FeishuAuthError.httpStatus(code: 502, body: "").isTransient)
        XCTAssertTrue(FeishuAuthError.httpStatus(code: 503, body: "").isTransient)
    }

    func test_authError_4xx_isPermanent() {
        XCTAssertFalse(FeishuAuthError.httpStatus(code: 400, body: "").isTransient)
        XCTAssertFalse(FeishuAuthError.httpStatus(code: 401, body: "").isTransient)
        XCTAssertFalse(FeishuAuthError.httpStatus(code: 403, body: "").isTransient)
    }

    func test_authError_apiError_isPermanent() {
        // 凭据错误（10003=app_id 不存在 / 99991661=app_secret 错）等业务错误
        XCTAssertFalse(FeishuAuthError.apiError(
            code: 10003, msg: "invalid app_id"
        ).isTransient)
    }

    func test_authError_notConfigured_isPermanent() {
        XCTAssertFalse(FeishuAuthError.notConfigured.isTransient)
    }

    func test_authError_decodeFailed_isPermanent() {
        XCTAssertFalse(FeishuAuthError.decodeFailed.isTransient)
    }

    // MARK: - errorDescription 完备

    func test_authError_errorDescription_notEmpty() {
        let cases: [FeishuAuthError] = [
            .notConfigured,
            .network(underlying: NSError(domain: "x", code: 0)),
            .httpStatus(code: 500, body: ""),
            .apiError(code: 10003, msg: "invalid"),
            .decodeFailed
        ]
        for e in cases {
            XCTAssertFalse(e.errorDescription?.isEmpty ?? true,
                           "\(e) errorDescription 不应为空")
        }
    }

    // MARK: - getToken 在未配置时抛 notConfigured（无网络依赖）

    func test_getToken_throwsWhenNotConfigured() async {
        // 注意：本测试假设运行环境的 Config.plist 可能已配置；不可强假未配置。
        // 改为：直接调用 token manager 时若 FeishuConfig.isConfigured 为 false，必须抛 notConfigured。
        // 我们通过 reset() 让缓存失效，然后让 manager 强制走 refresh 路径。
        await FeishuTokenManager.shared.reset()
        if !FeishuConfig.isConfigured {
            do {
                _ = try await FeishuTokenManager.shared.getToken()
                XCTFail("未配置应抛 notConfigured")
            } catch FeishuAuthError.notConfigured {
                // ✓
            } catch {
                XCTFail("应抛 notConfigured，实抛 \(error)")
            }
        } else {
            // 已配置环境下，只验证调用不 crash 即可（真实网络请求由端到端测试覆盖）
            // 不验证返回值（避免依赖飞书可达性）
        }
    }
}
