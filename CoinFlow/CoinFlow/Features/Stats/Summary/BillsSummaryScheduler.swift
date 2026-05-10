//  BillsSummaryScheduler.swift
//  CoinFlow · M10
//
//  调度器：决定"用户进入 App 时是否要为某个周期生成总结"。
//
//  规则（用户决策的默认值）：
//   - 优先级：年 > 月 > 周（一次启动只触发一个）
//   - 周报：每周一进入 App 后；上一自然周（周一~周日）笔数 ≥3；上一周对应周期未生成过
//   - 月报：每月 1 日进入 App；上一月笔数 ≥5；上月未生成过
//   - 年报：每年 1 月 1 日进入 App；去年笔数 ≥12；去年未生成过
//   - 节流：同一台设备同一天最多触发一次（user_settings 写"summary.last_check_date"）
//
//  调用方：CoinFlowApp.scenePhase == .active 时（已存在的 onScenePhaseActive）调用一次 check
//
//  设计：
//  - 不主动等待 LLM 完成；服务由 BillsSummaryService 异步串行处理
//  - UI 层用 Combine 监听 SQLiteBillsSummaryRepository（暂未做，由用户主动进设置页查看）
//
//  [Boundary Warnings]
//  - 中国大陆周一为一周开始（与 BillsSummaryAggregator.calendar() 一致）
//  - 节流 key 用本地日期字符串：跨时区切换时可能漏触发一次（接受）

import Foundation

enum BillsSummaryScheduler {

    /// user_settings 节流 key（避免反复触发 LLM）
    private static let lastCheckDateKey = "summary.last_check_date"
    /// user_settings 总开关：用户在设置页可关闭自动总结
    static let autoGenerateEnabledKey  = "summary.auto_generate_enabled"

    /// 入口：App 切到 active 时调用一次。
    /// - 一天最多调一次 LLM；用 user_settings 表持久化"今日已检查过"
    /// - 主线程：仅做"读 settings + 决定要不要触发"；触发本身用 Task 异步进 BillsSummaryService
    @MainActor
    static func checkOnAppActive() async {
        // 0. 总开关（默认开启；用户可在设置页关）
        let settings = SQLiteUserSettingsRepository.shared
        let enabled = settings.bool(autoGenerateEnabledKey, default: true)
        guard enabled else { return }

        // 1. 节流：今天是否已 check 过
        let todayKey = todayKeyString()
        if let last = settings.get(key: lastCheckDateKey), last == todayKey {
            return
        }

        // 2. 决定优先级最高的待生成 kind（年 > 月 > 周）
        guard let candidate = pickCandidate() else {
            // 无候选时也写入 today key，避免反复进入计算
            settings.set(key: lastCheckDateKey, value: todayKey)
            return
        }

        settings.set(key: lastCheckDateKey, value: todayKey)

        // 3. 异步触发（不阻塞 UI；失败不弹 toast，仅落 SyncLogger）
        Task.detached(priority: .background) {
            do {
                let s = try await BillsSummaryService.shared.generate(
                    kind: candidate.kind,
                    reference: candidate.reference,
                    force: false
                )
                SyncLogger.info(phase: "summary.scheduler",
                                "auto-generated kind=\(s.periodKind.rawValue) records=\(s.recordCount)")
            } catch BillsSummaryServiceError.noData {
                // 阈值不够：忽略，不报错
            } catch {
                SyncLogger.failure(phase: "summary.scheduler", error: error,
                                   extra: "kind=\(candidate.kind.rawValue)")
            }
        }
    }

    // MARK: - 候选选取

    /// 选择今天应当生成的（kind, reference）；reference 指向"上一周/月/年"的某个时间点
    /// 这样 BillsSummaryAggregator.periodBounds 算出的就是上周/上月/去年的边界。
    private static func pickCandidate() -> (kind: BillsSummaryPeriodKind, reference: Date)? {
        let cal = BillsSummaryAggregator.calendar()
        let now = Date()

        // 年报：每年 1 月 1 日；reference = 去年某天
        let yearComps = cal.dateComponents([.month, .day], from: now)
        if yearComps.month == 1 && yearComps.day == 1 {
            if let lastYear = cal.date(byAdding: .year, value: -1, to: now),
               !exists(kind: .year, reference: lastYear) {
                return (.year, lastYear)
            }
        }

        // 月报：每月 1 日；reference = 上月某天
        if yearComps.day == 1 {
            if let lastMonth = cal.date(byAdding: .month, value: -1, to: now),
               !exists(kind: .month, reference: lastMonth) {
                return (.month, lastMonth)
            }
        }

        // 周报：每周一；reference = 上周某天
        // weekday: 1 = Sunday（gregorian 默认），firstWeekday=2 = 周一
        let weekday = cal.component(.weekday, from: now)
        if weekday == 2 {
            if let lastWeek = cal.date(byAdding: .day, value: -7, to: now),
               !exists(kind: .week, reference: lastWeek) {
                return (.week, lastWeek)
            }
        }
        return nil
    }

    private static func exists(kind: BillsSummaryPeriodKind, reference: Date) -> Bool {
        let bounds = BillsSummaryAggregator.periodBounds(kind: kind, reference: reference)
        if let s = try? SQLiteBillsSummaryRepository.shared.find(kind: kind, periodStart: bounds.start) {
            return s.summaryText.isEmpty == false
        }
        return false
    }

    private static func todayKeyString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
