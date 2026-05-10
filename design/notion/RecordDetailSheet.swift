// RecordDetailSheet.swift
//
// 单笔流水详情 / 编辑 Bottom Sheet
//
// 设计决策（已确认）：
//   d1 = Bottom Sheet（.presentationDetents([.medium, .large])）
//   d2 = 可编辑字段：金额 / 分类 / 备注（核心 3 项；其他字段只读展示）
//   d3 = 实时保存：每个字段 onChange / 失焦立即写入（类 Notion；无"保存"按钮）
//
// 与 §5.5 设计基线对齐：
//   - PingFang 字体（B9）
//   - 默认深色（B10）
//   - 分类网格用 9 色 palette 中的 .gray/.orange/.blue 等（B8）
//   - 动画 150ms cubic-bezier(0.2,0,0,1)（§5.5.6）
//   - 唯一 shadow 来自 sheet 自身（系统提供，非自绘）

import SwiftUI

struct RecordDetailSheet: View {
    /// 传入要编辑的初始 row；本 sheet 内部维护可变副本，每次变化触发 onCommit
    let initial: RecordRow
    /// 字段任意一个变化后的回调（外部据此写 SQLite + 入同步队列）
    var onCommit: (RecordRow) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var amountText: String
    @State private var categoryName: String
    @State private var categoryIcon: String
    @State private var categoryColor: NotionColor
    @State private var note: String
    @State private var showCategoryPicker = false

    @FocusState private var amountFocused: Bool
    @FocusState private var noteFocused: Bool

    init(initial: RecordRow, onCommit: @escaping (RecordRow) -> Void = { _ in }) {
        self.initial = initial
        self.onCommit = onCommit
        // 金额初始化：显示用户友好的字符串（不带末尾 0）
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = false      // 编辑态不显千位逗号，避免输入麻烦
        _amountText      = State(initialValue: f.string(from: initial.amount as NSDecimalNumber) ?? "0")
        _categoryName    = State(initialValue: initial.categoryName)
        _categoryIcon    = State(initialValue: initial.categoryIcon)
        _categoryColor   = State(initialValue: initial.categoryColor)
        _note            = State(initialValue: initial.note)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部 grabber 是系统自带的（presentationDragIndicator(.visible)）
            // 这里只放标题区
            header
            ScrollView {
                VStack(spacing: NotionTheme.space7) {
                    amountSection
                    categorySection
                    noteSection
                    metaSection                  // 只读元信息：日期 / 来源 / 同步状态
                    deleteButton
                }
                .padding(.horizontal, NotionTheme.space6)
                .padding(.top, NotionTheme.space5)
                .padding(.bottom, NotionTheme.space9)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.canvasBG)
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(selectedName: $categoryName,
                                selectedIcon: $categoryIcon,
                                selectedColor: $categoryColor,
                                onPick: { commitField() })
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - 头部（"流水详情" + 关闭）

    private var header: some View {
        ZStack {
            Text("流水详情")
                .font(.custom("PingFangSC-Semibold", size: 17))
                .foregroundColor(.inkPrimary)
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.inkSecondary)
                        .frame(width: 32, height: 32)
                        .background(Color.hoverBg)
                        .clipShape(Circle())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, NotionTheme.space5)
        .frame(height: 52)
    }

    // MARK: - 金额（最大字号，居中编辑）

