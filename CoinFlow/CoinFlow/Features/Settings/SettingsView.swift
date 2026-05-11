//  SettingsView.swift
//  CoinFlow · M9 · 飞书多维表格切换版
//
//  M9 变化：
//  - 移除"账户"段中的 Apple Sign In（飞书自建应用模式不需要按用户隔离 uid）
//  - 移除"从云端恢复"行（功能已并入 SyncStatusView 的"从飞书拉取"按钮）
//  - "同步与数据"段保留：同步状态 + 数据导入导出
//  - 保留：Face ID / Back Tap / 语音必填字段 / 分类管理 / 隐私 / 关于

import SwiftUI

struct SettingsView: View {

    /// 是否作为 Tab 嵌入（true：隐藏返回按钮，自带 NavigationStack）
    let embeddedInTab: Bool

    init(embeddedInTab: Bool = false) {
        self.embeddedInTab = embeddedInTab
    }

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var amountTint: AmountTintStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// 观察主题开关：设置页自身需要在主题切换时同步刷新"外观"段的选中态
    @ObservedObject private var themeStore = LGAThemeStore.shared

    private let settings = SQLiteUserSettingsRepository.shared

    // MARK: - State

    @State private var biometricEnabled: Bool = false
    @State private var backTapEnabled: Bool = false
    @State private var voiceRequiredFields: Set<String> = ["amount", "occurred_at", "direction"]
    /// 流水列表统一布局选择（从段头切换器迁移到全局设置）
    @State private var recordsListLayout: RecordsLayout = .list
    /// 流水列表布局选择器展开（默认收起，点击行展开 list/grid 选项）
    @State private var recordsLayoutExpanded: Bool = false
    /// 语音必填字段组展开（默认收起，点击行展开 4 个 toggle）
    @State private var voiceFieldsExpanded: Bool = false
    @State private var showBackTapDoc = false
    @State private var showCategoryManager = false
    @State private var showAppearancePage: Bool = false
    @State private var recordCount: Int = 0
    @State private var diagnosticsExpanded: Bool = false
    @State private var showSyncStatus: Bool = false
    @State private var showDataIO: Bool = false
    @State private var showSummaryList: Bool = false
    @State private var privacyAmountMask: Bool = false
    /// 首次启动日期 → "加入 N 天"副标题
    @State private var joinedDaysText: String = ""
    /// “系统配置”页跳转状态
    @State private var showSystemConfig: Bool = false

    private var biometricKind: BiometricKind {
        BiometricAuthService.shared.availableKind
    }
    private var biometricAvailable: Bool { biometricKind != .none }

    /// 主题感知 accent（LGA → iOS 系统蓝 #007AFF，对齐参考图 Toggle 视觉；Notion → 原 accentBlue）
    /// 用于 Toggle `.tint()`；卡片选中描边走 LGATheme.accentSelection 不复用此值。
    private var themedTint: Color {
        themeStore.isEnabled ? Color(red: 0.0, green: 0x7A / 255.0, blue: 1.0) : Color.accentBlue
    }

    /// 主题感知次要文字色（LGA → #A0A0A5；Notion → inkSecondary）
    /// 用于行右侧 valueText、行内副文等"次要"信息层。
    private var themedSecondary: Color {
        themeStore.isEnabled ? LGATheme.textSecondary : Color.inkSecondary
    }

    /// 主题感知三级文字色（LGA → #A0A0A5 同次要色；Notion → inkTertiary）
    /// 用于更弱层级的辅助说明、chevron、micro 提示。
    private var themedTertiary: Color {
        themeStore.isEnabled ? LGATheme.textSecondary : Color.inkTertiary
    }

    /// 主题感知行内图标色（LGA → #A0A0A5 冷灰；Notion → inkSecondary）
    /// 用于设置项左侧的 SF Symbol 图标。
    private var themedIcon: Color {
        themeStore.isEnabled ? LGATheme.textSecondary : Color.inkSecondary
    }

    private var displayName: String {
        if FeishuConfig.isConfigured { return "CoinFlow 用户" }
        return "未配置同步"
    }

    /// 设置页"账单总结"行右侧统计文案：本地总结条数；为 0 时显示"未生成"
    private var summaryRightText: String? {
        let count = (try? SQLiteBillsSummaryRepository.shared.listAll(includesDeleted: false).count) ?? 0
        return count == 0 ? "未生成" : "\(count) 篇"
    }

