//  StatsWordCloudView.swift
//  CoinFlow · V2 Stats · 分类词云
//
//  设计基线：design/screens/05-stats/hub-light.png（命名错位，实际是 wordcloud）
//  - 顶部"分类支出词云"：按分类金额作字号权重，旋转 ±12° 散布
//  - 底部"分类排行"列表（按金额降序）

import SwiftUI

struct StatsWordCloudView: View {
    @StateObject private var vm = StatsViewModel()
    @Environment(\.colorScheme) private var scheme
    @State private var showSearch = false

    /// 词云原始数据保留 categoryId，用于点击跳转到分类详情页。
    private var categoryWords: [(id: String, word: String, weight: Int, color: NotionColor)] {
        vm.expenseCategorySlices.map { c in
            (id: c.id,
             word: c.name,
             weight: (c.amount as NSDecimalNumber).intValue,
             color: c.tone)
        }
    }

    private var totalExpense: Decimal {
        vm.expenseCategorySlices.map(\.amount).reduce(0, +)
    }

    var body: some View {
        VStack(spacing: 0) {
            StatsSubNavBar(title: "分类词云",
                           subtitle: "\(StatsFormat.ymSubtitle(vm.month)) · 分类支出",
                           trailingIcon: "magnifyingglass",
                           trailingAction: { showSearch = true },
                           trailingAccessibility: "搜索分类")
            ScrollView {
                VStack(spacing: NotionTheme.space7) {
                    if vm.expenseCategorySlices.isEmpty {
                        StatsEmptyState(title: "本月暂无支出",
                                        subtitle: "记录支出后会按分类生成词云")
                            .frame(height: 360)
                    } else {
                        cloudCard
                        topListCard
                    }
                }
                .padding(.horizontal, NotionTheme.space5)
                .padding(.top, NotionTheme.space6)
                .padding(.bottom, NotionTheme.space9)
            }
        }
        .background(ThemedBackgroundLayer(kind: .stats))
        .navigationBarHidden(true)
        .onAppear { vm.reload() }
        .sheet(isPresented: $showSearch) {
            StatsCategorySearchSheet(allSlices: vm.expenseCategorySlices,
                                     scheme: scheme)
        }
    }

    private var cloudCard: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            HStack {
                Text("分类支出词云")
                    .font(.custom("PingFangSC-Semibold", size: 14))
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
                Text("总支出 ¥" + StatsFormat.intGrouped(totalExpense))
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
            }
            .padding(.leading, 4)
            CategoryWordFlowView(words: categoryWords, scheme: scheme)
                .frame(minHeight: 220)
                .padding(NotionTheme.space5)
                .background(
                    RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                        .fill(Color.hoverBg.opacity(0.5))
                )
        }
    }

    private var topListCard: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            Text("分类排行")
                .font(.custom("PingFangSC-Semibold", size: 14))
                .foregroundStyle(Color.inkPrimary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                let items = vm.expenseCategorySlices
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, cat in
                    NavigationLink(value: CategoryDetailTarget(categoryId: cat.id)) {
                        HStack {
                            Text("\(idx + 1)")
                                .font(.custom("PingFangSC-Semibold", size: 12))
                                .foregroundStyle(Color.inkTertiary)
                                .frame(width: 18)
                            ZStack {
                                RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                                    .fill(cat.tone.background(scheme))
                                Image(systemName: cat.icon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(cat.tone.text(scheme))
                            }
                            .frame(width: 24, height: 24)
                            Text(cat.name)
                                .font(NotionFont.body())
                                .foregroundStyle(Color.inkPrimary)
                            Spacer()
                            Text("¥" + StatsFormat.intGrouped(cat.amount))
                                .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(Color.inkSecondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.inkTertiary)
                        }
                        .padding(.horizontal, NotionTheme.space5)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressableSoft)
                    .accessibilityLabel("\(cat.name)，¥\(StatsFormat.intGrouped(cat.amount))，点击查看详情")
                    if idx < items.count - 1 {
                        Rectangle().fill(Color.divider).frame(height: 0.5)
                            .padding(.leading, NotionTheme.space5 + 18 + NotionTheme.space4)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                    .fill(Color.hoverBg.opacity(0.5))
                )
        }
    }
}

/// 分类词云布局（每个词分类色 + 旋转散落 + 点击跳转分类详情页）。
struct CategoryWordFlowView: View {
    let words: [(id: String, word: String, weight: Int, color: NotionColor)]
    let scheme: ColorScheme

    private let rotations: [Double] = [-12, -6, 0, 6, 12]

    var body: some View {
        let maxW = max(1, words.map(\.weight).max() ?? 1)
        let scattered = scatter(words)

        StatsScatteredFlowLayout(hSpacing: 12, vSpacing: 16) {
            ForEach(Array(scattered.enumerated()), id: \.offset) { idx, w in
                let ratio = Double(w.weight) / Double(maxW)
                let size: CGFloat = 14 + CGFloat(ratio * ratio * 30)
                NavigationLink(value: CategoryDetailTarget(categoryId: w.id)) {
                    Text(w.word)
                        .font(.custom("PingFangSC-Semibold", size: size))
                        .foregroundStyle(w.color.text(scheme))
                        .rotationEffect(.degrees(rotations[idx % rotations.count]))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSoft)
                .accessibilityLabel("\(w.word) 分类，点击查看详情")
            }
        }
    }

