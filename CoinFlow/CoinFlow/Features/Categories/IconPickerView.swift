//  IconPickerView.swift
//  CoinFlow · 分类图标选择面板（可复用组件）
//
//  使用：
//   IconPickerView(
//       selected: $selectedIcon,         // String binding（SF Symbol systemName）
//       tintColorHex: selectedColor,     // 选中态高亮色
//       initialGroup: nil                // 首次显示哪个 chip；nil = "全部"
//   )
//
//  布局：
//   ┌──────────────────────────────────┐
//   │ 🔍 [ 搜索 ]                       │
//   ├──────────────────────────────────┤
//   │ [全部] [餐饮] [交通] [购物] …    │  ← 横滑 chip 行
//   ├──────────────────────────────────┤
//   │ 餐饮                              │  ← 仅"全部"模式下显示分组小标题
//   │ ┌──┬──┬──┬──┬──┬──┐              │
//   │ │🍴│☕│🍔│🍷│🥗│🍰│              │  ← 6 列网格
//   │ └──┴──┴──┴──┴──┴──┘              │
//   │ 交通                              │
//   │ ┌──┬──┬──┬──┬──┬──┐              │
//   │ │🚗│🚌│🚇│🚲│✈️│⛽│              │
//   │ └──┴──┴──┴──┴──┴──┘              │
//   └──────────────────────────────────┘
//
//  搜索态：
//   - 用户输入 query → 走 CategoryIconLibrary.search
//   - 命中结果按一个网格平铺，分组 chip 行此时仍可见（点击切回浏览态）
//   - 0 命中 → 显示空态文案

import SwiftUI

struct IconPickerView: View {

    @Binding var selected: String
    /// 选中态高亮色（与外层 Color Picker 联动；十六进制 e.g. "#6B95D0"）
    let tintColorHex: String

    @State private var query: String = ""
    @State private var selectedGroup: String = "全部"
    @FocusState private var searchFocused: Bool

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchBar
            chipRow
            ScrollView(showsIndicators: false) {
                if let hits = CategoryIconLibrary.search(query) {
                    // 搜索态
                    if hits.isEmpty {
                        emptyState
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("找到 \(hits.count) 个图标")
                                .font(NotionFont.micro())
                                .foregroundStyle(Color.inkTertiary)
                                .padding(.top, 4)
                            grid(icons: hits)
                        }
                    }
                } else if selectedGroup == "全部" {
                    // 浏览态 + 全部：按分组依次铺
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(CategoryIconLibrary.groups) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.title)
                                    .font(NotionFont.micro())
                                    .foregroundStyle(Color.inkTertiary)
                                grid(icons: group.icons)
                            }
                        }
                    }
                } else {
                    // 浏览态 + 单组：只铺该组
                    let group = CategoryIconLibrary.groups.first { $0.title == selectedGroup }
                    if let g = group {
                        grid(icons: g.icons)
                            .padding(.top, 4)
                    }
                }
            }
        }
    }

    // MARK: - 搜索栏

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Color.inkTertiary)
            TextField("搜索图标 / 输入「咖啡」「打车」", text: $query)
                .font(NotionFont.body())
                .foregroundStyle(Color.inkPrimary)
                .focused($searchFocused)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button {
                    query = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.inkTertiary)
                }
                .buttonStyle(.pressableSoft)
                .accessibilityLabel("清空搜索")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                .fill(Color.hoverBg.opacity(0.5))
        )
    }

    // MARK: - 分组 chip

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(title: "全部", isFirst: true)
                ForEach(CategoryIconLibrary.groups) { g in
                    chip(title: g.title)
                }
            }
            .padding(.horizontal, 1)   // 避免 stroke 被裁
        }
    }

    @ViewBuilder
    private func chip(title: String, isFirst: Bool = false) -> some View {
        let active = (selectedGroup == title) && query.isEmpty
        Button {
            withAnimation(Motion.smooth) {
                selectedGroup = title
                if !query.isEmpty {
                    query = ""    // 切 chip 自动清空搜索
                }
            }
        } label: {
            Text(title)
                .font(.custom("PingFangSC-Regular", size: 12))
                .foregroundStyle(active ? Color.inkPrimary : Color.inkSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(active ? Color(hex: tintColorHex).opacity(0.18) : Color.hoverBg.opacity(0.5))
                )
                .overlay(
                    Capsule()
                        .stroke(active ? Color(hex: tintColorHex) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.pressableSoft)
        .accessibilityLabel("分类 \(title)")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: - 网格

    private func grid(icons: [CategoryIcon]) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(icons) { ic in
                cell(ic)
            }
        }
    }

    private func cell(_ ic: CategoryIcon) -> some View {
        let active = selected == ic.systemName
        let tint = Color(hex: tintColorHex)
        return Button {
            selected = ic.systemName
            Haptics.select()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                    .fill(active ? tint.opacity(0.18) : Color.hoverBg.opacity(0.5))
                Image(systemName: ic.systemName)
                    .font(.system(size: 17))
                    .foregroundStyle(active ? tint : Color.inkSecondary)
                    .symbolRenderingMode(.monochrome)
            }
            .frame(height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                    .stroke(active ? tint : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.pressableSoft)
        .accessibilityLabel("图标 \(ic.aliases.first ?? ic.systemName)")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(Color.inkTertiary)
            Text("没有匹配「\(query)」的图标")
                .font(NotionFont.body())
                .foregroundStyle(Color.inkSecondary)
            Text("试试搜「咖啡」「打车」「健身」")
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}
