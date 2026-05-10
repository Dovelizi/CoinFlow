//  StatsAnalysisHostView.swift
//  CoinFlow · V2 Stats · 8 分析页面路由
//
//  设计基线：design/screens/05-stats 的 8 张图（trend / sankey / wordcloud / budget /
//  aa-balance / category-detail / year-view / hourly），每张为独立全屏页面。
//
//  入口：StatsHubView 中 8 张 hubCard 通过 `NavigationLink(value: .trend)` 等触达。
//  这里不持有 ViewModel；每个子视图独立 init StatsViewModel（VM 内部对 .recordsDidChange
//  做监听 + 自动重算，多实例间数据保持同步且各自闭环管理生命周期）。

import SwiftUI

/// Stats Hub 9 个深度分析子页面 ID。
enum StatsAnalysisDestination: String, Hashable, CaseIterable {
    case trend       // 月度趋势曲线
    case sankey      // 收入→支出资金流
    case wordcloud   // 备注/分类词云
    case budget      // 预算环
    case aa          // AA 账本结算
    case category    // 分类详情下钻
    case year        // 12 月年度视图
    case hourly      // 24 小时分布
    case summary     // M10 · LLM 账单复盘历史
}

/// 词云 / 分类排行点击 → 跳转到分类详情页时携带的目标 categoryId。
/// 用 struct 包一层避免与其他 String navigation 冲突；Hashable 让 NavigationStack path 可识别。
struct CategoryDetailTarget: Hashable {
    let categoryId: String
}

/// 统一空态。所有子视图在 `vm.hasAnyData == false` 时回退到此组件。
struct StatsEmptyState: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: NotionTheme.space5) {
            Spacer(minLength: 80)
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(Color.inkTertiary)
            Text(title)
                .font(NotionFont.bodyBold())
                .foregroundStyle(Color.inkSecondary)
            Text(subtitle)
                .font(NotionFont.small())
                .foregroundStyle(Color.inkTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, NotionTheme.space7)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 8 子视图通用 NavBar：返回按钮 + 双行标题 + 可选右侧 icon。
struct StatsSubNavBar: View {
    let title: String
    let subtitle: String
    let trailingIcon: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(title)
                    .font(.custom("PingFangSC-Semibold", size: 17))
                    .foregroundStyle(Color.inkPrimary)
                Text(subtitle)
                    .font(.custom("PingFangSC-Regular", size: 11))
                    .foregroundStyle(Color.inkTertiary)
            }
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.inkPrimary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")
                Spacer()
                if let trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: 36, height: 36)
                }
            }
        }
        .padding(.horizontal, NotionTheme.space4)
        .frame(height: 52)
        .background(Color.appCanvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.divider).frame(height: NotionTheme.borderWidth)
        }
    }
}

// MARK: - Common formatting helpers（所有子视图共用）

enum StatsFormat {
    /// 整数 + 千分位（图表轴标签 / 卡片大数字）
    static func intGrouped(_ d: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 0
        f.usesGroupingSeparator = true
        return f.string(from: d as NSDecimalNumber) ?? "0"
    }

    /// 紧凑万/千格式（年度/AA hero 用）
    static func compactK(_ d: Decimal) -> String {
        let v = (d as NSDecimalNumber).doubleValue
        if v >= 10000 { return String(format: "%.1fw", v / 10000) }
        if v >= 1000  { return String(format: "%.1fk", v / 1000) }
        return intGrouped(d)
    }

    /// 月份 / 子页 subtitle 通用
    static func ymSubtitle(_ ym: YearMonth) -> String {
        "\(ym.year) 年 \(ym.month) 月"
    }
}
