//  AASplitDetailView.swift
//  CoinFlow · M11 — AA 分账详情页
//
//  支持 3 种状态展示：
//  - recording：流水列表 + "+ 添加流水" + 底部"开始结算"
//  - settling：成员管理 + 流水分摊 + 支付确认（三个 Section）
//  - completed：只读模式 + "查看回写流水"快捷入口 + "导出 CSV"

import SwiftUI

struct AASplitDetailView: View {

    @StateObject private var vm: AASplitDetailViewModel
    @State private var showAddRecord = false
    @State private var showStartSettleConfirm = false
    @State private var showRevertConfirm = false
    @State private var showCompleteError: String?
    @State private var showWritebackList = false
    /// M11 需求 11.4：进入 settling 状态的账本时一次性提示"上次结算中断"
    @State private var showResumeSettleHint = false
    @State private var hasShownResumeSettleHint = false
    /// 方案 C1：点击流水弹 RecordDetailSheet 编辑
    @State private var editingRecord: Record?

    init(ledgerId: String) {
        _vm = StateObject(wrappedValue: AASplitDetailViewModel(ledgerId: ledgerId))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 详情页不提供删除入口：删除分账统一走 AA 分账 Tab 列表的左滑手势。
            StatsSubNavBar(
                title: vm.ledger?.name ?? "AA 分账",
                subtitle: subtitle
            )
            ScrollView {
                VStack(spacing: NotionTheme.space5) {
                    heroCard
                    statusBanner
                    switch vm.status {
                    case .recording:
                        recordingContent
                    case .settling:
                        settlingContent
                    case .completed:
                        completedContent
                    }
                    if let err = vm.loadError {
                        Text(err)
                            .font(NotionFont.small())
                            .foregroundStyle(Color.dangerRed)
                            .padding()
                    }
                    // 底部操作栏：作为列表最后一个区块随 ScrollView 一起滚动
                    // （非吸底）。bar 内部已有 padding(.space5) 与左右负 padding 抵消
                    // 父 VStack 的水平 padding，让背景横铺到屏幕两侧，保留原视觉。
                    bottomBar
                        .padding(.horizontal, -NotionTheme.space5)
                }
                .padding(.horizontal, NotionTheme.space5)
                .padding(.top, NotionTheme.space5)
                .padding(.bottom, NotionTheme.space7)
            }
        }
        .background(ThemedBackgroundLayer(kind: .stats))
        .navigationBarHidden(true)
        .hideTabBar()
        .onAppear {
            vm.reload()
            // 需求 11.4：进入 settling 状态时一次性提示用户"上次结算中断"。
            // 仅在本次进入页面后第一次检测到 settling 状态时弹出，避免来回切换反复打扰。
            if !hasShownResumeSettleHint, vm.status == .settling {
                hasShownResumeSettleHint = true
                showResumeSettleHint = true
            }
        }
        .sheet(isPresented: $showAddRecord) {
            NewRecordModal(lockedLedgerId: vm.ledgerId, onSaved: { _ in
                vm.reload()
            })
        }
        .sheet(item: $editingRecord) { rec in
            // AA 已完成账本里点击原始流水：进入只读流水详情（带 readOnlyBanner，不可编辑/不可删除）。
            // recording / settling 态保持原有可编辑行为。
            RecordDetailSheet(record: rec, forceReadOnly: vm.status == .completed)
        }
        .sheet(isPresented: $showWritebackList) {
            WritebackRecordListSheet(aaSettlementId: vm.ledgerId)
                .presentationDetents([.medium, .large])
        }
        .alert("开始结算？",
               isPresented: $showStartSettleConfirm) {
            Button("取消", role: .cancel) {}
            Button("开始结算") {
                do {
                    // M12：开始结算前自动把"曾经支付过"的人和"我"全部加为分账成员。
                    // - "我"：始终作为成员加入（即使我没出钱，方便后续调整分摊）
                    // - 其他 payer：扫描本账本所有未删流水的 payerUserId，未在成员表的全部补一条
                    // 关键时序：必须在 startSettlement 之前完成，
                    // 这样 startSettlement 内部首次 recomputePlaceholder(.settling) 计算
                    // mineShareSum 时就能算到我的份额，一次到位写出占位流水。
                    try? vm.enrollPayersAsMembers()
                    try vm.startSettlement()
                } catch {
                    showCompleteError = error.localizedDescription
                }
            }
        } message: {
            Text("进入结算后，本账本将不再出现在新建流水的可选列表，且账本下流水变为只读。请准备好分账成员名单。")
        }
        .alert("回退到记录中？",
               isPresented: $showRevertConfirm) {
            Button("取消", role: .cancel) {}
            Button("回退") {
                do {
                    try vm.revertToRecording()
                } catch {
                    showCompleteError = error.localizedDescription
                }
            }
        } message: {
            Text("回退后可继续添加流水。再次进入结算时，已添加的成员、分摊和支付确认都会保留。")
        }
        .alert("结算未完成",
               isPresented: Binding(
                get: { showCompleteError != nil },
                set: { if !$0 { showCompleteError = nil } }
               )) {
            Button("好") { showCompleteError = nil }
        } message: {
            Text(showCompleteError ?? "")
        }
        .alert("上次结算未完成",
               isPresented: $showResumeSettleHint) {
            Button("继续结算") { showResumeSettleHint = false }
        } message: {
            Text("该分账已进入结算流程但尚未完成。请在下方继续完成成员配置、分摊与支付确认；如需调整流水，可点击『回退到记录中』。")
        }
    }

    // MARK: - Header

    private var subtitle: String {
        switch vm.status {
        case .recording: return "分账记录中"
        case .settling:  return "分账结算中"
        case .completed: return "已完成"
        }
    }

    private var heroCard: some View {
        VStack(spacing: NotionTheme.space3) {
            Text("累计金额")
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
            Text("¥" + StatsFormat.decimalGrouped(vm.totalAmount))
                .font(.system(size: 38, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.inkPrimary)
            HStack(spacing: NotionTheme.space5) {
                pill(icon: "doc.text", text: "\(vm.visibleRecords.count) 笔流水")
                if !vm.members.isEmpty {
                    pill(icon: "person.2.fill", text: "\(vm.members.count) 位成员")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(NotionTheme.space6)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .fill(Color.hoverBg.opacity(0.5))
        )
    }

    private func pill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(NotionFont.micro())
        }
        .foregroundStyle(Color.inkSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(Color.hoverBg)
        )
    }

    @ViewBuilder
    private var statusBanner: some View {
        let (text, color, icon) = bannerStyle
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text(text)
                .font(NotionFont.small())
                .foregroundStyle(Color.inkSecondary)
            Spacer(minLength: 0)
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .fill(color.opacity(0.10))
        )
    }

    private var bannerStyle: (String, Color, String) {
        switch vm.status {
        case .recording:
            return ("记录阶段：自由添加流水，无需配置成员。完成消费后点击「开始结算」即可进入分摊。",
                    Color.accentBlue, "tray.full")
        case .settling:
            return ("结算阶段：流水已只读。请添加成员、调整分摊、确认支付，全部完成后点击「完成结算」。",
                    Color.statusWarning, "person.2.gobackward")
        case .completed:
            let s = vm.ledger?.completedAt.map { formatDate($0) } ?? ""
            return ("已完成 · \(s)。账本只读；查看回写流水可在个人账单中追溯。",
                    Color.statusSuccess, "checkmark.seal.fill")
        }
    }

    // MARK: - recording 阶段

    private var recordingContent: some View {
        VStack(spacing: NotionTheme.space5) {
            recordsList
        }
    }

    // MARK: - settling 阶段

    private var settlingContent: some View {
        VStack(spacing: NotionTheme.space6) {
            // 成员
            AAMemberManageSection(vm: vm)
            // 分摊
            AAShareEditSection(vm: vm)
            // 支付确认
            AAPaymentConfirmSection(vm: vm)
            // 流水（只读）
            recordsList
        }
    }

    // MARK: - completed 阶段

    private var completedContent: some View {
        VStack(spacing: NotionTheme.space5) {
            // 成员摘要（只读）
            if !vm.members.isEmpty {
                memberSummary
            }
            // 分摊明细：每条原始流水 × 各成员分摊（只读，高亮"我"）
            if !vm.members.isEmpty && !vm.visibleRecords.isEmpty {
                shareBreakdownSection
            }
            // 流水列表（只读）
            recordsList
            // 操作
            HStack(spacing: NotionTheme.space5) {
                Button {
                    showWritebackList = true
                } label: {
                    Label("查看回写流水", systemImage: "arrow.uturn.right.square")
                        .font(NotionFont.small())
                        .padding(.horizontal, NotionTheme.space5)
                        .padding(.vertical, NotionTheme.space3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.hoverBg)
                        )
                }
                .buttonStyle(.plain)
                Button {
                    exportCSV()
                } label: {
                    Label("导出 CSV", systemImage: "square.and.arrow.up")
                        .font(NotionFont.small())
                        .padding(.horizontal, NotionTheme.space5)
                        .padding(.vertical, NotionTheme.space3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.hoverBg)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, NotionTheme.space3)
        }
    }

    private var memberSummary: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            Text("成员")
                .font(NotionFont.bodyBold())
                .foregroundStyle(Color.inkPrimary)
            ForEach(vm.members) { m in
                HStack {
                    Text(m.avatarEmoji ?? "👤").font(.system(size: 18))
                    Text(m.name).font(NotionFont.body())
                    Spacer()
                    Text("¥" + StatsFormat.decimalGrouped(vm.owe(of: m.id)))
                        .font(NotionFont.body().monospacedDigit())
                        .foregroundStyle(Color.inkSecondary)
                    if let pa = m.paidAt {
                        Text(formatDate(pa))
                            .font(NotionFont.micro())
                            .foregroundStyle(Color.statusSuccess)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .fill(Color.hoverBg.opacity(0.5))
        )
    }

    // MARK: - 分摊明细（completed 态只读）
    //
    // 以"原始流水为行，各成员分摊额为子行"的矩阵呈现。
    // 入口：个人账单点已结算占位流水 → RecordDetailSheet → AA 链接行
    //   → AASplitDetailView(completed) → 本 Section
    // “我"的那一行额外以 accentBlue 高亮，与个人账单上那条总额对上。
    private var shareBreakdownSection: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            HStack {
                Text("分摊明细")
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
                Text("按流水 × 成员")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
            }
            VStack(spacing: NotionTheme.space3) {
                ForEach(vm.visibleRecords) { r in
                    breakdownRow(record: r)
                }
            }
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .fill(Color.hoverBg.opacity(0.5))
        )
    }

    @ViewBuilder
    private func breakdownRow(record r: Record) -> some View {
        let cat = categoryById(r.categoryId)
        let iconColor = cat.map { Color(hex: $0.colorHex) } ?? Color.inkTertiary
        // 该条 record 下的 share：从 vm.shares 过滤出 recordId == r.id
        let recordShares = vm.shares.filter { $0.recordId == r.id && $0.deletedAt == nil }
        VStack(alignment: .leading, spacing: 6) {
            // 顶部：原始流水本身
            HStack(spacing: NotionTheme.space3) {
                Image(systemName: cat?.icon ?? "questionmark.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 18)
                Text((r.note?.isEmpty == false) ? r.note! : (cat?.name ?? "未填备注"))
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkPrimary)
                    .lineLimit(1)
                Spacer()
                Text("¥" + StatsFormat.decimalGrouped(r.amount))
                    .font(NotionFont.small().monospacedDigit())
                    .foregroundStyle(Color.inkPrimary)
            }
            // 子行：该条流水下各成员的分摊
            if recordShares.isEmpty {
                Text("未分摊")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
                    .padding(.leading, 26)
            } else {
                VStack(spacing: 2) {
                    ForEach(recordShares) { s in
                        let m = vm.members.first(where: { $0.id == s.memberId })
                        let isMe = AAOwner.isOwnerMemberId(s.memberId)
                        HStack(spacing: 6) {
                            Text(m?.avatarEmoji ?? "👤").font(.system(size: 12))
                            Text(m?.name ?? "(已删除成员)")
                                .font(NotionFont.micro())
                                .foregroundStyle(isMe ? Color.accentBlue : Color.inkSecondary)
                            if isMe {
                                Text("我")
                                    .font(NotionFont.micro())
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color.accentBlue)
                                    )
                            }
                            if s.isCustom {
                                Text("自定义")
                                    .font(NotionFont.micro())
                                    .foregroundStyle(Color.statusWarning)
                            }
                            Spacer()
                            Text("¥" + StatsFormat.decimalGrouped(s.amount))
                                .font(NotionFont.micro().monospacedDigit())
                                .foregroundStyle(isMe ? Color.accentBlue : Color.inkSecondary)
                        }
                        .padding(.leading, 26)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 流水列表（按日期分组）

    private var recordsList: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            HStack {
                Text("流水")
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
                if vm.status == .recording {
                    Button {
                        showAddRecord = true
                    } label: {
                        Label("添加流水", systemImage: "plus.circle.fill")
                            .font(NotionFont.small())
                            .foregroundStyle(Color.accentBlue)
                    }
                    .buttonStyle(.plain)
                }
            }
            if vm.visibleRecords.isEmpty {
                Text("暂无流水")
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, NotionTheme.space5)
            } else {
                let groups = DateGrouping.group(vm.visibleRecords)
                ForEach(groups) { g in
                    Text(g.headerText)
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.inkTertiary)
                        .padding(.top, NotionTheme.space3)
                    VStack(spacing: 0) {
                        ForEach(g.records) { r in
                            recordRow(r)
                            if r.id != g.records.last?.id {
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
            }
        }
    }

    @ViewBuilder
    private func recordRow(_ r: Record) -> some View {
        // 方案 C1：AA 账本里的流水卡片样式与个人账单一致 —— 真彩分类图标 + 可点击编辑。
        // 已 completed 的 AA 不可改金额（要修改请先回退到记录中），点击给提示。
        let cat = categoryById(r.categoryId)
        let iconName = cat?.icon ?? "questionmark.circle"
        let iconColor = cat.map { Color(hex: $0.colorHex) } ?? Color.inkTertiary
        Button {
            Haptics.tap()
            // 所有状态都直接打开流水详情；completed 态由 sheet 侧 forceReadOnly 切只读模式
            // （含 readOnlyBanner / 金额备注只读 / 无删除按钮），符合"账本只读"语义。
            editingRecord = r
        } label: {
            HStack(spacing: NotionTheme.space5) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.14))
                        .frame(width: 32, height: 32)
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text((r.note?.isEmpty == false) ? r.note! : (cat?.name ?? "未填备注"))
                        .font(NotionFont.body())
                        .foregroundStyle(Color.inkPrimary)
                        .lineLimit(1)
                    Text(formatTime(r.occurredAt))
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.inkTertiary)
                }
                Spacer()
                Text("¥" + StatsFormat.decimalGrouped(r.amount))
                    .font(NotionFont.body().monospacedDigit())
                    .foregroundStyle(Color.inkPrimary)
            }
            .padding(NotionTheme.space5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 分类查询（AA 账本里 record 的 categoryId 与个人账本共用同一张 category 表）。
    private func categoryById(_ id: String) -> Category? {
        try? SQLiteCategoryRepository.shared.find(id: id)
    }

    // MARK: - bottomBar（recording / settling 才显示）

    @ViewBuilder
    private var bottomBar: some View {
        switch vm.status {
        case .recording:
            startSettleButton
        case .settling:
            VStack(spacing: NotionTheme.space2) {
                HStack(spacing: NotionTheme.space5) {
                    Button {
                        showRevertConfirm = true
                    } label: {
                        Text("回退到记录中")
                            .font(NotionFont.body())
                            .foregroundStyle(Color.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, NotionTheme.space4)
                            .background(
                                RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                                    .fill(Color.hoverBg)
                            )
                    }
                    .buttonStyle(.plain)
                    completeButton
                }
                // 副文本从按钮内部上提到按钮下方，避免双按钮高度不一致。
                // 与 startSettleButton 的"先添加至少一笔流水再结算"提示写法保持一致。
                completeHintText
            }
        .padding(NotionTheme.space5)
            .background(
                // 不透明：避免 ScrollView 内容（如分摊参与者 chip）透出出现在底部按钮 bar 上方
                Color.appCanvas
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.divider).frame(height: NotionTheme.borderWidth)
                    }
            )
        case .completed:
            EmptyView()
        }
    }

    @ViewBuilder
    private var startSettleButton: some View {
        let enabled = vm.canStartSettlement
        VStack(spacing: 4) {
            Button {
                showStartSettleConfirm = true
            } label: {
                Text("开始结算")
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, NotionTheme.space5)
                    .background(
                        RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                            .fill(enabled ? Color.accentBlue : Color.inkTertiary.opacity(0.4))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            if !enabled {
                Text("先添加至少一笔流水再结算")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
            }
        }
        .padding(NotionTheme.space5)
        .background(
            // 不透明：避免 ScrollView 内容透出出现在底部按钮 bar 上方
            Color.appCanvas
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.divider).frame(height: NotionTheme.borderWidth)
                }
        )
    }

    @ViewBuilder
    private var completeButton: some View {
        // M12：与 AAPaymentConfirmSection 同详，按 net = 应付 - 实付 计算。
        // 只有「net > 0 且 status == pending」的成员会阻塞完成结算。
        let pendingCount = vm.members.filter { vm.netOwe(of: $0.id) > 0 && $0.status == .pending }.count
        let enabled = pendingCount == 0 && !vm.members.isEmpty
        Button {
            do {
                _ = try vm.completeSettlement()
            } catch {
                showCompleteError = error.localizedDescription
            }
        } label: {
            Text("完成结算")
                .font(NotionFont.bodyBold())
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, NotionTheme.space4)
                .background(
                    RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                        .fill(enabled ? Color.statusSuccess : Color.inkTertiary.opacity(0.4))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // “完成结算”按钮下方的提示文案，从按钮内部上提，保证双按钮高度一致。
    @ViewBuilder
    private var completeHintText: some View {
        let pendingCount = vm.members.filter { vm.netOwe(of: $0.id) > 0 && $0.status == .pending }.count
        let enabled = pendingCount == 0 && !vm.members.isEmpty
        if !enabled {
            Text(pendingCount > 0 ? "还有 \(pendingCount) 位未确认支付" : "请先添加成员")
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
        }
    }

    // MARK: - 工具

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        // 与设计稿规范一致：yyyy.MM.dd HH:mm（成员"已确认时间"、CSV 导出时间等共用）
        f.dateFormat = "yyyy.MM.dd HH:mm"
        return f.string(from: d)
    }

    private func formatTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private func exportCSV() {
        guard let l = vm.ledger else { return }
        var lines: [String] = []
        lines.append("分账名称,\(escapeCSV(l.name))")
        lines.append("状态,\(l.aaStatus?.rawValue ?? "-")")
        lines.append("")
        lines.append("=== 流水 ===")
        lines.append("时间,备注,金额")
        for r in vm.visibleRecords {
            lines.append("\(formatDate(r.occurredAt)),\(escapeCSV(r.note ?? "")),\(r.amount)")
        }
        lines.append("")
        lines.append("=== 成员 ===")
        lines.append("昵称,应付,状态,已付时间")
        for m in vm.members {
            let owe = vm.owe(of: m.id)
            let paid = m.paidAt.map { formatDate($0) } ?? "-"
            lines.append("\(escapeCSV(m.name)),\(owe),\(m.status.rawValue),\(paid)")
        }
        let csv = lines.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AA-\(l.name)-\(Int(Date().timeIntervalSince1970)).csv")
        try? csv.data(using: .utf8)?.write(to: url)
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first?
            .present(av, animated: true)
    }

    private func escapeCSV(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

}

// MARK: - 回写流水列表 Sheet（completed 态用）

private struct WritebackRecordListSheet: View {
    let aaSettlementId: String
    @Environment(\.dismiss) private var dismiss
    @State private var records: [Record] = []

    var body: some View {
        NavigationStack {
            List {
                if records.isEmpty {
                    Text("暂无回写流水").foregroundStyle(Color.inkTertiary)
                } else {
                    ForEach(records) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.note ?? "AA 回写流水")
                                .font(NotionFont.body())
                            HStack {
                                Text("¥" + StatsFormat.decimalGrouped(r.amount))
                                    .font(NotionFont.small().monospacedDigit())
                                Spacer()
                                Text(r.occurredAt, style: .date)
                                    .font(NotionFont.micro())
                                    .foregroundStyle(Color.inkTertiary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("AA 回写流水")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                records = (try? SQLiteRecordRepository.shared
                    .findByAASettlementId(aaSettlementId)) ?? []
            }
        }
    }
}