    private var avatarLetter: String {
        guard let first = displayName.first else { return "?" }
        return String(first).uppercased()
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            ThemedBackgroundLayer(kind: .settings)
            VStack(spacing: 0) {
                navBar
                scrollBody
            }
        }
        .onAppear { loadFromStorage() }
        .navigationBarHidden(true)
        .enableInteractivePop()
        .hideTabBar(if: !embeddedInTab)
        .navigationDestination(isPresented: $showBackTapDoc) {
            BackTapSetupView()
        }
        .navigationDestination(isPresented: $showCategoryManager) {
            CategoryListView()
        }
        .navigationDestination(isPresented: $showSyncStatus) {
            SyncStatusView()
        }
        .navigationDestination(isPresented: $showDataIO) {
            DataImportExportView()
        }
        .navigationDestination(isPresented: $showSummaryList) {
            BillsSummaryListView()
        }
        .navigationDestination(isPresented: $showAppearancePage) {
            AppearanceSettingsView()
        }
        .navigationDestination(isPresented: $showSystemConfig) {
            SystemConfigView()
        }
    }

    @ViewBuilder
    private var scrollBody: some View {
        if embeddedInTab {
            // Tab 模式：底部留白给浮动 tabBar + 注入滚动探针
            ScrollViewWithTabBarTracking {
                VStack(spacing: NotionTheme.space6) {
                    Color.clear.frame(height: 0).tabBarScrollAnchor()
                    userHeaderCard
                    appearanceEntrySection
                    accountSection
                    recordSection
                    syncDataSection
                    privacySection
                    aboutSection
                }
                .padding(NotionTheme.space5)
                .padding(.bottom, 100)
            }
        } else {
            ScrollView {
                VStack(spacing: NotionTheme.space6) {
                    userHeaderCard
                    appearanceEntrySection
                    accountSection
                    recordSection
                    syncDataSection
                    privacySection
                    aboutSection
                }
                .padding(NotionTheme.space5)
            }
        }
    }

    // MARK: - Nav

    private var navBar: some View {
        ZStack {
            // v5 统一 nav 标题字号（17pt PingFangSC-Semibold），主题切换仅文字色变化
            Text("设置")
                .font(.custom("PingFangSC-Semibold", size: 17))
                .foregroundStyle(themeStore.isEnabled ? Color.white : Color.inkPrimary)
            if !embeddedInTab {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(themeStore.isEnabled ? Color.white : Color.inkPrimary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.pressableSoft)
                    .accessibilityLabel("返回")
                    Spacer()
                }
                .padding(.horizontal, NotionTheme.space5)
            }
        }
        .frame(height: NotionTheme.topbarHeight)
        .background(Color.appCanvas)
        .overlay(alignment: .bottom) {
            // v5 一致性：两套主题都显示 navbar 底部 hairline；仅颜色随主题
            Rectangle()
                .fill(themeStore.isEnabled ? Color.white.opacity(0.06) : Color.divider)
                .frame(height: NotionTheme.borderWidth)
        }
    }

    // MARK: - User header card（iOS "Apple ID" 风格：居中大头像 + 居中用户名 + 居中副标题）

    private var userHeaderCard: some View {
        VStack(spacing: NotionTheme.space4) {
            ZStack {
                Circle()
                    .fill(avatarCircleFill)
                    .frame(width: 88, height: 88)
                Text(avatarLetter)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(avatarLetterColor)
            }
            VStack(spacing: 4) {
                Text(displayName)
                    .font(.custom("PingFangSC-Semibold", size: 22))
                    .foregroundStyle(themeStore.isEnabled ? Color.white : Color.inkPrimary)
                Text(headerSubtitle)
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NotionTheme.space6)
    }

    /// LGA 模式：参考图头像 = 深紫蓝实色圆 #2F3556（接近 indigo dim），字母浅紫蓝 #A8B5FF
    /// Notion 模式：保留原 accentBlue 半透明圆圈
    private var avatarCircleFill: Color {
        LGAThemeRuntime.isEnabled
            ? Color(red: 0x2F / 255.0, green: 0x35 / 255.0, blue: 0x56 / 255.0)
            : Color.accentBlue.opacity(0.15)
    }
    private var avatarLetterColor: Color {
        LGAThemeRuntime.isEnabled
            ? Color(red: 0xA8 / 255.0, green: 0xB5 / 255.0, blue: 0xFF / 255.0)
            : Color.accentBlue
    }

    private var headerSubtitle: String {
        let leading = recordCount > 0 ? "已记账 \(recordCount) 笔" : "尚未记账"
        if joinedDaysText.isEmpty {
            return leading
        }
        return "\(leading) · \(joinedDaysText)"
    }

    // MARK: - 外观入口（合并主题 + 金额颜色）
    //
    // 点击整行 push 到 AppearanceSettingsView；右侧值预览 "主题名 · 配色名"。

    private var appearanceEntrySection: some View {
        SettingsSection(title: "外观", icon: "paintpalette") {
            Button {
                showAppearancePage = true
            } label: {
                HStack(spacing: NotionTheme.space5) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(themedIcon)
                        .frame(width: 24)
                    Text("主题与颜色")
                        .font(NotionFont.body())
                        .foregroundStyle(themeStore.isEnabled ? Color.white : Color.inkPrimary)
                    Spacer()
                    Text(appearanceSummaryText)
                        .font(NotionFont.small())
                        .foregroundStyle(themedTertiary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(themedTertiary)
                }
                .padding(.horizontal, NotionTheme.space5)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSoft)
            .accessibilityLabel("主题与颜色，当前 \(appearanceSummaryText)")
        }
    }

    /// 右侧值预览："Dark Notion · 系统"
    private var appearanceSummaryText: String {
        let themeName: String
        switch themeStore.kind {
        case .notion:       themeName = "Dark Notion"
        case .darkLiquid:   themeName = "Dark Liquid"
        case .liquidGlass:  themeName = "Liquid Glass"
        }
        return "\(themeName) · \(amountTint.palette.displayName)"
    }

    // MARK: - 账户段（M9 仅保留 Face ID）

    private var accountSection: some View {
        SettingsSection(title: "账户与安全", icon: "person.crop.circle") {
            VStack(spacing: 0) {
                navRow(
                    icon: "key",
                    title: "系统配置",
                    rightText: systemConfigRightText,
                    accessibilityHint: "编辑 LLM 与飞书 API 凭据"
                ) {
                    showSystemConfig = true
                }
                rowDivider
                biometricRow
            }
        }
    }

    /// 右侧状态提示：未配置 / 仅飞书 / 仅 LLM / 全部
    private var systemConfigRightText: String {
        let s = SystemConfigStore.shared
        let feishu = s.isFeishuConfigured
        let text   = s.isTextConfigured
        let vision = s.isVisionConfigured
        switch (feishu, text || vision) {
        case (false, false): return "未配置"
        case (true, false):  return "仅飞书"
        case (false, true):  return "仅 LLM"
        case (true, true):   return "已配置"
        }
    }

    private var biometricRow: some View {
        Toggle(isOn: $biometricEnabled) {
            HStack(spacing: NotionTheme.space5) {
                Image(systemName: biometricKind == .faceID ? "faceid" : "touchid")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(biometricAvailable ? themedIcon : themedTertiary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(biometricAvailable
                         ? "启动需 \(biometricKind.displayName) 解锁"
                         : "本机未配置 Face / Touch ID")
                        .font(NotionFont.body())
                        .foregroundStyle(biometricAvailable
                                         ? (themeStore.isEnabled ? Color.white : Color.inkPrimary)
                                         : themedTertiary)
                    Text("启用后，App 冷启动会先要求生物验证")
                        .font(NotionFont.micro())
                        .foregroundStyle(themedTertiary)
                }
            }
        }
        .tint(themedTint)
        .disabled(!biometricAvailable)
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 12)
        .accessibilityLabel("启动需要生物验证")
        .onChange(of: biometricEnabled) { newValue in
            settings.setBool(SettingsKey.biometricEnabled, newValue)
            UserDefaults.standard.set(newValue, forKey: "security.biometric_enabled_mirror")
        }
    }

    // MARK: - 记账段

    private var recordSection: some View {
        SettingsSection(title: "记账", icon: "square.and.pencil") {
            VStack(spacing: 0) {
                backTapToggleRow
                rowDivider
                voiceFieldsToggleGroup
                rowDivider
                recordsLayoutRow
                rowDivider
                navRow(
                    icon: "folder",
                    title: "分类管理",
                    accessibilityHint: "进入分类管理页"
                ) {
                    showCategoryManager = true
                }
                rowDivider
                navRow(
                    icon: "book",
                    title: "默认账本",
                    rightText: "我的账本",
                    accessibilityHint: "默认账本设置（V2 开放）"
                ) {
                    // V2：账本切换页面
                }
            }
        }
    }

    // MARK: - 流水列表布局选择
    //
    // 三选一切换器（List / Stack / Grid），改动后下次进入流水页生效。
    // 设计决策：用本地 @State + onChange 写 settings，不实时通知流水页 ——
    // 因为本设置项变更频率极低，且 RecordsListView.onAppear 会重新读取 settings，
    // 用户切完回去就生效。如未来发现"切完不立即生效"体验差，可改 NotificationCenter。
    //
    // v2（用户反馈）：默认收起，点击行展开切换器；用 DisclosureGroup 视觉约定。
    private var recordsLayoutRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.snap) {
                    recordsLayoutExpanded.toggle()
                }
            } label: {
                HStack(spacing: NotionTheme.space5) {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(themedIcon)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("流水列表布局")
                            .font(NotionFont.body())
                            .foregroundStyle(themeStore.isEnabled ? Color.white : Color.inkPrimary)
                        Text(layoutLabel(recordsListLayout))
                            .font(NotionFont.micro())
                            .foregroundStyle(themedTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(themedTertiary)
                        .rotationEffect(.degrees(recordsLayoutExpanded ? 90 : 0))
                }
                .padding(.horizontal, NotionTheme.space5)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSoft)
            .accessibilityLabel("流水列表布局，当前 \(layoutLabel(recordsListLayout))，点击展开选项")

            if recordsLayoutExpanded {
                HStack(spacing: 0) {
                    ForEach(RecordsLayout.allCases, id: \.self) { l in
                        layoutSegmentButton(l)
                    }
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: NotionTheme.radiusMD, style: .continuous)
                        .fill(Color.hoverBg)
                )
                .padding(.horizontal, NotionTheme.space5)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func layoutSegmentButton(_ l: RecordsLayout) -> some View {
        let active = recordsListLayout == l
        // liquidGlass 主题下 Color.surfaceOverlay 渲染为深色实心 → 在紫色玻璃胶囊上呈黑块。
        // 与 NewRecordModal 中支出/收入段控件保持同一兜底方案：液态玻璃下走半透白高亮。
        let activeFill: Color = LGAThemeRuntime.isLiquidGlass
            ? Color.white.opacity(0.18)
            : Color.surfaceOverlay
        return Button {
            recordsListLayout = l
            settings.set(key: SettingsKey.recordsListLayout, value: l.rawValue)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: l.iconName)
                    .font(.system(size: 12, weight: .regular))
                Text(layoutLabel(l))
                    .font(NotionFont.small())
            }
            .foregroundStyle(active ? Color.inkPrimary : Color.inkTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusSM, style: .continuous)
                    .fill(active ? activeFill : Color.clear)
            )
        }
        .buttonStyle(.pressableSoft)
        .accessibilityLabel("\(layoutLabel(l)) 布局\(active ? "，已选中" : "")")
    }

    private func layoutLabel(_ l: RecordsLayout) -> String {
        switch l {
        case .list:  return "列表"
        case .grid:  return "网格"
        }
    }

    private var backTapToggleRow: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $backTapEnabled) {
                HStack(spacing: NotionTheme.space5) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(themedIcon)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("敲击背面 ×2 触发")
                            .font(NotionFont.body())
                            .foregroundStyle(themeStore.isEnabled ? Color.white : Color.inkPrimary)
                        Text("需要在系统设置中绑定 CoinFlow 快捷指令")
                            .font(NotionFont.micro())
                            .foregroundStyle(themedTertiary)
                    }
                }
            }
            .tint(themedTint)
            .padding(.horizontal, NotionTheme.space5)
            .padding(.vertical, 12)
            .accessibilityLabel("敲击背面快速记账")
            .onChange(of: backTapEnabled) { newValue in
                settings.setBool(SettingsKey.backTapEnabled, newValue)
            }

            Button { showBackTapDoc = true } label: {
                HStack(spacing: NotionTheme.space5) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.accentBlue)
                        .frame(width: 24)
                    Text("如何配置")
                        .font(NotionFont.small())
                        .foregroundStyle(Color.accentBlue)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentBlue)
                }
                .padding(.horizontal, NotionTheme.space5)
                .padding(.bottom, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSoft)
            .accessibilityLabel("查看 Back Tap 配置教程")
        }
    }

    private var voiceFieldsToggleGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.snap) {
                    voiceFieldsExpanded.toggle()
                }
            } label: {
                HStack(spacing: NotionTheme.space5) {
                    Image(systemName: "mic")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(themedIcon)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("语音必填字段")
                            .font(NotionFont.body())
                            .foregroundStyle(themeStore.isEnabled ? Color.white : Color.inkPrimary)
                        Text(voiceFieldsSummary)
                            .font(NotionFont.micro())
                            .foregroundStyle(themedTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(themedTertiary)
                        .rotationEffect(.degrees(voiceFieldsExpanded ? 90 : 0))
                }
                .padding(.horizontal, NotionTheme.space5)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSoft)
            .accessibilityLabel("语音必填字段，当前 \(voiceFieldsSummary)，点击展开选项")

            if voiceFieldsExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    voiceFieldToggle("amount", label: "金额", icon: "yensign.circle")
                    voiceFieldToggle("occurred_at", label: "日期", icon: "calendar")
                    voiceFieldToggle("direction", label: "收支方向", icon: "arrow.left.arrow.right")
                    voiceFieldToggle("category", label: "分类", icon: "folder")
                }
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .clipped()
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )
            }
        }
        // 让外层 VStack 在子项 insertion/removal 时裁剪掉滑出可视区的部分，
        // 视觉效果即"从触发行下方向下伸展"的手风琴动画。
        .clipped()
    }

    /// 折叠时副标题文案：当前已勾选字段数 / 总数
    private var voiceFieldsSummary: String {
        let total = 4
        let selected = voiceRequiredFields.count
        return "\(selected)/\(total) 项必填"
    }

    @ViewBuilder
    private func voiceFieldToggle(_ key: String, label: String, icon: String) -> some View {
        let isOn = Binding<Bool>(
            get: { voiceRequiredFields.contains(key) },
            set: { newValue in
                if newValue { voiceRequiredFields.insert(key) }
                else { voiceRequiredFields.remove(key) }
                persistRequiredFields()
            }
        )
        Toggle(isOn: isOn) {
            HStack(spacing: NotionTheme.space5) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(themedIcon)
                    .frame(width: 24)
                Text(label)
                    .font(NotionFont.small())
                    .foregroundStyle(themeStore.isEnabled ? Color.white : Color.inkPrimary)
            }
        }
        .tint(themedTint)
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 8)
        .accessibilityLabel("将\(label)设为必填字段")
    }

    // MARK: - 同步与数据段

    private var syncDataSection: some View {
        SettingsSection(title: "同步与数据", icon: "arrow.triangle.2.circlepath") {
            VStack(spacing: 0) {
                navRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "同步状态",
                    rightText: appState.data.pendingCount == 0 ? "已同步" : "\(appState.data.pendingCount) 待上传",
                    accessibilityHint: "查看同步队列、错误详情，并可从飞书拉取"
                ) {
                    showSyncStatus = true
                }
                rowDivider
                navRow(
                    icon: "tray.and.arrow.up",
                    title: "数据导入 / 导出",
                    accessibilityHint: "导出 CSV / JSON，或从其他 App 导入"
                ) {
                    showDataIO = true
                }
                rowDivider
                navRow(
                    icon: "sparkles",
                    title: "账单总结",
                    rightText: summaryRightText,
                    accessibilityHint: "查看 LLM 生成的周/月/年情绪化复盘"
                ) {
                    showSummaryList = true
                }
            }
        }
    }

    // MARK: - 隐私段

    private var privacySection: some View {
        SettingsSection(title: "隐私", icon: "lock.shield") {
            VStack(spacing: 0) {
                Toggle(isOn: $privacyAmountMask) {
                    HStack(spacing: NotionTheme.space5) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(themedIcon)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("金额脱敏显示")
                                .font(NotionFont.body())
                                .foregroundStyle(themeStore.isEnabled ? Color.white : Color.inkPrimary)
                            Text("V2 开放 · 首页与列表金额显示 ¥•••")
                                .font(NotionFont.micro())
                                .foregroundStyle(themedTertiary)
                        }
                    }
                }
                .tint(themedTint)
                .disabled(true)
                .padding(.horizontal, NotionTheme.space5)
                .padding(.vertical, 12)
                .accessibilityLabel("金额脱敏显示（V2 开放）")
            }
        }
    }

    // MARK: - 关于段

    private var aboutSection: some View {
        SettingsSection(title: "关于", icon: "info.circle") {
            VStack(spacing: 0) {
                SettingsRow(
                    icon: "info.circle",
                    title: "版本",
                    valueText: appVersion
                )
                rowDivider
                DisclosureGroup(isExpanded: $diagnosticsExpanded) {
                    VStack(spacing: 0) {
                        rowDivider
                        SettingsRow(
                            icon: "doc.badge.gearshape",
                            title: "配置文件",
                            valueText: AppConfig.shared.sourceDescription
                        )
                        rowDivider
                        feishuConfigRow
                        ForEach(AppConfig.shared.configurationSummary(), id: \.name) { item in
                            rowDivider
                            HStack(spacing: NotionTheme.space5) {
                                Image(systemName: item.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(item.ok ? Color.statusSuccess : Color.statusWarning)
                                    .frame(width: 24)
                                Text(item.name)
                                    .font(NotionFont.body())
                                    .foregroundStyle(themeStore.isEnabled ? Color.white : Color.inkPrimary)
                                Spacer()
                                Text(item.ok ? "已配置" : "未配置")
                                    .font(NotionFont.small())
                                    .foregroundStyle(item.ok ? Color.statusSuccess : Color.statusWarning)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, NotionTheme.space5)
                            .padding(.vertical, 14)
                        }
                    }
                } label: {
                    HStack(spacing: NotionTheme.space5) {
                        Image(systemName: "stethoscope")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(themedIcon)
                            .frame(width: 24)
                        Text("配置诊断")
                            .font(NotionFont.body())
                            .foregroundStyle(themeStore.isEnabled ? Color.white : Color.inkPrimary)
                    }
                }
                .tint(themedTertiary)
                .padding(.horizontal, NotionTheme.space5)
                .padding(.vertical, 14)
            }
        }
    }

    private var feishuConfigRow: some View {
        let ok = FeishuConfig.isConfigured
        return HStack(spacing: NotionTheme.space5) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(ok ? Color.statusSuccess : Color.statusWarning)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("飞书多维表格")
                    .font(NotionFont.body())
                    .foregroundStyle(themeStore.isEnabled ? Color.white : Color.inkPrimary)
                if ok, FeishuConfig.hasBitable, let url = FeishuConfig.bitableURL, !url.isEmpty {
                    Text(url)
                        .font(NotionFont.micro())
                        .foregroundStyle(themedTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Text(ok ? "已配置" : "未配置")
                .font(NotionFont.small())
                .foregroundStyle(ok ? Color.statusSuccess : Color.statusWarning)
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 14)
    }

    // MARK: - Helpers

    private func navRow(icon: String,
                        title: String,
                        rightText: String? = nil,
                        accessibilityHint: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: NotionTheme.space5) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(themedIcon)
                    .frame(width: 24)
                Text(title)
                    .font(NotionFont.body())
                    .foregroundStyle(themeStore.isEnabled ? Color.white : Color.inkPrimary)
                Spacer()
                if let rightText {
                    Text(rightText)
                        .font(NotionFont.small())
                        .foregroundStyle(themedSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(themedTertiary)
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSoft)
        .accessibilityHint(accessibilityHint)
    }

    @ViewBuilder
    private var rowDivider: some View {
        // v5 一致性：两套主题都显示行内 hairline；仅颜色随主题
        Rectangle()
            .fill(themeStore.isEnabled ? Color.white.opacity(0.06) : Color.divider)
            .frame(height: NotionTheme.borderWidth)
            .padding(.leading, NotionTheme.space6 + 24 + NotionTheme.space5)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    // MARK: - Persistence

    private func loadFromStorage() {
        biometricEnabled = settings.bool(SettingsKey.biometricEnabled)
        backTapEnabled   = settings.bool(SettingsKey.backTapEnabled)
        if let arr: [String] = settings.getJSON(key: SettingsKey.voiceRequiredFields, as: [String].self) {
            voiceRequiredFields = Set(arr)
        }
        if let raw = settings.get(key: SettingsKey.recordsListLayout) {
            if let layout = RecordsLayout(rawValue: raw) {
                recordsListLayout = layout
            } else {
                // 旧版本可能存过已废弃的 "stack" 值——清理回写默认值
                settings.set(key: SettingsKey.recordsListLayout,
                             value: RecordsLayout.list.rawValue)
            }
        }
        do {
            let records = try SQLiteRecordRepository.shared.list(.init(
                ledgerId: DefaultSeeder.defaultLedgerId,
                includesDeleted: false,
                limit: 10000
            ))
            recordCount = records.count
        } catch {
            recordCount = 0
        }

        // 读取首次启动日期计算"加入 N 天"（AppState.bootstrap 在首次启动时写入；
        // 旧用户升级后没有该键，第一次打开设置页时不展示，等下次 bootstrap 写入）
        if let raw = settings.get(key: SettingsKey.firstLaunchDate),
           let ms = Int64(raw) {
            let firstLaunch = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
            let cal = Calendar.current
            let d0 = cal.startOfDay(for: firstLaunch)
            let d1 = cal.startOfDay(for: Date())
            let days = max(0, cal.dateComponents([.day], from: d0, to: d1).day ?? 0)
            joinedDaysText = days == 0 ? "今天加入" : "加入 \(days) 天"
        } else {
            joinedDaysText = ""
        }
    }

    private func persistRequiredFields() {
        settings.setJSON(key: SettingsKey.voiceRequiredFields, value: Array(voiceRequiredFields))
    }
}

// MARK: - Reusable building blocks

struct SettingsSection<Content: View>: View {
    let title: String
    /// 分组左侧 SF Symbol（v3.1 参考图：所有分组都带小图标）
    let icon: String?
    /// 是否给内容包一层 cardSurface（外观切换器场景内部已是独立卡片，不需要再包）
    let wrapInCard: Bool
    let content: () -> Content
    @ObservedObject private var themeStore = LGAThemeStore.shared
    init(title: String,
         icon: String? = nil,
         wrapInCard: Bool = true,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.wrapInCard = wrapInCard
        self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            // 全主题统一：13pt / Regular / 灰色 + 左侧小图标（参考图 09-settings 风格）
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(themeStore.isEnabled
                                         ? LGATheme.textSecondary
                                         : Color.inkTertiary)
                }
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(themeStore.isEnabled
                                     ? LGATheme.textSecondary
                                     : Color.inkTertiary)
            }
            .padding(.leading, NotionTheme.space3)

            if wrapInCard {
                content()
                    .cardSurface(cornerRadius: 14)
            } else {
                content()
            }
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let valueText: String
    @ObservedObject private var themeStore = LGAThemeStore.shared
    var body: some View {
        let isLGA = themeStore.isEnabled
        let iconColor: Color = isLGA ? LGATheme.textSecondary : Color.inkSecondary
        let titleColor: Color = isLGA ? Color.white : Color.inkPrimary
        let valueColor: Color = isLGA ? LGATheme.textSecondary : Color.inkSecondary
        return HStack(spacing: NotionTheme.space5) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(iconColor)
                .frame(width: 24)
            Text(title)
                .font(NotionFont.body())
                .foregroundStyle(titleColor)
            Spacer()
            Text(valueText)
                .font(NotionFont.small())
                .foregroundStyle(valueColor)
                .lineLimit(1)
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 14)
    }
}

/// Settings 在 Tab 模式下使用的 ScrollView 包装：
/// 用一个独立 View 获取 TabBarVisibility（仅 Tab 模式注入），
/// 避免 SettingsView 本体在非 Tab 模式下 crash。
private struct ScrollViewWithTabBarTracking<Content: View>: View {
    @EnvironmentObject private var tabBarVisibility: TabBarVisibility
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            content()
        }
        .trackScrollForTabBar(tabBarVisibility)
    }
}
