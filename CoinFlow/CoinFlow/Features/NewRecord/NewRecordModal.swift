//  NewRecordModal.swift
//  CoinFlow · M3.2 · §5.5.10
//
//  Notion 风格新建流水 Modal：
//  - 顶部 nav 44pt：左 取消 / 中 新建流水 / 右 保存
//  - 字段：金额 / 方向 / 分类 / 时间 / 账本 / 备注
//  - 保存写本地 SQLite + 触发 SyncQueue.tick

import SwiftUI

struct NewRecordModal: View {

    @StateObject private var vm: NewRecordViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCategoryPicker = false
    @State private var showTimePicker = false
    @State private var showLedgerPicker = false
    @State private var showPayerPicker = false

    /// 金额拦截彩蛋 toast：当 vm.amountClampedAt 变化时弹一次。
    /// 文案是金额超限的轻吐槽，用 DispatchWorkItem 控制 1.6s 自动消失。
    @State private var clampedToastText: String? = nil
    @State private var clampedToastTask: DispatchWorkItem? = nil

    /// 保存成功回调（父视图据此关闭并可选择展示 toast）
    let onSaved: ((Record) -> Void)?

    /// M11：外部锁定的账本 id（不为 nil 时，账本行不可点击与切换）。
    /// AA 分账详情页点击"+ 添加流水"时传入当前 AA 账本 id，
    /// 锁定后用户不能在该 modal 里再切换为个人账户或其他 AA 账本。
    let lockedLedgerId: String?

    init(lockedLedgerId: String? = nil,
         onSaved: ((Record) -> Void)? = nil) {
        self.lockedLedgerId = lockedLedgerId
        self.onSaved = onSaved
        _vm = StateObject(wrappedValue: NewRecordViewModel(
            ledgerId: lockedLedgerId ?? DefaultSeeder.defaultLedgerId
        ))
    }

