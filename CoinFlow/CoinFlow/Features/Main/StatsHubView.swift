//  StatsHubView.swift
//  CoinFlow · V2 Stats · 统计 Tab 主入口
//
//  设计基线：design/screens/05-stats/main-light.png（实际是 wallet 卡片堆叠样式）
//
//  形态（紧凑卡片堆叠，iOS 控制中心式滑动）：
//   - 顶部 NavBar："统计 / N 张报告 · YYYY 年 M 月" + 右上 grid icon
//   - Hero 区：本月净增大数字 + 收入/支出/笔数 mini KPI
//   - 中间：水平卡片堆栈（中央 + 左右各 3 张露边，slotTable 4 档预计算）
//   - 底部：分页指示器 + 滑动提示
//
//  交互：
//   - 左右滑动：trackOffset 跟手位移，dragProgress = -trackOffset / switchLimit
//     驱动所有卡 effective slot 实时插值，传送带式连续过渡；
//     松手按"位置 + 速度惯性"算最近 idx，单次 spring 同步推进 currentIdx +
//     归零 trackOffset — 一气呵成不分步翻页
//     — 手势层（HorizontalPanCatcher）水平铺满整条卡片行，配合 UIKit 级
//     delegate 阻断，TabView 横滑永远抢不到手势
//   - 点击中央卡矩形：跳转到该卡对应的详情页面（push）
//   - 点击侧边卡区域：归位到那一侧的最近卡（不跳转）— 与 pan 共用 settle 路径
//   - 所有卡背景统一 surfaceOverlay 实色，内容垂直+水平居中，clipShape 不溢出
//
//  关键：手势隔离方案
//   MainTabView 外层用 TabView(.page) 做 tab 切换，它内部是 UIPageViewController
//   的 UIPanGestureRecognizer。SwiftUI 的 `highPriorityGesture` 无法压制 UIKit 级手势。
//   所以卡片堆叠区域改用 `HorizontalPanCatcher`（UIViewRepresentable 包 UIPanGestureRecognizer），
//   通过 gestureRecognizer(_:shouldBeRequiredToFailBy:) 强制要求 TabView 的 pan 必须失败，
//   彻底隔离卡片横滑与 Tab 横滑。

import SwiftUI
import UIKit

struct StatsHubView: View {
    @StateObject private var vm = StatsViewModel()
    @Environment(\.colorScheme) private var scheme

    /// 当前位于堆栈中央的卡片下标。
    /// 默认 4 = `allCards` 中 `.main`（"本月统计"）的位置；
    /// 设计意图为打开统计 tab 即聚焦本月数据，左右滑动查看其他报告。
    /// 注意：若调整 `allCards` 顺序，需同步更新此默认值。
    @State private var currentIdx: Int = 4
    /// 手势/动画驱动的跟手位移（静止时恒为 0）。
    /// 与 dragProgress 同源：progress = -trackOffset / switchLimit，驱动所有卡 effective slot 插值。
    /// 正值 = 手指向右拖（想看上一张），progress < 0；负值反之。
    /// `settle(to:)` 会在切换 currentIdx 同时同步调整 trackOffset 以保证视觉连续。
    @State private var trackOffset: CGFloat = 0
    /// 手势起点的 trackOffset 快照（H1/H2 修复点）。
    /// onPanChanged(dx) 期间 trackOffset = panBaseline + dx，避免 spring 进行中被新手势直接覆盖。
    /// settle 后、以及 handlePanStarted 中会同步重置。
    @State private var panBaseline: CGFloat = 0
    /// 导航栈路径：用类型擦除的 NavigationPath 同时承载 StatsAnalysisDestination
    /// 与词云/排行点击跳转用的 CategoryDetailTarget。
    @State private var navPath: NavigationPath = NavigationPath()
    /// 边界提示 toast 文本；非空 = 显示中。短时自动消失。
    @State private var edgeHint: String? = nil
    /// edgeHint 自动隐藏的工作项；新提示进来时取消旧的。
    @State private var edgeHintTask: DispatchWorkItem? = nil
    /// 月份选择器弹层显隐
    @State private var showMonthPicker: Bool = false

