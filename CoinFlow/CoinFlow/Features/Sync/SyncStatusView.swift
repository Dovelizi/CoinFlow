//  SyncStatusView.swift
//  CoinFlow · M9 · 飞书多维表格切换
//
//  设计基线：design/screens/15-sync-status/{main,loading,error}-*.png +
//           CoinFlowPreview MiscScreensView.SyncStatusView（L648-922）
//
//  三态：
//    - synced：全部已同步
//    - syncing：上传中
//    - failed：存在失败或 pending
//
//  数据源：
//    - AppState.data.pendingCount：本地待同步/失败数
//    - AppState.feishu：飞书配置/表状态
//    - 触发"立即同步" → AppState.manualSyncTickWithRevive()
//    - 触发"从飞书拉取" → AppState.pullFromFeishu()（Q5=L 手动按钮）

import SwiftUI

struct SyncStatusView: View {

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// 最近的 pending/failed 记录（UI 展示最多 5 条）
    @State private var pendingPreview: [PendingItem] = []
    @State private var isActioning: Bool = false
    @State private var pullState: PullState = .idle

    private struct PendingItem: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let status: QueueStatus
    }

    enum QueueStatus { case uploading, pending, synced, failed }

    private enum PullState: Equatable {
        case idle
        case pulling
        case done(inserted: Int, skipped: Int, decodeFailures: Int)
        case error(String)
    }

    // MARK: - Derived mode

    private enum DisplayMode { case synced, syncing, failed }

    private var mode: DisplayMode {
        let pendingCount = appState.data.pendingCount
        if pendingCount == 0 { return .synced }
        if isActioning { return .syncing }
        return .failed
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            ScrollView {
                VStack(spacing: NotionTheme.space7) {
                    statusHero
                    queueCard
                    if mode == .failed {
                        errorCard
                    }
                    syncMetaCard
                    pullFromFeishuCard
                }
                .padding(.horizontal, NotionTheme.space5)
                .padding(.top, NotionTheme.space6)
                .padding(.bottom, NotionTheme.space9)
            }
            actionBar
        }
        .background(ThemedBackgroundLayer(kind: .sync))
        .navigationBarHidden(true)
        .onAppear { reload() }
    }

    // MARK: - Nav

    private var navBar: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("同步状态")
                    .font(.custom("PingFangSC-Semibold", size: 17))
                    .foregroundStyle(Color.inkPrimary)
                Text("飞书多维表格")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
            }
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.inkPrimary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSoft)
                .accessibilityLabel("返回")
                Spacer()
                Button { reload() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSoft)
                .accessibilityLabel("刷新")
            }
            .padding(.horizontal, NotionTheme.space4)
        }
        .frame(height: NotionTheme.topbarHeight)
        .background(Color.appCanvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.divider).frame(height: NotionTheme.borderWidth)
        }
    }

    // MARK: - Hero

    private var heroIcon: String {
        switch mode {
        case .synced:  return "checkmark.circle.fill"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .failed:  return "exclamationmark.triangle.fill"
        }
    }
    private var heroTitle: String {
        switch mode {
        case .synced:  return "已同步"
        case .syncing: return "正在同步…"
        case .failed:  return "待同步"
        }
    }
    private var heroSubtitle: String {
        let total = appState.data.recordTotal
        let pending = appState.data.pendingCount
        switch mode {
        case .synced:
            if let t = appState.data.lastTickAt {
                return "\(timeText(t)) · \(total) 笔流水全部已上传"
            }
            return "\(total) 笔流水全部已上传"
        case .syncing:
            return "正在上传 \(pending) 笔流水"
        case .failed:
            return "\(pending) 笔待上传 · 请检查网络"
        }
    }
    private var heroColor: Color {
        switch mode {
        case .synced:  return Color.statusSuccess
        case .syncing: return Color.accentBlue
        case .failed:  return Color.statusWarning
        }
    }

    private var statusHero: some View {
        VStack(spacing: NotionTheme.space4) {
            Image(systemName: heroIcon)
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(heroColor)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(heroTitle)
                    .font(.custom("PingFangSC-Semibold", size: 24))
                    .foregroundStyle(Color.inkPrimary)
                Text(heroSubtitle)
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, NotionTheme.space5)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Queue

    private var queueCard: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            HStack {
                Text("同步队列")
                    .font(.custom("PingFangSC-Semibold", size: 14))
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
                Text(queueSummaryText)
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
            }
            .padding(.leading, 4)

            VStack(spacing: 0) {
                if pendingPreview.isEmpty {
                    emptyQueueRow
                } else {
                    ForEach(Array(pendingPreview.enumerated()), id: \.element.id) { idx, item in
                        queueRow(item: item)
                        if idx < pendingPreview.count - 1 {
                            Rectangle().fill(Color.divider).frame(height: 0.5)
                                .padding(.leading, NotionTheme.space5 + 24 + NotionTheme.space5)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                    .fill(Color.hoverBg.opacity(0.5))
            )
        }
    }

    private var queueSummaryText: String {
        let pending = appState.data.pendingCount
        if pending == 0 { return "0 项待同步" }
        if mode == .syncing { return "\(pending) 项进行中" }
        return "\(pending) 项待上传"
    }

    @ViewBuilder
    private func queueRow(item: PendingItem) -> some View {
        HStack(spacing: NotionTheme.space5) {
            ZStack {
                Circle()
                    .fill(statusColor(item.status).opacity(0.2))
                    .frame(width: 24, height: 24)
                Image(systemName: statusIcon(item.status))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor(item.status))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.inkPrimary)
                Text(item.subtitle)
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer()
            if item.status == .failed {
                Button { triggerSync() } label: {
                    Text("重试")
                        .font(.custom("PingFangSC-Semibold", size: 12))
                        .foregroundStyle(Color.accentBlue)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSoft)
                .accessibilityLabel("重试同步")
            }
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 12)
    }

    private func statusColor(_ s: QueueStatus) -> Color {
        switch s {
        case .uploading: return Color.accentBlue
        case .pending:   return Color.statusWarning
        case .synced:    return Color.statusSuccess
        case .failed:    return Color.dangerRed
        }
    }
    private func statusIcon(_ s: QueueStatus) -> String {
        switch s {
        case .uploading: return "arrow.up"
        case .pending:   return "clock"
        case .synced:    return "checkmark"
        case .failed:    return "xmark"
        }
    }

    private var emptyQueueRow: some View {
        VStack(spacing: NotionTheme.space3) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.statusSuccess)
                .accessibilityHidden(true)
            Text("队列为空")
                .font(NotionFont.bodyBold())
                .foregroundStyle(Color.inkSecondary)
            Text("所有数据已同步到飞书多维表格")
                .font(NotionFont.small())
                .foregroundStyle(Color.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NotionTheme.space7)
    }

    // MARK: - Error card

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.dangerRed)
                Text("状态说明")
                    .font(.custom("PingFangSC-Semibold", size: 14))
                    .foregroundStyle(Color.inkPrimary)
            }
            VStack(alignment: .leading, spacing: 6) {
                if !appState.isSyncEligible {
                    Text("前置未就绪：飞书 App ID / Secret 未配置")
                        .font(NotionFont.small())
                        .foregroundStyle(Color.dangerRed)
                } else {
                    Text("\(appState.data.pendingCount) 笔本地记录尚未上传；可能原因：网络不稳 / 飞书 token 失效 / API 权限未开通")
                        .font(NotionFont.small())
                        .foregroundStyle(Color.inkSecondary)
                }
                Text("点击下方「立即同步」可手动触发重试")
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
            }
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                .fill(Color.dangerRed.opacity(0.12))
        )
    }

    // MARK: - Sync meta card（飞书状态）

    private var syncMetaCard: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            Text("同步信息")
                .font(.custom("PingFangSC-Semibold", size: 14))
                .foregroundStyle(Color.inkPrimary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                metaRow(label: "飞书", value: feishuStatusText)
                rowDivider
                metaRow(label: "多维表格", value: bitableStatusText)
                rowDivider
                metaRow(label: "上次 tick",
                        value: appState.data.lastTickAt.map(timeText) ?? "—")
            }
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                    .fill(Color.hoverBg.opacity(0.5))
            )
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(Color.divider).frame(height: 0.5)
            .padding(.leading, NotionTheme.space5)
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(spacing: NotionTheme.space4) {
            Text(label)
                .font(NotionFont.body())
                .foregroundStyle(Color.inkSecondary)
            Spacer()
            Text(value)
                .font(NotionFont.small())
                .foregroundStyle(Color.inkPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 12)
    }

    private var feishuStatusText: String {
        switch appState.feishu {
        case .pending: return "初始化中"
        case .configuredWaitingTable: return "已配置 · 待建表"
        case .ready: return "已就绪"
        case .notConfigured(let r): return "未配置（\(r)）"
        }
    }
    private var bitableStatusText: String {
        switch appState.feishu {
        case .ready(_, _, let url):
            return url.isEmpty ? "已建表" : "已建表"
        case .configuredWaitingTable: return "首次同步时自动创建"
        case .notConfigured: return "—"
        case .pending: return "—"
        }
    }

    // MARK: - 从飞书拉取卡片（Q5=L）

    private var pullFromFeishuCard: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            Text("从飞书拉取")
                .font(.custom("PingFangSC-Semibold", size: 14))
                .foregroundStyle(Color.inkPrimary)
                .padding(.leading, 4)

            Button { triggerPullFromFeishu() } label: {
                HStack(spacing: NotionTheme.space5) {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(pullEnabled ? Color.inkSecondary : Color.inkTertiary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("从飞书拉取数据")
                            .font(NotionFont.body())
                            .foregroundStyle(pullEnabled ? Color.inkPrimary : Color.inkTertiary)
                        Text(pullSubtitle)
                            .font(NotionFont.micro())
                            .foregroundStyle(pullSubtitleColor)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    if case .pulling = pullState {
                        ProgressView().controlSize(.small).tint(Color.accentBlue)
                    }
                }
                .padding(NotionTheme.space5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSoft)
            .disabled(!pullEnabled)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                    .fill(Color.hoverBg.opacity(0.5))
            )
            .accessibilityLabel("从飞书多维表格拉取账单")
            .accessibilityHint("一次性拉取飞书有但本地没有的账单，不会覆盖本地已存在的记录")
        }
    }

    private var pullEnabled: Bool {
        if case .pulling = pullState { return false }
        return appState.isSyncEligible
    }

    private var pullSubtitle: String {
        switch pullState {
        case .idle:
            return "只新增飞书有、本地没有的账单（不覆盖本地）"
        case .pulling:
            return "正在拉取…"
        case .done(let inserted, let skipped, let decFail):
            var parts: [String] = ["新增 \(inserted) 条"]
            if skipped > 0 { parts.append("跳过本地已存在 \(skipped)") }
            if decFail > 0 { parts.append("解析失败 \(decFail)") }
            return parts.joined(separator: " · ")
        case .error(let msg):
            return "拉取失败：\(msg)"
        }
    }

    private var pullSubtitleColor: Color {
        switch pullState {
        case .error: return Color.dangerRed
        case .done:  return Color.statusSuccess
        default:     return Color.inkTertiary
        }
    }

    private func triggerPullFromFeishu() {
        guard pullEnabled else { return }
        pullState = .pulling
        Task {
            let result = await appState.pullFromFeishu()
            await MainActor.run {
                switch result {
                case .success(let r):
                    pullState = .done(
                        inserted: r.inserted,
                        skipped: r.skippedExisting,
                        decodeFailures: r.decodeFailures
                    )
                    reload()
                case .failure(let err):
                    pullState = .error(err.localizedDescription)
                }
            }
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.divider).frame(height: 0.5)
            Button { triggerSync() } label: {
                Text(actionText)
                    .font(.custom("PingFangSC-Semibold", size: 15))
                    .foregroundStyle(canAction ? Color.canvasBG : Color.inkTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                            .fill(canAction ? Color.inkPrimary : Color.hoverBgStrong)
                    )
            }
            .buttonStyle(.pressableSoft)
            .disabled(!canAction || isActioning)
            .padding(.horizontal, NotionTheme.space5)
            .padding(.top, NotionTheme.space4)
            .padding(.bottom, NotionTheme.space5)
        }
        .background(Color.appCanvas)
    }

    private var actionText: String {
        if isActioning { return "同步中…" }
        switch mode {
        case .synced:  return "立即同步"
        case .syncing: return "同步中…"
        case .failed:  return "全部重试"
        }
    }

    private var canAction: Bool { appState.isSyncEligible }

    // MARK: - Actions

    private func triggerSync() {
        guard canAction else { return }
        isActioning = true
        Task {
            _ = await appState.manualSyncTickWithRevive()
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                reload()
                isActioning = false
            }
        }
    }

    // MARK: - Data

    private func reload() {
        do {
            let all = try SQLiteRecordRepository.shared.list(.init(
                ledgerId: DefaultSeeder.defaultLedgerId,
                includesDeleted: false,
                limit: 100
            ))
            let pending = all
                .filter { $0.syncStatus == .pending || $0.syncStatus == .failed }
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(5)
            pendingPreview = pending.map { r in
                PendingItem(
                    id: r.id,
                    title: titleFor(r),
                    subtitle: "\(relativeTime(r.updatedAt)) · \(statusText(r.syncStatus))",
                    status: r.syncStatus == .failed ? .failed : .pending
                )
            }
        } catch {
            pendingPreview = []
        }
    }

    private func titleFor(_ r: Record) -> String {
        let prefix = "¥" + AmountFormatter.display(r.amount)
        if let note = r.note, !note.isEmpty {
            return "\(note) · \(prefix)"
        }
        return prefix
    }

    private func statusText(_ s: SyncStatus) -> String {
        switch s {
        case .pending: return "等待上传"
        case .syncing: return "正在上传"
        case .synced:  return "已同步"
        case .failed:  return "同步失败"
        }
    }

    private func timeText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    private func relativeTime(_ d: Date) -> String {
        let secs = Int(Date().timeIntervalSince(d))
        if secs < 60 { return "刚刚" }
        if secs < 3600 { return "\(secs / 60) 分钟前" }
        if secs < 86400 { return "\(secs / 3600) 小时前" }
        return "\(secs / 86400) 天前"
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        SyncStatusView()
            .environmentObject(AppState())
    }
    .preferredColorScheme(.dark)
}
#endif
