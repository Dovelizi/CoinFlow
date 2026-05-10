//  RecordDetailSheet.swift
//  CoinFlow · M3.3 · §5.5.9
//
//  Bottom Sheet（presentationDetents medium/large）。
//  - 金额、分类、备注 实时保存
//  - 失焦/选中即 commit
//  - 删除按钮在底部，破坏性操作

import SwiftUI

struct RecordDetailSheet: View {

    /// 键盘焦点统一枚举（官方最佳实践：单一 FocusState + 外层单一 toolbar）
    private enum Field: Hashable { case amount, note }

    @StateObject private var vm: RecordDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCategoryPicker = false
    /// 删除确认弹窗显隐（ActionSheet / confirmationDialog）
    @State private var showDeleteConfirm = false
    /// 统一管理金额/备注的键盘焦点
    @FocusState private var focusedField: Field?
    /// 跟踪上一次焦点：用于"焦点从 amount/note 离开时触发 commit"——
    /// 保持旧行为（任一字段失焦即保存）。onChange(of:) 只提供新值，需自行记忆旧值。
    @State private var lastFocus: Field?

    init(record: Record) {
        _vm = StateObject(wrappedValue: RecordDetailViewModel(record: record))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appSheetCanvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: NotionTheme.space6) {
                        amountField
                        categoryField
                        noteField
                        metaInfo
                        deleteButton
                    }
                    .padding(NotionTheme.space5)
                }
            }
            .navigationTitle("流水详情")
            .navigationBarTitleDisplayMode(.inline)
            // 焦点变化：从有焦点切到另一个字段 / 收起 → 触发 commit（保持旧语义）
            .onChange(of: focusedField) { newValue in
                if lastFocus != nil && lastFocus != newValue {
                    vm.commit()
                }
                lastFocus = newValue
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.inkPrimary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.hoverBg))
                    }
                }
            }
            // 自绘键盘「完成」工具栏（替代原生 .toolbar { .keyboard }——
            // 后者在 sheet + presentationDetents + 多 TextField 切换下不稳定）
            .keyboardDoneToolbar()
            .sheet(isPresented: $showCategoryPicker) {
                CategoryPickerSheet(
                    categories: vm.availableCategories,
                    selectedId: vm.selectedCategory?.id,
                    onSelect: { vm.selectCategory($0) }
                )
                .presentationDetents([.medium, .large])
            }
            // 删除确认：底部 ActionSheet 样式（confirmationDialog 在 iOS 15+ 底部弹出）
            .confirmationDialog(
                "删除这笔流水？",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("都删除（本地 + 云端）", role: .destructive) {
                    vm.delete(localOnly: false)
                    dismiss()
                }
                Button("仅删除本地") {
                    vm.delete(localOnly: true)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("「仅删除本地」不会影响飞书多维表格中的记录；下次从飞书拉取时该记录会被重新同步到本地。")
            }
        }
    }

    // MARK: - Amount

    private var amountField: some View {
        VStack(alignment: .center, spacing: NotionTheme.space3) {
            HStack(alignment: .firstTextBaseline, spacing: NotionTheme.space2) {
                Spacer(minLength: 0)
                Text("¥")
                    .font(NotionFont.amountBold(size: 28))
                    .foregroundStyle(DirectionColor.amountForeground(kind: vm.direction))
                TextField("0", text: $vm.amountText)
                    .keyboardType(.decimalPad)
                    .font(NotionFont.amountBold(size: 44))
                    .foregroundStyle(DirectionColor.amountForeground(kind: vm.direction))
                    .focused($focusedField, equals: .amount)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
            }
            Text(vm.direction == .expense ? "支出" : "收入")
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
            if let err = vm.saveError {
                Text(err)
                    .font(NotionFont.small())
                    .foregroundStyle(Color(hex: "#DF5452"))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Category

    private var categoryField: some View {
        Button { showCategoryPicker = true } label: {
            fieldRow(
                icon: vm.selectedCategory?.icon ?? "questionmark",
                label: "分类",
                value: vm.selectedCategory?.name ?? "未分类",
                showChevron: true
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Note
    //
    // 直接 TextField 编辑（与 NewRecord 行为对齐）。失焦自动 commit()。
    private var noteField: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            HStack(spacing: NotionTheme.space5) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 24)
                Text("备注")
                    .font(NotionFont.body())
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
            }
            TextField("点击添加备注…", text: $vm.note, axis: .vertical)
                .lineLimit(2...5)
                .font(NotionFont.body())
                .foregroundStyle(Color.inkPrimary)
                .focused($focusedField, equals: .note)
                .padding(NotionTheme.space4)
                .background(
                    RoundedRectangle(cornerRadius: NotionTheme.radiusMD, style: .continuous)
                        .fill(Color.canvasBG)
                )
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                .fill(Color.hoverBg)
        )
    }

    // MARK: - Meta info（只读）

    private var metaInfo: some View {
        VStack(spacing: 0) {
            metaRow(label: "发生时间", value: vm.occurredAtDisplay)
            Divider().background(Color.divider).padding(.leading, NotionTheme.space5)
            metaRow(label: "来源",     value: vm.sourceDisplay)
            Divider().background(Color.divider).padding(.leading, NotionTheme.space5)
            metaRow(label: "同步状态", value: vm.syncDisplay)
        }
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                .fill(Color.hoverBg)
        )
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(NotionFont.small())
                .foregroundStyle(Color.inkTertiary)
            Spacer()
            Text(value)
                .font(NotionFont.small())
                .foregroundStyle(Color.inkPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, NotionTheme.space4)
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            HStack {
                Spacer()
                Text("删除")
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color(hex: "#DF5452"))
                Spacer()
            }
            .padding(NotionTheme.space5)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                    .fill(Color(hex: "#DF5452").opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Generic field row

    private func fieldRow(icon: String, label: String, value: String, showChevron: Bool) -> some View {
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
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                .fill(Color.hoverBg)
        )
    }
}
