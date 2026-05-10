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

    /// SyncQueue 是否就绪（DB ready + 飞书已配置 App ID/Secret）
    var isSyncEligible: Bool {
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
