//  VoiceWizardStepView.swift
//  CoinFlow · M5 · §7.5.5 逐笔向导
//
//  视觉基线：CoinFlowPreview VoiceWizardStepView（进度条 + 进度点 + 金额巨字 + 字段行 + 备注 + CTA）
//
//  交互：
//  - 金额：缺失态红框 + 点击聚焦键盘
//  - direction segmented：expense / income
//  - 分类：NewRecord 风格的行 Button → CategoryPickerSheet
//  - 时间：行 + DatePicker
//  - 备注：只读展示 ASR 原文片段（M5 不让改；M6 若用户有需求再开放）
//  - 底部：放弃此笔 / 确认 & 下一笔（最后一笔文案 "完成"）

import SwiftUI

struct VoiceWizardStepView: View {

    /// 键盘焦点枚举（官方最佳实践）
    private enum Field: Hashable { case amount, note }

    @ObservedObject var vm: VoiceWizardViewModel

    /// 结束整个向导（父 Container 关掉 sheet）
    let onExit: () -> Void

    @State private var showCategoryPicker = false
    @FocusState private var focusedField: Field?

    /// 当前笔当前方向下可选分类（用于 CategoryPickerSheet）
    private var availableCategories: [Category] {
        guard let dir = vm.currentBill.direction else { return [] }
        let kind: CategoryKind = dir == .expense ? .expense : .income
        return (try? SQLiteCategoryRepository.shared
            .list(kind: kind, includeDeleted: false)) ?? []
    }

    /// 当前已选 Category.id（用于 picker 高亮）
    private var currentCategoryId: String? {
        guard let name = vm.currentBill.categoryName else { return nil }
        return availableCategories.first(where: { $0.name == name })?.id
    }

    private var isMissingAmount:   Bool { vm.currentBill.missingFields.contains("amount") }
    private var isMissingCategory: Bool { vm.currentBill.missingFields.contains("category") }
    private var isMissingTime:     Bool { vm.currentBill.missingFields.contains("occurred_at") }
    private var isMissingDirection: Bool { vm.currentBill.missingFields.contains("direction") }

    /// M7 修复问题 4：是否"确认当前笔后就会进入 summary"——即除当前笔外所有笔均已 confirmed 或 skipped
    private var isLastPendingBill: Bool {
        for (i, b) in vm.bills.enumerated() where i != vm.currentIndex {
            if !vm.confirmedIds.contains(b.id) && !vm.skippedIds.contains(b.id) {
                return false
            }
        }
        return true
    }

    private var amountText: Binding<String> {
        Binding(
            get: {
                vm.currentBill.amount.map { AmountFormatter.display($0) } ?? ""
            },
            set: { newValue in
                let cleaned = newValue.trimmingCharacters(in: .whitespaces)
                let parsed = Decimal(string: cleaned.replacingOccurrences(of: ",", with: ""))
                vm.currentBill.amount = (parsed ?? 0) > 0 ? parsed : nil
                vm.recomputeMissing()
                vm.commitCurrentEdits()
            }
        )
    }

    private var occurredAtBinding: Binding<Date> {
        Binding(
            get: { vm.currentBill.occurredAt ?? Date() },
            set: { vm.currentBill.occurredAt = $0; vm.recomputeMissing(); vm.commitCurrentEdits() }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            progressHeader
            ScrollView {
                VStack(spacing: NotionTheme.space7) {
                    amountSection
                    directionSection
                    fieldRows
                    noteSection
                }
                .padding(.horizontal, NotionTheme.space6)
                .padding(.top, NotionTheme.space6)
                .padding(.bottom, NotionTheme.space9)
            }
            bottomBar
        }
        .background(Color.appSheetCanvas.ignoresSafeArea())
        // 自绘键盘「完成」工具栏（替代原生 .toolbar { .keyboard }）
        .keyboardDoneToolbar()
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(
                categories: availableCategories,
                selectedId: currentCategoryId,
                onSelect: { cat in
                    vm.currentBill.categoryName = cat.name
                    vm.recomputeMissing()
                    vm.commitCurrentEdits()
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Nav

    private var navigationBar: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("语音记账")
                    .font(NotionFont.h3())
                    .foregroundStyle(Color.inkPrimary)
                Text("第 \(vm.currentIndex + 1) / \(vm.bills.count) 笔")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
            }
            HStack {
                Button { onExit() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.inkPrimary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭语音记账")
                Spacer()
                Button { vm.skipCurrent() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color.dangerRed)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除当前笔")
            }
            .padding(.horizontal, NotionTheme.space5)
        }
        .frame(height: NotionTheme.topbarHeight)
        .background(Color.appSheetCanvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.divider).frame(height: NotionTheme.borderWidth)
        }
    }

    // MARK: - Progress

