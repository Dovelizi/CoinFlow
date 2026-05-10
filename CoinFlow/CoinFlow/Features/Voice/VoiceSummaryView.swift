//  VoiceSummaryView.swift
//  CoinFlow · M5 · §7.5.5 summary
//
//  录音/识别/向导全部完成后的汇总页：
//    - K/N 笔已确认、M 笔已放弃
//    - 展示各笔的 amount + direction + categoryName
//    - 关闭即回到流水页（流水页 onChange 会自动 reload）

import SwiftUI

struct VoiceSummaryView: View {

    let confirmed: [ParsedBill]
    let skipped: [ParsedBill]
    let totalParsed: Int
    let onDone: () -> Void

    private var totalExpense: Decimal {
        confirmed
            .filter { $0.direction == .expense }
            .compactMap { $0.amount }
            .reduce(0, +)
    }

    private var totalIncome: Decimal {
        confirmed
            .filter { $0.direction == .income }
            .compactMap { $0.amount }
            .reduce(0, +)
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            ScrollView {
                VStack(spacing: NotionTheme.space6) {
                    headerStats
                    if !confirmed.isEmpty {
                        sectionHeader("已确认", count: confirmed.count)
                        ForEach(confirmed) { bill in
                            billRow(bill, kind: .confirmed)
                        }
                    }
                    if !skipped.isEmpty {
                        sectionHeader("已放弃", count: skipped.count)
                        ForEach(skipped) { bill in
                            billRow(bill, kind: .skipped)
                        }
                    }
                }
                .padding(NotionTheme.space5)
            }
            bottomBar
        }
        .background(Color.appSheetCanvas.ignoresSafeArea())
    }

    // MARK: - Nav

    private var navBar: some View {
        ZStack {
            Text("本次语音记账")
                .font(NotionFont.h3())
                .foregroundStyle(Color.inkPrimary)
            HStack {
                Spacer()
                Button { onDone() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.inkPrimary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .padding(.trailing, NotionTheme.space4)
            }
        }
        .frame(height: NotionTheme.topbarHeight)
        .background(Color.appSheetCanvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.divider).frame(height: NotionTheme.borderWidth)
        }
    }

    // MARK: - Stats

    private var headerStats: some View {
        VStack(spacing: NotionTheme.space3) {
            Text("\(confirmed.count) / \(totalParsed) 笔已入账")
                .font(NotionFont.h3())
                .foregroundStyle(Color.inkPrimary)
            HStack(spacing: NotionTheme.space6) {
                statPair(label: "支出",
                         amount: AmountFormatter.display(totalExpense),
                         color: Color(hex: "#D44C47"))
                statPair(label: "收入",
                         amount: AmountFormatter.display(totalIncome),
                         color: Color(hex: "#448361"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(NotionTheme.space6)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusXL, style: .continuous)
                .fill(Color.surfaceOverlay)
        )
    }

    private func statPair(label: String, amount: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
            Text("¥\(amount)")
                .font(NotionFont.amountBold(size: 20))
                .foregroundStyle(color)
        }
    }

    // MARK: - Rows

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: NotionTheme.space3) {
            Text(title)
                .font(NotionFont.bodyBold())
                .foregroundStyle(Color.inkPrimary)
            Text("\(count) 笔")
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
            Spacer()
        }
    }

    enum RowKind { case confirmed, skipped }

    private func billRow(_ bill: ParsedBill, kind: RowKind) -> some View {
        HStack(spacing: NotionTheme.space5) {
            Image(systemName: kind == .confirmed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(kind == .confirmed ? Color(hex: "#448361") : Color.inkTertiary)
                .font(.system(size: 18))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(bill.categoryName ?? "未分类")
                    .font(NotionFont.body())
                    .foregroundStyle(Color.inkPrimary)
                if let note = bill.note, !note.isEmpty {
                    Text(note)
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.inkTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(amountText(bill))
                .font(NotionFont.amountBold(size: 16))
                .foregroundStyle(amountColor(bill, kind: kind))
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                .fill(Color.hoverBg)
        )
    }

    private func amountText(_ bill: ParsedBill) -> String {
        guard let a = bill.amount else { return "—" }
        return "¥" + AmountFormatter.display(a)
    }

    private func amountColor(_ bill: ParsedBill, kind: RowKind) -> Color {
        if kind == .skipped { return Color.inkTertiary }
        guard let d = bill.direction else { return Color.inkTertiary }
        return MainActor.assumeIsolated { AmountTintStore.shared.color(for: d) }
    }

    // MARK: - Bottom

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.divider).frame(height: NotionTheme.borderWidth)
            Button {
                onDone()
            } label: {
                Text("查看流水")
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                            .fill(Color.accentBlue)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, NotionTheme.space5)
            .padding(.top, NotionTheme.space4)
            .padding(.bottom, NotionTheme.space5)
        }
        .background(Color.appSheetCanvas)
    }
}
