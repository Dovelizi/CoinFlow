//  AASplitListView.swift
//  CoinFlow · M11 — AA 分账主页（列表 + 创建入口）
//
//  入口：StatsHubView 的 .aa 路由 → 替代 StatsAABalanceView 占位

import SwiftUI

struct AASplitListView: View {

    @StateObject private var vm = AASplitListViewModel()
    @State private var showCreate: Bool = false

    /// 是否被嵌入到 Tab（如 AA Tab 主入口）：
    /// - false（独立路由场景，例如从 StatsHub.aa 路由进来）：保留原行为
    ///   （独占 NavigationStack + 隐藏外部 TabBar）
    /// - true：作为 Tab 的根视图嵌入；不调用 .hideTabBar()（保留底部 TabBar 可见），
    ///   外层由 MainTabView 提供 NavigationStack。顶部 navBar 仍然显示，
    ///   保证创建按钮入口可用。
    let embedded: Bool

    init(embedded: Bool = false) {
        self.embedded = embedded
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部 navBar 始终显示——独立路由 / Tab 嵌入两种场景都有创建入口
            StatsSubNavBar(
                title: "AA 分账",
                subtitle: subtitle,
                trailingIcon: "plus.circle.fill",
                trailingAction: { showCreate = true },
                trailingAccessibility: "新建分账",
                // Tab 嵌入场景无栈可返回，不渲染左上 chevron.left；独立路由（StatsHub.aa 进入）保留返回。
                showsBackButton: !embedded
            )
            filterTabs
            // 改用 List 承载，以获得原生 .swipeActions 左滑删除能力。
            // .listStyle(.plain) + 透明背景/分隔线/insets 还原原 LazyVStack 视觉。
            List {
                if vm.filteredItems.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                } else {
                    ForEach(vm.filteredItems) { item in
                        // ZStack + 隐藏 NavigationLink：
                        // 默认 NavigationLink 会在 List 里给行尾追加系统 chevron（>），
                        // 用户已经知道可点击/可滑动，不再需要 chevron。
                        // 这里把 NavigationLink 透明叠在卡片下方仅承担跳转，
                        // 卡片自身则保持纯展示（无 disclosure indicator）。
                        ZStack {
                            NavigationLink(value: AASplitListDestination(
                                ledgerId: item.ledger.id
                            )) {
                                EmptyView()
                            }
                            .opacity(0)
                            AASplitListCard(item: item)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(
                            top: 0,
                            leading: NotionTheme.space5,
                            bottom: NotionTheme.space5,
                            trailing: NotionTheme.space5
                        ))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                vm.softDelete(id: item.ledger.id)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                if let err = vm.loadError {
                    Text(err)
                        .font(NotionFont.small())
                        .foregroundStyle(Color.dangerRed)
                        .padding()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
        }
        .background(ThemedBackgroundLayer(kind: .stats))
        .navigationDestination(for: AASplitListDestination.self) { dest in
            AASplitDetailView(ledgerId: dest.ledgerId)
        }
        .modifier(EmbedAwareNavModifier(embedded: embedded))
        .onAppear { vm.reload() }
        .sheet(isPresented: $showCreate) {
            AASplitCreateSheet(onCreated: { _ in
                showCreate = false
                vm.reload()
            })
            .presentationDetents([.medium, .large])
        }
    }

    private var subtitle: String {
        let total = vm.items.count
        if total == 0 { return "等待启用" }
        let recording = vm.items.filter { $0.status == .recording }.count
        return "\(total) 个 · 记录中 \(recording)"
    }

    private var filterTabs: some View {
        // 横向 ScrollView 装 filter 胶囊。
        // 注：创建入口统一由顶部 StatsSubNavBar 的 trailingIcon 提供，
        // 此处不再追加额外的 + 按钮，避免重复入口。
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NotionTheme.space3) {
                ForEach(AASplitListFilter.allCases) { f in
                    let active = vm.filter == f
                    Button {
                        Haptics.select()
                        vm.filter = f
                    } label: {
                        Text(f.displayName)
                            .font(NotionFont.small())
                            .fontWeight(active ? .semibold : .regular)
                            .foregroundStyle(active ? Color.white : Color.inkSecondary)
                            .padding(.horizontal, NotionTheme.space5)
                            .padding(.vertical, NotionTheme.space3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(active ? Color.accentBlue : Color.hoverBg)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, NotionTheme.space5)
        }
        .frame(height: 44)
        .padding(.top, NotionTheme.space3)
    }

    private var emptyState: some View {
        VStack(spacing: NotionTheme.space5) {
            Spacer(minLength: 80)
            Image(systemName: "person.2.fill")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(Color.accentPurple.opacity(0.6))
            Text(emptyTitle)
                .font(NotionFont.bodyBold())
                .foregroundStyle(Color.inkSecondary)
            Text("把旅游、聚餐等场景的多笔流水记到一处，结算时一键回写到个人账单")
                .font(NotionFont.small())
                .foregroundStyle(Color.inkTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, NotionTheme.space7)
            Button {
                showCreate = true
            } label: {
                Text("立即创建")
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, NotionTheme.space7)
                    .padding(.vertical, NotionTheme.space4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentBlue)
                    )
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var emptyTitle: String {
        switch vm.filter {
        case .all: return "还没有 AA 分账"
        case .recording: return "没有「分账记录中」的账本"
        case .settling: return "没有「结算中」的账本"
        case .completed: return "还没有已完成的分账"
        }
    }
}

// MARK: - 列表卡片

private struct AASplitListCard: View {
    let item: AASplitListItem
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            HStack {
                Text(item.ledger.name)
                    .font(NotionFont.h3())
                    .foregroundStyle(Color.inkPrimary)
                    .lineLimit(1)
                Spacer()
                statusBadge
            }
            HStack(alignment: .firstTextBaseline, spacing: NotionTheme.space3) {
                Text("¥" + StatsFormat.decimalGrouped(item.totalAmount))
                    .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
                Text("\(item.recordCount) 笔")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
            }
            HStack(spacing: NotionTheme.space3) {
                if let last = item.lastRecordAt {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.inkTertiary)
                    Text("最近 \(formatRelative(last))")
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.inkTertiary)
                } else {
                    Text("尚无流水")
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.inkTertiary)
                }
                Spacer()
                if item.memberCount > 0 {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.inkTertiary)
                    Text("\(item.memberCount) 人")
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.inkTertiary)
                }
            }
        }
        .padding(NotionTheme.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .fill(Color.hoverBg.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .stroke(Color.divider, lineWidth: NotionTheme.borderWidth)
        )
    }

    private var statusBadge: some View {
        let (text, color) = statusStyle(item.status)
        return Text(text)
            .font(NotionFont.micro())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.16))
            )
    }

    private func statusStyle(_ s: AAStatus) -> (String, Color) {
        switch s {
        case .recording: return ("分账记录中", Color.accentBlue)
        case .settling:  return ("分账结算中", Color.statusWarning)
        case .completed: return ("已完成",     Color.statusSuccess)
        }
    }

    private func formatRelative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}

// MARK: - Navigation

/// AA 分账列表的导航值。用专属类型避免外层 NavigationStack 的 `String`
/// destination 路由冲突（账单页 Tab 嵌入场景）。
struct AASplitListDestination: Hashable {
    let ledgerId: String
}

/// 嵌入感知的 nav modifier：
/// - 顶部统一隐藏系统 nav bar：页面自绘 `StatsSubNavBar` 已含标题/副标题/右上 + 入口，
///   不依赖系统 nav bar；不隐藏会让外层 NavigationStack 默认露出"<"返回角标。
/// - embedded = false（独立路由）：额外 .hideTabBar() 隐藏底部 TabBar
/// - embedded = true（被 Tab 嵌入）：保留 TabBar 可见
private struct EmbedAwareNavModifier: ViewModifier {
    let embedded: Bool
    func body(content: Content) -> some View {
        if embedded {
            content
                .navigationBarHidden(true)
        } else {
            content
                .navigationBarHidden(true)
                .hideTabBar()
        }
    }
}
