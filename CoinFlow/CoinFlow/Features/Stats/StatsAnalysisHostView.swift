//  StatsAnalysisHostView.swift
//  CoinFlow · V2 Stats · 10 分析页面路由
//
//  设计基线：design/screens/05-stats 的 10 张图（trend / sankey / wordcloud / budget /
//  main / aa-balance / category-detail / year-view / hourly + summary M10），
//  每张为独立全屏页面。
//
//  入口：StatsHubView 中 10 张 hubCard 通过 `NavigationLink(value: .trend)` 等触达。
//  这里不持有 ViewModel；每个子视图独立 init StatsViewModel（VM 内部对 .recordsDidChange
//  做监听 + 自动重算，多实例间数据保持同步且各自闭环管理生命周期）。

import SwiftUI
import UIKit

/// Stats Hub 10 个深度分析子页面 ID。
enum StatsAnalysisDestination: String, Hashable, CaseIterable {
    case trend       // 月度趋势曲线
    case sankey      // 收入→支出资金流
    case wordcloud   // 备注/分类词云
    case budget      // 预算环
    case main        // 本月统计（净增 + 收支笔数 + 日历热力 + 分类构成）
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
/// 当 `trailingAction` 提供时，右侧 icon 变成可点击按钮；不提供则保持装饰态（向后兼容旧调用点）。
/// `showsBackButton` 默认 true 保持原行为；当作为 Tab 根视图嵌入（无栈可返回）时显式传 false 以隐藏左侧 chevron。
struct StatsSubNavBar: View {
    let title: String
    let subtitle: String
    let trailingIcon: String?
    let trailingAction: (() -> Void)?
    let trailingAccessibility: String?
    let showsBackButton: Bool
    @Environment(\.dismiss) private var dismiss

    init(title: String,
         subtitle: String,
         trailingIcon: String? = nil,
         trailingAction: (() -> Void)? = nil,
         trailingAccessibility: String? = nil,
         showsBackButton: Bool = true) {
        self.title = title
        self.subtitle = subtitle
        self.trailingIcon = trailingIcon
        self.trailingAction = trailingAction
        self.trailingAccessibility = trailingAccessibility
        self.showsBackButton = showsBackButton
    }

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
                if showsBackButton {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.inkPrimary)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressableSoft)
                    .accessibilityLabel("返回")
                }
                Spacer()
                if let trailingIcon {
                    if let trailingAction {
                        Button(action: trailingAction) {
                            Image(systemName: trailingIcon)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(Color.inkPrimary)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressableSoft)
                        .accessibilityLabel(trailingAccessibility ?? "更多")
                    } else {
                        Image(systemName: trailingIcon)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(Color.inkSecondary)
                            .frame(width: 36, height: 36)
                    }
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

// MARK: - 通用分享工具：SwiftUI 视图 → UIImage → UIActivityViewController
//
// 八个统计页面里"分享"类按钮共用的工具。
// 用法：
//   .sheet(isPresented: $showShare) {
//       StatsShareSheet(items: [snapshotImage])
//   }
// 截图：StatsSnapshot.render { 任意 SwiftUI 视图 }

/// `UIActivityViewController` 的 SwiftUI 包装。
struct StatsShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// 把任意 SwiftUI 视图渲染为 `UIImage`（用于截图分享卡片）。
@MainActor
enum StatsSnapshot {
    /// 渲染一个固定宽度的 SwiftUI 视图为 UIImage。
    /// - parameter width: 渲染目标宽度，默认 390（iPhone 标准宽度）
    static func render<V: View>(width: CGFloat = 390,
                                @ViewBuilder _ view: () -> V) -> UIImage? {
        let host = view()
            .frame(width: width)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: host)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}

// MARK: - Common formatting helpers（所有子视图共用）

enum StatsFormat {
    /// 整数 + 千分位（仅图表轴标签用；金额展示请用 `decimalGrouped`）
    static func intGrouped(_ d: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 0
        f.usesGroupingSeparator = true
        return f.string(from: d as NSDecimalNumber) ?? "0"
    }

    /// 金额展示：最多 2 位小数 + 千分位，且整数时不显示小数点（智能）
    /// 例：123.2 → "123.2"，100 → "100"，1234.56 → "1,234.56"，1234.50 → "1,234.5"
    static func decimalGrouped(_ d: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = true
        return f.string(from: d as NSDecimalNumber) ?? "0"
    }

    /// 紧凑万/千格式（年度/AA hero 用）
    /// 小额（<1000）走 `decimalGrouped` 保留最多 2 位小数；≥1k/1w 才压缩
    static func compactK(_ d: Decimal) -> String {
        let v = (d as NSDecimalNumber).doubleValue
        if v >= 10000 { return String(format: "%.1fw", v / 10000) }
        if v >= 1000  { return String(format: "%.1fk", v / 1000) }
        return decimalGrouped(d)
    }

    /// 月份 / 子页 subtitle 通用
    static func ymSubtitle(_ ym: YearMonth) -> String {
        "\(ym.year) 年 \(ym.month) 月"
    }
}
