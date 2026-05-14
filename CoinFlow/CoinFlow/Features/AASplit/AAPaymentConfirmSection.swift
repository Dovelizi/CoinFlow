//  AAPaymentConfirmSection.swift
//  CoinFlow · M11 — 结算阶段·支付确认
//
//  - 顶部进度条："已支付 N / 全部 M  ¥已收 / ¥应收"
//  - 成员行：头像 + 昵称 + 应付总额 + 状态徽标 + "标记已支付" / "撤销"
//  - 应付额为 0 的成员自动判定 paid（不阻塞结算完成）

import SwiftUI

struct AAPaymentConfirmSection: View {

    @ObservedObject var vm: AASplitDetailViewModel
    @State private var unmarkConfirm: AAMember? = nil
    @State private var actionError: String? = nil

    /// 应付额 > 0 且未支付的成员（这些成员阻塞结算完成）
    private var pendingActiveMembers: [AAMember] {
        vm.members.filter { vm.owe(of: $0.id) > 0 && $0.status == .pending }
    }

    /// 应付额 > 0 且已支付的成员
    private var paidActiveMembers: [AAMember] {
        vm.members.filter { vm.owe(of: $0.id) > 0 && $0.status == .paid }
    }

    /// 总应收（成员部分）
    private var totalDue: Decimal {
        vm.members.reduce(Decimal(0)) { $0 + vm.owe(of: $1.id) }
    }

    /// 已收（已支付成员的应付额累加）
    private var totalCollected: Decimal {
        paidActiveMembers.reduce(Decimal(0)) { $0 + vm.owe(of: $1.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space5) {
            HStack {
                Text("支付确认")
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
            }

            progressBar

            if vm.members.isEmpty {
                Text("先添加成员才能进行支付确认")
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(NotionTheme.space5)
                    .background(
                        RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                            .fill(Color.hoverBg.opacity(0.5))
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(vm.members) { m in
                        memberRow(m)
                        if m.id != vm.members.last?.id {
                            Rectangle()
                                .fill(Color.divider)
                                .frame(height: NotionTheme.borderWidth)
                                .padding(.leading, 48)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                        .fill(Color.hoverBg.opacity(0.5))
                )
            }

            if let err = actionError {
                Text(err)
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.dangerRed)
            }
        }
        .alert("撤销支付确认？",
               isPresented: Binding(
                get: { unmarkConfirm != nil },
                set: { if !$0 { unmarkConfirm = nil } }
               ),
               presenting: unmarkConfirm) { target in
            Button("取消", role: .cancel) { unmarkConfirm = nil }
            Button("撤销", role: .destructive) {
                do {
                    try vm.unmarkPaid(memberId: target.id)
                } catch {
                    actionError = error.localizedDescription
                }
                unmarkConfirm = nil
            }
        } message: { target in
            Text("将「\(target.name)」的支付状态回到待支付？")
        }
    }

    // MARK: - 进度条

    private var progressBar: some View {
        let total = vm.members.count
        let paidCount = vm.members.filter { vm.owe(of: $0.id) <= 0 || $0.status == .paid }.count
        let frac: Double = total > 0
            ? Double(paidCount) / Double(total)
            : 0
        return VStack(alignment: .leading, spacing: NotionTheme.space3) {
            HStack {
                Text("已支付 \(paidCount) / \(total)")
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
                Spacer()
                Text("¥\(StatsFormat.decimalGrouped(totalCollected)) / ¥\(StatsFormat.decimalGrouped(totalDue))")
                    .font(NotionFont.small().monospacedDigit())
                    .foregroundStyle(Color.inkSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.hoverBg)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(
                            colors: [Color.statusSuccess, Color.accentBlue],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: max(0, geo.size.width * frac))
                }
            }
            .frame(height: 8)
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .fill(Color.hoverBg.opacity(0.4))
        )
    }

    // MARK: - 成员行

    private func memberRow(_ m: AAMember) -> some View {
        let owe = vm.owe(of: m.id)
        let zeroOwe = owe <= 0
        // 应付为 0 的成员自动判定 paid（不可手动撤销）
        let effectivePaid = zeroOwe || m.status == .paid
        return HStack(spacing: NotionTheme.space5) {
            Text(m.avatarEmoji ?? "👤")
                .font(.system(size: 22))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name)
                    .font(NotionFont.body())
                    .foregroundStyle(Color.inkPrimary)
                if zeroOwe {
                    Text("应付 ¥0 · 自动判定已支付")
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.inkTertiary)
                } else if effectivePaid, let pa = m.paidAt {
                    Text("应付 ¥\(StatsFormat.decimalGrouped(owe)) · 已确认 \(formatDate(pa))")
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.statusSuccess)
                } else {
                    Text("应付 ¥\(StatsFormat.decimalGrouped(owe))")
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer()
            actionButton(member: m, zeroOwe: zeroOwe, paid: effectivePaid)
        }
        .padding(NotionTheme.space5)
    }

    @ViewBuilder
    private func actionButton(member m: AAMember, zeroOwe: Bool, paid: Bool) -> some View {
        if zeroOwe {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.statusSuccess.opacity(0.6))
        } else if paid {
            Button {
                unmarkConfirm = m
            } label: {
                Text("撤销")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.hoverBg)
                    )
            }
            .buttonStyle(.plain)
        } else {
            Button {
                do {
                    try vm.markPaid(memberId: m.id)
                    Haptics.success()
                } catch {
                    actionError = error.localizedDescription
                }
            } label: {
                Text("标记已支付")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.statusSuccess)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        // 支付确认时间格式：yyyy.MM.dd HH:mm（与设计稿规范一致）
        f.dateFormat = "yyyy.MM.dd HH:mm"
        return f.string(from: d)
    }
}
