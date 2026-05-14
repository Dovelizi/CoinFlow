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

    /// 需补付的活动成员（net > 0）中未点 paid 的，这些人阻塞「完成结算」
    private var pendingActiveMembers: [AAMember] {
        vm.members.filter { vm.netOwe(of: $0.id) > 0 && $0.status == .pending }
    }

    /// 需补付的活动成员中已点 paid 的
    private var paidActiveMembers: [AAMember] {
        vm.members.filter { vm.netOwe(of: $0.id) > 0 && $0.status == .paid }
    }

    /// 总应收（需补付的成员部分、不含多付者的待入账）
    private var totalDue: Decimal {
        vm.members.reduce(Decimal(0)) { acc, m in
            let net = vm.netOwe(of: m.id)
            return net > 0 ? acc + net : acc
        }
    }

    /// 已收（需补付且已 paid 的成员的 net 累加）
    private var totalCollected: Decimal {
        paidActiveMembers.reduce(Decimal(0)) { $0 + vm.netOwe(of: $1.id) }
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
        // 「进度」以 net 为准：net ≤0 的成员自动计为已付，多付者/刚好持平者不需人为点击
        let paidCount = vm.members.filter { vm.netOwe(of: $0.id) <= 0 || $0.status == .paid }.count
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
        // M12 新语义：并行展示「应付 / 已付 / 差额」，差额 ≤0 的人自动判定已付。
        let due = vm.owe(of: m.id)            // 应付（均分份额）
        let paidIn = vm.paid(by: m.id)        // 实付（作为 payer 垫付金额总和）
        let net = due - paidIn                // 差额：正=要补付 / 负=待入账
        let needsPay = net > 0                // 还需补付
        let neutralOrCredit = net <= 0        // 刚好/多付 -> 自动已付
        let effectivePaid = neutralOrCredit || m.status == .paid
        return HStack(spacing: NotionTheme.space5) {
            Text(m.avatarEmoji ?? "👤")
                .font(.system(size: 22))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name)
                    .font(NotionFont.body())
                    .foregroundStyle(Color.inkPrimary)
                paymentDetailLine(due: due, paidIn: paidIn, net: net,
                                  neutralOrCredit: neutralOrCredit,
                                  needsPay: needsPay,
                                  effectivePaid: effectivePaid,
                                  paidAt: m.paidAt)
            }
            Spacer()
            actionButton(member: m, neutralOrCredit: neutralOrCredit, paid: effectivePaid)
        }
        .padding(NotionTheme.space5)
    }

    /// 成员行第二行的「应/已/差额」文案。
    /// - net <= 0：已付 · 待入账 ¥|net|（net < 0）/ 刚好持平（net == 0）
    /// - net > 0 且未点 paid：应付 ¥due · 已付 ¥paidIn · 补付 ¥net
    /// - net > 0 且已点 paid：补付 ¥net · 已确认 时间
    @ViewBuilder
    private func paymentDetailLine(due: Decimal, paidIn: Decimal, net: Decimal,
                                   neutralOrCredit: Bool, needsPay: Bool,
                                   effectivePaid: Bool, paidAt: Date?) -> some View {
        if neutralOrCredit {
            if net < 0 {
                Text("已付 ¥\(StatsFormat.decimalGrouped(paidIn)) · 待入账 ¥\(StatsFormat.decimalGrouped(-net))")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.statusSuccess)
            } else {
                Text("应付 ¥\(StatsFormat.decimalGrouped(due)) · 刚好持平")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
            }
        } else if effectivePaid, let pa = paidAt {
            Text("补付 ¥\(StatsFormat.decimalGrouped(net)) · 已确认 \(formatDate(pa))")
                .font(NotionFont.micro())
                .foregroundStyle(Color.statusSuccess)
        } else {
            // 还需补付
            if paidIn > 0 {
                Text("应付 ¥\(StatsFormat.decimalGrouped(due)) · 已付 ¥\(StatsFormat.decimalGrouped(paidIn)) · 补付 ¥\(StatsFormat.decimalGrouped(net))")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkSecondary)
            } else {
                Text("应付 ¥\(StatsFormat.decimalGrouped(due)) · 补付 ¥\(StatsFormat.decimalGrouped(net))")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkSecondary)
            }
        }
    }

    @ViewBuilder
    private func actionButton(member m: AAMember, neutralOrCredit: Bool, paid: Bool) -> some View {
        if neutralOrCredit {
            // 多付者/刚好持平者 -> 自动已付，不允许手动撤销
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
