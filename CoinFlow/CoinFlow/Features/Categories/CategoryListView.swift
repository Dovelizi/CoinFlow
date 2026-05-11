//  CategoryListView.swift
//  CoinFlow · M7 · [10-1/10-2/10-3]
//
//  分类管理 — Notion 数据库表风（重写）
//
//  设计基线：
//    - design/screens/10-categories/{main,edit,quick-action}-*.png
//    - CoinFlowPreview MiscScreensView.CategoryMgmtView（L298-589）
//
//  三态：
//    - main：只读列表，表头「名称 / 类型 / 已用」三列，底部"+ 新建分类"行按钮
//    - edit：每行左侧 line.3.horizontal（仅视觉锚点，V2 接 .onMove 真 drag）+ 右侧 minus.circle.fill 红色删除
//    - add：贴底 sheet，图标 6 候选 + 颜色 9 候选
//
//  真实数据源：SQLiteCategoryRepository + SQLiteRecordRepository（按 categoryId 统计 usedCount）

import SwiftUI

struct CategoryListView: View {

    enum Mode { case main, edit }

    @State private var mode: Mode = .main
    @State private var rows: [CategoryRow] = []
    @State private var showAddSheet: Bool = false
    @State private var showDeleteAlert: CategoryRow?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    struct CategoryRow: Identifiable, Equatable {
        let id: String
        let name: String
        let kind: CategoryKind
        let icon: String
        let colorHex: String
        let usedCount: Int
        let isPreset: Bool
    }

