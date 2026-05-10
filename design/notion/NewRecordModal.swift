// NewRecordModal.swift
//
// 页面 2：新建流水的全屏 Modal（独立于详情 sheet §5.5.9）
//
// 决策（已确认）：
//   p2a = 全屏 Modal Sheet（左上 取消 / 右上 保存），区分"新增 = 郑重事"vs"编辑 = 轻量"
//   p2b = 与详情 sheet 拆开，不复用
//   p2c = 6 字段：金额 / 方向 / 分类 / 发生时间 / 账本 / 备注
//   p2d = 校验错误态：金额未填 → 保存置灰 + 红框 + "请输入金额"提示
//
// 与 §5.5 设计基线对齐：
//   - PingFang 字体（B9）
//   - 默认深色（B10）
//   - status color 仅用于金额、错误提示（§5.5.2）
//   - 动画 150ms cubic-bezier（§5.5.6）
//   - 保存按钮在校验失败时灰色但仍可点击触发提示（标准 iOS 表单交互）

import SwiftUI

enum RecordDirection: String, CaseIterable {
    case expense = "支出"
    case income  = "收入"
}

struct LedgerOption: Identifiable, Hashable {
    let id: String
    let name: String
    let isAA: Bool
}

struct NewRecordModal: View {
    var onSave: (RecordRow) -> Void = { _ in }
    var onCancel: () -> Void = { }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    // 表单状态
    @State private var amountText: String = ""
    @State private var direction: RecordDirection = .expense
    @State private var category: (name: String, icon: String, color: NotionColor) = ("其他", "ellipsis.circle", .gray)
    @State private var occurredAt: Date = Date()
    @State private var ledger: LedgerOption = .init(id: "personal", name: "我的账本", isAA: false)
    @State private var note: String = ""
    @State private var attemptedSubmit: Bool = false   // 用户点过保存才显示错误提示
    @State private var showCategoryPicker = false
    @State private var showDatePicker = false
    @State private var showLedgerPicker = false

    @FocusState private var amountFocused: Bool
    @FocusState private var noteFocused: Bool

    /// 演示账本列表
    private let ledgers: [LedgerOption] = [
        .init(id: "personal", name: "我的账本", isAA: false),
        .init(id: "aa-1",     name: "2026 大理之旅", isAA: true),
        .init(id: "aa-2",     name: "5 月家庭日常", isAA: true),
    ]

    // MARK: 计算属性

    private var parsedAmount: Decimal? {
        guard !amountText.trimmingCharacters(in: .whitespaces).isEmpty,
              let d = Decimal(string: amountText), d > 0 else { return nil }
        return d
    }

    private var amountError: String? {
        guard attemptedSubmit else { return nil }
        if amountText.trimmingCharacters(in: .whitespaces).isEmpty { return "请输入金额" }
        if Decimal(string: amountText) == nil                       { return "金额格式不正确" }
        if let d = Decimal(string: amountText), d <= 0              { return "金额必须大于 0" }
        return nil
    }

