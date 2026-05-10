// NewRecordScreenHost.swift
//
// 页面 2：新建流水的 3 个状态变体 host
//
// 状态映射：
//   main  → 完全空白（金额为空，所有字段默认）
//   edit  → 部分填充（金额已输入 + 分类已选 + 备注已写，演示积极态）
//   error → 提交校验失败（attemptedSubmit=true，金额未填，红框 + 提示文案）
//
// 技术注意：simctl 截图不能稳定捕捉 .sheet 弹起态，
// 这里把 NewRecordModal 直接以 root 形式渲染（不包 .sheet），等价于"已弹出"的截图态。

import SwiftUI

struct NewRecordScreenHost: View {
    let state: StateID

    var body: some View {
        switch state {
        case .empty, .main, .summary, .loading:
            // empty / main：完全空白
            NewRecordHostInner(initial: .blank)
        case .edit:
            NewRecordHostInner(initial: .partial)
        case .error, .fail:
            NewRecordHostInner(initial: .errorAttempted)
        }
    }
}

// MARK: - 内部包装：用 ZStack 模拟 sheet 容器，便于截图态稳定渲染

private struct NewRecordHostInner: View {
    let initial: NewRecordPreviewState

    var body: some View {
        ZStack {
            // 假装"背后"还有流水页（黑色背景模拟 modal 蒙层）
            Color.black.ignoresSafeArea()
            // sheet 模拟容器
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.inkTertiary.opacity(0.4))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                NewRecordPreviewWrapper(state: initial)
            }
            .background(Color.canvasBG)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.top, 60)              // 顶部留白模拟 large detent 的位置
        }
    }
}

// MARK: - 准备好预填态的包装（避免改 NewRecordModal 自身的初始化签名）

enum NewRecordPreviewState {
    case blank
    case partial
    case errorAttempted
}

private struct NewRecordPreviewWrapper: View {
    let state: NewRecordPreviewState

    var body: some View {
        // 用 .id 强制按 state 重新初始化，确保 @State 正确反映预填值
        NewRecordModalConfigured(state: state).id(stateKey)
    }

    private var stateKey: String {
        switch state {
        case .blank:           return "blank"
        case .partial:         return "partial"
        case .errorAttempted:  return "error"
        }
    }
}

/// NewRecordModal 的预设变体——通过外部 init 注入初值
private struct NewRecordModalConfigured: View {
    let state: NewRecordPreviewState

    var body: some View {
        switch state {
        case .blank:
            NewRecordModal()
        case .partial:
            NewRecordModalWithDefaults(
                amount: "128.50",
                category: ("餐饮", "fork.knife", .orange),
                note: "周末和小李吃饭"
            )
        case .errorAttempted:
            NewRecordModalWithDefaults(
                amount: "",
                category: ("其他", "ellipsis.circle", .gray),
                note: "",
                preTriggerError: true
            )
        }
    }
}

/// 复刻 NewRecordModal 的可注入初值版本（避免改原组件 API）
private struct NewRecordModalWithDefaults: View {
    let amount: String
    let category: (name: String, icon: String, color: NotionColor)
    let note: String
    var preTriggerError: Bool = false

    var body: some View {
        InjectedNewRecordModal(
            initialAmount: amount,
            initialCategory: category,
            initialNote: note,
            preTriggerError: preTriggerError
        )
    }
}

/// 真正的可注入初值实现（结构与 NewRecordModal 一致，仅初值与 attemptedSubmit 可外部控制）
private struct InjectedNewRecordModal: View {
    let initialAmount: String
    let initialCategory: (name: String, icon: String, color: NotionColor)
    let initialNote: String
    let preTriggerError: Bool

    @State private var amountText: String
    @State private var direction: RecordDirection = .expense
    @State private var category: (name: String, icon: String, color: NotionColor)
    @State private var occurredAt: Date = Date()
    @State private var ledger: LedgerOption = .init(id: "personal", name: "我的账本", isAA: false)
    @State private var note: String
    @State private var attemptedSubmit: Bool