    var body: some View {
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
        .overlay(clampedToastView)
        .themedSheetSurface()
        // 键盘「完成」按钮：由 AmountTextFieldUIKit / NoteTextFieldUIKit 自身的
        // inputAccessoryView 提供（系统级，自动定位在键盘正上方，绝对稳定）
        // 金额拦截 → 弹彩蛋 toast（每次新拦截都重置 1.6s 显示）
        .onChange(of: vm.amountClampedAt) { _ in
            showClampedToast()
        }
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
        .sheet(isPresented: $showLedgerPicker) {
            AALedgerPickerSheet(
                currentSelection: vm.selectedAALedger,
                onPick: { picked in
                    vm.selectedAALedger = picked
                    vm.refreshPayersForCurrentAA()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPayerPicker) {
            AAPayerPickerSheet(vm: vm)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Clamped Toast（金额超限彩蛋）

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
        // 仅对"超过 1 亿"弹彩蛋；小数位/整数位/非法字符走红字提示就够了
        guard vm.amountClampReason == .overLimit else { return }
        let text = "吹🐮🍺呢，你会有一个小目标？？？"
        withAnimation(Motion.exit(0.18)) {
            clampedToastText = text
        }
        clampedToastTask?.cancel()
        let task = DispatchWorkItem {
            withAnimation(Motion.standard(0.22)) {
                clampedToastText = nil
            }
        }
        clampedToastTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: task)
    }

    /// 红字文案：按 vm.amountClampReason 分流（默认走 overLimit 文案兼容旧路径）
    private var clampedHintText: String {
        switch vm.amountClampReason {
        case .tooManyFractionDigits:
            return "金额仅支持小数点后两位"
        case .tooManyIntegerDigits, .overLimit:
            return "已达上限（1 亿）"
        case .invalidCharacter:
            return "包含不支持的字符"
        case .none:
            return "已达上限（1 亿）"
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
            // 内边距由 space5(12) → space6(16)：与系统 nav bar 16~20pt 内边距对齐，
            // 避免文字过分贴近屏幕边缘
            HStack {
                Button("取消") {
                    Haptics.tap()
                    dismiss()
                }
                .font(NotionFont.body())
                .foregroundStyle(Color.inkPrimary)
                .buttonStyle(.pressable(haptic: false))
                Spacer()
            }
            .padding(.horizontal, NotionTheme.space6)

            // 右 保存
            HStack {
                Spacer()
                Button {
                    Task {
                        if let saved = await vm.save() {
                            Haptics.success()
                            onSaved?(saved)
                            dismiss()
                        } else {
                            // 保存失败：error 触觉
                            Haptics.error()
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
                .buttonStyle(.pressable(haptic: false))
            }
            .padding(.horizontal, NotionTheme.space6)
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
            // 字号自适应（按数值档位）：< 10万 44pt → 1亿 26.4pt
            // 用 UIKit AmountTextFieldUIKit 在 UITextFieldDelegate 层做硬拦截，
            // 杜绝 SwiftUI Binding 在快速输入下"UI 已显示但 state 拒绝"的不一致问题。
            let dynSize = AmountFontScale.scaledSize(base: 44, forText: vm.amountText)
            let amountColor = UIColor(DirectionColor.amountForeground(kind: vm.direction))
            // ¥ + TextField 作为整组居中：
            //  - 内层 HStack 按内容真实宽度（fixedSize）—— 整组像一个原子元素
            //  - 外层 VStack 用 .frame(maxWidth: .infinity) 让这个"原子"水平居中
            //  - Gate 已硬锁整数 ≤ 9 位 / 小数 ≤ 2 位（最长 12 字符），44pt 下整组约 330pt
            //    仍小于屏宽，居中有余量
            HStack(alignment: .firstTextBaseline, spacing: NotionTheme.space2) {
                Text("¥")
                    .font(NotionFont.amountBold(size: dynSize * 28 / 44))
                    .foregroundStyle(DirectionColor.amountForeground(kind: vm.direction))
                AmountTextFieldUIKit(
                    text: $vm.amountText,
                    placeholder: "0",
                    font: NotionFont.amountBoldUIKit(size: dynSize),
                    textColor: amountColor,
                    placeholderColor: UIColor(Color.inkTertiary),
                    alignment: .left,
                    autoFocus: true,
                    onClamp: { reason in vm.handleClamp(reason) }
                )
                .frame(height: dynSize * 1.2)
                .fixedSize(horizontal: true, vertical: false)
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .center)

            // 提示行：
            // - 校验错误（红） · 优先级最高
            // - 拦截原因红字（小数位/整数位/上限） · vm 拦截后 2 秒内显示
            if let msg = vm.amountValidationMessage {
                Text(msg)
                    .font(NotionFont.small())
                    .foregroundStyle(Color.dangerRed)
            } else if vm.amountClampedHintVisible {
                Text(clampedHintText)
                    .font(NotionFont.small())
                    .foregroundStyle(Color.dangerRed)
                    .transition(.opacity)
            }
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                .stroke(vm.isAmountInError ? Color.dangerRed : Color.clear, lineWidth: 1)
                .animation(Motion.snap, value: vm.isAmountInError)
        )
        // 金额超限/非法字符时整张卡片抖动
        .shake(trigger: vm.amountClampedAt)
        .animation(Motion.standard(0.18), value: vm.amountClampedAt)
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
            Haptics.select()
            withAnimation(Motion.snap) {
                vm.setDirection(kind)
            }
        } label: {
            Text(label)
                .font(NotionFont.bodyBold())
                .foregroundStyle(active ? Color.inkPrimary : Color.inkTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, NotionTheme.space3)
                .background(
                    RoundedRectangle(cornerRadius: NotionTheme.radiusMD, style: .continuous)
                        .fill(directionActiveFill(active: active))
                        .animation(Motion.snap, value: active)
                )
        }
        .buttonStyle(.pressable(haptic: false))
    }

    /// 「支出/收入」active 段填色：
    /// - liquidGlass 主题：用半透白，叠在 hoverBg 胶囊上呈现明显但不刺眼的高亮，
    ///   避免 `Color.surfaceOverlay` 在深色系统下变成黑色实心胶囊
    /// - notion / darkLiquid：维持原 `Color.surfaceOverlay`，行为完全不变
    private func directionActiveFill(active: Bool) -> Color {
        guard active else { return Color.clear }
        return LGAThemeStore.shared.kind == .liquidGlass
            ? Color.white.opacity(0.18)
            : Color.surfaceOverlay
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
            .buttonStyle(.pressableRow)

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
            .buttonStyle(.pressableRow)

            innerDivider

            // 账本（M11：点击弹出 AA 分账选择器；默认个人账户）
            // 锁定模式下（如从 AA 详情页"+ 添加流水"进入）账本不可点击与切换。
            if lockedLedgerId == nil {
                Button { showLedgerPicker = true } label: {
                    fieldRowContent(
                        icon: vm.selectedAALedger == nil ? "book" : "person.2.fill",
                        label: "账本",
                        value: vm.selectedAALedger?.name ?? "个人账户",
                        showChevron: true
                    )
                }
                .buttonStyle(.pressableRow)
            } else {
                fieldRowContent(
                    icon: "person.2.fill",
                    label: "账本",
                    value: lockedLedgerName,
                    showChevron: false
                )
            }

            // M12 AA 支付人：仅在 AA 账本下出现。默认"我"，可切换为账本下其他成员或新增成员。
            if vm.selectedAALedger != nil {
                innerDivider
                Button { showPayerPicker = true } label: {
                    fieldRowContent(
                        icon: "creditcard.fill",
                        label: "支付人",
                        value: payerDisplayName,
                        showChevron: true
                    )
                }
                .buttonStyle(.pressableRow)
            }
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

    /// 锁定账本名（AA 详情页进入时传入 lockedLedgerId）
    private var lockedLedgerName: String {
        guard let lid = lockedLedgerId else { return "个人账户" }
        if lid == DefaultSeeder.defaultLedgerId { return "我的账本" }
        if let l = try? SQLiteLedgerRepository.shared.find(id: lid) {
            return l.name
        }
        return "AA 分账"
    }

    /// 当前选中的 payer 在 UI 上展示的名字（兜底"我"）。
    private var payerDisplayName: String {
        guard let pid = vm.selectedPayerMemberId else { return "我" }
        if let m = vm.availablePayers.first(where: { $0.id == pid }) {
            return m.name
        }
        return "我"
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
        // liquidGlass 主题下用 `themedSheetSurface()` 让 sheet 透出玻璃折射；
        // 其他主题等价于原 `Color.appSheetCanvas` 实色背景
        .themedSheetSurface()
    }

    // MARK: - Note field（设计稿：label 外置上方 + 单层 hover_bg 输入框）

    private var noteField: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            Text("备注")
                .font(NotionFont.small())
                .foregroundStyle(Color.inkSecondary)
                .padding(.leading, NotionTheme.space2)

            // 用 UIKit 包装的 NoteTextFieldUIKit，键盘上方带「完成」按钮（inputAccessoryView）
            NoteTextFieldUIKit(
                text: $vm.note,
                placeholder: "点击添加备注…",
                font: NotionFont.bodyUIKit(),
                textColor: UIColor(Color.inkPrimary),
                placeholderColor: UIColor(Color.inkTertiary),
                minLines: 2,
                maxLines: 5
            )
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
