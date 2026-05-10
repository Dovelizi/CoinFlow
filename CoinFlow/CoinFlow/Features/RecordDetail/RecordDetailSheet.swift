//  RecordDetailSheet.swift
//  CoinFlow · M3.3 · §5.5.9
//
//  Bottom Sheet（presentationDetents medium/large）。
//  - 金额、分类、备注 显式保存（顶部「保存」按钮）
//  - 关闭时若有未保存修改 → 二次确认
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
    /// 「未保存就关闭」二次确认弹窗
    @State private var showDiscardConfirm = false
    /// 统一管理金额/备注的键盘焦点
    @FocusState private var focusedField: Field?

    /// 金额拦截彩蛋 toast（与 NewRecordModal 行为完全一致）
    @State private var clampedToastText: String? = nil
    @State private var clampedToastTask: DispatchWorkItem? = nil

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
                clampedToastView
            }
            .navigationTitle("流水详情")
            .navigationBarTitleDisplayMode(.inline)
            // 金额拦截 → 弹彩蛋 toast（仅 overLimit 触发，与 NewRecordModal 一致）
            .onChange(of: vm.amountClampedAt) { _ in
                showClampedToast()
            }
            .toolbar {
                // 左上：关闭（同时作为「取消」；脏标记才弹二次确认）
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        attemptDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.inkPrimary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.hoverBg))
                    }
                }
                // 右上：保存（仅在有修改且输入合法时可点）
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        // 收起键盘后再 commit，避免焦点未同步到 vm 中间态的 race
                        focusedField = nil
                        if vm.commit() { dismiss() }
                    }
                    .font(NotionFont.bodyBold())
                    .foregroundStyle((vm.isDirty && vm.canSave) ? Color.inkPrimary : Color.inkTertiary)
                    .disabled(!vm.isDirty || !vm.canSave)
                }
            }
            // 键盘「完成」按钮：由 AmountTextFieldUIKit / NoteTextFieldUIKit 自身的
            // inputAccessoryView 提供（系统级，sheet/detents 下也稳定）
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
            // 未保存就关闭：二次确认
            .confirmationDialog(
                "放弃未保存的修改？",
                isPresented: $showDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button("放弃修改", role: .destructive) {
                    dismiss()
                }
                Button("继续编辑", role: .cancel) {}
            }
        }
    }

    /// 关闭请求统一入口：有脏改 → 弹二次确认；否则直接关闭。
    private func attemptDismiss() {
        focusedField = nil
        if vm.isDirty {
            showDiscardConfirm = true
        } else {
            dismiss()
        }
    }

    // MARK: - Amount

    private var amountField: some View {
        VStack(alignment: .center, spacing: NotionTheme.space3) {
            // 字号自适应（数值档位 + 字符兜底）：base 36pt 按数值大小分档缩放
            // 用 UIKit 包装的 AmountTextFieldUIKit 在 delegate 层硬拦截输入，
            // 与新建流水/语音/OCR 行为完全一致。
            let dynSize = AmountFontScale.scaledSize(base: 36, forText: vm.amountText)
            let amountColor = UIColor(DirectionColor.amountForeground(kind: vm.direction))
            // ¥ + TextField 整组居中：内层 HStack fixedSize（按内容排版），
            // 外层 .frame(maxWidth: .infinity, alignment: .center) 把整组推到中央。
            // 对齐用 .firstTextBaseline：与「新建流水」页保持一致，
            // ¥ 底部与数字底部齐平（数字无下降部，基线≈视觉底）。
            // ¥ 与数字字重/字体/比例统一（全局规则 §AmountSymbolStyle）。
            HStack(alignment: .firstTextBaseline, spacing: NotionTheme.space2) {
                Text("¥")
                    .font(NotionFont.amountBold(size: dynSize * AmountSymbolStyle.symbolScale))
                    .foregroundStyle(DirectionColor.amountForeground(kind: vm.direction))
                AmountTextFieldUIKit(
                    text: $vm.amountText,
                    placeholder: "0",
                    font: NotionFont.amountBoldUIKit(size: dynSize),
                    textColor: amountColor,
                    placeholderColor: UIColor(Color.inkTertiary),
                    alignment: .left,
                    onClamp: { reason in vm.handleClamp(reason) },
                    onFocusChange: { isFocused in
                        focusedField = isFocused ? .amount : nil
                    }
                )
                .frame(height: dynSize * 1.2)
                .fixedSize(horizontal: true, vertical: false)
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .center)
            // 拦截原因红字（与 NewRecord 文案一致）
            if vm.amountClampedHintVisible, let reason = vm.amountClampReason {
                Text(AmountInputGate.hintText(for: reason))
                    .font(NotionFont.small())
                    .foregroundStyle(Color.dangerRed)
                    .transition(.opacity)
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
        .animation(.easeInOut(duration: 0.18), value: vm.amountClampedAt)
    }

    // MARK: - Clamped Toast（金额超限彩蛋，与 NewRecordModal 行为一致）

    @ViewBuilder
    private var clampedToastView: some View {
        if let text = clampedToastText {
            VStack {
                Spacer()
                Text(text)
                    .font(NotionFont.small())
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.82))
                    )
                    .padding(.bottom, 120)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            .allowsHitTesting(false)
            .zIndex(2000)
        }
    }

    private func showClampedToast() {
        guard let reason = vm.amountClampReason,
              AmountInputGate.shouldShowDreamToast(for: reason) else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            clampedToastText = AmountInputGate.dreamToastText
        }
        clampedToastTask?.cancel()
        let task = DispatchWorkItem {
            withAnimation(.easeIn(duration: 0.22)) {
                clampedToastText = nil
            }
        }
        clampedToastTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: task)
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
    // 用 UIKit NoteTextFieldUIKit（键盘上方带「完成」按钮）。
    // 失焦 → onFocusChange(false) → focusedField = nil，仍走现有 onChange 触发 commit() 的路径。
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
            NoteTextFieldUIKit(
                text: $vm.note,
                placeholder: "点击添加备注…",
                font: NotionFont.bodyUIKit(),
                textColor: UIColor(Color.inkPrimary),
                placeholderColor: UIColor(Color.inkTertiary),
                minLines: 2,
                maxLines: 5,
                onFocusChange: { isFocused in
                    focusedField = isFocused ? .note : nil
                }
            )
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