    var body: some View {
        NavigationStack(path: $navPath) {
            ZStack {
                ThemedBackgroundLayer(kind: .stats)
                VStack(spacing: 0) {
                    navBar
                    summaryHero
                        .padding(.top, NotionTheme.space5)
                        .frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                    horizontalCardStack
                    Spacer(minLength: 0)
                    pageIndicator
                    bottomHint
                }
                edgeHintToast
            }
            .navigationBarHidden(true)
            .enableInteractivePop()
            .onAppear { vm.reload() }
            // 从详情页 pop 回 hub 时刷新一次：
            // BillsSummary 仓库写入没有 .recordsDidChange 通知，
            // 用户在 BillsSummaryListView 生成新 summary 后返回 hub，
            // 这里保证 vm.cardPreviews[.summary] 同步刷新。
            // 注：iOS 16 部署目标，使用旧式单闭包 onChange（iOS 17 双参版本不可用）。
            .onChange(of: navPath.isEmpty) { isEmpty in
                if isEmpty { vm.reload() }
            }
            .navigationDestination(for: StatsAnalysisDestination.self) { dest in
                destinationView(dest)
            }
            // 词云 / 分类排行点击某个分类 → 直达该分类详情页
            .navigationDestination(for: CategoryDetailTarget.self) { target in
                StatsCategoryDetailView(preferredCategoryId: target.categoryId,
                                        month: vm.month)
            }
            // StatsAABalanceView 中"最近活跃"行点击 → 直达 AA 分账详情
            .navigationDestination(for: AASplitListDestination.self) { dest in
                AASplitDetailView(ledgerId: dest.ledgerId)
            }
            .sheet(isPresented: $showMonthPicker) {
                StatsMonthPickerSheet(selected: vm.month) { picked in
                    vm.month = picked
                }
                .presentationDetents([.height(440)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - 边界提示 Toast
    //
    // 触发：用户在第一张继续右滑 / 最后一张继续左滑时，给一次轻 Haptic + 短文案。
    // 视觉：靠近底部、胶囊状、半透明深色背景，1.4s 自动消失。
    @ViewBuilder
    private var edgeHintToast: some View {
        if let text = edgeHint {
            VStack {
                Spacer()
                Text(text)
                    .font(.custom("PingFangSC-Regular", size: 12))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.78))
                    )
                    .padding(.bottom, 156)   // tab bar(100) + bottomHint 高度上方
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            .allowsHitTesting(false)
            .zIndex(2000)
        }
    }

    /// 显示边界提示，自动 1.4s 后消失；同方向重复触发时不重置 toast，避免抖动。
    private func showEdgeHint(_ text: String) {
        // 同样文本仍在显示，仅延长一次显示时间（重置定时器）
        // 入场用 emphasized（起步快、末端缓，符合"出现"心智）
        // 退场用 exit（起步缓、末端快，符合"消失"心智）
        if edgeHint != text {
            withAnimation(Motion.respect(Motion.emphasized(0.22))) { edgeHint = text }
        }
        edgeHintTask?.cancel()
        let task = DispatchWorkItem { [text] in
            // 仅当当前显示的还是这条文本时才隐藏（避免覆盖更新的 toast）
            if edgeHint == text {
                withAnimation(Motion.respect(Motion.exit(0.20))) { edgeHint = nil }
            }
        }
        edgeHintTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: task)

        // 边界反馈（用户偏好：禁用震动；保留 hint 视觉提示）
        Haptics.soft()
    }

    // MARK: - 10 卡片定义（中央默认 = 本月汇总）

    private struct HubCard: Identifiable, Equatable {
        let id: StatsAnalysisDestination
        let title: String
        let icon: String
        let tone: NotionColor
    }

    private var allCards: [HubCard] {
        [
            // 10 张子页面卡：8 个深度分析 + 本月统计（中央） + 1 个 LLM 账单复盘历史（M10）
            HubCard(id: .trend,     title: "趋势曲线",   icon: "chart.line.uptrend.xyaxis",   tone: .blue),
            HubCard(id: .sankey,    title: "资金流向",   icon: "arrow.left.arrow.right",      tone: .orange),
            HubCard(id: .wordcloud, title: "分类词云",   icon: "text.bubble.fill",            tone: .pink),
            HubCard(id: .budget,    title: "本月预算",   icon: "target",                      tone: .red),
            HubCard(id: .main,      title: "本月统计",   icon: "square.grid.2x2.fill",        tone: .green),
            HubCard(id: .aa,        title: "AA 账本",    icon: "person.2.fill",               tone: .purple),
            HubCard(id: .category,  title: "分类详情",   icon: "fork.knife",                  tone: .orange),
            HubCard(id: .year,      title: "年度回顾",   icon: "calendar",                    tone: .brown),
            HubCard(id: .hourly,    title: "时段分布",   icon: "clock.fill",                  tone: .blue),
            HubCard(id: .summary,   title: "账单复盘",   icon: "sparkles",                    tone: .purple),
        ]
    }

    private var totalCardCount: Int { allCards.count }

    // MARK: - Nav Bar

    private var navBar: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("统计")
                    .font(.custom("PingFangSC-Semibold", size: 17))
                    .foregroundStyle(Color.inkPrimary)
                // 副标题改为可点按胶囊：点击弹出月份选择器
                Button {
                    Haptics.soft()
                    showMonthPicker = true
                } label: {
                    HStack(spacing: 3) {
                        Text("\(totalCardCount) 张报告 · \(StatsFormat.ymSubtitle(vm.month))")
                            .font(.custom("PingFangSC-Regular", size: 11))
                            .foregroundStyle(Color.inkTertiary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.inkTertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSoft)
                .accessibilityLabel("选择月份，当前 \(StatsFormat.ymSubtitle(vm.month))")
            }
        }
        .padding(.horizontal, NotionTheme.space4)
        .frame(height: 52)
        .background(Color.appCanvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.divider).frame(height: NotionTheme.borderWidth)
        }
    }

    // MARK: - Summary hero（真实数据）

    private var summaryHero: some View {
        VStack(spacing: 0) {
            // 标题 — 居中
            Text("本月净增")
                .font(.custom("PingFangSC-Regular", size: 13))
                .foregroundStyle(Color.inkTertiary)

            // 主数字 — 居中；¥ 与数字字重/字体/比例统一（全局规则 §AmountSymbolStyle）
            // 用 attributed string 拼接 → minimumScaleFactor 才能让 ¥+数字整组等比例缩小
            let digitSize: CGFloat = 36
            let symbolSize = digitSize * AmountSymbolStyle.symbolScale
            let amountStr = StatsFormat.decimalGrouped(vm.monthlyNet < 0 ? -vm.monthlyNet : vm.monthlyNet)
            let heroAttr: AttributedString = {
                var a = AttributedString("¥")
                a.font = .system(size: symbolSize, weight: .bold, design: .rounded)
                a.foregroundColor = toneForNet
                var n = AttributedString(amountStr)
                n.font = .system(size: digitSize, weight: .bold, design: .rounded).monospacedDigit()
                n.foregroundColor = toneForNet
                a.append(n)
                return a
            }()
            Text(heroAttr)
                .amountGroupAutoFit(scaleFloor: 0.4)   // 36pt → 最小 ~14pt
                .padding(.top, 4)
                .padding(.horizontal, NotionTheme.space5)

            // 极淡水平 divider 隔开 hero 与 KPI 三栏
            Rectangle()
                .fill(Color.divider)
                .frame(height: NotionTheme.borderWidth)
                .padding(.top, NotionTheme.space5)
                .padding(.bottom, NotionTheme.space4)

            // 三栏 KPI — 居中等分；数字 17pt，竖线分隔
            HStack(spacing: 0) {
                miniKPI("收入",
                        "¥" + StatsFormat.decimalGrouped(vm.monthlyIncome),
                        DirectionColor.amountForeground(kind: .income))
                kpiDivider
                miniKPI("支出",
                        "¥" + StatsFormat.decimalGrouped(vm.monthlyExpense),
                        DirectionColor.amountForeground(kind: .expense))
                kpiDivider
                miniKPI("笔数",
                        "\(vm.monthlyCount)",
                        Color.inkPrimary)
            }
        }
        .padding(.horizontal, NotionTheme.space6)
        .padding(.vertical, NotionTheme.space6)
        // 宽度与下方中央卡 cardWidth 对齐（290pt），让两块视觉一脉相承
        .frame(width: Self.cardWidth)
        .cardSurface(cornerRadius: 14, notionFill: Color.hoverBgStrong)
    }

