//  NewRecordModal.swift
//  CoinFlow · M3.2 · §5.5.10
//
//  Notion 风格新建流水 Modal：
//  - 顶部 nav 44pt：左 取消 / 中 新建流水 / 右 保存
//  - 字段：金额 / 方向 / 分类 / 时间 / 账本 / 备注
//  - 保存写本地 SQLite + 触发 SyncQueue.tick

import SwiftUI

struct NewRecordModal: View {

    /// 键盘焦点枚举（官方最佳实践：单一 FocusState + 外层单一 toolbar）
    private enum Field: Hashable { case amount, note }

    @StateObject private var vm = NewRecordViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showCategoryPicker = false
    @State private var showTimePicker = false
    @FocusState private var focusedField: Field?

    /// 保存成功回调（父视图据此关闭并可选择展示 toast）
    let onSaved: ((Record) -> Void)?

    init(onSaved: ((Record) -> Void)? = nil) {
        self.onSaved = onSaved
    }

    var body: some View {
        ZStack {
            Color.appSheetCanvas.ignoresSafeArea()
            VStack(spacing: 0) {
                navBar
                ScrollView {
                    VStack(alignment: .leading, spacing: NotionTheme.space6) {
                        amountField
                        directionToggle
                        fieldsGroupCard
                        noteField
                        if let err = vm.saveError {
                            errorBanner(err)
                        }
                    }
                    .padding(NotionTheme.space5)
                }
            }
        }
        // 自绘键盘「完成」工具栏（替代原生 .toolbar { .keyboard }）
        .keyboardDoneToolbar()
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(
                categories: vm.availableCategories,
                selectedId: vm.selectedCategory?.id,
                onSelect: { vm.selectedCategory = $0 }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTimePicker) {
            timePickerSheet
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Nav Bar (§5.5.10)

    private var navBar: some View {
        ZStack {
            // 中
            Text("新建流水")
                .font(NotionFont.h3())
                .foregroundStyle(Color.inkPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            // 左 取消
            HStack {
                Button("取消") { dismiss() }
                    .font(NotionFont.body())
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
            }
            .padding(.horizontal, NotionTheme.space5)

            // 右 保存
            HStack {
                Spacer()
                Button {
                    Task {
                        if let saved = await vm.save() {
                            onSaved?(saved)
                            dismiss()
                        }
                    }
                } label: {
                    if vm.isSaving {
                        ProgressView().scaleEffect(0.85)
                    } else {
                        Text("保存")
                            .font(NotionFont.bodyBold())
                            .foregroundStyle(vm.canSave ? Color.accentBlue : Color.inkTertiary)
                    }
                }
                .disabled(!vm.canSave)
            }
            .padding(.horizontal, NotionTheme.space5)
        }
        .frame(height: NotionTheme.topbarHeight)
        .background(Color.appSheetCanvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.divider)
                .frame(height: NotionTheme.borderWidth)
        }
    }

    // MARK: - Amount field（巨字 44pt · 居中 · 占位灰 · 错误红框）

    private var amountField: some View {
        VStack(alignment: .center, spacing: NotionTheme.space3) {
            // 占位 0 用 ZStack 显式画灰色层，避免 TextField placeholder 继承前景色变红
            ZStack(alignment: .center) {
                HStack(alignment: .firstTextBaseline, spacing: NotionTheme.space2) {
                    Spacer(minLength: 0)
                    Text(vm.direction == .expense ? "-¥" : "+¥")
                        .font(NotionFont.amountBold(size: 28))
                        .foregroundStyle(DirectionColor.amountForeground(kind: vm.direction))
                    if vm.amountText.isEmpty {
                        Text("0")
                            .font(NotionFont.amountBold(size: 44))
                            .foregroundStyle(Color.inkTertiary)
                    }
                    TextField("", text: $vm.amountText)
                        .keyboardType(.decimalPad)
                        .font(NotionFont.amountBold(size: 44))
                        .foregroundStyle(DirectionColor.amountForeground(kind: vm.direction))
                        .focused($focusedField, equals: .amount)
                        .onAppear { focusedField = .amount }
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if let msg = vm.amountValidationMessage {
                Text(msg)
                    .font(NotionFont.small())
                    .foregroundStyle(Color.dangerRed)
            }
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                .stroke(vm.isAmountInError ? Color.dangerRed : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Direction segmented

    private var directionToggle: some View {
        HStack(spacing: 0) {
            directionButton(.expense, label: "支出")
            directionButton(.income, label: "收入")
        }
        .padding(NotionTheme.space2)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                .fill(Color.hoverBg)
        )
    }

    private func directionButton(_ kind: CategoryKind, label: String) -> some View {
        let active = vm.direction == kind
        return Button {
            vm.setDirection(kind)
        } label: {
            Text(label)
                .font(NotionFont.bodyBold())
                .foregroundStyle(active ? Color.inkPrimary : Color.inkTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, NotionTheme.space3)
                .background(
                    RoundedRectangle(cornerRadius: NotionTheme.radiusMD, style: .continuous)
                        .fill(active ? Color.surfaceOverlay : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 分类 / 时间 / 账本（设计稿严格对齐：单卡 + 内部 hairline 分隔）

    private var fieldsGroupCard: some View {
        VStack(spacing: 0) {
            // 分类
            Button { showCategoryPicker = true } label: {
                fieldRowContent(
                    icon: vm.selectedCategory?.icon ?? "questionmark",
                    label: "分类",
                    value: vm.selectedCategory?.name ?? "未选择",
                    showChevron: true
                )
            }
            .buttonStyle(.plain)

            innerDivider

            // 时间
            Button { showTimePicker = true } label: {
                fieldRowContent(
                    icon: "calendar",
                    label: "时间",
                    value: formattedOccurredAt,
                    showChevron: true
                )
            }
            .buttonStyle(.plain)

            innerDivider

            // 账本（M3.2 单账本，不可改 → 不显示 chevron）
            fieldRowContent(
                icon: "book",
                label: "账本",
                value: "我的账本",
                showChevron: false
            )
        }
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                .fill(Color.hoverBg)
        )
    }

    private var innerDivider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(height: NotionTheme.borderWidth)
            .padding(.leading, NotionTheme.space5 + 24 + NotionTheme.space5)
    }

    private func fieldRowContent(icon: String,
                                 label: String,
                                 value: String,
                                 showChevron: Bool) -> some View {
        HStack(spacing: NotionTheme.space5) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 24)
            Text(label)
                .font(NotionFont.body())
                .foregroundStyle(Color.inkPrimary)
            Spacer()
            Text(value)
                .font(NotionFont.body())
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(1)
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.inkTertiary)
            }
        }
        .padding(NotionTheme.space5)
        .contentShape(Rectangle())
    }

    private var formattedOccurredAt: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: vm.occurredAt)
    }

    // MARK: - Time picker sheet (wheel)

    private var timePickerSheet: some View {
        VStack(spacing: NotionTheme.space5) {
            HStack {
                Button("取消") { showTimePicker = false }
                    .foregroundStyle(Color.inkSecondary)
                Spacer()
                Text("选择时间")
                    .font(NotionFont.h3())
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
                Button("完成") { showTimePicker = false }
                    .foregroundStyle(Color.accentBlue)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.top, NotionTheme.space5)

            DatePicker(
                "",
                selection: $vm.occurredAt,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "zh_CN"))

            Spacer(minLength: 0)
        }
        .background(Color.appSheetCanvas)
    }

    // MARK: - Note field（设计稿：label 外置上方 + 单层 hover_bg 输入框）

    private var noteField: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            Text("备注")
                .font(NotionFont.small())
                .foregroundStyle(Color.inkSecondary)
                .padding(.leading, NotionTheme.space2)

            TextField("点击添加备注…", text: $vm.note, axis: .vertical)
                .lineLimit(2...5)
                .font(NotionFont.body())
                .foregroundStyle(Color.inkPrimary)
                .focused($focusedField, equals: .note)
                .padding(NotionTheme.space5)
                .background(
                    RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                        .fill(Color.hoverBg)
                )
        }
    }

    // MARK: - Error banner

    private func errorBanner(_ msg: String) -> some View {
        Text(msg)
            .font(NotionFont.small())
            .foregroundStyle(Color.dangerRed)
            .padding(NotionTheme.space5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                    .fill(Color.dangerRed.opacity(0.12))
            )
    }
}

#if DEBUG
#Preview {
    NewRecordModal(onSaved: { _ in })
        .preferredColorScheme(.dark)
}
#endif