    private var canSave: Bool { parsedAmount != nil }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
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
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.canvasBG.ignoresSafeArea())
        .sheet(isPresented: $showCategoryPicker) {
            // 复用 RecordDetailSheet 里的 CategoryPickerSheet（同一组件）
            CategoryPickerSheet(
                selectedName: Binding(get: { category.name }, set: { category.name = $0 }),
                selectedIcon: Binding(get: { category.icon }, set: { category.icon = $0 }),
                selectedColor: Binding(get: { category.color }, set: { category.color = $0 })
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDatePicker) { datePickerSheet }
        .sheet(isPresented: $showLedgerPicker) { ledgerPickerSheet }
    }

    // MARK: 顶部 nav bar（44pt 标准高，左 取消 / 中 标题 / 右 保存）

    private var navigationBar: some View {
        ZStack {
            Text("新建流水")
                .font(.custom("PingFangSC-Semibold", size: 17))
                .foregroundColor(.inkPrimary)
            HStack {
                Button { onCancel(); dismiss() } label: {
                    Text("取消")
                        .font(.custom("PingFangSC-Regular", size: 17))
                        .foregroundColor(.inkPrimary)
                        .padding(.horizontal, 8)
                        .frame(height: 36)
                }.buttonStyle(.plain)
                Spacer()
                Button { tryCommit() } label: {
                    Text("保存")
                        .font(.custom("PingFangSC-Semibold", size: 17))
                        .foregroundColor(canSave ? Color.accentBlue : .inkTertiary)
                        .padding(.horizontal, 8)
                        .frame(height: 36)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, NotionTheme.space4)
        .frame(height: 44)
        .background(Color.canvasBG)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.divider).frame(height: 0.5)
        }
    }

    // MARK: 金额（巨字 + 校验红框）

    private var amountSection: some View {
        VStack(spacing: NotionTheme.space2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(direction == .expense ? "-¥" : "+¥")
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundColor(directionColor)
                TextField("0", text: $amountText)
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundColor(directionColor)
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, NotionTheme.space5)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                    .stroke(amountError != nil ? NotionColor.red.text(scheme) : Color.clear, lineWidth: 1.5)
            )

            if let err = amountError {
                Text(err)
                    .font(NotionFont.small())
                    .foregroundColor(NotionColor.red.text(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
                    .transition(.opacity)
            }
        }
        .animation(NotionTheme.animDefault, value: amountError)
    }

    private var directionColor: Color {
        direction == .expense
            ? NotionColor.red.text(scheme)
            : NotionColor.green.text(scheme)
    }

    // MARK: 收支方向（Segmented）

    private var directionSection: some View {
        HStack(spacing: 0) {
            ForEach(RecordDirection.allCases, id: \.self) { d in
                Button { withAnimation(NotionTheme.animDefault) { direction = d } } label: {
                    Text(d.rawValue)
                        .font(NotionFont.bodyBold())
                        .foregroundColor(direction == d ? .inkPrimary : .inkTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(direction == d ? Color.canvasBG : Color.clear)
                        .cornerRadius(6)
                        .padding(2)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.hoverBg)
        .cornerRadius(NotionTheme.radiusLG)
    }

    // MARK: 字段行（分类 / 时间 / 账本）

    private var fieldRows: some View {
        VStack(spacing: 0) {
            fieldRow(label: "分类",
                     value: category.name,
                     icon: category.icon,
                     iconTone: .inkSecondary) { showCategoryPicker = true }
            divider
            fieldRow(label: "时间",
                     value: formatDate(occurredAt),
                     icon: "calendar",
                     iconTone: .inkSecondary) { showDatePicker = true }
            divider
            fieldRow(label: "账本",
                     value: ledger.name,
                     icon: ledger.isAA ? "person.2" : "book",
                     iconTone: .inkSecondary) { showLedgerPicker = true }
        }
        .background(Color.hoverBg.opacity(0.5))
        .cornerRadius(NotionTheme.radiusLG)
    }

    @ViewBuilder
    private func fieldRow(label: String,
                          value: String,
                          icon: String,
                          iconTone: Color,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: NotionTheme.space5) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(iconTone)
                    .frame(width: 24)
                Text(label)
                    .font(NotionFont.body())
                    .foregroundColor(.inkSecondary)
                Spacer()
                Text(value)
                    .font(NotionFont.body())
                    .foregroundColor(.inkPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.inkTertiary)
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(height: 0.5)
            .padding(.leading, NotionTheme.space5 + 24 + NotionTheme.space5)
    }

    // MARK: 备注

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            Text("备注")
                .font(NotionFont.micro())
                .foregroundColor(.inkTertiary)
                .padding(.leading, 4)
            TextField("点击添加备注…",
                      text: $note,
                      axis: .vertical)
                .font(NotionFont.body())
                .foregroundColor(.inkPrimary)
                .lineLimit(2...5)
                .focused($noteFocused)
                .padding(.horizontal, NotionTheme.space5)
                .padding(.vertical, 12)
                .background(Color.hoverBg.opacity(0.5))
                .cornerRadius(NotionTheme.radiusLG)
        }
    }

    // MARK: 时间 picker sheet（演示 medium detent）

    private var datePickerSheet: some View {
        VStack {
            ZStack {
                Text("选择时间")
                    .font(.custom("PingFangSC-Semibold", size: 17))
                    .foregroundColor(.inkPrimary)
                HStack {
                    Spacer()
                    Button("完成") { showDatePicker = false }
                        .foregroundColor(Color.accentBlue)
                        .font(.custom("PingFangSC-Semibold", size: 15))
                }
                .padding(.horizontal, NotionTheme.space5)
            }
            .padding(.vertical, NotionTheme.space5)

            DatePicker("", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding(.horizontal, NotionTheme.space5)

            Spacer()
        }
        .background(Color.canvasBG)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: 账本 picker sheet

    private var ledgerPickerSheet: some View {
        VStack(spacing: 0) {
            Text("选择账本")
                .font(.custom("PingFangSC-Semibold", size: 17))
                .foregroundColor(.inkPrimary)
                .padding(.vertical, NotionTheme.space5)

            ForEach(ledgers) { l in
                Button {
                    ledger = l; showLedgerPicker = false
                } label: {
                    HStack(spacing: NotionTheme.space5) {
                        Image(systemName: l.isAA ? "person.2" : "book")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.inkSecondary)
                            .frame(width: 24)
                        Text(l.name)
                            .font(NotionFont.body())
                            .foregroundColor(.inkPrimary)
                        Spacer()
                        if l.id == ledger.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.accentBlue)
                        }
                    }
                    .padding(.horizontal, NotionTheme.space6)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if l.id != ledgers.last?.id {
                    Rectangle().fill(Color.divider).frame(height: 0.5)
                        .padding(.leading, NotionTheme.space6 + 24 + NotionTheme.space5)
                }
            }
            Spacer()
        }
        .background(Color.canvasBG)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }

    // MARK: 提交

    private func tryCommit() {
        attemptedSubmit = true
        guard let amt = parsedAmount else { return }   // 校验失败：UI 已自动通过 amountError 显示提示

        let row = RecordRow(
            id: UUID().uuidString,
            categoryName: category.name,
            categoryIcon: category.icon,
            categoryColor: category.color,
            amount: amt,
            direction: direction == .expense ? .expense : .income,
            note: note,
            occurredAt: occurredAt,
            source: .manual,
            syncStatus: .pending,
            isAA: ledger.isAA
        )
        onSave(row)
        dismiss()
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日 HH:mm"
        return f.string(from: d)
    }
}
