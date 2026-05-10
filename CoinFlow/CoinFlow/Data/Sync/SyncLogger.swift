//  SyncLogger.swift
//  CoinFlow · M9 · 同步链路结构化日志（飞书多维表格版）
//
//  - 所有同步相关日志走此处，不再散落 NSLog
//  - 每条日志带 `phase`（tick/auth/feishu.bootstrap/write/softDelete/markSynced/markFailed/reconcile/pull/...）
//    和可选 `recordId` / `attempts` / `errorCode`，便于 grep + 单条记录全链路追踪
//  - 失败路径必须 logFailure，禁止 silent swallow
//
//  生产构建：仍走 NSLog（被 Apple Console 统一收集）；DEBUG 构建额外 print 到 stdout

import Foundation

enum SyncLogger {

    /// 失败码：从飞书错误枚举名映射，便于日志聚合
    private static func errorCode(_ error: Error) -> String {
        if let e = error as? FeishuBitableError {
            switch e {
            case .notConfigured:           return "feishu.notConfigured"
            case .authFailed:              return "feishu.authFailed"
            case .network:                 return "feishu.network"
            case .httpStatus(let c, _):    return "feishu.http\(c)"
            case .apiError(let c, _, _):   return "feishu.api\(c)"
            case .decodeFailed:            return "feishu.decodeFailed"
            case .bitableNotInitialized:   return "feishu.bitableNotInitialized"
            }
        }
        if let e = error as? FeishuAuthError {
            switch e {
            case .notConfigured:           return "feishu.auth.notConfigured"
            case .network:                 return "feishu.auth.network"
            case .httpStatus(let c, _):    return "feishu.auth.http\(c)"
            case .apiError(let c, _):      return "feishu.auth.api\(c)"
            case .decodeFailed:            return "feishu.auth.decodeFailed"
            }
        }
        if let e = error as? RecordBitableMapperError {
            switch e {
            case .missingRequiredField:    return "mapper.missingField"
            case .invalidValue:            return "mapper.invalidValue"
            }
        }
        return "unknown"
    }

    /// INFO 级别：正常路径关键节点。
    static func info(phase: String,
                     recordId: String? = nil,
                     attempts: Int? = nil,
                     _ message: String) {
        emit(level: "INFO", phase: phase, recordId: recordId,
             attempts: attempts, errorCode: nil, message: message)
    }

    /// WARN 级别：非致命异常。
    static func warn(phase: String,
                     recordId: String? = nil,
                     attempts: Int? = nil,
                     _ message: String) {
        emit(level: "WARN", phase: phase, recordId: recordId,
             attempts: attempts, errorCode: nil, message: message)
    }

    /// FAILURE：单条同步失败，必带 error。
    static func failure(phase: String,
                        recordId: String? = nil,
                        attempts: Int? = nil,
                        error: Error,
                        extra: String? = nil) {
        emit(level: "FAIL", phase: phase, recordId: recordId,
             attempts: attempts, errorCode: errorCode(error),
             message: extra.map { "\($0) | \(error.localizedDescription)" }
                 ?? error.localizedDescription)
    }

    // MARK: - Private

    private static func emit(level: String,
                             phase: String,
                             recordId: String?,
                             attempts: Int?,
                             errorCode: String?,
                             message: String) {
        var fields: [String] = ["level=\(level)", "phase=\(phase)"]
        if let r = recordId { fields.append("recordId=\(r)") }
        if let a = attempts { fields.append("attempts=\(a)") }
        if let c = errorCode { fields.append("code=\(c)") }
        let prefix = "[CoinFlow.Sync] " + fields.joined(separator: " ")
        let line = "\(prefix) | \(message)"
        NSLog("%@", line)
        #if DEBUG
        print(line)
        #endif
    }
}
