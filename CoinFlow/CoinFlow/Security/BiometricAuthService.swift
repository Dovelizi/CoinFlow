//  BiometricAuthService.swift
//  CoinFlow · M6 · §11 Face ID / Touch ID 启动鉴权
//
//  设计：
//  - 鉴权开关存 user_settings(`security.biometric_enabled` = "true"/"false")，默认关闭
//  - 启动 + 从 background 回前台 时，若开关开启 → 调 `evaluatePolicy` 拦门
//  - 失败/取消 → AppState.bioLocked = true（UI 显示锁屏），用户可"再次尝试"
//  - 设备不支持 Face/Touch ID（如旧设备） → 视开关为 false（无视）；设置页对应 toggle 灰
//
//  Info.plist：iOS 16+ 用 Face ID 需要 NSFaceIDUsageDescription（已在 gen_xcodeproj.py 注入 M6）

import Foundation
import LocalAuthentication

enum BiometricAuthError: Error, LocalizedError {
    case notAvailable        // 设备不支持 / 未录入生物特征
    case userCancelled       // 用户主动取消
    case authenticationFailed(reason: String)
    case lockout             // 多次失败被锁

    var errorDescription: String? {
        switch self {
        case .notAvailable:                      return "本机未启用 Face ID / Touch ID"
        case .userCancelled:                     return "已取消"
        case .authenticationFailed(let r):       return "鉴权失败：\(r)"
        case .lockout:                           return "尝试次数过多已被锁定，请在设置中验证密码后重试"
        }
    }
}

enum BiometricKind {
    case none
    case touchID
    case faceID
    case opticID

    var displayName: String {
        switch self {
        case .none:     return "无"
        case .touchID:  return "Touch ID"
        case .faceID:   return "Face ID"
        case .opticID:  return "Optic ID"
        }
    }
}

@MainActor
final class BiometricAuthService {

    static let shared = BiometricAuthService()
    private init() {}

    /// 防重入：UI 快速双击"再试一次"时，复用同一个鉴权 Task
    private var inFlight: Task<Void, Error>?

    /// 检测当前设备支持的生物识别类型 + 是否已录入。
    var availableKind: BiometricKind {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch ctx.biometryType {
        case .faceID:   return .faceID
        case .touchID:  return .touchID
        case .opticID:  return .opticID
        case .none:     return .none
        @unknown default: return .none
        }
    }

    var isAvailable: Bool { availableKind != .none }

    /// 调起鉴权。成功返回 ()；失败抛 BiometricAuthError。
    /// - Parameter reason: iOS 弹窗显示的理由文案
    func authenticate(reason: String = "解锁 CoinFlow 查看流水") async throws {
        // 若已有进行中的鉴权，直接复用，避免并发弹多个 Face ID 系统弹窗
        if let inFlight {
            try await inFlight.value
            return
        }
        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            try await self.doAuthenticate(reason: reason)
        }
        self.inFlight = task
        defer { self.inFlight = nil }
        try await task.value
    }

    private func doAuthenticate(reason: String) async throws {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "输入密码"  // 失败时提供 fallback
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw BiometricAuthError.notAvailable
        }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication,
                                                   localizedReason: reason)
            if !ok { throw BiometricAuthError.authenticationFailed(reason: "未通过") }
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .appCancel, .systemCancel:
                throw BiometricAuthError.userCancelled
            case .biometryLockout:
                throw BiometricAuthError.lockout
            default:
                throw BiometricAuthError.authenticationFailed(reason: laError.localizedDescription)
            }
        }
    }
}