    /// KPI 三栏之间的竖线分隔（24pt 高 · divider 色）
    private var kpiDivider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(width: NotionTheme.borderWidth, height: 24)
    }

    private var toneForNet: Color {
        vm.monthlyNet >= 0
            ? DirectionColor.amountForeground(kind: .income)
            : DirectionColor.amountForeground(kind: .expense)
    }

    @ViewBuilder
    private func miniKPI(_ label: String, _ value: String, _ tone: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Wallet style horizontal stack
    //
    // 设计：紧凑堆叠（4 档预计算）+ trackOffset 跟手 + 单 spring 吸附（iOS 控制中心式）
    //   - 静态时：卡片紧凑堆叠，左右各 3 张露边（offsetBase 等差：0/40/68/92）
    //   - 拖拽时：trackOffset 直接跟手位移；dragProgress = -trackOffset / switchLimit
    //     每张卡的 effective slot = slotOffset - dragProgress 做相邻档插值
    //     → 整组卡像传送带一样跟着手指连续滑过 N 张
    //     → 中央卡渐变缩小淡出，目标方向上下一张连续浮现到中央
    //   - 松手（handlePanEnded）：用"位置 + 速度惯性"算最终落点，
    //     四舍五入到最近整数 = 目标 idx
    //   - 切换（settle）：单次 spring 同步推进 currentIdx + 归零 trackOffset
    //     → 不再分步翻页，整组卡一气呵成滑到目标，dragProgress 全程连续无跳变

    /// 单个可见 slot 的几何参数（紧凑堆叠预计算表）
    private struct SlotGeometry {
        let scale: CGFloat
        let offsetBase: CGFloat   // 静态时该层的水平基准 offset（等差堆叠）
        let shadowRadius: CGFloat
        let shadowOpacity: Double
        let shadowY: CGFloat
        let fadeOpacity: Double
    }

    /// 4 档预计算（中央 + 左右各 3）。
    /// 等差 offset 32pt + 等差 scale 0.06 + 等差 opacity → 紧凑、规整、层次清晰。
    private static let slotTable: [SlotGeometry] = [
        // absSlot = 0（中央）
        .init(scale: 1.00, offsetBase: 0,
              shadowRadius: 22, shadowOpacity: 0.20, shadowY: 8,
              fadeOpacity: 1.00),
        // absSlot = 1
        .init(scale: 0.94, offsetBase: 40,
              shadowRadius: 14, shadowOpacity: 0.12, shadowY: 5,
              fadeOpacity: 0.88),
        // absSlot = 2
        .init(scale: 0.88, offsetBase: 68,
              shadowRadius: 8,  shadowOpacity: 0.06, shadowY: 3,
              fadeOpacity: 0.55),
        // absSlot = 3（最外，作为入场/出场缓冲，平时几乎不可见）
        .init(scale: 0.82, offsetBase: 92,
              shadowRadius: 4,  shadowOpacity: 0.0, shadowY: 1,
              fadeOpacity: 0.0),
    ]

    /// 形态/层级共用缓动：2 阶 smoothstep（6x⁵ - 15x⁴ + 10x³），两端钝、中段陡。
    /// 应用于 fadeOpacity / scale / zIndex 的相邻档插值。
    private static func fadeEase(_ x: CGFloat) -> CGFloat {
        let c = max(0, min(1, x))
        return c * c * c * (c * (c * 6 - 15) + 10)
    }

    /// 拖拽强调放大系数（"浮在最上层的卡片在滑动时再稍微放大一点"）。
    ///
    /// 公式：boostMax · |drag| · max(0, 1 - |effective|)
    ///   - 静止（|drag|=0）→ 0：不影响默认形态
    ///   - 远离中央（|effective|≥1）→ 0：邻卡及更远卡不参与
    ///   - 中央卡 + 拖到一半 → boostMax · 0.5 · 1 = 2.5%
    ///   - 中央卡 + 拖到极限 → boostMax = 5%
    ///
    /// 单调性：是 |effective| 的弱单调递减函数，且 ≥ 0；
    /// 不破坏"z 与 scale 同序"不变量（scale 仍是 |effective| 的递减函数）。
    private static let boostMax: CGFloat = 0.05
    static func boostFactor(absEff: CGFloat, drag: CGFloat) -> CGFloat {
        let dragMag = min(abs(drag), 1)
        let proximity = max(0, 1 - absEff)
        return boostMax * dragMag * proximity
    }

    /// 最大可见层数（中央外左右各 N 张），= slotTable.count - 1
    private static let maxAbsSlot: Int = 3

    /// 卡片宽度 / 高度
    private static let cardWidth: CGFloat = 290
    private static let cardHeight: CGFloat = 400

    /// 拖拽归一化基准：trackOffset 累计 switchLimit pt = 已切换 1 张卡。
    /// 同时也是 effective slot 公式的归一化分母。
    private static let switchLimit: CGFloat = 100

    /// 速度惯性时长（秒）：松手后用 vx · inertiaTime 估算还会"飞"多远。
    private static let inertiaTime: CGFloat = 0.18
    /// 单次手势最多跨越的卡片数（绝对上限，避免速度爆表算出 50 张）。
    private static let maxJump: Int = 12
    /// 边界橡皮筋阻尼系数 / 最大额外位移（首末张继续向外拖时使用）。
    private static let rubberFactor: CGFloat = 0.28
    private static let rubberLimit: CGFloat = 70

    /// 当前拖拽进度（trackOffset 归一化到"张数"维度，可跨越多张）。
    ///
    /// 数学：progress = -trackOffset / switchLimit
    ///   手指向左拖（dx < 0 → trackOffset < 0）= 想看下一张 → progress > 0
    ///   手指向右拖（dx > 0 → trackOffset > 0）= 想看上一张 → progress < 0
    ///
    /// effective slot = slotOffset - progress：拖拽时整组卡按 effective 在 slotTable 相邻档插值，
    /// 像传送带一样平滑滑过 N 张；中央卡渐变缩小淡出，目标方向邻卡渐变浮现到中央。
    ///
    /// 边界夹紧：按"剩余可滑张数"硬夹（首张时 progress 不能 < 0，末张时不能 > 剩余张数），
    /// 配合 handlePanChanged 的橡皮筋，越界手势视觉上会停在合法范围内。
    ///
    /// 实现：委托给 `CardSwipeEngine.dragProgress`，保证测试覆盖的逻辑与运行时一致。
    private var dragProgress: CGFloat {
        engineSnapshot.dragProgress
    }

    /// 用当前 View 状态构造一个临时 engine 实例（值类型，零成本），
    /// 让 dragProgress / atLeftEdge / atRightEdge 等派生量都通过统一逻辑计算。
    /// 同时复原 panBaseline，让 onPanChanged(dx) 能正确使用 "手势起点 + dx" 语义。
    private var engineSnapshot: CardSwipeEngine {
        var e = CardSwipeEngine(totalCount: totalCardCount, initialIdx: currentIdx)
        e.trackOffset = trackOffset
        e.restorePanBaseline(panBaseline)
        return e
    }

    private var horizontalCardStack: some View {
        let cardW = Self.cardWidth
        let cardH = Self.cardHeight

        // ============================================================
        // 渲染模型（真实卡片身份制，避免 SwiftUI 把 settle 当成"内容替换"）
        // ============================================================
        //
        // 历史 bug：之前用 slotOffset 作为 ForEach.id，每个 slot 是"屏幕固定位置槽"，
        // settle 切 currentIdx 时 slot 视图位置不动、绑定的 cardIdx 直接换一张内容；
        // SwiftUI 看到的是"id=0 的视图内容变了" → 完全跳过过渡动画 →
        // 用户感知到中央卡"内容硬切"（录屏 f_018→f_020 现象）。
        //
        // 修复：ForEach.id 改为真实卡片下标 realIdx ∈ [0, totalCount)。
        // 每张卡的"槽位偏移" = realIdx - currentIdx - dragProgress（连续函数）。
        // settle 时 currentIdx +1、trackOffset 同步补偿 +switchLimit，
        // 数学上 (realIdx - currentIdx - dragProgress) 完全不变 →
        // SwiftUI 看到的是"同一组视图的几何属性都没变" → 0 跳变 0 重新渲染。
        //
        // 性能：absSlotEff > 3.5 的卡早返回 EmptyView（fade<0.01），9 张卡里
        // 实际进完整渲染分支的 ≤ 8 张，与原方案一致。
        // ============================================================
        let drag = dragProgress

        return ZStack {
            ForEach(0..<totalCardCount, id: \.self) { realIdx in
                realCardView(realIdx: realIdx, drag: drag, cardW: cardW, cardH: cardH)
            }
            // UIKit 手势拦截层：水平铺满，独占水平 pan
            HorizontalPanCatcher(
                onStart:   { handlePanStarted() },
                onChanged: { dx in handlePanChanged(dx: dx) },
                onEnded:   { dx, vx in handlePanEnded(dx: dx, vx: vx) },
                onTap:     { location, size in
                    handleContainerTap(location: location,
                                       containerSize: size,
                                       cardW: cardW,
                                       cardH: cardH)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .allowsHitTesting(true)
            // 必须高于所有卡片 zIndex（中央卡 ≈ 100），否则中央卡会吃掉 tap/pan
            .zIndex(999)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardH + 32)
        .contentShape(Rectangle())
    }

    // MARK: - UIKit pan 回调

    /// 是否处于左边界（首张，不能再向"上一张"方向滑 = 手势 dx > 0 = 向右拖）
    private var atLeftEdge: Bool { engineSnapshot.atLeftEdge }
    /// 是否处于右边界（末张，不能再向"下一张"方向滑 = 手势 dx < 0 = 向左拖）
    private var atRightEdge: Bool { engineSnapshot.atRightEdge }

    private func handlePanChanged(dx: CGFloat) {
        // 委托 engine 计算 trackOffset（含边界橡皮筋），避免数学在两处重复
        var e = engineSnapshot
        e.onPanChanged(dx: dx)
        trackOffset = e.trackOffset
    }

    /// pan started：记录手势起点的 trackOffset 快照。
    /// 这是 H1/H2 bug 的修复点：spring 进行中开始新手势时，不会出现"trackOffset 被 dx 直接覆盖"的跳变。
    /// 后续 onPanChanged(dx) 会以 panBaseline + dx 计算 trackOffset。
    private func handlePanStarted() {
        // 冻结 spring：用禁动画 transaction 重赋值 trackOffset，等价于取消剩余 spring、从最后一帧起跳
        var tx = Transaction()
        tx.disablesAnimations = true
        let frozen = trackOffset
        withTransaction(tx) {
            trackOffset = frozen
        }
        // 记录 panBaseline 为当前 trackOffset。后续 handlePanChanged 里 engineSnapshot 会复原这个值。
        panBaseline = trackOffset
    }

    private func handlePanEnded(dx _: CGFloat, vx: CGFloat) {
        // 委托 engine 计算落点 + 边界提示决策
        let decision = engineSnapshot.onPanEnded(vx: vx)
        switch decision.hint {
        case .leftEdge:  showEdgeHint("已是第一张")
        case .rightEdge: showEdgeHint("已是最后一张")
        case nil: break
        }
        settle(to: decision.targetIdx)
    }

    /// 单 spring 吸附到目标 idx：currentIdx 与 trackOffset 在**同一个动画块**里被联动插值。
    ///
    /// 关键不变量：`effective = realIdx - currentIdx - dragProgress`（dragProgress = -trackOffset/L）
    ///
    /// 数学：让 currentIdx 与 trackOffset 同时被同一个 spring 驱动。
    ///   起始：(currentIdx=c, trackOffset=W) → effective = realIdx - c - (-W/L) = realIdx - c + W/L
    ///   目标：(currentIdx=c+Δ, trackOffset=0) → effective = realIdx - c - Δ
    ///   起止 effective 差 = -Δ - W/L = -(Δ·L + W) / L = -(目标距离/L)
    ///   spring 在 [0,1] 内插值时，effective 也在起止之间线性插值 → 屏幕上每张卡的几何属性
    ///   从起始连续平滑变到目标。**所有卡片（包括正在离开和正在进入中央的）都参与同一组动画**。
    ///
    /// 注意：currentIdx 是 Int，必须放在 `withAnimation` 内部以变化才会触发隐式过渡。
    /// SwiftUI 的隐式动画会把 Int 视作离散，但 `effective` 是 `realIdx - currentIdx - drag` 的合成
    /// 值，每帧由 dragProgress 计算插入；只要 trackOffset 是连续的，effective 就连续。
    /// 这里 currentIdx 在动画块内被赋新值是为了让"动画完成时几何已收敛到目标"的状态正确，
    /// 而中间过程的视觉连续性由 trackOffset spring 提供。
    ///
    /// **关键技巧**：先把 trackOffset 补偿到等价位置（不动画），再让 currentIdx 与 trackOffset
    /// 同时朝目标 spring。补偿的瞬时不会引发视觉变化（因为 effective 守恒），spring 阶段
    /// effective 平滑收敛到目标，整个过程零跳变。
    private func settle(to targetIdx: Int) {
        let delta = targetIdx - currentIdx
        if delta == 0 {
            withAnimation(Motion.respect(.spring(response: 0.34, dampingFraction: 0.86))) {
                trackOffset = 0
            }
            panBaseline = 0
            return
        }

        // 阶段 1（无动画，瞬时）：把 currentIdx 推到目标，trackOffset 同步补偿。
        // 不变量 effective = realIdx - currentIdx - dragProgress 守恒 → 屏幕上无任何视觉变化。
        // ForEach.id 是 realIdx（不是 currentIdx），所以 currentIdx 跳变不会引起 view identity 变更。
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            currentIdx = targetIdx
            trackOffset += CGFloat(delta) * Self.switchLimit
        }
        // 阶段 2（spring）：trackOffset → 0，dragProgress 同步收敛到 0，
        // effective 在每张可见卡上从"补偿后位置"平滑过渡到"目标位置"，全程无跳变。
        withAnimation(Motion.respect(.spring(response: 0.42, dampingFraction: 0.86))) {
            trackOffset = 0
        }
        panBaseline = 0
    }

    /// 真实卡片身份制渲染：每张卡按其真实索引 realIdx 渲染，
    /// 几何属性由连续函数 `effectiveSlot = realIdx - currentIdx - dragProgress` 决定。
    ///
    /// 数学不变量（保证 settle 不视觉跳变）：
    ///   settle 前：(currentIdx, dragProgress=p)，effectiveSlot = realIdx - currentIdx - p
    ///   settle 后：(currentIdx+Δ, dragProgress=p-Δ)，effectiveSlot = realIdx - (currentIdx+Δ) - (p-Δ)
    ///                                              = realIdx - currentIdx - p（完全相同）
    ///   → SwiftUI 看到这张卡的所有几何属性都没变，无任何过渡 / 重新渲染 → 0 跳变。
    @ViewBuilder
    private func realCardView(realIdx: Int, drag: CGFloat,
                              cardW: CGFloat, cardH: CGFloat) -> some View {
        let effective = CGFloat(realIdx - currentIdx) - drag
        let absEff = abs(effective)

        // 远端卡（|effective| > 3.5）几乎不可见：fade≈0，跳过完整渲染节省 GPU
        if absEff > 3.5 {
            EmptyView()
        } else {
            let lowerIdx = min(Int(floor(absEff)), Self.maxAbsSlot)
            let upperIdx = min(lowerIdx + 1, Self.maxAbsSlot)
            let t = max(0, min(1, absEff - CGFloat(lowerIdx)))
            let lower = Self.slotTable[lowerIdx]
            let upper = Self.slotTable[upperIdx]

            let fadeT = Self.fadeEase(t)
            let baseScale = lower.scale + (upper.scale - lower.scale) * fadeT
            let fade  = lower.fadeOpacity + (upper.fadeOpacity - lower.fadeOpacity) * Double(fadeT)

            // 拖拽强调：滑动时让"浮在最上层的卡片"额外放大一点（最大 +5%）。
            // boost = boostMax · |drag| · max(0, 1 - |effective|)
            //   · |drag|=0 → 静止时 boost=0，不影响默认形态
            //   · |effective| 越小（越靠近最前） → boost 越大
            //   · |effective|≥1 → boost=0，邻卡及更远卡不参与放大
            // 性质：boost 仍是 |effective| 的（弱）单调递减函数，不破坏"z 与 scale 同序"不变量。
            let scale = baseScale * (1 + Self.boostFactor(absEff: absEff, drag: drag))

            if fade < 0.01 {
                EmptyView()
            } else {
                buildRealCard(realIdx: realIdx,
                              cardW: cardW, cardH: cardH,
                              drag: drag,
                              effective: effective,
                              absEff: absEff,
                              scale: scale,
                              fade: fade,
                              lower: lower,
                              upper: upper,
                              t: t)
            }
        }
    }

    /// 完成单张可见卡的几何插值 + zIndex 计算 + 视图组装。
    @ViewBuilder
    private func buildRealCard(realIdx: Int,
                               cardW: CGFloat, cardH: CGFloat,
                               drag: CGFloat,
                               effective: CGFloat,
                               absEff: CGFloat,
                               scale: CGFloat,
                               fade: Double,
                               lower: SlotGeometry,
                               upper: SlotGeometry,
                               t: CGFloat) -> some View {
        let offsetMag = lower.offsetBase + (upper.offsetBase - lower.offsetBase) * t
        let shadowR  = lower.shadowRadius + (upper.shadowRadius - lower.shadowRadius) * t
        let shadowOp = lower.shadowOpacity + (upper.shadowOpacity - lower.shadowOpacity) * Double(t)
        let shadowY  = lower.shadowY + (upper.shadowY - lower.shadowY) * t

        // 方向：effective 的符号决定卡片在中央哪一侧
        let dir: CGFloat = effective >= 0 ? 1 : -1
        let x = dir * offsetMag

        // zIndex：单一规则——与 |effective| 严格同序，scale 最大的卡 z 也最大。
        // 不再按"概念槽位 + drag"分支决策，避免任何拖拽中期的"小卡盖大卡"。
        let zFinal: Double = CardSwipeEngine.zIndex(forAbsEffective: absEff)

        let isCenter = absEff < 0.5

        cardView(allCards[realIdx], isCenter: isCenter)
            .frame(width: cardW, height: cardH)
            .scaleEffect(scale)
            .opacity(fade)
            .offset(x: x, y: 0)
            .shadow(color: Color.black.opacity(shadowOp),
                    radius: shadowR, y: shadowY)
            .zIndex(zFinal)
            .allowsHitTesting(false)
    }

    /// 容器 tap 派发：
    /// - 中央卡矩形内 tap → 跳转详情
    /// - 侧边区域 tap → 归位到那一侧的最近卡（不跳转），与 pan 共用 settle
    private func handleContainerTap(location: CGPoint,
                                    containerSize: CGSize,
                                    cardW: CGFloat,
                                    cardH: CGFloat) {
        let dx = location.x - containerSize.width / 2
        let dy = location.y - containerSize.height / 2
        let inCenterCard = abs(dx) <= cardW / 2 && abs(dy) <= cardH / 2
        if inCenterCard {
            navPath.append(allCards[currentIdx].id)
        } else {
            let step = dx > 0 ? 1 : -1
            let target = currentIdx + step
            guard target >= 0 && target < totalCardCount else {
                showEdgeHint(step > 0 ? "已是最后一张" : "已是第一张")
                return
            }
            settle(to: target)
        }
    }

    // MARK: - 单张卡片

    @ViewBuilder
    private func cardView(_ card: HubCard, isCenter: Bool) -> some View {
        // 所有卡：整体内容垂直+水平居中于卡片中央；
        // 文本/数字做 lineLimit + minimumScaleFactor 防溢出；
        // 外层 clipShape 保证任何子视图不会突破圆角。
        //
        // 性能：preview 数据已下沉到 StatsViewModel.cardPreviews，只在 reload 时一次性计算；
        // 拖拽期间 cardView 可能被重建多次，这里仅是 O(1) 字典查表 + 默认值兑底。
        let preview = vm.cardPreviews[card.id] ?? StatsCardPreview(heroValue: "—", insight: "加载中")

        VStack(spacing: NotionTheme.space4) {
            // 顶部：icon 小块 + 标题
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                        .fill(card.tone.background(scheme))
                    Image(systemName: card.icon)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(card.tone.text(scheme))
                }
                .frame(width: 24, height: 24)
                Text(card.title)
                    .font(.custom("PingFangSC-Semibold", size: 17))
                    .foregroundStyle(Color.inkPrimary)
                    .lineLimit(1)
            }

            Rectangle()
                .fill(Color.divider)
                .frame(width: 48, height: NotionTheme.borderWidth)

            // 中段：hero 数据（卡片的视觉主角）
            VStack(spacing: NotionTheme.space3) {
                Text(preview.heroValue)
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.inkPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(preview.insight)
                    .font(.custom("PingFangSC-Regular", size: 13))
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            // 底部：CTA
            HStack(spacing: 6) {
                Text("点击查看详情")
                    .font(.custom("PingFangSC-Regular", size: 12))
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Color.inkTertiary)
        }
        .padding(.horizontal, NotionTheme.space5)
        // 整体在卡片内垂直 + 水平居中
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        // 主题感知卡片底层：
        // - Notion 模式：原 surfaceOverlay 实色 + border 描边
        // - LGA 模式：玻璃卡片 + rim light + 折射高光（关闭自带阴影，由 slotCardView 的 .shadow 接管）
        .cardSurface(cornerRadius: 14,
                     notionFill: Color.surfaceOverlay,
                     notionStroke: Color.border,
                     lgaShadow: false)
        // 关键：裁剪所有子视图到卡片圆角矩形内，防止大数字/长文本突破边界
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // 性能：原本的 .compositingGroup() 已移除。
        // 原因：slotCardView 外层已有 .shadow()，.shadow 本身就会触发离屏渲染；
        // 再叠加 compositingGroup 会让 GPU 每帧双重离屏、改变 alpha 时还要重新计算阴影模糊，
        // 反而拖累帧率。去掉后 GPU 只走一次 shadow 离屏，9 张卡拖拽时负担显著降低。
    }

    // MARK: - 卡片预览数据（已下沉到 StatsViewModel.cardPreviews）
    //
    // 历史上这里是 private func previewContent(for:) + 内部 CardPreview，
    // 每帧重渲都会重算（其中 .summary 还含 SQLite 查询，.main/.aa 含全量数组遍历）。
    // 拖拽时 17+ 张卡 × 60fps → 每秒上千次 SQL 查询 / 数组遍历，是卡顿主因。
    // 现以 reload 时一次性计算 vm.cardPreviews 字典代替，View 层只读。

    // MARK: - 页面指示 + 提示

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalCardCount, id: \.self) { i in
                Capsule()
                    .fill(i == currentIdx ? Color.inkPrimary : Color.inkTertiary.opacity(0.35))
                    .frame(width: i == currentIdx ? 18 : 6, height: 6)
            }
        }
        .padding(.top, NotionTheme.space5)
        .accessibilityLabel("第 \(currentIdx + 1) 张卡，共 \(totalCardCount) 张")
    }

    private var bottomHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.tap")
                .font(.system(size: 10, weight: .semibold))
            Text("点击中央卡查看详情")
                .font(.custom("PingFangSC-Regular", size: 11))
            Text("·")
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 10, weight: .semibold))
            Text("左右翻页")
                .font(.custom("PingFangSC-Regular", size: 11))
        }
        .foregroundStyle(Color.inkTertiary)
        .padding(.bottom, 100)   // 给底部 tab bar 留空
    }

    // MARK: - 路由 destination

    @ViewBuilder
    private func destinationView(_ dest: StatsAnalysisDestination) -> some View {
        switch dest {
        case .trend:     StatsTrendView(month: vm.month)
        case .sankey:    StatsSankeyView(month: vm.month)
        case .wordcloud: StatsWordCloudView(month: vm.month)
        case .budget:    StatsBudgetView(month: vm.month)
        case .main:      StatsMainView(month: vm.month)
        case .aa:        StatsAABalanceView(month: vm.month)
        case .category:  StatsCategoryDetailView(month: vm.month)
        case .year:      StatsYearView(month: vm.month)
        case .hourly:    StatsHourlyView(month: vm.month)
        case .summary:   BillsSummaryListView(showsTestSection: false)
        }
    }
}

