//  HomeMainView.swift
//  CoinFlow · M6 后期 · 首页
//
//  设计基线：design/screens/00-home/{main,empty,quick-action}-light.png
//  - brandHero（钱袋 icon + CoinFlow wordmark + slogan）
//  - 月度净额 hero 数字（56pt bold rounded）+ KPI 三栏（收入/支出/今日）
//  - 两个入口卡（截图记账 / 语音记账）
//  - 最近记录预览（最多 3 行；为空显示 emptyRecentHint）
//
//  入口动作：
//  - 截图记账 → 弹 quickAction sheet：两项「从相册选择截图」/「拍照获取」
//  - 语音记账 → 直接在首页弹 VoiceWizardContainerView sheet
//  记录保存后自动 reload 最近记录 + KPI 数据

import SwiftUI
import PhotosUI
import Combine

/// `sheet(item:)` 需要 Identifiable 载体
/// M7-Fix20：id 使用 PhotoCaptureCoordinator.captureId（每次 handle 重置的 UUID），
/// sheet 会完整重建 → CaptureConfirmView 内部 @State 全部重置 → OCR/LLM 流水线从头跑
private struct HomeCaptureSession: Identifiable {
    let id: UUID
    let image: UIImage
}

struct HomeMainView: View {

    /// 切换到指定 tab 的回调（由 MainTabView 注入；语音/截图入口直接首页处理，保留 tab 切换接口）
    let switchTab: (AppTab) -> Void
    /// M7 [G2]：全局意图 coordinator（由 MainTabView 注入）；保留引用但 M7 问题 2 修复后主路径不再走
    @ObservedObject var coordinator: MainCoordinator

