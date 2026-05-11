//  ScreenshotInbox.swift
//  CoinFlow · 快捷指令一键截屏记账（剪贴板方案）
//
//  职责：App 启动 / 回前台时，探测系统剪贴板里是否有用户刚截到的图片，若有则
//       触发识别流水线。
//
//  流程：
//    1. 用户在系统"快捷指令 App"里配置一条 3 动作串联：
//         [拍摄屏幕截图] → [拷贝到剪贴板] → [打开 CoinFlow]
//       并绑定到"双击背面 / 主屏图标 / 锁屏小组件"
//    2. 用户触发时，系统依次执行上述动作 → CoinFlow 被拉起
//    3. CoinFlow 启动前，Intent.perform() 把当前时间戳写入 UserDefaults
//       作为 intent-to-read-pasteboard 授权窗口（"最近 3 秒内允许读剪贴板"）
//    4. scenePhase==.active 时，本类的 tryConsumePasteboardImage() 被调用：
//       - 先用 UIPasteboard.hasImages（iOS 10+ 同步属性）**静默探测**剪贴板是否含图片
//         （此属性不触发"粘贴"授权弹窗）
//       - 若含图片且在 3 秒时间窗内 → 调 pasteboard.image
//         （此时 iOS 会弹系统级"允许粘贴"授权小弹窗，用户点一下即可）
//       - 读到图片 → 通过 imageSubject 发布给 MainTabView 根层订阅者
//         （任何 tab 下都能立即弹 CaptureConfirmView 识别流程）
//    5. 消费成功后清掉时间戳，同一张图不会重复触发
//
//  设计要点：
//  - 3 秒时间窗：iOS 17.2+ 快捷指令有 "截图预览" 环节可能让启动延后，3 秒足以覆盖；
//    同时避免"用户昨天复制了张图，今天打开 App 误触发"
//  - hasImages 先行：避免用户剪贴板里只有文本时无谓弹粘贴授权

import Foundation
import UIKit
import Combine

final class ScreenshotInbox {

    static let shared = ScreenshotInbox()

    /// UI 层订阅此 subject 即可拿到新到的图片
    let imageSubject = PassthroughSubject<UIImage, Never>()

    /// 授权时间戳的 UserDefaults key。快捷指令 Intent perform() 时写入，
    /// 主 App 读剪贴板前检查是否在 3 秒有效期内。
    private let intentTimestampKey = "coinflow.pasteboardIntentRequestedAt"

    /// 授权窗口（秒）：Intent 触发后多久内允许读剪贴板
    private let validWindow: TimeInterval = 3.0

    private init() {}

    // MARK: - Writer 侧（App Intent 进程调用）

    /// 由 CoinFlowCaptureIntent.perform() 调用：打上时间戳，声明"接下来 3 秒主 App 可以读剪贴板"。
    /// 只写一个 Double，不触发任何 UI。
    func markPasteboardIntent() {
        UserDefaults.standard.set(Date().timeIntervalSince1970,
                                  forKey: intentTimestampKey)
    }

    // MARK: - Reader 侧（主 App 进程 scenePhase==.active 时调用）

    /// 尝试消费剪贴板中的图片。
    /// - 不在授权窗口内 → 直接返回 false（不读剪贴板，不弹任何系统授权）
    /// - 剪贴板无图（pb.hasImages 静默探测）→ 返回 false，清掉时间戳
    /// - 剪贴板有图 → 会触发系统"允许粘贴"弹窗；用户同意后发布 image
    ///   用户拒绝时 UIPasteboard.image 返回 nil，不发布，时间戳也清掉
    /// - Returns: 是否发布了图片（true = 进入识别流水线）
    @discardableResult
    func tryConsumePasteboardImage() async -> Bool {
        // 1. 校验授权时间窗
        let ts = UserDefaults.standard.double(forKey: intentTimestampKey)
        guard ts > 0 else { return false }
        let age = Date().timeIntervalSince1970 - ts
        guard age >= 0, age <= validWindow else {
            // 过期：清掉避免未来误触发
            UserDefaults.standard.removeObject(forKey: intentTimestampKey)
            return false
        }

        // 2. 静默探测是否含图片（hasImages 是 iOS 10+ 同步属性，不触发粘贴授权弹窗）
        let pb = UIPasteboard.general
        guard pb.hasImages else {
            UserDefaults.standard.removeObject(forKey: intentTimestampKey)
            return false
        }

        // 3. 读取图片（此处才会触发系统"允许粘贴"授权弹窗）
        //    pb.image 是 UIImage?；用户拒绝或系统失败时为 nil
        let image: UIImage? = pb.image
        // 无论成功失败都清时间戳：同一次 intent 只消费一次
        UserDefaults.standard.removeObject(forKey: intentTimestampKey)

        guard let img = image else { return false }

        // 4. 清空剪贴板的图片，避免下次 hasImages 误触发
        //    （用户 Intent 已消费完，清空是合理语义）
        pb.items = []

        await MainActor.run {
            imageSubject.send(img)
        }
        return true
    }
}