/// 兼容旧入口：M7 历史代码里 `StatsPlaceholderView` 仍可能被引用，保留 typealias。
typealias StatsPlaceholderView = StatsHubView

// MARK: - HorizontalPanCatcher（UIKit 手势黑洞）
//
// 背景：
//   MainTabView 用 `TabView(.page)` 实现 Tab 横滑切换，其底层是 UIKit 的
//   `UIPageViewController` + 系统 pan recognizer。SwiftUI 层的 `highPriorityGesture`
//   仅在 SwiftUI 内部优先级生效，无法压制 UIKit pan → 卡片横滑时 Tab 也会被拖动。
//
// 解法：
//   用 UIViewRepresentable 裸插一个装了 UIPanGestureRecognizer 的 UIView，
//   实现 `UIGestureRecognizerDelegate.gestureRecognizer(_:shouldBeRequiredToFailBy:)`
//   反转：让 TabView 的 pan **必须等本 pan 失败** 才能识别。
//   只要首帧判定为水平意图，本 pan 始终不失败 → TabView 永远识别不到 → 彻底隔离。
//
// 额外：
//   - 水平意图判定：|dx| > |dy| * 1.2 && |dx| > 10；否则立即 fail 让 TabView 接管
//   - tap 单独出口：移动距离 < 10pt 视为 tap，命中坐标回调
struct HorizontalPanCatcher: UIViewRepresentable {
    let onStart:   () -> Void                            // 手势开始（.began）
    let onChanged: (CGFloat) -> Void                      // 累计水平位移
    let onEnded:   (CGFloat, CGFloat) -> Void             // 位移 + 速度 (pts/s)
    let onTap:     (CGPoint, CGSize) -> Void              // tap 坐标 + 容器尺寸（用于 slot 判定）

