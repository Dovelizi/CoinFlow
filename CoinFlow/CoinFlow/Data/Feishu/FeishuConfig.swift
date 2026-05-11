//  FeishuConfig.swift
//  CoinFlow · M9 · 飞书多维表格同步
//
//  集中管理飞书相关配置：
//  - App ID / Secret（自建应用 tenant_access_token 鉴权）
//  - Wiki 模式（推荐）：用户在飞书 Wiki 空间里自己建好多维表格，填 Wiki Node Token + Table Id
//    App 不再自动建表；首次同步时会把 Wiki Node Token 换成真实 app_token 并缓存
//  - 自动建表模式（fallback）：两个 Wiki 字段留空时，App 自动在"我的空间"根目录建一张新表
//
//  Q1=A 主键列「账单描述」处理：写 record.note 到主键列（飞书 Wiki 表已有该字段）

import Foundation

enum FeishuConfig {

    // MARK: - 用户配置（来自 SystemConfigStore，App 内可改）

    static var appID: String { SystemConfigStore.shared.feishuAppID }
    static var appSecret: String { SystemConfigStore.shared.feishuAppSecret }

    /// Wiki 节点 token（若用户指定了 Wiki 模式）
    static var wikiNodeToken: String { SystemConfigStore.shared.feishuWikiNodeToken }

    /// Wiki 模式下用户指定的 table_id
    static var configuredTableId: String { SystemConfigStore.shared.feishuBillsTableId }

    /// 自动建表模式的 folder_token
    static var folderToken: String { SystemConfigStore.shared.feishuFolderToken }

    /// 用户 open_id（建表后给此用户自动加 full_access 协作者权限）
    static var ownerOpenID: String { SystemConfigStore.shared.feishuOwnerOpenID }

    /// 配置是否完整（appID + appSecret 都填了）
    static var isConfigured: Bool {
        SystemConfigStore.shared.isFeishuConfigured
    }

    /// 是否使用 Wiki 模式（两项都填 = Wiki 模式；否则走自动建表）
    static var isWikiMode: Bool {
        !wikiNodeToken.isEmpty && !configuredTableId.isEmpty
    }

    // MARK: - 动态状态（来自 UserDefaults，首次 bootstrap 后写入）

    private static let udAppTokenKey = "feishu.bitable.app_token"
    private static let udTableIdKey  = "feishu.bitable.table_id"
    private static let udBitableURLKey = "feishu.bitable.url"
    /// M10-Fix2 · 账单总结独立 bitable 元数据缓存
    private static let udSummaryAppTokenKey = "feishu.summary_bitable.app_token"
    private static let udSummaryTableIdKey  = "feishu.summary_bitable.table_id"
    private static let udSummaryBitableURLKey = "feishu.summary_bitable.url"

    /// 多维表格 App Token（Wiki 模式下是 obj_token；自动建表模式下是 create_app 返回值）
    static var bitableAppToken: String? {
        get { UserDefaults.standard.string(forKey: udAppTokenKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: udAppTokenKey)
            NotificationCenter.default.post(name: bitableMetadataDidChange, object: nil)
        }
    }

    /// 主"账单"数据表的 table_id
    static var billsTableId: String? {
        get { UserDefaults.standard.string(forKey: udTableIdKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: udTableIdKey)
            NotificationCenter.default.post(name: bitableMetadataDidChange, object: nil)
        }
    }

    /// 用户友好的多维表格 URL
    static var bitableURL: String? {
        get { UserDefaults.standard.string(forKey: udBitableURLKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: udBitableURLKey)
            NotificationCenter.default.post(name: bitableMetadataDidChange, object: nil)
        }
    }

    /// bitable 元数据（app_token / table_id / url）变更通知。
    /// 触发场景：首次 bootstrap、resetBitableCache 后重建、Wiki 模式初始化。
    /// UI （SystemConfigView 等）可监听后实时刷新只读展示。
    static let bitableMetadataDidChange = Notification.Name("FeishuConfig.bitableMetadataDidChange")

    /// 是否已经建好/关联好多维表格
    static var hasBitable: Bool {
        guard let t = bitableAppToken, !t.isEmpty,
              let id = billsTableId, !id.isEmpty else { return false }
        return true
    }

    /// M10-Fix2 · 账单总结独立 bitable 元数据
    static var summaryAppToken: String? {
        get { UserDefaults.standard.string(forKey: udSummaryAppTokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: udSummaryAppTokenKey) }
    }
    static var summaryTableId: String? {
        get { UserDefaults.standard.string(forKey: udSummaryTableIdKey) }
        set { UserDefaults.standard.set(newValue, forKey: udSummaryTableIdKey) }
    }
    static var summaryBitableURL: String? {
        get { UserDefaults.standard.string(forKey: udSummaryBitableURLKey) }
        set { UserDefaults.standard.set(newValue, forKey: udSummaryBitableURLKey) }
    }
    static var hasSummaryBitable: Bool {
        guard let t = summaryAppToken, !t.isEmpty,
              let id = summaryTableId, !id.isEmpty else { return false }
        return true
    }

    /// 重置所有 bitable 缓存（测试 / 用户手动重建用）
    static func resetBitableCache() {
        let ud = UserDefaults.standard
        ud.removeObject(forKey: udAppTokenKey)
        ud.removeObject(forKey: udTableIdKey)
        ud.removeObject(forKey: udBitableURLKey)
        NotificationCenter.default.post(name: bitableMetadataDidChange, object: nil)
    }

    /// M10-Fix2 · 重置 summary bitable 缓存
    static func resetSummaryBitableCache() {
        let ud = UserDefaults.standard
        ud.removeObject(forKey: udSummaryAppTokenKey)
        ud.removeObject(forKey: udSummaryTableIdKey)
        ud.removeObject(forKey: udSummaryBitableURLKey)
    }
}
