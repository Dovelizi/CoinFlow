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
            // 焦点变化：从有焦点切到另一个字段 / 收起 → 触发 commit（保持旧语义）
            .onChange(of: focusedField) { newValue in
                if lastFocus != nil && lastFocus != newValue {
                    vm.commit()
                }
                lastFocus = newValue
            }
            // 金额拦截 → 弹彩蛋 toast（仅 overLimit 触发，与 NewRecordModal 一致）
            .onChange(of: vm.amountClampedAt) { _ in
                showClampedToast()
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
            // 字号自适应（数值档位 + 字符兜底）：base 36pt 按数值大小分档缩放
            // 用 UIKit 包装的 AmountTextFieldUIKit 在 delegate 层硬拦截输入，
            // 与新建流水/语音/OCR 行为完全一致。
            let dynSize = AmountFontScale.scaledSize(base: 36, forText: vm.amountText)
            let amountColor = UIColor(DirectionColor.amountForeground(kind: vm.direction))
            // ¥ + TextField 整组居中：内层 HStack fixedSize（按内容排版），
            // 外层 .frame(maxWidth: .infinity, alignment: .center) 把整组推到中央。
            // 对齐用 .center 而非 .firstTextBaseline：¥ 与数字字号不同（28 vs 36），
            // 基线对齐会让小字号的 ¥ 视觉偏下，视觉中心不齐。用 frame 中心对齐更稳。
            HStack(alignment: .center, spacing: NotionTheme.space2) {
                Text("¥")
                    .font(NotionFont.amountBold(size: dynSize * 28 / 36))
                    .foregroundStyle(DirectionColor.amountForeground(kind: vm.direction))
                    .frame(height: dynSize * 1.2)
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