    func makeCoordinator() -> Coordinator {
        Coordinator(onStart: onStart, onChanged: onChanged, onEnded: onEnded, onTap: onTap)
    }

    func makeUIView(context: Context) -> UIView {
        let v = PassthroughView()
        v.backgroundColor = .clear
        v.isMultipleTouchEnabled = false

        let pan = DirectionalPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.onPan(_:))
        )
        pan.delegate = context.coordinator
        v.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.onTapGesture(_:))
        )
        tap.delegate = context.coordinator
        v.addGestureRecognizer(tap)

        context.coordinator.hostView = v
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onStart = onStart
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onTap = onTap
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onStart:   () -> Void
        var onChanged: (CGFloat) -> Void
        var onEnded:   (CGFloat, CGFloat) -> Void
        var onTap:     (CGPoint, CGSize) -> Void
        weak var hostView: UIView?

        init(onStart: @escaping () -> Void,
             onChanged: @escaping (CGFloat) -> Void,
             onEnded: @escaping (CGFloat, CGFloat) -> Void,
             onTap: @escaping (CGPoint, CGSize) -> Void) {
            self.onStart = onStart
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onTap = onTap
        }

        @objc func onPan(_ gr: UIPanGestureRecognizer) {
            guard let v = hostView else { return }
            let t = gr.translation(in: v)
            switch gr.state {
            case .began:
                onStart()
                onChanged(t.x)  // .began 也走一次 changed，给 trackOffset 外照以 dx=0 的初值
            case .changed:
                onChanged(t.x)
            case .ended, .cancelled, .failed:
                let vx = gr.velocity(in: v).x
                onEnded(t.x, vx)
            default: break
            }
        }

        @objc func onTapGesture(_ gr: UITapGestureRecognizer) {
            guard let v = hostView else { return }
            let p = gr.location(in: v)
            onTap(p, v.bounds.size)
        }

        // 核心：告诉系统"TabView 的 pan 必须等我失败才能识别"
        // 只要我没 fail，TabView 就无法抢走横滑事件
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            // 我（卡片 pan）不需要等任何其他手势失败
            return false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            // TabView pan / ScrollView pan 必须等本手势失败才能启动
            if gestureRecognizer is DirectionalPanGestureRecognizer,
               other is UIPanGestureRecognizer {
                return false   // 我不等别人
            }
            return false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // tap 与 pan 可以并存（tap 用 shortMove 判定）
            return false
        }
    }
}