    @StateObject private var vm = HomeViewModel()
    @StateObject private var captureCoord = PhotoCaptureCoordinator()
    /// M8-Fix 冷启动竞态：观察 appState.database 切换到 ready 后才 reload
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var tabBarVisibility: TabBarVisibility
    @Environment(\.colorScheme) private var scheme
    /// M7 [00-1]：长按截图卡展示的 ActionSheet 叠层
    @State private var showQuickAction = false
    /// M7 修复问题 2：直接在首页弹语音 sheet / PhotosPicker
    @State private var showVoice = false
    @State private var showPhotosPicker = false
    /// 拍照记账：UIImagePickerController camera sheet
    @State private var showCamera = false
    /// M10-Fix4 · 被 banner 唤出的浮窗（仅 HomeMainView 局部 state 即可，
    /// 因为浮窗只在用户点击 banner 时即时弹出；推送源数据在 AppState.pendingSummaryPush）
    @State private var summaryFloating: BillsSummary?

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackgroundLayer(kind: .home)
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: NotionTheme.space7) {
                            // 滚动方向探针（0 高度，供 TabBarVisibility 读取偏移）
                            Color.clear.frame(height: 0).tabBarScrollAnchor()
                            brandHero
                            heroData
                            entriesRow
                            // M7 [00-3]：loadError inline 渲染
                            if let err = vm.loadError {
                                loadErrorCard(err)
                            }
                            if vm.recentRecords.isEmpty {
                                emptyRecentHint
                            } else {
                                recentRecords
                            }
                        }
                        .padding(.horizontal, NotionTheme.space5)
                        .padding(.top, NotionTheme.space6)
                        // 底部留白给浮动 tab bar
                        .padding(.bottom, 100)
                    }
                    .trackScrollForTabBar(tabBarVisibility)
                }
            }
            // 真机性能修复：之前对底层主界面加 .blur(8) 跟随 sheet 动画，
            // 真机每帧整屏高斯模糊 + sheet 自带 .ultraThinMaterial 双重模糊 → 掉帧。
            // 删除底层 .blur，由 sheet 的真玻璃负责毛玻璃观感。
            .navigationBarHidden(true)
            .enableInteractivePop()
            .onAppear { vm.reload() }
            // M8-Fix：冷启动时 .onAppear 早于 .task 里的 AppState.bootstrap()，
            // DatabaseManager.handle 还是 nil，会抛 "DB handle nil"。
            // HomeViewModel.reload() 已经会 guard isHandleOpen；这里额外监听
            // database 状态切 ready 再触发一次，确保首帧看到正常数据。
            .onChange(of: appState.database) { newValue in
                if case .ready = newValue {
                    vm.reload()
                }
            }
            // 订阅 ScreenshotInbox：快捷指令 Intent 把截图放进系统剪贴板后，
            // CoinFlowApp 在 scenePhase==.active 时读取并通过 imageSubject 发布；
            // 这里直接喂给 captureCoord 触发现有 CaptureConfirmView sheet。
            .onReceive(ScreenshotInbox.shared.imageSubject) { image in
                Task { await captureCoord.handle(image: image) }
            }
            // quickAction 改走系统 sheet（presentationDetents），天然盖住底部 tab bar
            .sheet(isPresented: $showQuickAction) {
                quickActionSheetContent
            }
            // 拍照记账：fullScreenCover 承载 UIImagePickerController (camera)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    showCamera = false
                    if let image { Task { await captureCoord.handle(image: image) } }
                }
                .ignoresSafeArea()
            }
            // M7 修复问题 2：首页直接承载语音 sheet + 截图 Photos picker + 确认页
            // M7-Fix15：改回 .sheet，因录音交互已改为"点击切换"(Siri 风)，不再有长按手势冲突；
            //          录音态半屏（medium），后续流程全屏（large），由容器内部动态切换
            .sheet(isPresented: $showVoice, onDismiss: { vm.reload() }) {
                VoiceWizardContainerView()
            }
            .photosPicker(isPresented: $showPhotosPicker,
                          selection: $captureCoord.pickerItem,
                          matching: .images,
                          photoLibrary: .shared())
            .onChange(of: captureCoord.pickerItem) { item in
                Task { await captureCoord.handle(item: item) }
            }
            .sheet(item: Binding(
                get: { captureCoord.sourceImage.map { HomeCaptureSession(id: captureCoord.captureId, image: $0) } },
                set: { _ in captureCoord.reset() }
            ), onDismiss: { vm.reload() }) { session in
                // M7-Fix20：截图 → CaptureConfirmView 内部跑 OCR + LLM
                CaptureConfirmView(
                    sourceImage: session.image,
                    scrollToBottom: false,
                    onSaved: { _ in
                        captureCoord.reset()
                        vm.reload()
                    },
                    onRetake: {
                        captureCoord.retake()
                    }
                )
            }
        }
        // M10-Fix4 · 首页推送 banner
        // 数据源：AppState.pendingSummaryPush（跨 tab 保活）
        // 关闭策略由 BillsSummaryPushBanner 内部承载：✕ / 点击 3 次 / 10 分钟超时
        .safeAreaInset(edge: .top, spacing: 0) {
            Group {
                if let s = appState.pendingSummaryPush {
                    BillsSummaryPushBanner(
                        push: BillsSummaryPush(s),
                        onTap: {
                            // 仅唤出浮窗，不清 pendingSummaryPush；
                            // banner 是否消失由其内部"3 次 / 10min / ✕"策略决定
                            summaryFloating = s
                        },
                        onDismiss: {
                            withAnimation(Motion.tabSwitch) {
                                appState.pendingSummaryPush = nil
                            }
                        }
                    )
                    .id(s.id)   // 新 push 触发 view 重建 + 重置计时
                }
            }
            .animation(Motion.smooth, value: appState.pendingSummaryPush?.id)
        }
        // 浮窗 overlay：由 banner 点击触发；关闭时清 state
        .overlay {
            if let s = summaryFloating {
                SummaryFloatingCard(summary: s) {
                    withAnimation(Motion.snap) {
                        summaryFloating = nil
                    }
                }
                .zIndex(60)
                .transition(.opacity)
            }
        }
        .animation(Motion.snap, value: summaryFloating?.id)
    }

    // MARK: - Brand hero

    private var brandHero: some View {
        VStack(spacing: NotionTheme.space4) {
            Image(systemName: "bag")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Color.inkPrimary)
            VStack(spacing: 4) {
                Text("CoinFlow")
                    .font(.custom("PingFangSC-Semibold", size: 28))
                    .foregroundStyle(Color.inkPrimary)
                    .tracking(-1)
                Text("一句话，一张图，一笔账")
                    .font(.custom("PingFangSC-Regular", size: 13))
                    .foregroundStyle(Color.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, NotionTheme.space7)
    }

    // MARK: - Hero data（月度净额 + KPI 三栏）

    private var heroData: some View {
        VStack(spacing: NotionTheme.space5) {
            VStack(spacing: 4) {
                Text(monthlyHeaderText)
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
                if vm.monthlyNet == 0 {
                    Text("¥0")
                        .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.inkTertiary)
                    Text("今天还没记账，从下方开始 ↓")
                        .font(NotionFont.small())
                        .foregroundStyle(Color.inkSecondary)
                } else {
                    // 用单个 Text 拼接 ¥ 与数字 → minimumScaleFactor 才能整组等比例缩小
                    // ¥ 与数字字重统一 .bold（全局规则 §AmountSymbolStyle）
                    // 字号 ¥ = 56 × 0.64 ≈ 36，与统计页 hero 一致
                    let amountStr = AmountFormatter.display(vm.monthlyNet < 0 ? -vm.monthlyNet : vm.monthlyNet)
                    let digitSize: CGFloat = 56
                    let symbolSize = digitSize * AmountSymbolStyle.symbolScale
                    let attr: AttributedString = {
                        var a = AttributedString("¥")
                        a.font = .system(size: symbolSize, weight: .bold, design: .rounded)
                        a.foregroundColor = netColor
                        var n = AttributedString(amountStr)
                        n.font = .system(size: digitSize, weight: .bold, design: .rounded).monospacedDigit()
                        n.foregroundColor = netColor
                        a.append(n)
                        return a
                    }()
                    Text(attr)
                        .numericTransition()
                        .amountGroupAutoFit(scaleFloor: 0.3)   // 56pt → 最小 ~17pt
                        .padding(.horizontal, NotionTheme.space5)
                }
            }
            HStack(spacing: NotionTheme.space5) {
                miniKPI("收入", "¥" + AmountFormatter.display(vm.monthlyIncome),
                        DirectionColor.amountForeground(kind: .income))
                vDivider
                miniKPI("支出", "¥" + AmountFormatter.display(vm.monthlyExpense),
                        DirectionColor.amountForeground(kind: .expense))
                vDivider
                miniKPI("今日", "\(vm.todayCount) 笔", Color.inkPrimary)
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.vertical, NotionTheme.space4)
            .cardSurface(cornerRadius: 14, notionFill: Color.hoverBgStrong)
        }
    }

    private var monthlyHeaderText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M"
        return "本月净增 · \(f.string(from: Date())) 月"
    }

    private var netColor: Color {
        vm.monthlyNet > 0
            ? DirectionColor.amountForeground(kind: .income)
            : DirectionColor.amountForeground(kind: .expense)
    }

    @ViewBuilder
    private func miniKPI(_ label: String, _ value: String, _ tone: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(tone)
                .amountAutoFit(base: 14, scaleFloor: 0.4)
            Text(label)
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var vDivider: some View {
        Rectangle().fill(Color.divider).frame(width: 0.5, height: 20)
    }

    // MARK: - Entries

    private var entriesRow: some View {
        HStack(spacing: NotionTheme.space4) {
            // 截图记账：弹 quickAction sheet，内含「从相册选择」+「拍照获取」两项
            entryCard(
                icon: "camera.viewfinder",
                title: "截图记账",
                subtitle: "OCR 自动识别",
                hint: "从相册选择 / 拍照",
                onTap: {
                    showQuickAction = true
                }
            )
            entryCard(
                icon: "mic.fill",
                title: "语音记账",
                subtitle: "一句话多笔",
                hint: "按住说一句",
                onTap: {
                    showVoice = true
                }
            )
        }
    }

    @ViewBuilder
    private func entryCard(icon: String, title: String, subtitle: String,
                           hint: String,
                           onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(spacing: NotionTheme.space5) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.inkPrimary)
                VStack(spacing: 4) {
                    Text(title)
                        .font(.custom("PingFangSC-Semibold", size: 17))
                        .foregroundStyle(Color.inkPrimary)
                    Text(subtitle)
                        .font(NotionFont.small())
                        .foregroundStyle(Color.inkSecondary)
                }
                .multilineTextAlignment(.center)
                Spacer(minLength: 0)
                Rectangle().fill(Color.divider).frame(height: 0.5)
                HStack(spacing: 4) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 9, weight: .regular))
                    Text(hint)
                        .font(.custom("PingFangSC-Regular", size: 10))
                }
                .foregroundStyle(Color.inkTertiary)
            }
            .padding(NotionTheme.space5)
            .frame(maxWidth: .infinity)
            .frame(height: 168)
            .cardSurface(cornerRadius: 14, notionFill: Color.hoverBg)
        }
        .buttonStyle(.pressableSoft)
        .accessibilityLabel("\(title)，\(subtitle)")
        // 真机滚动修复：之前在此挂了一个 LongPressGesture(0.4s)，但所有
        // 调用方都传 onLongPress: nil（永远不触发动作），却会和 ScrollView 的
        // pan 抢手势仲裁 → 用户从这两张大卡片起手向上滑时，0.4s 内 ScrollView
        // 不响应 → 表现为"滑不动"。直接删除该手势。
    }

    // MARK: - Load error card（M7 [00-3]）

    private func loadErrorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: NotionTheme.space3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.dangerRed)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("数据加载出现问题")
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.inkPrimary)
                Text(message)
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(3)
            }
            Spacer()
            Button { vm.reload() } label: {
                Text("重试")
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.accentBlue)
                    .padding(.horizontal, NotionTheme.space3)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                .fill(Color.dangerRed.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                .stroke(Color.dangerRed.opacity(0.3), lineWidth: NotionTheme.borderWidth)
        )
    }

    // MARK: - Quick action sheet 内容（由系统 .sheet presentationDetents 承载）

    @ViewBuilder
    private var quickActionSheetContent: some View {
        if #available(iOS 16.4, *) {
            actionSheetCard
                .presentationDetents([.height(200)])
                .presentationDragIndicator(.visible)
                .themedPresentationBackground()
        } else {
            actionSheetCard
                .presentationDetents([.height(200)])
                .presentationDragIndicator(.visible)
        }
    }

    private var actionSheetCard: some View {
        VStack(spacing: 0) {
            quickActionRow(
                icon: "photo.on.rectangle.angled",
                title: "从相册选择截图",
                subtitle: "支持微信 / 支付宝 / 银行 App",
                action: {
                    showQuickAction = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        showPhotosPicker = true
                    }
                }
            )
            Rectangle()
                .fill(Color.divider)
                .frame(height: NotionTheme.borderWidth)
                .padding(.leading, NotionTheme.space5 + 28 + NotionTheme.space5)
            quickActionRow(
                icon: "camera",
                title: "拍照获取",
                subtitle: "调用相机拍摄小票 / 账单",
                action: {
                    showQuickAction = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showCamera = true
                    }
                }
            )
        }
        .padding(.top, NotionTheme.space5)
        .frame(maxWidth: .infinity, alignment: .top)
        .themedSheetSurface()
    }

    @ViewBuilder
    private func quickActionRow(icon: String, title: String, subtitle: String,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: NotionTheme.space5) {
                ZStack {
                    RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                        .fill(Color.accentBlueBG)
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentBlue)
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(NotionFont.bodyBold())
                        .foregroundStyle(Color.inkPrimary)
                    Text(subtitle)
                        .font(NotionFont.small())
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableRow)
        .accessibilityLabel(title)
    }

    // MARK: - Recent records

    private var recentRecords: some View {
        // 真机滚动修复：之前用 .tappableCard { ... } 包裹整个 VStack，
        // 该 modifier 内部依赖 simultaneousGesture(DragGesture(minimumDistance: 0))
        // 检测按压，在嵌套 ScrollView 中会与 pan 抢手势仲裁 → 卡片区域无法上下滑。
        // 改用 Button + .pressableSoft：iOS 标准做法，按钮的系统 hit-test 与
        // ScrollView 已被苹果优化协作（手指落下后系统先观察是否移动 → 移动则让 ScrollView 接管，
        // 静止抬手才触发 Button action），既保留按压视觉反馈又不阻塞滚动。
        // 这里直接换 Button 而非改通用 modifier，因为 recentRow 内部纯展示无 NavigationLink。
        Button { switchTab(.records) } label: {
            VStack(spacing: NotionTheme.space4) {
                Text("最近记录")
                    .font(.custom("PingFangSC-Semibold", size: 14))
                    .foregroundStyle(Color.inkPrimary)
                    .frame(maxWidth: .infinity)

                VStack(spacing: 0) {
                    ForEach(Array(vm.recentRecords.prefix(3).enumerated()), id: \.element.id) { idx, record in
                        recentRow(record: record, category: vm.category(for: record))
                        if idx < min(2, vm.recentRecords.count - 1) {
                            Rectangle().fill(Color.divider).frame(height: 0.5)
                                .padding(.leading, 28 + NotionTheme.space5)
                        }
                    }
                }
                .cardSurface(cornerRadius: 14, notionFill: Color.hoverBg)
            }
        }
        .buttonStyle(.pressableSoft)
    }

    @ViewBuilder
    private func recentRow(record: Record, category: Category?) -> some View {
        HStack(spacing: NotionTheme.space5) {
            ZStack {
                RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                    .fill(Color.hoverBgStrong)
                Image(systemName: category?.icon ?? "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.inkSecondary)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(category?.name ?? "—")
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.inkPrimary)
                HStack(spacing: 4) {
                    Text(timeText(record.occurredAt))
                        .font(NotionFont.small())
                        .foregroundStyle(Color.inkSecondary)
                    Text("·").foregroundStyle(Color.inkTertiary)
                    Text(sourceText(record.source))
                        .font(NotionFont.small())
                        .foregroundStyle(Color.inkTertiary)
                }
            }
            Spacer()
            Text(amountText(record, kind: category?.kind ?? .expense))
                .font(NotionFont.amount(size: 15))
                .foregroundStyle(DirectionColor.amountForeground(kind: category?.kind ?? .expense))
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 12)
        // 让 HStack 内 Spacer 占据的中间空白区也参与命中测试，
        // 否则 Button label 的 hit-test 不覆盖 Spacer，点击行中间空白区无反应。
        .contentShape(Rectangle())
    }

    private func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func sourceText(_ source: RecordSource) -> String {
        switch source {
        case .manual:                       return "手动"
        case .voiceLocal, .voiceCloud:      return "语音"
        case .ocrVision, .ocrAPI, .ocrLLM:  return "截图"
        }
    }

    private func amountText(_ record: Record, kind: CategoryKind) -> String {
        "¥" + AmountFormatter.display(record.amount)
    }

    private var emptyRecentHint: some View {
        VStack(spacing: NotionTheme.space4) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.inkTertiary)
            Text("还没有任何记录")
                .font(NotionFont.bodyBold())
                .foregroundStyle(Color.inkPrimary)
            Text("用上方两种方式开启你的第一笔")
                .font(NotionFont.small())
                .foregroundStyle(Color.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NotionTheme.space7)
    }
}

