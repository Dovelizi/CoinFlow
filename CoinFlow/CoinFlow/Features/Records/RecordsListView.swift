//  RecordsListView.swift
//  CoinFlow · M3.3
//
//  M3.3 升级：
//  - 布局切换器（List/Grid）已迁移到设置中（settings.records.list_layout）—— Stack 已废弃
//  - 行点击 → RecordDetailSheet（编辑）
//  - nav 右上 ⋯ 菜单 → 分类管理
//  - 整页统一一种布局，由 Settings 控制；仅保留 list / grid

import SwiftUI
import PhotosUI

/// `sheet(item:)` 需要 Identifiable；包一层以便驱动确认页 sheet。
/// M7-Fix20：id 使用 PhotoCaptureCoordinator.captureId（每次 handle 重置的 UUID），
/// sheet 会完整重建 → CaptureConfirmView 内部 OCR/LLM 流水线从头跑
private struct CaptureSession: Identifiable {
    let id: UUID
    let image: UIImage
}

struct RecordsListView: View {

    /// M7 [G2]：外部 coordinator（可选注入）；从 Home 进入时带上，以便消费 pendingAction
    @ObservedObject var coordinator: MainCoordinator

    @MainActor
    init(coordinator: MainCoordinator? = nil) {
        self.coordinator = coordinator ?? MainCoordinator()
    }

    @StateObject private var vm = RecordsListViewModel()
    @StateObject private var captureCoord = PhotoCaptureCoordinator()
    @EnvironmentObject private var tabBarVisibility: TabBarVisibility
    @State private var showNewRecord = false
    @State private var showVoice = false
    @State private var detailRecord: Record?
    @State private var showCategoryManager = false
    @State private var showSettings = false
    /// Menu 中"识别截图"触发的 PhotosPicker
    @State private var showCapturePicker = false
    /// 全页统一布局；onAppear 从 settings 读取
    @State private var currentLayout: RecordsLayout = .list
    /// M7 [01-2]：月份 popover 显隐
    @State private var showMonthPicker: Bool = false
    /// M7 [01-3]：搜索 inline 栏显隐（搜索内容在 vm.searchQuery）
    @State private var showSearchBar: Bool = false
    /// 待确认删除的记录（左滑触发；nil 表示无 pending）
    @State private var pendingDeleteRecord: Record?
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackgroundLayer(kind: .records)
                VStack(spacing: 0) {
                    navBar
                    // M7 [01-3]：搜索栏以 inline transition 插入 nav 下方
                    if showSearchBar {
                        searchBarInline
                            .transition(Motion.dropDown)
                    }
                    content
                }