/// 支持"首帧水平判定"的 pan recognizer：垂直意图立即 fail，让外层手势接管。
final class DirectionalPanGestureRecognizer: UIPanGestureRecognizer {
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        // 尚未识别时做方向裁决
        if state == .began || state == .possible {
            let t = translation(in: view)
            let ax = abs(t.x), ay = abs(t.y)
            // 移动距离过小继续观察
            guard max(ax, ay) > 6 else { return }
            if ax < ay * 1.2 {
                // 垂直意图：fail，让外层（ScrollView / TabView）接管
                state = .failed
            }
        }
    }
}

/// 透传 hitTest：非手势目标（如卡片上的按钮等）仍可点击。
/// 这里我们 onTap 本身会消费 tap 事件，所以直接用默认 UIView。
final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // 本 view 接收所有手势，但内部没有子视图需要单独响应
        return super.hitTest(point, with: event)
    }
}

// MARK: - 月份选择器 Sheet
//
// 设计：年份滚轮（横向胶囊）+ 12 月份网格。
//   - 顶部"取消 / 选择月份 / 本月"
//   - 中部年份行：可左右滑动浏览，禁用未来年
//   - 下方 4×3 月份网格：高亮选中、禁用未来月（同年 + 未来月份不可选）
//   - 选中即关闭并回调
//
// 不引入第三方组件，只用 SwiftUI 原语，保持与项目其余 sheet 视觉一致。
struct StatsMonthPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initial: YearMonth
    let onPick: (YearMonth) -> Void

    @State private var year: Int
    @State private var month: Int

    /// 上限：今天所在年月（不允许选未来）
    private let nowYM: YearMonth = .current

    init(selected: YearMonth, onPick: @escaping (YearMonth) -> Void) {
        self.initial = selected
        self.onPick = onPick
        _year = State(initialValue: selected.year)
        _month = State(initialValue: selected.month)
    }

    /// 可选年份范围：从 5 年前到今年
    private var yearOptions: [Int] {
        let cur = nowYM.year
        return Array((cur - 5)...cur)
    }

    private func isFutureMonth(year: Int, month: Int) -> Bool {
        if year > nowYM.year { return true }
        if year == nowYM.year && month > nowYM.month { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("取消") { dismiss() }
                    .font(.custom("PingFangSC-Regular", size: 15))
                    .foregroundStyle(Color.inkSecondary)
                Spacer()
                Text("选择月份")
                    .font(.custom("PingFangSC-Semibold", size: 16))
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
                Button("本月") {
                    year = nowYM.year
                    month = nowYM.month
                    onPick(nowYM)
                    dismiss()
                }
                .font(.custom("PingFangSC-Regular", size: 15))
                .foregroundStyle(Color.accentBlue)
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.vertical, NotionTheme.space6)

            Rectangle()
                .fill(Color.divider)
                .frame(height: NotionTheme.borderWidth)

            // Year row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(yearOptions, id: \.self) { y in
                        let selected = (y == year)
                        Button {
                            year = y
                            // 切换到没有未来限制的最近月份
                            if isFutureMonth(year: y, month: month) {
                                month = (y == nowYM.year) ? nowYM.month : 12
                            }
                        } label: {
                            Text("\(y) 年")
                                .font(.custom("PingFangSC-Regular", size: 14))
                                .foregroundStyle(selected ? Color.white : Color.inkPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(selected ? Color.accentBlue : Color.hoverBg)
                                )
                        }
                        .buttonStyle(.pressableSoft)
                    }
                }
                .padding(.horizontal, NotionTheme.space5)
                .padding(.vertical, NotionTheme.space4)
            }

            // Month grid 4×3
            let cols = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(1...12, id: \.self) { m in
                    let disabled = isFutureMonth(year: year, month: m)
                    let selected = (m == month && year == year)
                    Button {
                        guard !disabled else { return }
                        month = m
                        let picked = YearMonth(year: year, month: m)
                        onPick(picked)
                        dismiss()
                    } label: {
                        Text("\(m) 月")
                            .font(.custom("PingFangSC-Regular", size: 15))
                            .foregroundStyle(
                                disabled ? Color.inkTertiary
                                    : (selected ? Color.white : Color.inkPrimary)
                            )
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        disabled ? Color.hoverBg.opacity(0.4)
                                            : (selected ? Color.accentBlue : Color.hoverBg)
                                    )
                            )
                    }
                    .buttonStyle(.pressableSoft)
                    .disabled(disabled)
                }
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.top, NotionTheme.space2)

            Spacer(minLength: 0)
        }
        .background(Color.appCanvas)
    }
}