    private func scatter(_ arr: [(id: String, word: String, weight: Int, color: NotionColor)])
        -> [(id: String, word: String, weight: Int, color: NotionColor)] {
        guard arr.count > 2 else { return arr }
        let n = arr.count
        let step: Int = {
            for s in [3, 5, 7] where gcd(s, n) == 1 { return s }
            return 1
        }()
        var result: [(id: String, word: String, weight: Int, color: NotionColor)] = []
        var idx = 0
        var visited = Set<Int>()
        while result.count < n {
            if !visited.contains(idx) {
                result.append(arr[idx])
                visited.insert(idx)
            }
            idx = (idx + step) % n
        }
        return result
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }
}

/// 散乱流式布局：行宽不够换行，行内居中。
struct StatsScatteredFlowLayout: Layout {
    var hSpacing: CGFloat
    var vSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = layoutRows(maxWidth: maxWidth, subviews: subviews)
        let totalHeight = rows.reduce(0) { $0 + $1.maxHeight }
            + CGFloat(max(0, rows.count - 1)) * vSpacing
        return CGSize(width: maxWidth.isFinite ? maxWidth : 320, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layoutRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let totalRowW = row.items.reduce(CGFloat(0)) { $0 + $1.size.width }
                + CGFloat(max(0, row.items.count - 1)) * hSpacing
            var x = bounds.minX + max(0, (bounds.width - totalRowW) / 2)
            for item in row.items {
                let placement = CGPoint(x: x + item.size.width / 2,
                                        y: y + row.maxHeight / 2)
                subviews[item.index].place(at: placement,
                                           anchor: .center,
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + hSpacing
            }
            y += row.maxHeight + vSpacing
        }
    }

    private struct RowItem { let index: Int; let size: CGSize }
    private struct Row { var items: [RowItem]; var maxHeight: CGFloat }

    private func layoutRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentRow: [RowItem] = []
        var currentMaxH: CGFloat = 0
        for (idx, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            let needed = currentRow.isEmpty
                ? size.width
                : currentRow.reduce(CGFloat(0)) { $0 + $1.size.width }
                  + hSpacing * CGFloat(currentRow.count) + size.width
            if !currentRow.isEmpty && needed > maxWidth {
                rows.append(Row(items: currentRow, maxHeight: currentMaxH))
                currentRow = []; currentMaxH = 0
            }
            currentRow.append(RowItem(index: idx, size: size))
            currentMaxH = max(currentMaxH, size.height)
        }
        if !currentRow.isEmpty {
            rows.append(Row(items: currentRow, maxHeight: currentMaxH))
        }
        return rows
    }
}

// MARK: - 分类搜索 Sheet
//
// 使用：词云页右上角 magnifyingglass → 弹出此 sheet
// 功能：实时模糊匹配本月支出分类名 → 点击跳转分类详情
//      （注：搜索结果不参与跳转 navigation stack；通过关闭 sheet 后回到词云页，
//        如果用户想进入分类详情，引导他点击底部"分类排行"列表，避免 sheet 内 push
//        带来的导航栈混乱。这里 sheet 的角色是"快速定位"。）

struct StatsCategorySearchSheet: View {
    let allSlices: [StatsCategorySlice]
    let scheme: ColorScheme
    @State private var query: String = ""
    @Environment(\.dismiss) private var dismiss

    private var results: [StatsCategorySlice] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return allSlices }
        return allSlices.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, NotionTheme.space5)
                    .padding(.top, NotionTheme.space5)
                    .padding(.bottom, NotionTheme.space4)

                if results.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.inkTertiary)
                        Text("没有匹配的分类")
                            .font(NotionFont.small())
                            .foregroundStyle(Color.inkSecondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { idx, cat in
                                NavigationLink(value: CategoryDetailTarget(categoryId: cat.id)) {
                                    resultRow(cat)
                                }
                                .buttonStyle(.pressableSoft)
                                if idx < results.count - 1 {
                                    Rectangle().fill(Color.divider).frame(height: 0.5)
                                        .padding(.leading, NotionTheme.space5 + 28 + NotionTheme.space4)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                                .fill(Color.hoverBg.opacity(0.5))
                        )
                        .padding(.horizontal, NotionTheme.space5)
                    }
                }
            }
            .background(Color.appCanvas)
            .navigationTitle("搜索分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .navigationDestination(for: CategoryDetailTarget.self) { target in
                StatsCategoryDetailView(preferredCategoryId: target.categoryId)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Color.inkTertiary)
            TextField("输入分类名（如：餐饮、交通）", text: $query)
                .font(NotionFont.body())
                .foregroundStyle(Color.inkPrimary)
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.inkTertiary)
                }
            }
        }
        .padding(.horizontal, NotionTheme.space4)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                .fill(Color.hoverBg)
        )
    }

    @ViewBuilder
    private func resultRow(_ cat: StatsCategorySlice) -> some View {
        HStack(spacing: NotionTheme.space4) {
            ZStack {
                RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                    .fill(cat.tone.background(scheme))
                Image(systemName: cat.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(cat.tone.text(scheme))
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(cat.name)
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.inkPrimary)
                Text("\(cat.count) 笔 · \(Int(cat.percentage * 100))%")
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer()
            Text("¥" + StatsFormat.intGrouped(cat.amount))
                .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.inkSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.inkTertiary)
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