                // M7 [01-2]：月份 picker popover 叠层
                if showMonthPicker {
                    monthPickerOverlay
                        .transition(.opacity.animation(Motion.smooth))
                        .zIndex(6)
                }
            }
            // 真机性能修复：删除底层全屏 .blur(8)（与 sheet 的 .ultraThinMaterial 双重模糊导致掉帧）
            .navigationBarHidden(true)
            .enableInteractivePop()
            .navigationDestination(isPresented: $showCategoryManager) {
                CategoryListView()
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showNewRecord) {
                NewRecordModal(onSaved: { _ in
                    showNewRecord = false
                })
            }
            // M7-Fix15：改回 .sheet（录音已从长按改为点击切换，无需规避 sheet 下拉手势）
            .sheet(isPresented: $showVoice) {
                VoiceWizardContainerView()
            }
            .sheet(item: $detailRecord) { record in
                RecordDetailSheet(record: record)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: Binding(
                get: { captureCoord.sourceImage.map { CaptureSession(id: captureCoord.captureId, image: $0) } },
                set: { _ in captureCoord.reset() }
            )) { session in
                // M7-Fix20：截图 → CaptureConfirmView 内部跑 OCR + LLM
                CaptureConfirmView(
                    sourceImage: session.image,
                    scrollToBottom: true,
                    onSaved: { _ in captureCoord.reset() },
                    onRetake: {
                        captureCoord.retake()
                    }
                )
            }
            .onChange(of: captureCoord.pickerItem) { item in
                Task { await captureCoord.handle(item: item) }
            }
            .photosPicker(isPresented: $showCapturePicker,
                          selection: $captureCoord.pickerItem,
                          matching: .images,
                          photoLibrary: .shared())
            .onAppear {
                consumePendingAction()
                loadLayoutFromSettings()
            }
            .onChange(of: coordinator.pendingAction) { _ in
                consumePendingAction()
            }
            // 左滑删除确认弹窗（ActionSheet 样式）
            .confirmationDialog(
                "删除这笔流水？",
                isPresented: Binding(
                    get: { pendingDeleteRecord != nil },
                    set: { if !$0 { pendingDeleteRecord = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeleteRecord
            ) { record in
                Button("都删除（本地 + 云端）", role: .destructive) {
                    vm.delete(record, localOnly: false)
                    pendingDeleteRecord = nil
                }
                Button("仅删除本地") {
                    vm.delete(record, localOnly: true)
                    pendingDeleteRecord = nil
                }
                Button("取消", role: .cancel) {
                    pendingDeleteRecord = nil
                }
            } message: { _ in
                Text("「仅删除本地」不会影响飞书多维表格中的记录；下次从飞书拉取时该记录会被重新同步到本地。")
            }
        }
    }

    /// 从 Settings 读取流水列表布局；用户在设置中切换后回到本页 onAppear 触发重读
    /// 旧版本可能存过已废弃的 "stack" 值；解析失败时保持默认 .list
    private func loadLayoutFromSettings() {
        let repo = SQLiteUserSettingsRepository.shared
        if let raw = repo.get(key: SettingsKey.recordsListLayout) {
            if let layout = RecordsLayout(rawValue: raw) {
                currentLayout = layout
            } else {
                // 旧 stack 值无效 → 清理为 list
                repo.set(key: SettingsKey.recordsListLayout,
                         value: RecordsLayout.list.rawValue)
                currentLayout = .list
            }
        }
    }

    /// M7 [G2]：消费 Home → Records 的入口意图
    private func consumePendingAction() {
        guard let action = coordinator.pendingAction else { return }
        switch action {
        case .photoPicker:
            coordinator.consume(.photoPicker)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                showCapturePicker = true
            }
        case .voiceRecord:
            coordinator.consume(.voiceRecord)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                showVoice = true
            }
        case .newManualRecord:
            coordinator.consume(.newManualRecord)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                showNewRecord = true
            }
        }
    }

    // MARK: - Nav Bar
    //
    // 设计基线（design/screens/01-records-list/main-light.png）：
    // - 左：日历 icon + chevron.down（月份切换器）
    // - 中：「{month} 月」h2 + 「月收支记录」micro 副标题
    // - 右：放大镜（搜索 toggle）+ 加号
    // 麦克风/截图/分类管理/设置入口：原 4 颗按钮删除，统一收编到加号 Menu（长按弹出）
    private var navBar: some View {
        ZStack {
            // 中央双层标题：M7-Fix2 显示选中的月份数字
            VStack(spacing: 2) {
                Text(navTitleText)
                    .font(NotionFont.h2())
                    .foregroundStyle(Color.inkPrimary)
                Text("月收支记录")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // 左：月份切换器
            HStack {
                Button {
                    Haptics.tap()
                    withAnimation(Motion.smooth) {
                        showMonthPicker.toggle()
                        if showMonthPicker { showSearchBar = false }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "calendar")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(Color.inkPrimary)
                        Image(systemName: showMonthPicker ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.inkPrimary)
                            // chevron 旋转过渡
                            .animation(Motion.snap, value: showMonthPicker)
                    }
                    .frame(height: 36)
                    .padding(.horizontal, NotionTheme.space4)
                    .background(
                        RoundedRectangle(cornerRadius: NotionTheme.radiusMD,
                                         style: .continuous)
                            .fill(showMonthPicker ? Color.hoverBgStrong : Color.hoverBg)
                            .animation(Motion.snap, value: showMonthPicker)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressableIcon)
                .accessibilityLabel("切换月份")
                Spacer()
            }
            .padding(.leading, NotionTheme.space5)

            // 右：搜索（inline toggle） + 加号 Menu
            HStack(spacing: NotionTheme.space3) {
                Spacer()
                Button {
                    Haptics.tap()
                    withAnimation(Motion.smooth) {
                        showSearchBar.toggle()
                        if showSearchBar {
                            showMonthPicker = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                searchFocused = true
                            }
                        } else {
                            searchFocused = false
                            vm.searchQuery = ""
                        }
                    }
                } label: {
                    Image(systemName: showSearchBar ? "xmark" : "magnifyingglass")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color.inkPrimary)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: NotionTheme.radiusMD,
                                             style: .continuous)
                                .fill(showSearchBar ? Color.hoverBgStrong : Color.hoverBg)
                                .animation(Motion.snap, value: showSearchBar)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableIcon)
                .accessibilityLabel(showSearchBar ? "关闭搜索" : "搜索流水")

                Menu {
                    Button {
                        showNewRecord = true
                    } label: {
                        Label("手动新建", systemImage: "plus")
                    }
                    Button {
                        showVoice = true
                    } label: {
                        Label("语音记账", systemImage: "mic.fill")
                    }
                    Button {
                        // 截图识别 → PhotosPicker；通过 captureCoord.pickerItem 触发
                        // 这里不能直接弹 PhotosPicker（需要 SwiftUI 修饰符），通过设置 flag 让 .photosPicker 拉起
                        showCapturePicker = true
                    } label: {
                        Label("识别截图", systemImage: "doc.text.viewfinder")
                    }
                    Divider()
                    Button {
                        showCategoryManager = true
                    } label: {
                        Label("分类管理", systemImage: "folder")
                    }
                    Button {
                        showSettings = true
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color.inkPrimary)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: NotionTheme.radiusMD,
                                             style: .continuous)
                                .fill(Color.hoverBg)
                        )
                } primaryAction: {
                    showNewRecord = true
                }
                .accessibilityLabel("新建（长按显示更多）")
            }
            .padding(.trailing, NotionTheme.space5)
        }
        .frame(height: NotionTheme.topbarHeight)
        .background(Color.appCanvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.divider)
                .frame(height: NotionTheme.borderWidth)
        }
    }

    /// M7-Fix2：当前月份筛选展示文本（"5 月"）
    private var navTitleText: String {
        if let ym = vm.selectedYearMonth {
            return "\(ym.month) 月"
        }
        return "全部"
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let err = vm.loadError {
            errorView(err)
        } else if vm.groups.isEmpty {
            EmptyRecordsView()
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: NotionTheme.space6, pinnedViews: []) {
                // 滚动方向探针（0 高度，供 TabBarVisibility 读取偏移）
                Color.clear.frame(height: 0).tabBarScrollAnchor()
                InlineStatsBar(expense: vm.totalExpense, income: vm.totalIncome)
                    .padding(.horizontal, NotionTheme.space5)
                    .padding(.top, NotionTheme.space4)

                ForEach(vm.groups) { group in
                    section(for: group)
                }
            }
            .padding(.bottom, 100)
        }
        .trackScrollForTabBar(tabBarVisibility)
    }

    private func section(for group: DayGroup) -> some View {
        let net = vm.dayNet(for: group)

        return VStack(alignment: .leading, spacing: NotionTheme.space4) {
            // 段头：左 H3 文案 + 当日合计（LayoutSwitcher 已迁至设置页）
            HStack(spacing: NotionTheme.space4) {
                Text(group.headerText)
                    .font(NotionFont.h3())
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
                Text(daySummaryText(net))
                    .font(NotionFont.amount(size: 13))
                    .foregroundStyle(Color.inkTertiary)
            }
            .padding(.horizontal, NotionTheme.space5)

            // 内容区按全局布局渲染（Settings 控制）
            switch currentLayout {
            case .list:
                listContent(for: group)
            case .grid:
                RecordGridView(
                    records: group.records,
                    categoryLookup: { vm.category(for: $0) },
                    onTap: { detailRecord = $0 }
                )
            }
        }
    }

    private func listContent(for group: DayGroup) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(group.records.enumerated()), id: \.element.id) { idx, record in
                RecordRow(record: record, category: vm.category(for: record))
                    .contentShape(Rectangle())
                    .background(
                        // 行级按下反馈：仅高亮背景，不缩放（避免相邻 cell 抖动）
                        Color.clear
                    )
                    .onTapGesture {
                        Haptics.tap()
                        detailRecord = record
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDeleteRecord = record
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    // M7 [01-6]：leading swipe → AA 结算（V2 真开放；当前显示"即将上线"）
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            // V2：打开 AA 结算 sheet
                        } label: {
                            Label("AA", systemImage: "person.2")
                        }
                        .tint(Color.accentBlue)
                    }
                if idx < group.records.count - 1 {
                    Divider()
                        .background(Color.divider)
                        .padding(.leading, NotionTheme.space5 + 32 + NotionTheme.space5)
                }
            }
        }
        .cardSurface(cornerRadius: 14)
        .padding(.horizontal, NotionTheme.space5)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: NotionTheme.space5) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(Color.inkTertiary)
            Text("加载失败")
                .font(NotionFont.h3())
                .foregroundStyle(Color.inkPrimary)
            Text(msg)
                .font(NotionFont.small())
                .foregroundStyle(Color.inkTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, NotionTheme.space7)
            Button("重试") { vm.reload() }
                .font(NotionFont.body())
                .foregroundStyle(Color.accentBlue)
                .buttonStyle(.pressable)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - M7 [01-3] Inline search bar

    private var searchBarInline: some View {
        HStack(spacing: NotionTheme.space3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.inkTertiary)
            // M7-Fix2：绑定到 vm.searchQuery，didSet 触发 reload
            TextField("搜索备注、金额、分类…", text: $vm.searchQuery)
                .font(NotionFont.body())
                .foregroundStyle(Color.inkPrimary)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !vm.searchQuery.isEmpty {
                Button {
                    Haptics.tap()
                    vm.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.inkTertiary)
                }
                .buttonStyle(.pressableIcon)
                .accessibilityLabel("清除搜索关键词")
            }
        }
        .padding(.horizontal, NotionTheme.space4)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusMD, style: .continuous)
                .fill(Color.hoverBg)
        )
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, NotionTheme.space3)
        .background(Color.appCanvas)
    }

    // MARK: - M7 [01-2] Month picker popover

    private var monthPickerOverlay: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.30)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(Motion.smooth) { showMonthPicker = false }
                }
            VStack(spacing: 0) {
                // 留 navBar 高度
                Color.clear.frame(height: NotionTheme.topbarHeight + 8)
                monthGridCard
                    .padding(.horizontal, NotionTheme.space5)
                Spacer()
            }
        }
    }

    private var monthGridCard: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            HStack {
                Text("选择月份")
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
                Text(String(Calendar.current.component(.year, from: Date())))
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkTertiary)
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.top, NotionTheme.space5)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: NotionTheme.space3), count: 4),
                      spacing: NotionTheme.space3) {
                ForEach(1...12, id: \.self) { m in
                    monthCell(m)
                }
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.bottom, NotionTheme.space5)
        }
        .cardSurface(cornerRadius: 14,
                     notionFill: Color.surfaceOverlay,
                     notionStroke: Color.border)
    }

    @ViewBuilder
    private func monthCell(_ month: Int) -> some View {
        // M7-Fix2：高亮已选月；点击真过滤到 vm.selectedYearMonth
        let selectedMonth = vm.selectedYearMonth?.month
        let year = vm.selectedYearMonth?.year ?? Calendar.current.component(.year, from: Date())
        let isSelected = selectedMonth == month
        Button {
            Haptics.select()
            vm.selectedYearMonth = YearMonth(year: year, month: month)
            withAnimation(Motion.smooth) { showMonthPicker = false }
        } label: {
            Text("\(month) 月")
                .font(NotionFont.body())
                .foregroundStyle(isSelected ? Color.inkPrimary : Color.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                        .fill(isSelected ? Color.accentBlueBG : Color.hoverBg.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                        .stroke(isSelected ? Color.accentBlue : Color.clear,
                                lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(haptic: false))
        .accessibilityLabel("\(month) 月\(isSelected ? "，已选中" : "")")
    }

    /// 段头右侧"¥xxx 当日合计"文案。按用户规范去掉正负号，方向由 daySummaryColor 表达。
    private func daySummaryText(_ net: Decimal) -> String {
        "¥" + AmountFormatter.display(net < 0 ? -net : net)
    }

    /// 当日净额颜色：支出多(net<0) = 红，收入多(net>0) = 绿，持平 = 灰。
    private func daySummaryColor(_ net: Decimal) -> Color {
        if net > 0 { return DirectionColor.amountForeground(kind: .income) }
        if net < 0 { return DirectionColor.amountForeground(kind: .expense) }
        return Color.inkTertiary
    }
}

extension Record {}
// 注：Record 已在 Data/Models/Record.swift 中实现 Identifiable；此处空 extension
// 仅作为「本视图依赖 Record.id 用作 sheet(item:)」的文档锚点，无运行时效应。

#if DEBUG
#Preview {
    RecordsListView(coordinator: MainCoordinator())
        .preferredColorScheme(.dark)
}
#endif
