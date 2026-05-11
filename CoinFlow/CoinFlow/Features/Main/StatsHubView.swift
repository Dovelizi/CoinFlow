//  StatsHubView.swift
//  CoinFlow · V2 Stats · 统计 Tab 主入口
//
//  设计基线：design/screens/05-stats/main-light.png（实际是 wallet 卡片堆叠样式）
//
//  形态：
//   - 顶部 NavBar："统计 / N 张报告 · YYYY 年 M 月" + 右上 grid icon
//   - Hero 区：本月净增大数字 + 收入/支出/笔数 mini KPI
//   - 中间：水平卡片堆栈（紧凑堆叠：中央 + 左右各 3，渐变切换无回弹）
//   - 底部：分页指示器 + 滑动提示
//
//  交互：
//   - 左右滑动：切换中央卡片（首末张为边界，越界给 toast 提示）— 手势层（HorizontalPanCatcher）水平铺满
//     整条卡片行，配合 UIKit 级 delegate 阻断，TabView 横滑永远抢不到手势
//   - 点击最上层卡（中央卡）任意位置：跳转到该卡对应的详情页面（push）
//   - 点击侧边卡区域（非中央卡矩形内）：归位到该方向的相邻卡（不跳转），
//     再次点击新的中央卡才跳转 — 避免误触发陌生页面
//   - 所有卡背景统一 surfaceOverlay 实色（完全不透明），内容垂直+水平居中，
//     外层 clipShape 保证不溢出卡片圆角边界
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
    @State private var currentIdx: Int = 0
    /// 横向拖拽偏移（由 UIKit pan catcher 驱动）
    @State private var dragOffsetX: CGFloat = 0
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
            .navigationDestination(for: StatsAnalysisDestination.self) { dest in
                destinationView(dest)
            }
            // 词云 / 分类排行点击某个分类 → 直达该分类详情页
            .navigationDestination(for: CategoryDetailTarget.self) { target in
                StatsCategoryDetailView(preferredCategoryId: target.categoryId,
                                        month: vm.month)
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
        if edgeHint != text {
            withAnimation(Motion.exit(0.18)) { edgeHint = text }
        }
        edgeHintTask?.cancel()
        let task = DispatchWorkItem { [text] in
            // 仅当当前显示的还是这条文本时才隐藏（避免覆盖更新的 toast）
            if edgeHint == text {
                withAnimation(Motion.standard(0.22)) { edgeHint = nil }
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
    // 设计：紧凑堆叠 + 渐变切换（A 缩小淡出 / B 放大淡入）
    //   - 静态时：卡片紧凑堆叠，左右各 3 张露边（offsetBase 等差 32pt）
    //   - 拖拽时：手指方向触发 progress；中央卡 scale↓ + opacity↓，相邻卡 scale↑ + opacity↑
    //     位移仅做"轻微跟手暗示"（×0.18），主要靠渐变表达切换意图
    //   - 切换：使用 easeOut（无回弹），currentIdx +=1 + dragOffsetX 归零，
    //     由于位移幅度极小（最大 ~50pt），切换瞬间无可感知跳变
    //   - drawingGroup()/compositingGroup 做 GPU 离屏合成

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
        .init(scale: 0.94, offsetBase: 32,
              shadowRadius: 14, shadowOpacity: 0.12, shadowY: 5,
              fadeOpacity: 0.88),
        // absSlot = 2
        .init(scale: 0.88, offsetBase: 60,
              shadowRadius: 8,  shadowOpacity: 0.06, shadowY: 3,
              fadeOpacity: 0.55),
        // absSlot = 3（最外，作为入场/出场缓冲，平时几乎不可见）
        .init(scale: 0.82, offsetBase: 84,
              shadowRadius: 4,  shadowOpacity: 0.0, shadowY: 1,
              fadeOpacity: 0.0),
    ]

    /// 最大可见层数（中央外左右各 N 张），= slotTable.count - 1
    private static let maxAbsSlot: Int = 3

    /// 卡片宽度 / 高度（用户反馈：中间卡片适当调大；260→290 / 360→400）
    private static let cardWidth: CGFloat = 290
    private static let cardHeight: CGFloat = 400

    /// 拖拽切换阈值（手指水平移动多少视为完成切换）。
    /// 紧凑堆叠下不做 1:1 跟手位移，所以 limit 与切换阈值合并：
    /// 拖过 100pt 即视为完成切换（dragProgress=±1）。
    private static let switchLimit: CGFloat = 100

    /// 当前拖拽进度：-1 ... 1（负=左拖切下一张，正=右拖切上一张）。
    private var dragProgress: CGFloat {
        max(-1, min(1, dragOffsetX / Self.switchLimit))
    }

    private var horizontalCardStack: some View {
        let cardW = Self.cardWidth
        let cardH = Self.cardHeight

        // 7 张可见：slotOffset ∈ [-3, ..., 3]，按边界裁剪（不再循环）
        // 实际只有 abs<=2 的卡有可见 opacity；abs=3 作为入场缓冲用于拖拽时淡入
        //
        // 边界处理：去掉循环。currentIdx 在两端时不再绕回，仅渲染存在的下标，
        // 这样首张左侧 / 末张右侧空缺，符合"不能再往那边滑"的视觉预期。
        let range = Self.maxAbsSlot
        let visibleSlots: [(slotOffset: Int, cardIdx: Int)] = (-range...range).compactMap {
            let idx = currentIdx + $0
            guard idx >= 0 && idx < totalCardCount else { return nil }
            return ($0, idx)
        }

        return ZStack {
            ForEach(visibleSlots, id: \.slotOffset) { slot in
                slotCardView(slot: slot, cardW: cardW, cardH: cardH)
            }
            // UIKit 手势拦截层：占满卡片堆叠行（水平铺满屏幕），独占水平 pan；
            // 这样无论手指落在卡片带的任何位置，TabView 都无法抢走手势，
            // 从根本上避免"左右滑卡片 → 整屏跟着滑"的串扰。
            // 视觉上卡片 x 位移在 slotCardView 内做 clamp，不会超出 cardW + 侧卡展开宽度。
            //
            // 关键：UIViewRepresentable 默认没有 intrinsic size，必须显式给 frame
            // 铺满 ZStack，否则 catcher 尺寸为 0 → tap/pan 都不会触发（点击/滑动全失效）
            HorizontalPanCatcher(
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
            // 必须高于所有卡片的 zIndex（中央卡 = 100），否则中央卡会吃掉 tap/pan
            // 这是 SwiftUI ZStack 的坑：显式 zIndex 会覆盖"后入者居上"的默认叠放顺序
            .zIndex(999)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardH + 32)
        .contentShape(Rectangle())
    }

    // MARK: - UIKit pan 回调

    /// 是否处于左边界（首张，不能再向"上一张"方向滑 = 手势 dx > 0 = 向右拖）
    private var atLeftEdge: Bool { currentIdx == 0 }
    /// 是否处于右边界（末张，不能再向"下一张"方向滑 = 手势 dx < 0 = 向左拖）
    private var atRightEdge: Bool { currentIdx == totalCardCount - 1 }

    private func handlePanChanged(dx: CGFloat) {
        // 边界橡皮筋：在边界向外侧拖时强阻尼 + clamp，让用户感到"拉得动但很重"。
        // 中部正常拖：超过 switchLimit 后加重阻尼（×0.35），保持手感但避免拖出去太远。
        let outward = (dx > 0 && atLeftEdge) || (dx < 0 && atRightEdge)
        let damped: CGFloat
        if outward {
            let sign: CGFloat = dx > 0 ? 1 : -1
            damped = sign * min(abs(dx) * 0.28, 70)
        } else {
            let limit = Self.switchLimit
            if abs(dx) > limit {
                let excess = abs(dx) - limit
                damped = (dx > 0 ? 1 : -1) * (limit + excess * 0.35)
            } else {
                damped = dx
            }
        }
        dragOffsetX = damped
    }

    private func handlePanEnded(dx: CGFloat, vx: CGFloat) {
        // 切换阈值：位移过 switchLimit 的 50% 或速度足够大
        let threshold: CGFloat = Self.switchLimit * 0.5
        let rawDelta: Int
        if vx < -500 || dx < -threshold {
            rawDelta = 1
        } else if vx > 500 || dx > threshold {
            rawDelta = -1
        } else {
            rawDelta = 0
        }

        // 边界判定：若意图越过边界，吞掉 delta 并提示
        var delta = rawDelta
        if rawDelta == 1 && atRightEdge {
            delta = 0
            showEdgeHint("已是最后一张")
        } else if rawDelta == -1 && atLeftEdge {
            delta = 0
            showEdgeHint("已是第一张")
        }

        // 切换动画：用 easeOut 替代 spring —— 无回弹，纯粹的"减速到位"
        // A 渐隐缩小 / B 渐显放大 靠 slotCardView 的形态插值完成，timing curve 决定节奏
        // duration 0.42s：与之前 spring response 手感匹配，舒展但不拖沓
        withAnimation(Motion.smooth) {
            if delta != 0 {
                currentIdx = max(0, min(totalCardCount - 1, currentIdx + delta))
            }
            dragOffsetX = 0
        }
    }

    /// 从 slot 预计算几何 → 生成单张卡视图（紧凑堆叠 + 渐变切换）。
    ///
    /// 数学模型：
    ///   - effectiveSlot = slotOffset - dragProgress（拖拽视为整组虚拟向反方向滑了 |drag| 格）
    ///   - 形态属性（scale / opacity / shadow / offsetBase）按 effective slot 在 slotTable 相邻档插值
    ///     → 中央卡（slot=0）拖到 progress=±1 时，effective=±1，形态变为 abs=1 档（变小变淡）
    ///     → 相邻卡（slot=±1，与拖拽方向相反那张）effective=0，变为中央档（变大变实）
    ///     → 这就是用户描述的"A 缩小淡出 + B 放大淡入"
    ///   - 位移 x = effective slot 的插值后 offset + dragOffsetX × 0.18（轻微跟手暗示方向）
    ///     ×0.18 系数：拖 100pt 时整组只挪 18pt，远小于 32pt 堆叠间距，
    ///     切换瞬间归零的视觉跳变 < 18pt，肉眼无感
    @ViewBuilder
    private func slotCardView(slot: (slotOffset: Int, cardIdx: Int),
                              cardW: CGFloat, cardH: CGFloat) -> some View {
        let drag = dragProgress
        let effective = CGFloat(slot.slotOffset) - drag

        // 形态属性按 effective slot 在相邻档插值
        let absEff = abs(effective)
        let lowerIdx = min(Int(floor(absEff)), Self.maxAbsSlot)
        let upperIdx = min(lowerIdx + 1, Self.maxAbsSlot)
        let t = max(0, min(1, absEff - CGFloat(lowerIdx)))
        let lower = Self.slotTable[lowerIdx]
        let upper = Self.slotTable[upperIdx]

        let scale = lower.scale + (upper.scale - lower.scale) * t
        let fade  = lower.fadeOpacity + (upper.fadeOpacity - lower.fadeOpacity) * Double(t)
        let offsetMag = lower.offsetBase + (upper.offsetBase - lower.offsetBase) * t
        let shadowR  = lower.shadowRadius + (upper.shadowRadius - lower.shadowRadius) * t
        let shadowOp = lower.shadowOpacity + (upper.shadowOpacity - lower.shadowOpacity) * Double(t)
        let shadowY  = lower.shadowY + (upper.shadowY - lower.shadowY) * t

        // 方向：effective 的符号决定卡片在中央哪一侧
        let dir: CGFloat = effective >= 0 ? 1 : -1
        // 位移 = 静态堆叠位置 + 轻微跟手暗示（×0.18）
        // 不做 1:1 跟手，避免破坏紧凑堆叠的视觉布局
        let x = dir * offsetMag + dragOffsetX * 0.18

        // zIndex：以 effective 距中央距离递减；越接近中央越靠前
        let z: Double = 100 - Double(absEff) * 10

        let isCenter = slot.slotOffset == 0

        cardView(allCards[slot.cardIdx], isCenter: isCenter)
            .frame(width: cardW, height: cardH)
            .scaleEffect(scale)
            .opacity(fade)
            .offset(x: x, y: 0)
            .shadow(color: Color.black.opacity(shadowOp),
                    radius: shadowR, y: shadowY)
            .zIndex(z)
            .allowsHitTesting(false)
    }

    /// 容器 tap 派发：
    /// - 只有"最上层卡片"（中央卡，slotOffset = 0）的矩形区域响应跳转
    /// - 侧边区域 tap 视为"归位到那个方向"的单步切换（不跳转），
    ///   这样下次再点击已成为中央卡的详情，保持"最上层卡片任意位置跳详情"的可发现性
    private func handleContainerTap(location: CGPoint,
                                    containerSize: CGSize,
                                    cardW: CGFloat,
                                    cardH: CGFloat) {
        // 以容器中心为原点（catcher 本身水平铺满屏幕，中心 = 屏宽/2）
        let dx = location.x - containerSize.width / 2
        let dy = location.y - containerSize.height / 2
        // 中央卡实际可视矩形：宽 cardW, 高 cardH（scale=1.0, offset=0）
        let inCenterCard = abs(dx) <= cardW / 2 && abs(dy) <= cardH / 2
        if inCenterCard {
            navPath.append(allCards[currentIdx].id)
        } else {
            // 侧边 → 归位一张（同样尊重边界，与 pan 切换使用一致的 easeOut 无回弹曲线）
            let delta = dx > 0 ? 1 : -1
            let target = currentIdx + delta
            guard target >= 0 && target < totalCardCount else {
                // 已是边界，不归位，给与拖拽相同的提示
                showEdgeHint(delta > 0 ? "已是最后一张" : "已是第一张")
                return
            }
            withAnimation(Motion.smooth) {
                currentIdx = target
            }
        }
    }

    // MARK: - 单张卡片

    @ViewBuilder
    private func cardView(_ card: HubCard, isCenter: Bool) -> some View {
        // 所有卡：整体内容垂直+水平居中于卡片中央；
        // 文本/数字做 lineLimit + minimumScaleFactor 防溢出；
        // 外层 clipShape 保证任何子视图不会突破圆角。
        let preview = previewContent(for: card)

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
        // Metal 离屏合成：把整张卡"栅格化"，scale/offset 变化时 GPU 直接搬运像素
        // 不再触发 SwiftUI 重新布局子视图，滚动帧率从 ~40fps → 60fps
        .compositingGroup()
    }

    // MARK: - 卡片预览数据（hero / insight）

    private struct CardPreview { let heroValue: String; let insight: String }

    private func previewContent(for card: HubCard) -> CardPreview {
        switch card.id {
        case .trend:
            let avg = vm.dailyTrend30.isEmpty ? 0 :
                vm.dailyTrend30.map(\.expense).reduce(Decimal(0), +) / Decimal(vm.dailyTrend30.count)
            return CardPreview(
                heroValue: "¥" + StatsFormat.compactK(avg),
                insight: "近 30 天日均支出"
            )
        case .sankey:
            return CardPreview(
                heroValue: "¥\(StatsFormat.compactK(vm.monthlyIncome)) → ¥\(StatsFormat.compactK(vm.monthlyExpense))",
                insight: vm.expenseCategorySlices.first.map { "\($0.name)占 \(Int($0.percentage * 100))%" }
                    ?? "查看资金流向"
            )
        case .wordcloud:
            let top = vm.expenseCategorySlices.first?.name ?? "—"
            return CardPreview(heroValue: top, insight: "本月最大支出分类")
        case .budget:
            let cur = vm.monthlyExpense
            let target = vm.prevMonthExpense > 0
                ? vm.prevMonthExpense * Decimal(string: "1.1")! : cur
            let pct = target > 0
                ? (cur as NSDecimalNumber).doubleValue / (target as NSDecimalNumber).doubleValue * 100
                : 0
            return CardPreview(
                heroValue: String(format: "%.0f%%", pct),
                insight: cur > target ? "本月已超出估算预算" : "预算执行良好"
            )
        case .main:
            // 本月统计：净增（收入 - 支出）+ 收支笔数
            let net = vm.monthlyIncome - vm.monthlyExpense
            let sign = net >= 0 ? "+" : "-"
            let absNet = net >= 0 ? net : -net
            let cal = Calendar.current
            let now = Date()
            let monthRecords = vm.allRecords.filter {
                cal.isDate($0.occurredAt, equalTo: now, toGranularity: .month)
            }
            let incomeCount = monthRecords.filter {
                (vm.categoriesById[$0.categoryId]?.kind ?? .expense) == .income
            }.count
            let expenseCount = monthRecords.filter {
                (vm.categoriesById[$0.categoryId]?.kind ?? .expense) == .expense
            }.count
            return CardPreview(
                heroValue: sign + "¥" + StatsFormat.compactK(absNet),
                insight: "收 \(incomeCount) 笔 · 支 \(expenseCount) 笔"
            )
        case .aa:
            let aaCount = vm.allRecords.filter { ($0.participants?.count ?? 0) > 0 }.count
            return CardPreview(
                heroValue: aaCount > 0 ? "\(aaCount) 笔" : "—",
                insight: aaCount > 0 ? "本月共享账单笔数" : "等待启用 AA"
            )
        case .category:
            let top = vm.expenseCategorySlices.first
            return CardPreview(
                heroValue: top.map { "¥" + StatsFormat.decimalGrouped($0.amount) } ?? "—",
                insight: top.map { "\($0.name) · \($0.count) 笔" } ?? "暂无支出"
            )
        case .year:
            let total = vm.last12Months.map(\.expense).reduce(Decimal(0), +)
            return CardPreview(
                heroValue: "¥" + StatsFormat.compactK(total),
                insight: "近 12 月累计支出"
            )
        case .hourly:
            let peak = vm.hourlyDistribution.max(by: { $0.amount < $1.amount })
            return CardPreview(
                heroValue: peak.map { String(format: "%02d:00", $0.hour) } ?? "—",
                insight: peak.map { "高峰时段 · ¥" + StatsFormat.decimalGrouped($0.amount) } ?? "暂无数据"
            )
        case .summary:
            // 同步轻查询：取 listAll 第一条作为最新一次复盘的预览
            // listAll 走 SQLite 单行索引扫描，DB ready 时几毫秒，view 重渲不会成为瓶颈
            let latest = (try? SQLiteBillsSummaryRepository.shared.listAll(includesDeleted: false))?.first
            if let s = latest {
                let kindLabel: String = {
                    switch s.periodKind {
                    case .week:  return "周报"
                    case .month: return "月报"
                    case .year:  return "年报"
                    }
                }()
                let digest = s.summaryDigest.isEmpty ? "查看完整 AI 复盘" : s.summaryDigest
                return CardPreview(heroValue: kindLabel, insight: digest)
            } else {
                return CardPreview(heroValue: "—", insight: "暂无复盘 · 点击查看历史")
            }
        }
    }

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
    let onChanged: (CGFloat) -> Void                      // 累计水平位移
    let onEnded:   (CGFloat, CGFloat) -> Void             // 位移 + 速度 (pts/s)
    let onTap:     (CGPoint, CGSize) -> Void              // tap 坐标 + 容器尺寸（用于 slot 判定）

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded, onTap: onTap)
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
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onTap = onTap
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGFloat) -> Void
        var onEnded:   (CGFloat, CGFloat) -> Void
        var onTap:     (CGPoint, CGSize) -> Void
        weak var hostView: UIView?

        init(onChanged: @escaping (CGFloat) -> Void,
             onEnded: @escaping (CGFloat, CGFloat) -> Void,
             onTap: @escaping (CGPoint, CGSize) -> Void) {
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onTap = onTap
        }

        @objc func onPan(_ gr: UIPanGestureRecognizer) {
            guard let v = hostView else { return }
            let t = gr.translation(in: v)
            switch gr.state {
            case .began, .changed:
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