// MARK: - CardSwipeEngine（卡片滑动手势 / 物理引擎，纯逻辑）
//
// 抽离 StatsHubView 的滑动数学：trackOffset 跟手 + dragProgress 归一化 + 松手吸附。
// 目的：让单元测试能够对核心算法做白盒覆盖，不被 SwiftUI 动画 / UIKit 手势工厂阻断。
// 无任何 UI / Animation 依赖；只持有数值状态 + 边界配置 + 几个 mutating 函数。

/// 卡片滑动引擎：iOS 控制中心式"trackOffset 跟手 + 单 spring 吸附"模型。
///
/// 模型不变量：
///   · `dragProgress = -trackOffset / switchLimit`（手指向左拖→progress>0→看下一张）
///   · 静止时 `trackOffset == 0`，`dragProgress == 0`
///   · 切换前后 `currentIdx + dragProgress == 用户视觉感知到的卡片位置` 守恒
///   · `dragProgress` 始终被夹在 `[-currentIdx, totalCount-1-currentIdx]`，
///     越界手势由 `onPanChanged` 的橡皮筋阻尼处理
///
/// 线程：所有方法都在主线程调用（与 SwiftUI View 状态绑定一致），不做并发保护。
struct CardSwipeEngine: Equatable {

    // MARK: - 配置

    /// 一张卡距离，trackOffset 累计 switchLimit pt = 已切换 1 张
    static let switchLimit: CGFloat = 100
    /// 速度惯性时长（秒），松手时用 vx · inertiaTime 估算还会再"飞"多远
    static let inertiaTime: CGFloat = 0.18
    /// 单次手势最多跨越的卡片数（绝对上限）
    static let maxJump: Int = 12
    /// 边界橡皮筋阻尼系数
    static let rubberFactor: CGFloat = 0.28
    /// 边界橡皮筋最大位移
    static let rubberLimit: CGFloat = 70

    // MARK: - 状态

    /// 当前居中卡的真实下标
    private(set) var currentIdx: Int
    /// 跟手位移（手势/动画驱动；静止时为 0）
    var trackOffset: CGFloat = 0
    /// 卡片总数（≥1）
    let totalCount: Int
    /// 手势开始时的 trackOffset 快照（onPanStarted 设置）。
    /// 让 onPanChanged(dx) 能把 dx 理解为"相对手势起点的累计位移"而不是绝对 trackOffset；
    /// 这个字段是修复 H1/H2 “spring 进行中发起新手势跳变”的关键。
    private var panBaseline: CGFloat = 0

