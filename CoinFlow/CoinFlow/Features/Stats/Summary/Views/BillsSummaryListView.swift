//  BillsSummaryListView.swift
//  CoinFlow · M10-Fix2
//
//  账单总结主页：
//  - 顶部 3 个测试按钮：周报 / 月报 / 年报，点击触发 LLM 生成
//  - 下方"历史总结"按 kind 分组（周报/月报/年报三段）整页展示
//  - 任意条目点击 → 居中浮窗（SummaryFloatingCard）展示
//  - 测试按钮成功生成后 → 自动弹出该总结的浮窗
//  - 加载/失败状态在按钮下方 inline 显示
//
//  设计取舍：
//  - 不再嵌入 NavigationDestination 二级页面（详情完全用浮窗替代）
//  - 浮窗用 ZStack overlay 承载（非 .sheet）→ 才能做"四边等距居中"视觉

import SwiftUI

struct BillsSummaryListView: View {

    /// 是否展示顶部"生成测试 + 模拟推送"区块。
    /// - 设置页（"我的"）入口：true（默认；保持原行为）
    /// - 统计页第 9 张卡入口：false（仅展示历史，移除调试入口）
    let showsTestSection: Bool

    init(showsTestSection: Bool = true) {
        self.showsTestSection = showsTestSection
    }

    @Environment(\.dismiss) private var dismiss

    /// 历史所有总结（按 period_start 降序）
    @State private var summaries: [BillsSummary] = []

    /// 当前正在生成的 kind（按钮 loading 态）
    @State private var generatingKind: BillsSummaryPeriodKind?
    /// 生成失败信息（按钮下方红卡）
    @State private var generationError: String?
    /// 调试信息（蓝色提示卡，与失败错误区分）；用于"模拟推送已触发"这类正向反馈
    @State private var debugInfoMessage: String?

    /// 浮窗当前展示的 summary；nil = 不展示浮窗
    @State private var floatingSummary: BillsSummary?

    var body: some View {
        ZStack {
            ThemedBackgroundLayer(kind: .settings)
            VStack(spacing: 0) {
                navBar
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: NotionTheme.space5) {
                        if showsTestSection {
                            testButtonsSection
                                .padding(.horizontal, NotionTheme.space5)
                                .padding(.top, NotionTheme.space5)

                            if let err = generationError {
                                errorBanner(err)
                                    .padding(.horizontal, NotionTheme.space5)
                            }

                            if let info = debugInfoMessage {
                                infoBanner(info)
                                    .padding(.horizontal, NotionTheme.space5)
                            }
                        }

                        // 历史区
                        historyArea
                            .padding(.horizontal, NotionTheme.space5)
                            .padding(.top, showsTestSection ? NotionTheme.space7 : NotionTheme.space5)
                    }
                    .padding(.bottom, NotionTheme.space7)
                }
            }

