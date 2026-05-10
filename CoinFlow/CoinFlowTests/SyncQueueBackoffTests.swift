//  SyncQueueBackoffTests.swift
//  CoinFlowTests · M9 · 飞书版退避测试
//
//  纯函数测试：SyncQueue.backoff / shouldRetry。
//  这些是无网络无 DB 依赖的 API，覆盖优先（CI 友好）。

import XCTest
@testable import CoinFlow

final class SyncQueueBackoffTests: XCTestCase {

    // MARK: - backoff

    /// attempt 0..7：base = min(2^a, 60)；±20% 抖动；最小 100ms 保护
    func test_backoff_baseFollowsExponential_clampedAtCap() {
        let zeroJitter = { 0.5 }  // jitterPct = 0 → delay == base
        XCTAssertEqual(SyncQueue.backoff(attempt: 0, randomSource: zeroJitter), 1.0,  accuracy: 1e-9)
        XCTAssertEqual(SyncQueue.backoff(attempt: 1, randomSource: zeroJitter), 2.0,  accuracy: 1e-9)
        XCTAssertEqual(SyncQueue.backoff(attempt: 2, randomSource: zeroJitter), 4.0,  accuracy: 1e-9)
        XCTAssertEqual(SyncQueue.backoff(attempt: 3, randomSource: zeroJitter), 8.0,  accuracy: 1e-9)
        XCTAssertEqual(SyncQueue.backoff(attempt: 4, randomSource: zeroJitter), 16.0, accuracy: 1e-9)
        XCTAssertEqual(SyncQueue.backoff(attempt: 5, randomSource: zeroJitter), 32.0, accuracy: 1e-9)
        // 2^6 = 64 > cap 60 → clamp 60
        XCTAssertEqual(SyncQueue.backoff(attempt: 6, randomSource: zeroJitter), 60.0, accuracy: 1e-9)
        XCTAssertEqual(SyncQueue.backoff(attempt: 7, randomSource: zeroJitter), 60.0, accuracy: 1e-9)
    }

    /// 抖动范围：±20%。random=0 → jitterPct=-0.2；random=1 → jitterPct=+0.2
    func test_backoff_jitterRangeWithin20Percent() {
        let minDelay = SyncQueue.backoff(attempt: 4, randomSource: { 0.0 })
        let maxDelay = SyncQueue.backoff(attempt: 4, randomSource: { 1.0 })
        // base = 16；min = 16 * 0.8 = 12.8；max = 16 * 1.2 = 19.2
        XCTAssertEqual(minDelay, 12.8, accuracy: 1e-9)
        XCTAssertEqual(maxDelay, 19.2, accuracy: 1e-9)
    }

    /// 100ms 最小保护：极端低 jitter 也不会低于 0.1
    func test_backoff_minProtection() {
        let result = SyncQueue.backoff(attempt: -4, randomSource: { 0.0 })
        XCTAssertEqual(result, 0.1, accuracy: 1e-9)
    }

    // MARK: - shouldRetry

    func test_shouldRetry_transientUnderMax_yes() {
        let netErr = FeishuBitableError.network(
            underlying: NSError(domain: NSURLErrorDomain, code: -1001)
        )
        XCTAssertTrue(SyncQueue.shouldRetry(netErr, attempts: 0))
        XCTAssertTrue(SyncQueue.shouldRetry(netErr, attempts: 4))

        let httpErr = FeishuBitableError.httpStatus(code: 500, body: "")
        XCTAssertTrue(SyncQueue.shouldRetry(httpErr, attempts: 0))

        let rateErr = FeishuBitableError.httpStatus(code: 429, body: "")
        XCTAssertTrue(SyncQueue.shouldRetry(rateErr, attempts: 0))

        // 飞书 token 即将过期 code=99991663 视为 transient
        let tokenErr = FeishuBitableError.apiError(code: 99991663, msg: "token expired", raw: "")
        XCTAssertTrue(SyncQueue.shouldRetry(tokenErr, attempts: 1))
    }

    func test_shouldRetry_transientAtMax_no() {
        let netErr = FeishuBitableError.network(
            underlying: NSError(domain: NSURLErrorDomain, code: -1001)
        )
        XCTAssertFalse(SyncQueue.shouldRetry(netErr, attempts: 5))
    }

    func test_shouldRetry_permanent_alwaysNo() {
        XCTAssertFalse(SyncQueue.shouldRetry(.notConfigured, attempts: 0))
        XCTAssertFalse(SyncQueue.shouldRetry(.bitableNotInitialized, attempts: 0))
        XCTAssertFalse(SyncQueue.shouldRetry(
            .decodeFailed(reason: "x"), attempts: 0
        ))
        // 4xx（非 429）= permanent（参数错误 / 鉴权 / 资源不存在等）
        XCTAssertFalse(SyncQueue.shouldRetry(
            .httpStatus(code: 400, body: ""), attempts: 0
        ))
        XCTAssertFalse(SyncQueue.shouldRetry(
            .httpStatus(code: 404, body: ""), attempts: 0
        ))
    }
}