    var body: some View {
        ZStack {
            ThemedBackgroundLayer(kind: .categories)
            VStack(spacing: 0) {
                navBar
                ScrollView {
                    VStack(spacing: 0) {
                        tableHeader
                        Rectangle().fill(Color.divider).frame(height: 0.5)
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                            tableRow(row)
                            if idx < rows.count - 1 {
                                Rectangle().fill(Color.divider).frame(height: 0.5)
                            }
                        }
                        addRowButton
                    }
                    .background(Color.appCanvas)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear { load() }
        .sheet(isPresented: $showAddSheet) {
            AddCategorySheet(onSaved: {
                showAddSheet = false
                load()
            })
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert(item: $showDeleteAlert) { row in
            Alert(
                title: Text("删除分类「\(row.name)」？"),
                message: Text(row.usedCount > 0
                              ? "该分类已被 \(row.usedCount) 笔流水使用，删除后流水分类将置空。"
                              : "删除后不可恢复。"),
                primaryButton: .destructive(Text("删除")) {
                    delete(row)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    // MARK: - Nav

    private var navBar: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("分类管理")
                    .font(.custom("PingFangSC-Semibold", size: 17))
                    .foregroundStyle(Color.inkPrimary)
                Text("\(rows.count) 个分类")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
            }
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.inkPrimary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSoft)
                .accessibilityLabel("返回")
                Spacer()
                Button {
                    withAnimation(Motion.smooth) {
                        mode = mode == .edit ? .main : .edit
                    }
                } label: {
                    Image(systemName: mode == .edit ? "checkmark" : "ellipsis")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(mode == .edit ? Color.accentBlue : Color.inkSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSoft)
                .accessibilityLabel(mode == .edit ? "完成编辑" : "进入编辑模式")
            }
            .padding(.horizontal, NotionTheme.space4)
        }
        .frame(height: 52)
        .background(Color.appCanvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.divider).frame(height: 0.5)
        }
    }

    // MARK: - Table

    private var tableHeader: some View {
        HStack(spacing: 0) {
            if mode == .edit {
                Color.clear.frame(width: 32, height: 28)
            }
            headerCell("名称", width: 120, isFirst: true)
            headerCell("类型", width: 56)
            headerCell("已用", width: 60)
            Spacer()
            if mode == .edit {
                Color.clear.frame(width: 32, height: 28)
            }
        }
        .padding(.horizontal, NotionTheme.space4)
        .frame(height: 32)
        .background(Color.hoverBg.opacity(0.4))
    }

    @ViewBuilder
    private func headerCell(_ text: String, width: CGFloat, isFirst: Bool = false) -> some View {
        Text(text)
            .font(.custom("PingFangSC-Regular", size: 11))
            .foregroundStyle(Color.inkTertiary)
            .frame(width: width, alignment: .leading)
            .padding(.leading, isFirst ? NotionTheme.space3 : 0)
    }

    @ViewBuilder
    private func tableRow(_ row: CategoryRow) -> some View {
        HStack(spacing: 0) {
            if mode == .edit {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.inkTertiary)
                    .frame(width: 32, height: 44)
                    .accessibilityHidden(true)
            }

            // 名称 cell（icon + 颜色 + 文字）
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: row.colorHex).opacity(0.18))
                    Image(systemName: row.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: row.colorHex))
                }
                .frame(width: 20, height: 20)
                Text(row.name)
                    .font(NotionFont.body())
                    .foregroundStyle(Color.inkPrimary)
                    .lineLimit(1)
            }
            .frame(width: 120, alignment: .leading)
            .padding(.leading, NotionTheme.space3)

            // 类型 cell（胶囊）
            Text(row.kind == .expense ? "支出" : "收入")
                .font(.custom("PingFangSC-Regular", size: 11))
                .foregroundStyle(row.kind == .expense ? Color.dangerRed : Color.statusSuccess)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(
                    Capsule().fill((row.kind == .expense ? Color.dangerRed : Color.statusSuccess).opacity(0.15))
                )
                .frame(width: 56, alignment: .leading)

            // 已用 cell
            Text("\(row.usedCount)")
                .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 60, alignment: .leading)

            Spacer()

            if mode == .edit {
                Button {
                    if row.isPreset {
                        // 预设不可删（用户偏好：禁用震动，仅保留视觉/逻辑约束）
                        Haptics.warn()
                        return
                    }
                    showDeleteAlert = row
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(row.isPreset ? Color.inkTertiary : Color.dangerRed)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSoft)
                .accessibilityLabel(row.isPreset ? "预设分类不可删除" : "删除分类 \(row.name)")
            }
        }
        .padding(.horizontal, NotionTheme.space4)
        .frame(height: 44)
    }

    private var addRowButton: some View {
        Button {
            showAddSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("新建分类")
                    .font(.custom("PingFangSC-Regular", size: 13))
            }
            .foregroundStyle(Color.inkTertiary)
            .padding(.horizontal, NotionTheme.space4)
            .frame(height: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSoft)
        .accessibilityLabel("新建分类")
    }

    // MARK: - Data

    private func load() {
        do {
            let all = try SQLiteCategoryRepository.shared.list(kind: nil, includeDeleted: false)
            let records = (try? SQLiteRecordRepository.shared.list(.init(
                ledgerId: DefaultSeeder.defaultLedgerId,
                includesDeleted: false,
                limit: nil
            ))) ?? []
            // 统计每个分类的 usedCount
            var counts: [String: Int] = [:]
            for r in records { counts[r.categoryId, default: 0] += 1 }
            rows = all.map { cat in
                CategoryRow(
                    id: cat.id,
                    name: cat.name,
                    kind: cat.kind,
                    icon: cat.icon,
                    colorHex: cat.colorHex,
                    usedCount: counts[cat.id] ?? 0,
                    isPreset: cat.isPreset
                )
            }
        } catch {
            rows = []
        }
    }

    private func delete(_ row: CategoryRow) {
        do {
            try SQLiteCategoryRepository.shared.delete(id: row.id)
            load()
        } catch {
            // 删除失败静默，load 保留原数据
            NSLog("[CategoryListView] delete failed: \(error)")
        }
    }
}

// MARK: - Add Category Sheet（贴底大卡片，图标 6 + 颜色 9）

struct AddCategorySheet: View {

    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var name: String = ""
    @State private var selectedKind: CategoryKind = .expense
    @State private var selectedIcon: String = CategoryIconLibrary.defaultIconName
    @State private var selectedColor: String = "#6B95D0"
    @FocusState private var nameFocused: Bool