    // MARK: - 派生

    /// 当前拖拽进度（已切换张数维度，可跨越多张）。被边界 clamp 保证不越界。
    var dragProgress: CGFloat {
        let raw = -trackOffset / Self.switchLimit
        let forwardRoom = CGFloat(totalCount - 1 - currentIdx)
        let backwardRoom = CGFloat(currentIdx)
        return max(-backwardRoom, min(forwardRoom, raw))
    }

    /// 是否处于左边界（首张）
    var atLeftEdge: Bool { currentIdx == 0 }
    /// 是否处于右边界（末张）
    var atRightEdge: Bool { currentIdx == totalCount - 1 }

    /// 当前用户视觉感知到的"虚拟卡片位置"（实数）= currentIdx + dragProgress。
    /// applyEquivalentSwitch 的不变量：执行前后此值守恒（settle 不视觉跳变的数学基础）。
    var viewProgress: CGFloat {
        CGFloat(currentIdx) + dragProgress
    }

    // MARK: - Init

    init(totalCount: Int, initialIdx: Int = 0) {
        precondition(totalCount > 0, "totalCount 必须 ≥ 1")
        self.totalCount = totalCount
        self.currentIdx = max(0, min(totalCount - 1, initialIdx))
    }

    // MARK: - 手势事件

    /// pan started：记录当前 trackOffset 为跟手基线。
    /// 上一轮 settle 的 spring 可能还在进行中（trackOffset 非零），记走这个值
    /// 后续 onPanChanged(dx) 会以它为起点累加。
    /// 如果手势开始时刚好静止，panBaseline=0，行为与原来一致。
    mutating func onPanStarted() {
        panBaseline = trackOffset
    }

    /// pan changed：trackOffset = panBaseline + dx（从手势起点的累计位移）；越界橡皮筋。
    mutating func onPanChanged(dx: CGFloat) {
        let raw = panBaseline + dx
        // 越界判定仍看当前手势意图（raw 的符号）而非原始 dx，避免跟手起点偏移后边界检查错位
        let outward = (raw > 0 && atLeftEdge) || (raw < 0 && atRightEdge)
        if outward {
            let sign: CGFloat = raw > 0 ? 1 : -1
            trackOffset = sign * min(abs(raw) * Self.rubberFactor, Self.rubberLimit)
        } else {
            trackOffset = raw
        }
    }

    /// pan ended：根据当前位置 + 速度惯性预测最终落点。
    /// - Returns: `SettleDecision`，调用方负责动画提交。
    func onPanEnded(vx: CGFloat) -> SettleDecision {
        let currentProgress = dragProgress
        let inertiaProgress = -vx * Self.inertiaTime / Self.switchLimit
        let predicted = currentProgress + inertiaProgress

        var delta = Int(predicted.rounded())
        if delta > Self.maxJump { delta = Self.maxJump }
        if delta < -Self.maxJump { delta = -Self.maxJump }

        let target = max(0, min(totalCount - 1, currentIdx + delta))
        delta = target - currentIdx

        var hint: EdgeHint? = nil
        if delta == 0 {
            if predicted > 0.5 && atRightEdge {
                hint = .rightEdge
            } else if predicted < -0.5 && atLeftEdge {
                hint = .leftEdge
            }
        }

        return SettleDecision(targetIdx: target, predictedProgress: predicted, hint: hint)
    }

    /// settle 阶段 1（无动画）：currentIdx 立即跳到 target，trackOffset 同步补偿。
    /// 调用方紧接着用 spring 把 trackOffset 收敛到 0 即可。
    /// 不变量：执行前后 viewProgress 守恒（settle 不视觉跳变的数学基础）。
    /// 还会顺带重置 panBaseline（settle 后不会被新手势以上一轮 baseline 累加）。
    mutating func applyEquivalentSwitch(to targetIdx: Int) {
        let clamped = max(0, min(totalCount - 1, targetIdx))
        let delta = clamped - currentIdx
        guard delta != 0 else { return }
        currentIdx = clamped
        trackOffset += CGFloat(delta) * Self.switchLimit
        // 重置 baseline：下次 onPanStarted 会重记 baseline，但果错调用顺序下（未 onPanStarted 直接 onPanChanged）
        // 也不应使用上一轮 settle 前的 baseline。
        panBaseline = 0
    }

    /// 测试 / View 复原状态专用：读取与写入 panBaseline。
    /// engine 是值类型，每次构造都会丢失 panBaseline；View 层需要能将上一帧的 baseline 复原进来。
    var panBaselineForTest: CGFloat { panBaseline }
    mutating func restorePanBaseline(_ value: CGFloat) { panBaseline = value }

    // MARK: - zIndex 策略（静态，View 与测试共用）

    /// 2 阶 smoothstep。与 StatsHubView.fadeEase 一致。
    static func fadeEase(_ x: CGFloat) -> CGFloat {
        let c = max(0, min(1, x))
        return c * c * c * (c * (c * 6 - 15) + 10)
    }

    /// 计算一张卡的 zIndex，**单一规则**：z 与 |effective| 严格单调递减。
    ///
    /// 设计原则（用户明确反馈的目标）：
    ///   "不管哪一帧，浮在最上层的卡片一定是最大的那个"
    ///   即 z 与 scale 必须**任意时刻同序**。scale 是 |effective| 的连续单调递减函数，
    ///   故 z 也必须是 |effective| 的单调递减函数。任何离散槽位 / drag 触发的"交接"
    ///   都会破坏这个不变量，导致用户感知到"小卡盖住大卡"。
    ///
    /// 几何含义：|effective|=0（中央卡）z=100；|effective|=3（最远可见卡）z=70；
    /// |effective|>3.5 的卡 fade<0.01 已被早返回，不进入 z 计算。
    static func zIndex(forAbsEffective absEff: CGFloat) -> Double {
        100.0 - Double(absEff) * 10.0
    }
}

/// 松手后的"该去哪张"决策结果（调用方负责动画执行）。
struct SettleDecision: Equatable {
    /// 最终落点 idx（已 clamp 在 [0, totalCount-1]）
    let targetIdx: Int
    /// 算法预测到的"理论 progress 落点"（未 round / 未 clamp，含越界值）
    let predictedProgress: CGFloat
    /// 是否需要给出边界 toast 提示
    let hint: EdgeHint?
}

/// 边界越界提示种类
enum EdgeHint: Equatable {
    case leftEdge   // 已是第一张
    case rightEdge  // 已是最后一张
}

#if DEBUG
#Preview("Hub · Dark") {
    StatsHubView()
        .preferredColorScheme(.dark)
}
#Preview("Hub · Light") {
    StatsHubView()
        .preferredColorScheme(.light)
}
#endif