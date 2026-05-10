//  SyncStateMachineTests.swift
//  CoinFlowTests · M9 · 飞书版状态机测试
//
//  覆盖 FeishuBitableError.isTransient 分类 + 同步状态机策略。

import XCTest
@testable import CoinFlow

final class SyncStateMachineTests: XCTestCase {

    // MARK: - isTransient 分类

    func test_isTransient_classification_transient() {
        // 网络错误
        XCTAssertTrue(FeishuBitableError.network(
            underlying: NSError(domain: NSURLErrorDomain, code: -1001)
        ).isTransient)
        // 5xx
        XCTAssertTrue(FeishuBitableError.httpStatus(code: 500, body: "").isTransient)
        XCTAssertTrue(FeishuBitableError.httpStatus(code: 502, body: "").isTransient)
        XCTAssertTrue(FeishuBitableError.httpStatus(code: 503, body: "").isTransient)
        // 限流 429
        XCTAssertTrue(FeishuBitableError.httpStatus(code: 429, body: "").isTransient)
        // 飞书 token 即将过期
        XCTAssertTrue(FeishuBitableError.apiError(
            code: 99991663, msg: "token will expire", raw: ""
        ).isTransient)
        // 飞书限流 9499
        XCTAssertTrue(FeishuBitableError.apiError(
            code: 9499, msg: "rate limited", raw: ""
        ).isTransient)
        // 鉴权错误中的 transient（FeishuAuthError.network）
        let authNetErr = FeishuAuthError.network(
            underlying: NSError(domain: NSURLErrorDomain, code: -1001)
        )
        XCTAssertTrue(FeishuBitableError.authFailed(underlying: authNetErr).isTransient)
    }

    func test_isTransient_classification_permanent() {
        XCTAssertFalse(FeishuBitableError.notConfigured.isTransient)
        XCTAssertFalse(FeishuBitableError.bitableNotInitialized.isTransient)
        XCTAssertFalse(FeishuBitableError.decodeFailed(reason: "x").isTransient)
        // 4xx 客户端错误（非 429）
        XCTAssertFalse(FeishuBitableError.httpStatus(code: 400, body: "").isTransient)
        XCTAssertFalse(FeishuBitableError.httpStatus(code: 401, body: "").isTransient)
        XCTAssertFalse(FeishuBitableError.httpStatus(code: 403, body: "").isTransient)
        XCTAssertFalse(FeishuBitableError.httpStatus(code: 404, body: "").isTransient)
        // 飞书业务参数错误（非 token 类）
        XCTAssertFalse(FeishuBitableError.apiError(
            code: 1254014, msg: "field already exists", raw: ""
        ).isTransient)
        // RecordIdNotFound（remoteId 失效）= permanent；SyncQueue 会专门 catch 这个 code 走 createRecord 降级
        XCTAssertFalse(FeishuBitableError.apiError(
            code: 1254043, msg: "RecordIdNotFound", raw: ""
        ).isTransient)
        // 1002 note has been deleted（多维表格被删）= permanent；SyncQueue.writeWithFallbacks 专门处理
        XCTAssertFalse(FeishuBitableError.apiError(
            code: 1002, msg: "note has been deleted", raw: ""
        ).isTransient)
        // 91402 NOTEXIST（app_token 不存在）= permanent；同上
        XCTAssertFalse(FeishuBitableError.apiError(
            code: 91402, msg: "NOTEXIST", raw: ""
        ).isTransient)
    }

    // MARK: - errorDescription 不为空

    func test_errorDescription_notEmpty_forAllCases() {
        let cases: [FeishuBitableError] = [
            .notConfigured,
            .authFailed(underlying: NSError(domain: "x", code: 0)),
            .network(underlying: NSError(domain: "x", code: 0)),
            .httpStatus(code: 500, body: ""),
            .apiError(code: 99991663, msg: "x", raw: ""),
            .decodeFailed(reason: "x"),
            .bitableNotInitialized
        ]
        for e in cases {
            XCTAssertNotNil(e.errorDescription, "\(e) 应有 errorDescription")
            XCTAssertFalse(e.errorDescription?.isEmpty ?? true, "\(e) errorDescription 不应为空")
        }
    }

    // MARK: - 状态机集成场景

    /// transient → attempts +1
    func test_attemptPolicy_transient_increments() {
        let next = modelAttempts(prev: 2, error: .httpStatus(code: 500, body: ""))
        XCTAssertEqual(next, 3)
    }

    /// permanent → 立即跳到 maxAttempts（marked dead）
    func test_attemptPolicy_permanent_jumpsToMax() {
        let next = modelAttempts(prev: 0, error: .notConfigured)
        XCTAssertEqual(next, SyncQueue.maxAttempts,
                       "notConfigured 必须立即标 dead")
    }

    func test_attemptPolicy_4xxNotRateLimited_jumpsToMax() {
        let next = modelAttempts(prev: 0, error: .httpStatus(code: 400, body: ""))
        XCTAssertEqual(next, SyncQueue.maxAttempts)
    }

    func test_attemptPolicy_decodeFailed_jumpsToMax() {
        let next = modelAttempts(prev: 1, error: .decodeFailed(reason: "x"))
        XCTAssertEqual(next, SyncQueue.maxAttempts)
    }

    /// 复刻 SyncQueue.syncOne 中决定 attempts 的策略。
    /// 测试目的：把策略锁在测试里，未来改 syncOne 必须同步这里。
    private func modelAttempts(prev: Int, error: FeishuBitableError) -> Int {
        if error.isTransient {
            return prev + 1
        }
        return SyncQueue.maxAttempts
    }
}