    private let colorCandidates = [
        "#9B9A97", "#A98A6A", "#D9730D", "#CA9849",
        "#448361", "#6B95D0", "#7C5BC2", "#C14C8A", "#D44C47"
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: NotionTheme.space6) {
                    previewBlock
                    nameBlock
                    kindBlock
                    iconBlock
                    colorBlock
                }
                .padding(.horizontal, NotionTheme.space5)
                .padding(.top, NotionTheme.space5)
                .padding(.bottom, NotionTheme.space9)
            }
        }
        .themedSheetSurface()
        .keyboardDoneToolbar()
    }

    private var header: some View {
        ZStack {
            Text("新建分类")
                .font(.custom("PingFangSC-Semibold", size: 17))
                .foregroundStyle(Color.inkPrimary)
            HStack {
                Button { dismiss() } label: {
                    Text("取消")
                        .font(NotionFont.body())
                        .foregroundStyle(Color.inkSecondary)
                        .padding(.horizontal, NotionTheme.space4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSoft)
                Spacer()
                Button { save() } label: {
                    Text("保存")
                        .font(.custom("PingFangSC-Semibold", size: 15))
                        .foregroundStyle(canSave ? Color.accentBlue : Color.inkTertiary)
                        .padding(.horizontal, NotionTheme.space4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSoft)
                .disabled(!canSave)
            }
            .padding(.horizontal, NotionTheme.space4)
        }
        .frame(height: 52)
        .background(Color.appSheetCanvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.divider).frame(height: 0.5)
        }
    }

    private var previewBlock: some View {
        VStack(spacing: NotionTheme.space3) {
            ZStack {
                RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                    .fill(Color(hex: selectedColor).opacity(0.18))
                    .frame(width: 56, height: 56)
                Image(systemName: selectedIcon)
                    .font(.system(size: 26))
                    .foregroundStyle(Color(hex: selectedColor))
            }
            Text(name.isEmpty ? "分类预览" : name)
                .font(.custom("PingFangSC-Semibold", size: 17))
                .foregroundStyle(name.isEmpty ? Color.inkTertiary : Color.inkPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NotionTheme.space5)
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space2) {
            Text("名称")
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
            TextField("如「早餐」「奶茶」", text: $name)
                .font(NotionFont.body())
                .foregroundStyle(Color.inkPrimary)
                .focused($nameFocused)
                .padding(.horizontal, NotionTheme.space5)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                        .fill(Color.hoverBg.opacity(0.5))
                )
        }
    }

    private var kindBlock: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            Text("类型")
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
            HStack(spacing: 0) {
                kindButton(.expense, label: "支出")
                kindButton(.income, label: "收入")
            }
            .padding(NotionTheme.space2)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                    .fill(Color.hoverBg.opacity(0.5))
            )
        }
    }

    private func kindButton(_ k: CategoryKind, label: String) -> some View {
        let active = selectedKind == k
        // liquidGlass 主题下 Color.surfaceOverlay 渲染为深色实心 → 在紫色玻璃 sheet 上呈黑块。
        // 与 NewRecordModal/SettingsView 段控件保持同一兜底方案：液态玻璃下走半透白高亮。
        let activeFill: Color = LGAThemeRuntime.isLiquidGlass
            ? Color.white.opacity(0.18)
            : Color.surfaceOverlay
        return Button {
            selectedKind = k
        } label: {
            Text(label)
                .font(NotionFont.bodyBold())
                .foregroundStyle(active ? Color.inkPrimary : Color.inkTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, NotionTheme.space3)
                .background(
                    RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                        .fill(active ? activeFill : Color.clear)
                )
        }
        .buttonStyle(.pressableSoft)
    }

    private var iconBlock: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            Text("图标")
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
            IconPickerView(selected: $selectedIcon, tintColorHex: selectedColor)
                .frame(height: 360)   // 固定高度避免 sheet 内 ScrollView 嵌套抖动
        }
    }

    private var colorBlock: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            Text("颜色")
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
            HStack(spacing: NotionTheme.space3) {
                ForEach(colorCandidates, id: \.self) { hex in
                    Button { selectedColor = hex } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .stroke(selectedColor == hex ? Color.inkPrimary : Color.clear,
                                            lineWidth: 2)
                                    .padding(-3)
                            )
                    }
                    .buttonStyle(.pressableSoft)
                    .accessibilityLabel("颜色 \(hex)")
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let cat = Category(
            id: UUID().uuidString,
            name: trimmed,
            kind: selectedKind,
            icon: selectedIcon,
            colorHex: selectedColor,
            parentId: nil,
            sortOrder: 100,
            isPreset: false,
            deletedAt: nil
        )
        do {
            try SQLiteCategoryRepository.shared.insert(cat)
            onSaved()
        } catch {
            NSLog("[AddCategorySheet] insert failed: \(error)")
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { CategoryListView() }
        .preferredColorScheme(.dark)
}
#endif
