//  SyncTrigger.swift
//  CoinFlow · M9 · 同步触发统一入口（飞书版）
//
//  ViewModel 的 insert/update/delete 流程触发同步用统一接口，避免各处重复 detach Task。
//  与 M8 版差异：飞书没有 listener 实时推送（Q5=L 手动拉取），所以本入口只负责 fire 一次 tick；
//  反向同步在用户点 SyncStatusView 的"从飞书拉取"按钮时由 AppState.pullFromFeishu() 触发。

import Foundation

enum SyncTrigger {

    /// 触发一次同步。fire-and-forget。
    /// 调用方无需 await；本方法内部 detach 一个 Task。
    /// - 若用户在「同步状态页」关闭了"自动同步"开关，本方法直接 return，不入队。
    ///   新增/编辑流水仍正常写入本地 pending 队列，等开关再次打开时一次性补推。
    static func fire(reason: String = "uiAction") {
        // 自动同步开关（默认 true）
        let autoEnabled = SQLiteUserSettingsRepository.shared.bool(
            SettingsKey.syncAutoEnabled, default: true
        )
        guard autoEnabled else {
            SyncLogger.info(phase: "trigger", "skip reason=\(reason): auto sync disabled by user")
            return
        }
        SyncLogger.info(phase: "trigger", "fire reason=\(reason)")
        Task.detached {
            await SyncQueue.shared.tick(defaultLedgerId: DefaultSeeder.defaultLedgerId)
        }
    }
}
