//  AppState.swift
//  CoinFlow · M9 · 飞书多维表格切换
//
//  全局启动状态聚合器。职责：
//  1. 串行 bootstrap：DB → Seed（默认账本+预设分类）→ 飞书配置检查
//  2. 暴露数据快照供 SyncStatusView / SettingsView 渲染
//  3. 提供"立即同步 / 全部重试 / 从飞书拉取"用户主动操作入口
//
//  与 M8 版（Firebase）的差异：
//  - 去掉 auth/crypto/firebase 子系统（飞书自建应用 + 不加密 + 用 tenant_access_token）
//  - 去掉 listener / ensureListenerStarted（飞书无实时推送，反向同步用 pullFromFeishu 手动按钮）
//  - 保留 hasCompletedOnboarding / bioLocked / Face ID 等本地特性

import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {

    // MARK: - Subsystem state snapshots

    enum DatabaseState: Equatable {
        case pending
        case ready(DatabaseManager.BootstrapResult)
        case failed(String)
    }

    enum SeedState: Equatable {
        case pending
        case done(ledgerCreated: Bool, categoriesAdded: Int)
        case failed(String)
    }

    /// 飞书配置 / 多维表格状态（取代旧的 firebase）
    enum FeishuState: Equatable {
        case pending
        /// 已配置 App ID/Secret，但还没创建多维表格（首次同步时会自动创建）
        case configuredWaitingTable
        /// App + 多维表格都就绪
        case ready(appToken: String, tableId: String, url: String)
        case notConfigured(reason: String)
    }

    // MARK: - Data snapshot（UI 展示）

    struct DataSnapshot: Equatable {
        var recordTotal: Int = 0
        var pendingCount: Int = 0
        var lastTickAt: Date?
    }

    // MARK: - Published state

    @Published var database: DatabaseState = .pending
    @Published var seed: SeedState = .pending
    @Published var feishu: FeishuState = .pending
    @Published var data: DataSnapshot = DataSnapshot()

    /// M10-Fix4 · 待展示的总结推送 banner（首页订阅）。
    /// service.generate 成功后会广播 .billsSummaryDidGenerate；首页 banner 用此 state 显示。
    /// 提到 AppState 而非 HomeMainView 内部 @State 的原因：
    /// HomeMainView 切 tab 时会被销毁（MainTabView 用条件渲染），HomeMainView 的 @State
    /// 不会保留；提到 AppState 后跨 tab 保活，banner 在切回首页时仍可显示。
    @Published var pendingSummaryPush: BillsSummary?

    /// 通知订阅 token；deinit 时取消防泄漏
    private var summaryGenerateObserver: NSObjectProtocol?

    init() {
        // M10-Fix4 · 在 AppState 生命周期内长驻订阅"账单总结已生成"
        // service 在生成成功后通过 NotificationCenter 广播；
        // 此处接收并写入 pendingSummaryPush，HomeMainView 通过 EnvironmentObject 监听显示 banner。
        summaryGenerateObserver = NotificationCenter.default.addObserver(
            forName: .billsSummaryDidGenerate,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let s = note.userInfo?["summary"] as? BillsSummary else { return }
            // 在主 actor 上更新（addObserver 队列 = .main 已保证）
            self?.pendingSummaryPush = s
        }
    }

    deinit {
        if let token = summaryGenerateObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    /// M6: 生物识别锁定状态。true = 显示锁屏页拦截 UI；false = 已解锁（或未启用）
    /// 启动即同步设初值：走 UserDefaults 镜像（DB bootstrap 前就要生效）
    @Published var bioLocked: Bool = UserDefaults.standard.bool(forKey: "security.biometric_enabled_mirror")

    /// M6: 当前是否需要在恢复前台时鉴权
    var biometricRequired: Bool {
        BiometricAuthService.shared.isAvailable
            && SQLiteUserSettingsRepository.shared.bool(SettingsKey.biometricEnabled)
    }

    /// M7 [13-1]：首次启动引导完成标志
    @Published var hasCompletedOnboarding: Bool =
        UserDefaults.standard.bool(forKey: "onboarding.completed_mirror")

    /// 用户级「自动同步」总开关（同步状态页 Toggle 控制）。默认 true。
    /// false 时：SyncTrigger.fire 短路、立即同步/从飞书拉取按钮置灰、顶部 hero 显示「已暂停同步」。
    /// 新增/edit 流水仍正常入本地 pending 队列；用户重新打开后一次性补推。
    ///
    /// ⚠️ 启动时机问题：AppState 的属性默认值会在 `DatabaseManager.bootstrap()` 之前求值，
    /// 此时 SQLite handle 还是 nil，从 user_settings 读不到值会回退到 default=true，
    /// 导致用户上次关闭的状态被覆盖。所以走 UserDefaults 镜像（与 biometricEnabled/
    /// onboardingCompleted 同模式），bootstrap 后再从 DB reconcile 一次。
    @Published var syncAutoEnabled: Bool =
        UserDefaults.standard.object(forKey: "sync.auto_enabled_mirror") as? Bool ?? true

    /// SyncQueue 是否就绪（DB ready + 飞书已配置 App ID/Secret + 用户未关闭自动同步）
    var isSyncEligible: Bool {
        guard case .ready = database else { return false }
        guard syncAutoEnabled else { return false }
        switch feishu {
        case .configuredWaitingTable, .ready: return true
        case .pending, .notConfigured: return false
        }
    }

    /// 区分「飞书配置就绪 ≠ 自动同步开启」：用于 UI 区分置灰原因
    /// （飞书配好但用户主动关闭 → 显示「已暂停」而非「未配置」）
    var isFeishuConfigured: Bool {
        guard case .ready = database else { return false }
        switch feishu {
        case .configuredWaitingTable, .ready: return true
        case .pending, .notConfigured: return false
        }
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        // 1. Database
        do {
            let r = try DatabaseManager.shared.bootstrap()
            database = .ready(r)
        } catch {
            database = .failed(error.localizedDescription)
            return  // DB 挂了后面全部无意义
        }

        // 2. Seed 默认账本 + 预设分类
        do {
            let r = try DefaultSeeder.seedIfNeeded()
            seed = .done(ledgerCreated: r.ledgerCreated, categoriesAdded: r.categoriesAdded)
        } catch {
            seed = .failed(error.localizedDescription)
        }

        // 2.1 M12 一次性迁移：清理 M11 方案 B 的 AA 双向回写残留（aaSettlementId 非空且
        //     sourceKind != .aaSettlement 的旧记录）。幂等：完成后写 flag，下次启动跳过。
        AAMigrationsM12.cleanupLegacyWritebacksIfNeeded()

        // 2.2 M13 一次性迁移：清理"AA 账本已被软删但占位流水仍存在"的孤儿占位。
        //     旧版 AASplitListViewModel.softDelete 没联动占位删除，留下了指向已删账本的占位。
        //     幂等：完成后写 flag；如清理了任何条目则广播刷新，让账单列表立刻反映。
        let m13Removed = AAMigrationsM13.cleanupOrphanPlaceholdersIfNeeded()
        if m13Removed > 0 {
            RecordChangeNotifier.broadcast(recordIds: [])
        }

        // 2.5 首次启动日期（Dark Glass 设置页"加入 N 天"副标题数据源）
        // - 只在首次启动时写入；后续启动不覆盖
        // - 无论 Seed 成功与否都尝试写入（读到 DB 就说明 bootstrap 步骤 1 已通过）
        if SQLiteUserSettingsRepository.shared.get(key: SettingsKey.firstLaunchDate) == nil {
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            SQLiteUserSettingsRepository.shared.set(
                key: SettingsKey.firstLaunchDate,
                value: String(nowMs)
            )
        }

        // 3. 飞书配置检查（不发起网络请求）
        if !FeishuConfig.isConfigured {
            feishu = .notConfigured(reason: "缺少 Feishu_App_ID / Feishu_App_Secret")
        } else if FeishuConfig.hasBitable {
            feishu = .ready(
                appToken: FeishuConfig.bitableAppToken ?? "",
                tableId: FeishuConfig.billsTableId ?? "",
                url: FeishuConfig.bitableURL ?? ""
            )
        } else {
            feishu = .configuredWaitingTable
        }

        // 4. 刷新本地数据统计
        refreshDataSnapshot()

        // 4.5 M9-Fix4：首次升级到附件支持版本时，强制 reset 所有 record 的同步元数据
        //     让 38 条历史 record 全部重推到（可能新建的）飞书表
        let resetFlag = "m9fix4.attachment.reset.done"
        if !UserDefaults.standard.bool(forKey: resetFlag) {
            do {
                let n = try SQLiteRecordRepository.shared.resetAllSyncMetadata()
                SyncLogger.info(phase: "migration", "M9-Fix4: reset \(n) records to pending")
                FeishuConfig.resetBitableCache()
                UserDefaults.standard.set(true, forKey: resetFlag)
                refreshDataSnapshot()
            } catch {
                SyncLogger.failure(phase: "migration", error: error,
                                   extra: "resetAllSyncMetadata failed")
            }
        }

        // 5. 生物识别拦门
        let shouldLock = biometricRequired
        UserDefaults.standard.set(shouldLock, forKey: "security.biometric_enabled_mirror")
        bioLocked = shouldLock

        // 6. onboarding flag reconcile
        let dbCompleted = SQLiteUserSettingsRepository.shared.bool(SettingsKey.onboardingCompleted)
        if dbCompleted != hasCompletedOnboarding {
            hasCompletedOnboarding = dbCompleted
            UserDefaults.standard.set(dbCompleted, forKey: "onboarding.completed_mirror")
        }

        // 7. 自动同步开关 reconcile
        // 启动时使用的是 UserDefaults 镜像值；DB 就绪后再从 user_settings 读一次权威值，
        // 修正可能被卸载重装/手工改 DB 等场景导致的镜像滞后。
        // 注意：仅在 DB 中确实存在该 key 时才覆盖，避免 DB 里没有这条记录时把镜像值清成 default。
        if let raw = SQLiteUserSettingsRepository.shared.get(key: SettingsKey.syncAutoEnabled) {
            let dbValue = ["true", "1", "yes"].contains(raw.lowercased())
            if dbValue != syncAutoEnabled {
                syncAutoEnabled = dbValue
                UserDefaults.standard.set(dbValue, forKey: "sync.auto_enabled_mirror")
            }
        }
    }

    // MARK: - Sync auto switch

    /// 切换「自动同步」开关。开 → 立即触发一次 tick 把积压的 pending 推上去。
    /// 同时写 user_settings DB（权威）+ UserDefaults 镜像（启动时早于 DB 用）。
    func setSyncAutoEnabled(_ enabled: Bool) {
        guard syncAutoEnabled != enabled else { return }
        syncAutoEnabled = enabled
        SQLiteUserSettingsRepository.shared.setBool(SettingsKey.syncAutoEnabled, enabled)
        UserDefaults.standard.set(enabled, forKey: "sync.auto_enabled_mirror")
        SyncLogger.info(phase: "trigger",
                        "user toggled auto sync = \(enabled)")
        if enabled {
            // 重新打开 → 立即推一次，把暂停期间积压的 pending 全部上云
            SyncTrigger.fire(reason: "resumeAutoSync")
        }
    }

    // MARK: - Onboarding

    func completeOnboarding() {
        SQLiteUserSettingsRepository.shared.setBool(SettingsKey.onboardingCompleted, true)
        UserDefaults.standard.set(true, forKey: "onboarding.completed_mirror")
        hasCompletedOnboarding = true
    }

    // MARK: - Biometric unlock

    func unlockWithBiometrics() async -> Result<Void, Error> {
        do {
            try await BiometricAuthService.shared.authenticate()
            bioLocked = false
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Scene phase hook

    /// App 从 background 或 inactive → active 时调用。
    /// 飞书版同 Firebase 版策略：不在此处自动 tick，避免被墙/网络抖动反复刷错。
    func onScenePhaseActive() {
        // 保留方法以保持对外兼容；未来如需"前台强制触发"可在此扩展。
    }

    // MARK: - 用户主动同步

    /// 同步状态页"立即同步 / 全部重试"按钮调用。
    /// - 复活已死的记录（attempts 达上限的）
    /// - 跑一次 SyncQueue.tick
    /// - Returns: 本次复活的死记录条数（用于 UI 反馈）
    @discardableResult
    func manualSyncTickWithRevive() async -> Int {
        let revived: Int
        do {
            revived = try SQLiteRecordRepository.shared.resetDeadRetries()
        } catch {
            SyncLogger.failure(phase: "manualRevive", error: error)
            return 0
        }
        await SyncQueue.shared.tick(defaultLedgerId: DefaultSeeder.defaultLedgerId)
        // tick 内部首次调用时会自动创建多维表格；创建后更新 feishu 状态
        if FeishuConfig.hasBitable, case .configuredWaitingTable = feishu {
            feishu = .ready(
                appToken: FeishuConfig.bitableAppToken ?? "",
                tableId: FeishuConfig.billsTableId ?? "",
                url: FeishuConfig.bitableURL ?? ""
            )
        }
        refreshDataSnapshot()
        data.lastTickAt = Date()
        return revived
    }

    /// 用户主动从飞书拉取的结果摘要（设置页 / 同步状态页展示）。
    struct PullResult: Equatable {
        var inserted: Int
        var skippedExisting: Int
        var decodeFailures: Int
    }

    /// 用户在「同步状态页 → 从飞书拉取」点击时调用（Q5=L 手动）。
    func pullFromFeishu() async -> Result<PullResult, Error> {
        do {
            let r = try await RemoteRecordPuller.pullAll(
                defaultLedgerId: DefaultSeeder.defaultLedgerId
            )
            refreshDataSnapshot()
            return .success(PullResult(
                inserted: r.inserted,
                skippedExisting: r.skippedExisting,
                decodeFailures: r.decodeFailures
            ))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - 清空云端并重新同步

    /// 「清空云端并重新同步」的进度阶段（驱动 UI 显示）。
    enum WipeAndResyncPhase: Equatable {
        case preparing                              // 暂停同步、检查环境
        case scanningRemote                         // 拉取云端 record_id 列表
        case deletingRemote(deleted: Int, total: Int) // 批量删除中
        case resettingLocal                         // 重置本地元数据
        case resyncing(uploaded: Int, total: Int)   // 重新上传
        case finished(uploaded: Int)                // 完成
        case failed(message: String)                // 出错
    }

    /// 清空飞书表内所有行，然后把本地数据全量重新推一次。
    /// 流程：暂停自动同步 → search 全部 record_id → batch_delete（500/批）→
    /// 重置本地同步元数据（remoteId/attempts/attachmentToken 全清）→
    /// 恢复自动同步原状态 → 触发 SyncQueue.tick 把本地数据推上去。
    /// - Parameter onPhase: 进度回调（在 MainActor 上调用，可直接驱动 SwiftUI 状态）
    /// - Returns: 是否成功
    @MainActor
    @discardableResult
    func wipeRemoteAndResync(
        onPhase: @MainActor @escaping (WipeAndResyncPhase) -> Void
    ) async -> Bool {
        // 0. 前置检查
        guard isFeishuConfigured else {
            onPhase(.failed(message: "飞书未配置，无法清空云端"))
            return false
        }

        // 1. 暂停自动同步（保存原状态以便结束时恢复）
        let originalAutoEnabled = syncAutoEnabled
        if originalAutoEnabled {
            // 直接走 setter，触发持久化；避免清空过程中 SyncTrigger 抢着推数据
            setSyncAutoEnabled(false)
        }
        onPhase(.preparing)
        // 让 .preparing 这一帧先被 SwiftUI 渲染
        try? await Task.sleep(nanoseconds: 200_000_000)
        SyncLogger.info(phase: "wipe", "begin (originalAutoEnabled=\(originalAutoEnabled))")

        // 帮助函数：恢复自动同步开关到原始状态（仅在暂停过的前提下打回）
        func restoreAutoSyncIfNeeded() {
            // 注意 setSyncAutoEnabled 内部 guard 了"无变化跳过"
            // 但 setter 在打开时会 fire 一次同步，这里我们只恢复用户原意；
            // 后续会主动 manualSyncTickWithRevive，所以即便不 fire 也无碍
            if syncAutoEnabled != originalAutoEnabled {
                setSyncAutoEnabled(originalAutoEnabled)
            }
        }

        // 2. 拉取云端所有 record_id
        onPhase(.scanningRemote)
        try? await Task.sleep(nanoseconds: 200_000_000)
        let remoteIds: [String]
        do {
            remoteIds = try await FeishuBitableClient.shared.listAllRecordIds()
            SyncLogger.info(phase: "wipe", "scanned remote ids=\(remoteIds.count)")
        } catch {
            SyncLogger.failure(phase: "wipe.scan", error: error)
            restoreAutoSyncIfNeeded()
            onPhase(.failed(message: "扫描云端失败：\(error.localizedDescription)"))
            return false
        }

        // 3. 批量删除（500 条/批）
        if !remoteIds.isEmpty {
            onPhase(.deletingRemote(deleted: 0, total: remoteIds.count))
            try? await Task.sleep(nanoseconds: 200_000_000)
            do {
                try await FeishuBitableClient.shared.batchDeleteRecords(
                    ids: remoteIds
                ) { deleted, total in
                    Task { @MainActor in
                        onPhase(.deletingRemote(deleted: deleted, total: total))
                    }
                }
                // 让最后一批的 d/t 状态也有时间被渲染
                try? await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                SyncLogger.failure(phase: "wipe.delete", error: error)
                restoreAutoSyncIfNeeded()
                onPhase(.failed(message: "清空云端失败：\(error.localizedDescription)"))
                return false
            }
        }

        // 4. 重置本地全量同步元数据（remoteId / attempts / lastError / attachmentToken）
        onPhase(.resettingLocal)
        try? await Task.sleep(nanoseconds: 200_000_000)
        let resetCount: Int
        do {
            resetCount = try SQLiteRecordRepository.shared.resetAllSyncMetadata()
            SyncLogger.info(phase: "wipe", "reset local rows=\(resetCount)")
        } catch {
            SyncLogger.failure(phase: "wipe.reset", error: error)
            restoreAutoSyncIfNeeded()
            onPhase(.failed(message: "重置本地状态失败：\(error.localizedDescription)"))
            return false
        }

        // 5. 恢复自动同步开关到原状态（用户原本关着的就不要替他打开）
        restoreAutoSyncIfNeeded()

        // 6. 显式触发 tick；不依赖 setSyncAutoEnabled 的 fire（如果原本就是 false 就不会 fire）
        onPhase(.resyncing(uploaded: 0, total: resetCount))
        // 让 0/total 这一帧先被渲染（否则数据量小时 tick 太快，UI 永远停在 0/N）
        try? await Task.sleep(nanoseconds: 200_000_000)
        // SyncQueue.tick 一次最多 batchSize 条；分多次直到 pendingCount 为 0 或上限
        var totalUploaded = 0
        var rounds = 0
        let maxRounds = 50  // 防御无限循环（极端情况下死记录会被识别）
        while rounds < maxRounds {
            await SyncQueue.shared.tick(defaultLedgerId: DefaultSeeder.defaultLedgerId)
            refreshDataSnapshot()
            let stillPending = data.pendingCount
            let uploadedSoFar = max(0, resetCount - stillPending)
            totalUploaded = uploadedSoFar
            onPhase(.resyncing(uploaded: uploadedSoFar, total: resetCount))
            // 关键：每轮 tick 后给 UI 一帧时间渲染最新进度，再判断是否退出
            try? await Task.sleep(nanoseconds: 200_000_000)
            if stillPending == 0 { break }
            rounds += 1
        }
        data.lastTickAt = Date()

        SyncLogger.info(phase: "wipe",
                        "done uploaded=\(totalUploaded)/\(resetCount) rounds=\(rounds)")
        onPhase(.finished(uploaded: totalUploaded))
        return true
    }

    // MARK: - Data snapshot refresh

    private func refreshDataSnapshot() {
        let repo = SQLiteRecordRepository.shared
        do {
            let all = try repo.list(.init(includesDeleted: false, limit: nil))
            data.recordTotal = all.count
            data.pendingCount = all.filter { $0.syncStatus == .pending || $0.syncStatus == .failed }.count
        } catch {
            SyncLogger.failure(phase: "snapshot", error: error)
        }
    }
}