// MARK: - HomeViewModel

@MainActor
final class HomeViewModel: ObservableObject {

    @Published private(set) var monthlyExpense: Decimal = 0
    @Published private(set) var monthlyIncome: Decimal = 0
    @Published private(set) var todayCount: Int = 0
    @Published private(set) var recentRecords: [Record] = []
    @Published private(set) var loadError: String?

    private var categoryById: [String: Category] = [:]
    private var observer: NSObjectProtocol?

    var monthlyNet: Decimal { monthlyIncome - monthlyExpense }

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .recordsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reload() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func reload() {
        // 冷启动竞态保护：SwiftUI .onAppear 在 `.task await appState.bootstrap()` **之前**触发，
        // 此时 DatabaseManager.handle 仍是 nil，`.list()` 会抛 `openFailed(-1): DB handle nil`，
        // 导致首页红色 loadError 卡片常驻。修复：DB 未就绪时静默跳过本次 reload，
        // HomeMainView 在 `appState.database` 变为 `.ready` 时会再调一次 reload。
        guard DatabaseManager.shared.isHandleOpen else {
            loadError = nil
            return
        }
        do {
            categoryById = Dictionary(
                uniqueKeysWithValues: try SQLiteCategoryRepository.shared
                    .list(kind: nil, includeDeleted: true)
                    .map { ($0.id, $0) }
            )
            let allRecords = try SQLiteRecordRepository.shared.list(.init(
                ledgerId: DefaultSeeder.defaultLedgerId,
                includesDeleted: false,
                limit: 500
            ))

            // 当月切片
            let cal = Calendar.current
            let now = Date()
            let monthInterval = cal.dateInterval(of: .month, for: now) ?? DateInterval(start: now, end: now)
            let monthly = allRecords.filter { monthInterval.contains($0.occurredAt) }

            var inc: Decimal = 0
            var exp: Decimal = 0
            for r in monthly {
                let kind = categoryById[r.categoryId]?.kind ?? .expense
                switch kind {
                case .income:  inc += r.amount
                case .expense: exp += r.amount
                }
            }
            monthlyIncome  = inc
            monthlyExpense = exp

            // 今日条目数
            todayCount = allRecords.filter { cal.isDateInToday($0.occurredAt) }.count

            // 最近 3 条
            recentRecords = Array(allRecords.prefix(3))
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func category(for record: Record) -> Category? {
        categoryById[record.categoryId]
    }
}

#if DEBUG
#Preview {
    HomeMainView(switchTab: { _ in }, coordinator: MainCoordinator())
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
#endif