    private var amountSection: some View {
        VStack(spacing: NotionTheme.space3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(initial.direction == .expense ? "-¥" : "+¥")
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundColor(directionColor)
                TextField("0", text: $amountText)
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundColor(directionColor)
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .fixedSize()                       // 不撑满，根据内容收缩，便于和 -¥ 紧贴居中
                    .onChange(of: amountFocused) { focused in
                        if !focused { commitField() } // 失焦立即提交（§d3）
                    }
            }
            .frame(maxWidth: .infinity)

            // 金额下方的小标签：方向（不可在此切换；要改方向走分类反推）
            Text(initial.direction == .expense ? "支出" : "收入")
                .font(NotionFont.micro())
                .foregroundColor(.inkTertiary)
        }
        .padding(.vertical, NotionTheme.space5)
    }

    private var directionColor: Color {
        initial.direction == .expense
            ? NotionColor.red.text(scheme)
            : NotionColor.green.text(scheme)
    }

    // MARK: - 分类（点击打开 CategoryPickerSheet）

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            sectionLabel("分类")
            Button { showCategoryPicker = true } label: {
                HStack(spacing: NotionTheme.space5) {
                    ZStack {
                        RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                            .fill(Color.hoverBg)
                        Image(systemName: categoryIcon)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.inkSecondary)
                    }
                    .frame(width: 32, height: 32)

                    Text(categoryName)
                        .font(NotionFont.body())
                        .foregroundColor(.inkPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.inkTertiary)
                }
                .padding(.horizontal, NotionTheme.space5)
                .padding(.vertical, 12)
                .background(Color.hoverBg.opacity(0.5))
                .cornerRadius(NotionTheme.radiusLG)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 备注（多行可输入，失焦保存）

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            sectionLabel("备注")
            TextField("点击添加备注…",
                      text: $note,
                      axis: .vertical)
                .font(NotionFont.body())
                .foregroundColor(.inkPrimary)
                .lineLimit(2...5)
                .focused($noteFocused)
                .onChange(of: noteFocused) { focused in
                    if !focused { commitField() }
                }
                .padding(.horizontal, NotionTheme.space5)
                .padding(.vertical, 12)
                .background(Color.hoverBg.opacity(0.5))
                .cornerRadius(NotionTheme.radiusLG)
        }
    }

    // MARK: - 元信息（只读：日期 / 来源 / 同步状态）

    private var metaSection: some View {
        VStack(spacing: 0) {
            metaRow(label: "发生时间", value: formatDate(initial.occurredAt))
            divider
            metaRow(label: "来源",     value: initial.source.rawValue)
            divider
            metaRow(label: "同步状态", value: syncStatusText, valueTone: syncStatusTone)
            if initial.isAA {
                divider
                metaRow(label: "AA 账本", value: "已加入共享")
            }
        }
        .background(Color.hoverBg.opacity(0.5))
        .cornerRadius(NotionTheme.radiusLG)
    }

    private func metaRow(label: String, value: String, valueTone: Color = .inkPrimary) -> some View {
        HStack {
            Text(label)
                .font(NotionFont.small())
                .foregroundColor(.inkTertiary)
            Spacer()
            Text(value)
                .font(NotionFont.small())
                .foregroundColor(valueTone)
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(height: 0.5)
            .padding(.leading, NotionTheme.space5)
    }

    private var syncStatusText: String {
        switch initial.syncStatus {
        case .pending:  return "待同步"
        case .syncing:  return "同步中"
        case .synced:   return "已同步"
        case .failed:   return "同步失败"
        case .dead:     return "已放弃"
        }
    }

    private var syncStatusTone: Color {
        switch initial.syncStatus {
        case .pending:  return NotionColor.yellow.text(scheme)
        case .syncing:  return NotionColor.blue.text(scheme)
        case .synced:   return NotionColor.green.text(scheme)
        case .failed,
             .dead:     return NotionColor.red.text(scheme)
        }
    }

    // MARK: - 删除按钮

    private var deleteButton: some View {
        Button { } label: {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                Text("删除这笔流水")
            }
            .font(NotionFont.body())
            .foregroundColor(NotionColor.red.text(scheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(NotionColor.red.background(scheme))
            .cornerRadius(NotionTheme.radiusLG)
        }
        .buttonStyle(.plain)
    }

    // MARK: - helpers

    private func sectionLabel(_ s: String) -> some View {
        Text(s)
            .font(NotionFont.micro())
            .foregroundColor(.inkTertiary)
            .padding(.leading, 4)
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月 d 日 HH:mm"
        return f.string(from: d)
    }

    /// 把当前 state 写回一个 RecordRow 副本，触发外部 onCommit
    private func commitField() {
        let parsed = Decimal(string: amountText) ?? initial.amount
        var copy = initial
        copy = RecordRow(id: initial.id,
                         categoryName: categoryName,
                         categoryIcon: categoryIcon,
                         categoryColor: categoryColor,
                         amount: parsed,
                         direction: initial.direction,
                         note: note,
                         occurredAt: initial.occurredAt,
                         source: initial.source,
                         syncStatus: .pending,        // 任何编辑都重置为 pending，等同步队列处理
                         isAA: initial.isAA)
        _ = copy   // 静音 unused 警告
        onCommit(copy)
    }
}

// MARK: - 分类选择子 sheet（最简：3 列网格 + 9 色 palette）

struct CategoryPickerSheet: View {
    @Binding var selectedName: String
    @Binding var selectedIcon: String
    @Binding var selectedColor: NotionColor
    var onPick: () -> Void = { }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    /// 简版预设：实际业务来自 SQLite category 表
    private let presets: [(name: String, icon: String, color: NotionColor)] = [
        ("餐饮", "fork.knife", .orange),
        ("交通", "car",        .blue),
        ("咖啡", "cup.and.saucer", .brown),
        ("外卖", "takeoutbag.and.cup.and.straw", .orange),
        ("购物", "bag",        .pink),
        ("娱乐", "gamecontroller", .purple),
        ("医疗", "cross.case", .red),
        ("教育", "graduationcap", .blue),
        ("聚餐", "person.2",   .purple),
        ("工资", "banknote",   .green),
        ("奖金", "gift",       .green),
        ("其他", "ellipsis.circle", .gray),
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: NotionTheme.space5), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("选择分类")
                    .font(.custom("PingFangSC-Semibold", size: 17))
                    .foregroundColor(.inkPrimary)
            }
            .padding(.vertical, NotionTheme.space5)

            ScrollView {
                LazyVGrid(columns: columns, spacing: NotionTheme.space5) {
                    ForEach(Array(presets.enumerated()), id: \.offset) { _, p in
                        let isSelected = (p.name == selectedName)
                        Button {
                            selectedName = p.name
                            selectedIcon = p.icon
                            selectedColor = p.color
                            onPick()
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                                        .fill(isSelected ? Color.accentBlueBG : Color.hoverBg)
                                    Image(systemName: p.icon)
                                        .font(.system(size: 18, weight: .regular))
                                        .foregroundColor(isSelected ? Color.accentBlue : .inkSecondary)
                                }
                                .frame(width: 44, height: 44)
                                Text(p.name)
                                    .font(NotionFont.small())
                                    .foregroundColor(.inkPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, NotionTheme.space4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, NotionTheme.space6)
                .padding(.bottom, NotionTheme.space9)
            }
        }
        .background(Color.canvasBG)
    }
}