            // 浮窗 overlay
            if let s = floatingSummary {
                SummaryFloatingCard(summary: s) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        floatingSummary = nil
                    }
                }
                .zIndex(50)
            }
        }
        .onAppear { reload() }
        .navigationBarHidden(true)
        .animation(.easeInOut(duration: 0.2), value: floatingSummary?.id)
    }

    // MARK: - NavBar

    private var navBar: some View {
        HStack(spacing: NotionTheme.space5) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.inkPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            Text("账单总结")
                .font(NotionFont.h3())
                .foregroundStyle(Color.inkPrimary)
            Spacer()
        }
        .padding(.horizontal, NotionTheme.space3)
        .frame(height: 56)
    }

    // MARK: - 顶部三按钮

    private var testButtonsSection: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            Text("生成测试")
                .font(NotionFont.small())
                .foregroundStyle(Color.inkSecondary)
            HStack(spacing: NotionTheme.space3) {
                ForEach(BillsSummaryPeriodKind.allCases, id: \.self) { k in
                    testButton(kind: k)
                }
            }
            Text("点击按钮立即生成对应周期的情绪化复盘；生成完成后会自动弹出浮窗。")
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)

            // M10-Fix4 · 调试：模拟首页推送链路
            // 行为：关闭本页 → 0.6s 后触发 generate → service 广播 notification → 首页 banner 出现
            // 仅用于在非周一 / 非月初等"调度器不会自动触发"的日子人工验证推送 UI
            HStack(spacing: NotionTheme.space3) {
                ForEach(BillsSummaryPeriodKind.allCases, id: \.self) { k in
                    debugPushButton(kind: k)
                }
            }
            .padding(.top, NotionTheme.space5)
            Text("调试 · 模拟首页推送：返回首页后会自动生成 + 触发 banner，可绕过周一/月初日期限制。")
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
        }
    }

    /// 调试按钮：模拟"首页推送"链路。
    /// 注意：不主动 dismiss 列表页（dismiss 只能回上一级 = 设置页，无法直接到首页）。
    /// 用法：点完按钮 → 用户**手动切到首页 tab** → 0.6s 延后给到切 tab 时间 →
    /// service.generate 完成 → 广播 notification → 首页 banner 出现。
    /// 5 秒 banner 存活窗口足够看清。
    private func debugPushButton(kind: BillsSummaryPeriodKind) -> some View {
        Button {
            triggerDebugPush(kind: kind)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 11, weight: .medium))
                Text("推送 \(kind.displayName)")
                    .font(NotionFont.micro())
            }
            .foregroundStyle(Color.inkSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: 999)
                    .stroke(Color.border, lineWidth: NotionTheme.borderWidth)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("模拟\(kind.displayName)首页推送")
    }

    private func triggerDebugPush(kind: BillsSummaryPeriodKind) {
        // 立即显示蓝色调试提示——banner 的 5s 计时在 onAppear 触发，
        // 用户切到首页之前 banner 不会"过期"，所以无需 await sleep。
        debugInfoMessage = "已触发 \(kind.displayName) 推送 · 请切到首页 tab 查看 banner（生成约 5-15 秒）"
        // 8 秒后清除提示文案
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            debugInfoMessage = nil
        }
        // 后台触发 generate；service 完成后会广播 notification，
        // AppState 收到 → pendingSummaryPush 写入 → 用户切回首页时 banner 自动展示
        Task.detached(priority: .userInitiated) {
            do {
                _ = try await BillsSummaryService.shared.generate(
                    kind: kind,
                    reference: Date(),
                    force: true
                )
            } catch {
                NSLog("[DebugPush] 触发失败：%@",
                      error.localizedDescription as NSString)
                // 把失败信息也回显到 UI（用红色错误卡，不混进调试 info）
                let msg = error.localizedDescription
                await MainActor.run {
                    debugInfoMessage = nil
                    generationError = "调试推送失败：\(msg)"
                }
            }
        }
    }

    private func testButton(kind: BillsSummaryPeriodKind) -> some View {
        let isLoading = generatingKind == kind
        return Button {
            tapTestButton(kind)
        } label: {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Color.white)
                } else {
                    Image(systemName: kind == .week ? "calendar.badge.clock"
                                      : kind == .month ? "calendar"
                                      : "sparkles")
                        .font(.system(size: 13, weight: .medium))
                }
                Text(kind.displayName + "总结")
                    .font(NotionFont.body())
                    .fontWeight(.medium)
            }
            .foregroundStyle(isLoading ? Color.white : Color.inkPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 999)
                    .fill(isLoading ? Color.accentBlue : Color.surfaceOverlay)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999)
                    .stroke(isLoading ? Color.accentBlue : Color.border,
                            lineWidth: NotionTheme.borderWidth)
            )
        }
        .disabled(isLoading)
        .accessibilityLabel("生成\(kind.displayName)总结")
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: NotionTheme.space3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.statusWarning)
            VStack(alignment: .leading, spacing: 4) {
                Text("生成失败")
                    .font(NotionFont.small())
                    .fontWeight(.medium)
                    .foregroundStyle(Color.inkPrimary)
                Text(message)
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            Button {
                generationError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.inkTertiary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .fill(Color.statusWarning.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .stroke(Color.statusWarning.opacity(0.25), lineWidth: NotionTheme.borderWidth)
        )
    }

    /// 蓝色调试信息卡（与红色 errorBanner 视觉区分，避免误以为出错）
    private func infoBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: NotionTheme.space3) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.accentBlue)
            VStack(alignment: .leading, spacing: 4) {
                Text("调试信息")
                    .font(NotionFont.small())
                    .fontWeight(.medium)
                    .foregroundStyle(Color.inkPrimary)
                Text(message)
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            Button {
                debugInfoMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.inkTertiary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .fill(Color.accentBlue.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .stroke(Color.accentBlue.opacity(0.30), lineWidth: NotionTheme.borderWidth)
        )
    }

    // MARK: - 历史区（按 kind 分组）

    @ViewBuilder
    private var historyArea: some View {
        if summaries.isEmpty {
            emptyState.padding(.top, 40)
        } else {
            VStack(alignment: .leading, spacing: NotionTheme.space7) {
                Text("历史总结")
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
                ForEach(BillsSummaryPeriodKind.allCases, id: \.self) { k in
                    kindSection(kind: k)
                }
            }
        }
    }

    private func kindSection(kind: BillsSummaryPeriodKind) -> some View {
        let items = summaries.filter { $0.periodKind == kind }
        return VStack(alignment: .leading, spacing: NotionTheme.space3) {
            // section header
            HStack(spacing: 6) {
                Image(systemName: kind == .week ? "calendar.badge.clock"
                                  : kind == .month ? "calendar"
                                  : "sparkles")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.inkSecondary)
                Text(kind.displayName + "报")
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.inkPrimary)
                Text("(\(items.count))")
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkTertiary)
                Spacer()
            }
            if items.isEmpty {
                Text("暂无\(kind.displayName)度总结")
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkTertiary)
                    .padding(.vertical, NotionTheme.space5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, NotionTheme.space5)
                    .background(
                        RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                            .fill(Color.surfaceOverlay.opacity(0.4))
                    )
            } else {
                VStack(spacing: NotionTheme.space3) {
                    ForEach(items) { s in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                floatingSummary = s
                            }
                        } label: {
                            historyRow(s)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func historyRow(_ s: BillsSummary) -> some View {
        HStack(alignment: .center, spacing: NotionTheme.space3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(periodLabel(s))
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.inkPrimary)
                if !s.summaryDigest.isEmpty {
                    Text(s.summaryDigest)
                        .font(NotionFont.small())
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    Label {
                        Text("¥\(formatAmount(s.totalExpense))")
                            .font(NotionFont.micro())
                            .foregroundStyle(Color.inkTertiary)
                    } icon: {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.statusWarning)
                    }
                    Text("·")
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.inkTertiary)
                    Text("\(s.recordCount) 笔")
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.inkTertiary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.inkTertiary)
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .fill(Color.surfaceOverlay)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .stroke(Color.border, lineWidth: NotionTheme.borderWidth)
        )
    }

    private var emptyState: some View {
        VStack(spacing: NotionTheme.space5) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(Color.inkTertiary)
            Text("还没有总结")
                .font(NotionFont.body())
                .foregroundStyle(Color.inkPrimary)
            Text("点击上方按钮即可生成第一份")
                .font(NotionFont.small())
                .foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 按钮逻辑

    private func tapTestButton(_ kind: BillsSummaryPeriodKind) {
        generatingKind = kind
        generationError = nil
        Task {
            do {
                let s = try await BillsSummaryService.shared.generate(
                    kind: kind,
                    reference: Date(),
                    force: true
                )
                await MainActor.run {
                    generatingKind = nil
                    reload()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        floatingSummary = s
                    }
                }
            } catch {
                await MainActor.run {
                    generatingKind = nil
                    generationError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Reload

    private func reload() {
        do {
            summaries = try SQLiteBillsSummaryRepository.shared.listAll(includesDeleted: false)
        } catch {
            summaries = []
        }
    }

    // MARK: - Helpers

    private func periodLabel(_ s: BillsSummary) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = .current
        switch s.periodKind {
        case .week:
            f.dateFormat = "yyyy 年第 w 周"
            return f.string(from: s.periodStart)
        case .month:
            f.dateFormat = "yyyy 年 M 月"
            return f.string(from: s.periodStart)
        case .year:
            f.dateFormat = "yyyy 年"
            return f.string(from: s.periodStart)
        }
    }

    private func formatAmount(_ d: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        f.groupingSeparator = ","
        return f.string(from: NSDecimalNumber(decimal: d)) ?? "\(d)"
    }
}