    init(initialAmount: String,
         initialCategory: (name: String, icon: String, color: NotionColor),
         initialNote: String,
         preTriggerError: Bool) {
        self.initialAmount = initialAmount
        self.initialCategory = initialCategory
        self.initialNote = initialNote
        self.preTriggerError = preTriggerError
        _amountText = State(initialValue: initialAmount)
        _category = State(initialValue: initialCategory)
        _note = State(initialValue: initialNote)
        _attemptedSubmit = State(initialValue: preTriggerError)
    }

    @Environment(\.colorScheme) private var scheme

    private var parsedAmount: Decimal? {
        guard !amountText.trimmingCharacters(in: .whitespaces).isEmpty,
              let d = Decimal(string: amountText), d > 0 else { return nil }
        return d
    }

    private var amountError: String? {
        guard attemptedSubmit else { return nil }
        if amountText.trimmingCharacters(in: .whitespaces).isEmpty { return "请输入金额" }
        return nil
    }

    private var canSave: Bool { parsedAmount != nil }

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
        }
    }

    private var navigationBar: some View {
        ZStack {
            Text("新建流水")
                .font(.custom("PingFangSC-Semibold", size: 17))
                .foregroundColor(.inkPrimary)
            HStack {
                Text("取消")
                    .font(.custom("PingFangSC-Regular", size: 17))
                    .foregroundColor(.inkPrimary)
                    .padding(.horizontal, 8).frame(height: 36)
                Spacer()
                Text("保存")
                    .font(.custom("PingFangSC-Semibold", size: 17))
                    .foregroundColor(canSave ? Color.accentBlue : .inkTertiary)
                    .padding(.horizontal, 8).frame(height: 36)
            }
        }
        .padding(.horizontal, NotionTheme.space4)
        .frame(height: 44)
        .background(Color.canvasBG)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.divider).frame(height: 0.5)
        }
    }

    private var amountSection: some View {
        VStack(spacing: NotionTheme.space2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(direction == .expense ? "-¥" : "+¥")
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundColor(directionColor)
                Text(amountText.isEmpty ? "0" : amountText)
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundColor(amountText.isEmpty ? .inkTertiary : directionColor)
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
            }
        }
    }

    private var directionColor: Color {
        direction == .expense ? NotionColor.red.text(scheme) : NotionColor.green.text(scheme)
    }

    private var directionSection: some View {
        HStack(spacing: 0) {
            ForEach(RecordDirection.allCases, id: \.self) { d in
                Text(d.rawValue)
                    .font(NotionFont.bodyBold())
                    .foregroundColor(direction == d ? .inkPrimary : .inkTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(direction == d ? Color.canvasBG : Color.clear)
                    .cornerRadius(6)
                    .padding(2)
            }
        }
        .background(Color.hoverBg)
        .cornerRadius(NotionTheme.radiusLG)
    }

    private var fieldRows: some View {
        VStack(spacing: 0) {
            fieldRow(label: "分类", value: category.name, icon: category.icon)
            divider
            fieldRow(label: "时间", value: formatDate(occurredAt), icon: "calendar")
            divider
            fieldRow(label: "账本", value: ledger.name, icon: ledger.isAA ? "person.2" : "book")
        }
        .background(Color.hoverBg.opacity(0.5))
        .cornerRadius(NotionTheme.radiusLG)
    }

    @ViewBuilder
    private func fieldRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: NotionTheme.space5) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.inkSecondary)
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
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(height: 0.5)
            .padding(.leading, NotionTheme.space5 + 24 + NotionTheme.space5)
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            Text("备注")
                .font(NotionFont.micro())
                .foregroundColor(.inkTertiary)
                .padding(.leading, 4)
            HStack {
                Text(note.isEmpty ? "点击添加备注…" : note)
                    .font(NotionFont.body())
                    .foregroundColor(note.isEmpty ? .inkTertiary : .inkPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.vertical, 12)
            .frame(minHeight: 44, alignment: .top)
            .background(Color.hoverBg.opacity(0.5))
            .cornerRadius(NotionTheme.radiusLG)
        }
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日 HH:mm"
        return f.string(from: d)
    }
}