    private var progressHeader: some View {
        VStack(spacing: NotionTheme.space3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.hoverBg).frame(height: 4)
                    Capsule()
                        .fill(Color.accentBlue)
                        .frame(width: geo.size.width
                               * CGFloat(vm.currentIndex + 1)
                               / CGFloat(max(1, vm.bills.count)),
                               height: 4)
                }
            }
            .frame(height: 4)

            HStack(spacing: 8) {
                ForEach(0..<vm.bills.count, id: \.self) { i in
                    Button {
                        // M7 修复问题 4：点击进度点跳到对应笔
                        vm.jumpTo(index: i)
                    } label: {
                        progressDot(index: i)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                let missingCount = vm.currentBill.missingFields.count
                if missingCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(missingCount) 项待补全")
                            .font(NotionFont.micro())
                    }
                    .foregroundStyle(Color.statusWarning)
                }
            }
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, NotionTheme.space4)
        .background(Color.appSheetCanvas)
    }

    @ViewBuilder
    private func progressDot(index: Int) -> some View {
        let isCurrent = index == vm.currentIndex
        let bill = vm.bills[index]
        // M7 修复问题 4：用 confirmedIds/skippedIds 判断，不再依赖 index 与 currentIndex 的大小关系
        let isDone    = vm.confirmedIds.contains(bill.id)
        let isSkipped = vm.skippedIds.contains(bill.id)
        // broken：非当前、未确认、未 skipped，且 missingFields 非空
        let isBroken = !isCurrent && !isDone && !isSkipped && !bill.missingFields.isEmpty
        ZStack {
            Circle()
                .fill(isCurrent ? Color.accentBlue
                      : isDone  ? Color.statusSuccess
                      : isSkipped ? Color.inkTertiary
                      : isBroken ? Color.statusWarning
                      : Color.hoverBg)
                .frame(width: 22, height: 22)
            if isCurrent {
                Text("\(index + 1)")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.white)
            } else if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white)
            } else if isSkipped {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white)
            } else if isBroken {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white)
            } else {
                Text("\(index + 1)")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
            }
        }
        .accessibilityLabel(
            isCurrent ? "当前第 \(index + 1) 笔"
            : isDone ? "第 \(index + 1) 笔已确认，点击回到该笔编辑"
            : isSkipped ? "第 \(index + 1) 笔已跳过，点击回到该笔"
            : isBroken ? "第 \(index + 1) 笔待补全"
            : "第 \(index + 1) 笔"
        )
    }

    // MARK: - Amount

    private var amountSection: some View {
        VStack(spacing: NotionTheme.space2) {
            HStack(alignment: .firstTextBaseline, spacing: NotionTheme.space2) {
                Spacer(minLength: 0)
                Text(directionSymbol)
                    .font(NotionFont.amountBold(size: 28))
                    .foregroundStyle(directionColor)
                ZStack(alignment: .leading) {
                    // 空态灰色 "0" 占位（与 Preview L527-529 一致）
                    if amountText.wrappedValue.isEmpty {
                        Text("0")
                            .font(NotionFont.amountBold(size: 44))
                            .foregroundStyle(Color.inkTertiary)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: amountText)
                        .keyboardType(.decimalPad)
                        .font(NotionFont.amountBold(size: 44))
                        .foregroundStyle(directionColor)
                        .focused($focusedField, equals: .amount)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, NotionTheme.space5)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                    .fill(isMissingAmount
                          ? Color.dangerRed.opacity(0.08)
                          : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                    .stroke(isMissingAmount ? Color.dangerRed : Color.clear,
                            lineWidth: 1.5)
            )
            if isMissingAmount {
                Text("请输入金额（语音未识别）")
                    .font(NotionFont.small())
                    .foregroundStyle(Color.dangerRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
            }
        }
    }

    private var directionColor: Color {
        switch vm.currentBill.direction {
        case .income:  return Color.incomeGreen
        case .expense: return Color.expenseRed
        case nil:      return Color.inkTertiary
        }
    }

    private var directionSymbol: String {
        // 方向已由独立的 directionSection segmented 表达，金额前不再加 +/-
        return "¥"
    }

    // MARK: - Direction

    private var directionSection: some View {
        HStack(spacing: 0) {
            directionButton(.expense, label: "支出")
            directionButton(.income,  label: "收入")
        }
        .padding(NotionTheme.space2)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG,
                             style: .continuous)
                .fill(Color.hoverBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                .stroke(isMissingDirection ? Color.dangerRed : Color.clear,
                        lineWidth: 1.5)
        )
    }

    private func directionButton(_ d: BillDirection, label: String) -> some View {
        let active = vm.currentBill.direction == d
        return Button {
            vm.currentBill.direction = d
            // 方向切换 → 若当前 category 不在新方向下，清空
            if let name = vm.currentBill.categoryName {
                let expected: CategoryKind = d == .expense ? .expense : .income
                let list = (try? SQLiteCategoryRepository.shared
                    .list(kind: expected, includeDeleted: false)) ?? []
                if !list.contains(where: { $0.name == name }) {
                    vm.currentBill.categoryName = nil
                }
            }
            vm.recomputeMissing()
            vm.commitCurrentEdits()
        } label: {
            Text(label)
                .font(NotionFont.bodyBold())
                .foregroundStyle(active ? Color.inkPrimary : Color.inkTertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)                         // Preview 基线高度
                .background(
                    RoundedRectangle(cornerRadius: NotionTheme.radiusMD, style: .continuous)
                        .fill(active ? Color.surfaceOverlay : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Field rows

    private var fieldRows: some View {
        VStack(spacing: 0) {
            categoryRow
            rowDivider
            timeRow
            rowDivider
            ledgerRow
        }
        .background(Color.hoverBg.opacity(0.5))
        .cornerRadius(NotionTheme.radiusLG)
        .overlay(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                .stroke(
                    (isMissingCategory || isMissingTime) ? Color.dangerRed : Color.clear,
                    lineWidth: 1.5
                )
        )
    }

    private var categoryRow: some View {
        Button {
            showCategoryPicker = true
        } label: {
            HStack(spacing: NotionTheme.space5) {
                Image(systemName: categoryIcon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(isMissingCategory ? Color.dangerRed : Color.inkSecondary)
                    .frame(width: 24)
                Text("分类")
                    .font(NotionFont.body())
                    .foregroundStyle(Color.inkSecondary)
                Spacer()
                HStack(spacing: 6) {
                    if isMissingCategory {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.dangerRed)
                    }
                    Text(vm.currentBill.categoryName ?? "请选择")
                        .font(NotionFont.body())
                        .foregroundStyle(isMissingCategory
                                         ? Color.dangerRed
                                         : Color.inkPrimary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.inkTertiary)
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var timeRow: some View {
        HStack(spacing: NotionTheme.space5) {
            Image(systemName: "calendar")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(isMissingTime ? Color.dangerRed : Color.inkSecondary)
                .frame(width: 24)
            Text("时间")
                .font(NotionFont.body())
                .foregroundStyle(Color.inkSecondary)
            Spacer()
            if isMissingTime {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dangerRed)
            }
            DatePicker("", selection: occurredAtBinding,
                       displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "zh_CN"))
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 14)
    }

    /// 账本行（M5 单账本，固定显示"我的账本"，不可点击）
    private var ledgerRow: some View {
        HStack(spacing: NotionTheme.space5) {
            Image(systemName: "book")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 24)
            Text("账本")
                .font(NotionFont.body())
                .foregroundStyle(Color.inkSecondary)
            Spacer()
            Text("我的账本")
                .font(NotionFont.body())
                .foregroundStyle(Color.inkPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 14)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(height: NotionTheme.borderWidth)
            .padding(.leading, NotionTheme.space5 + 24 + NotionTheme.space5)
    }

    private var categoryIcon: String {
        // 当前分类找到对应 Category → 取其 icon；否则占位
        guard let name = vm.currentBill.categoryName,
              let c = availableCategories.first(where: { $0.name == name })
        else { return "questionmark.circle" }
        return c.icon
    }

    // MARK: - Note

    /// 备注双向绑定：来源默认是 ASR/OCR 原文（vm 在解析阶段填入 currentBill.note），
    /// 用户可在向导里直接修改；修改即时回写 bills[currentIndex]。
    private var noteBinding: Binding<String> {
        Binding(
            get: { vm.currentBill.note ?? "" },
            set: { newValue in
                vm.currentBill.note = newValue.isEmpty ? nil : newValue
                vm.commitCurrentEdits()
            }
        )
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            HStack {
                Text("备注（语音原文）")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
                Spacer()
                Image(systemName: "waveform")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkTertiary)
            }
            .padding(.leading, 4)
            TextField("（无备注）", text: noteBinding, axis: .vertical)
                .lineLimit(2...6)
                .font(NotionFont.body())
                .foregroundStyle(Color.inkPrimary)
                .focused($focusedField, equals: .note)
                .padding(.horizontal, NotionTheme.space5)
                .padding(.vertical, 12)
                .frame(minHeight: 44, alignment: .top)
                .background(Color.hoverBg.opacity(0.5))
                .cornerRadius(NotionTheme.radiusLG)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.divider).frame(height: NotionTheme.borderWidth)
            HStack(spacing: NotionTheme.space4) {
                Button {
                    vm.skipCurrent()
                } label: {
                    Text("放弃此笔")
                        .font(NotionFont.bodyBold())
                        .foregroundStyle(Color.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                                .fill(Color.hoverBg)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("放弃此笔")

                Button {
                    Task { await vm.confirmCurrent() }
                } label: {
                    Text(isLastPendingBill ? "完成" : "确认 & 下一笔")
                        .font(NotionFont.bodyBold())
                        .foregroundStyle(vm.canProceed ? Color.white : Color.inkTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                                .fill(vm.canProceed
                                      ? Color.accentBlue
                                      : Color.hoverBgStrong)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!vm.canProceed)
                .accessibilityLabel(isLastPendingBill ? "完成录入" : "确认并进入下一笔")
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.top, NotionTheme.space4)
            .padding(.bottom, NotionTheme.space5)
        }
        .background(Color.appSheetCanvas)
    }
}
