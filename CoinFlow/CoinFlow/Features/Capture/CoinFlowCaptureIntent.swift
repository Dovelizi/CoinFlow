//  CoinFlowCaptureIntent.swift
//  CoinFlow · 快捷指令一键截屏记账（剪贴板方案）
//
//  本 Intent 是"打开 CoinFlow 的入口"，不带参数。配合系统快捷指令的前置动作：
//      [拍摄屏幕截图] → [拷贝到剪贴板] → [打开 CoinFlow]
//
//  perform() 仅做一件事：在 UserDefaults 打上"剪贴板图片授权时间戳"，
//  声明"接下来 3 秒 CoinFlow 可以读剪贴板"。主 App 启动后由 ScreenshotInbox
//  校验时间戳并探测剪贴板。
//
//  为什么不用带 IntentFile 参数的版本：iOS 17.2+ 快捷指令的"拍摄屏幕截图"动作
//  会强制弹系统"截图预览"面板（取消 / 完成），用户体验不佳。改走剪贴板后，
//  "拷贝到剪贴板"动作在 iOS 18 以下不弹预览面板，用户侧接近"无感一次点击"。

import AppIntents

@available(iOS 16, *)
struct CoinFlowCaptureIntent: AppIntent {

    static var title: LocalizedStringResource = "CoinFlow · 截图记账"
    static var description = IntentDescription(
        "读取剪贴板中的截图并进入识别流程。配合『拍摄屏幕截图』和『拷贝到剪贴板』动作使用。",
        categoryName: "记账"
    )

    /// 让 iOS 把 App 拉到前台
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // 标记"接下来 3 秒允许读剪贴板"——主 App scenePhase.active 时会校验并消费
        ScreenshotInbox.shared.markPasteboardIntent()
        return .result()
    }
}

@available(iOS 16, *)
struct CoinFlowAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CoinFlowCaptureIntent(),
            phrases: [
                "用 \(.applicationName) 记一笔",
                "\(.applicationName) 截图记账",
                "让 \(.applicationName) 识别截图"
            ],
            shortTitle: "截图记账",
            systemImageName: "doc.text.viewfinder"
        )
    }
}
