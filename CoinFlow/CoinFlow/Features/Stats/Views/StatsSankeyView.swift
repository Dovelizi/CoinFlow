//  StatsSankeyView.swift
//  CoinFlow · V2 Stats · 资金流向（桑基图）
//
//  设计基线：design/screens/05-stats/main-light.png（实际是 sankey）
//  - 左：收入分类（绿色族）；右：支出分类（多色）；中间：贝塞尔流量带
//  - 流量带宽 = 该收入按总支出占比映射到该支出节点
//  - 实现：自绘 GeometryReader + Path 贝塞尔；渐变色 = income.color * 0.35

import SwiftUI

struct StatsSankeyView: View {
    @StateObject private var vm = StatsViewModel()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            StatsSubNavBar(title: "资金流向",
                           subtitle: StatsFormat.ymSubtitle(vm.month),
                           trailingIcon: "square.and.arrow.up")
            ScrollView {
                VStack(spacing: NotionTheme.space7) {
                    if vm.incomeCategorySlices.isEmpty || vm.expenseCategorySlices.isEmpty {
                        StatsEmptyState(title: "数据不足",
                                        subtitle: "需要本月有收入和支出记录，才能展示资金流向")
                            .frame(height: 360)
                    } else {
                        sankeyCard
                        legendCard
                    }
                }
                .padding(.horizontal, NotionTheme.space5)
                .padding(.top, NotionTheme.space6)
                .padding(.bottom, NotionTheme.space9)
            }
        }
        .background(ThemedBackgroundLayer(kind: .stats))
        .navigationBarHidden(true)
        .onAppear { vm.reload() }
    }

    private var sankeyCard: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            HStack {
                Text("收入 → 支出")
                    .font(.custom("PingFangSC-Semibold", size: 14))
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
                Text("总计 ¥\(StatsFormat.compactK(vm.monthlyIncome)) → ¥\(StatsFormat.compactK(vm.monthlyExpense))")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
            }
            .padding(.leading, 4)

            StatsSankeyDiagram(income: vm.incomeCategorySlices,
                               outgo: vm.expenseCategorySlices,
                               scheme: scheme)
                .frame(height: 320)
                .padding(NotionTheme.space5)
                .background(
                    RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                        .fill(Color.hoverBg.opacity(0.5))
                )
        }
    }

    private var legendCard: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            Text("流入流出明细")
                .font(.custom("PingFangSC-Semibold", size: 14))
                .foregroundStyle(Color.inkPrimary)
                .padding(.leading, 4)

            HStack(alignment: .top, spacing: NotionTheme.space5) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("收入来源")
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.inkTertiary)
                    ForEach(vm.incomeCategorySlices.prefix(8)) { n in
                        legendRow(name: n.name, amount: n.amount, color: n.tone.text(scheme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("支出去向")
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.inkTertiary)
                    ForEach(vm.expenseCategorySlices.prefix(8)) { n in
                        legendRow(name: n.name, amount: n.amount, color: n.tone.text(scheme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(NotionTheme.space5)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                    .fill(Color.hoverBg.opacity(0.5))
            )
        }
    }

    @ViewBuilder
    private func legendRow(name: String, amount: Decimal, color: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(name)
                .font(NotionFont.small())
                .foregroundStyle(Color.inkPrimary)
            Spacer()
            Text("¥" + StatsFormat.intGrouped(amount))
                .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.inkSecondary)
        }
    }
}

// MARK: - 桑基图核心绘制

struct StatsSankeyDiagram: View {
    let income: [StatsCategorySlice]
    let outgo:  [StatsCategorySlice]
    let scheme: ColorScheme

    private struct Band: Identifiable {
        let id = UUID()
        let i: Int
        let j: Int
        let startYTop: CGFloat
        let startHeight: CGFloat
        let endYTop: CGFloat
        let endHeight: CGFloat
    }

    private struct Layout {
        let leftX: CGFloat
        let rightX: CGFloat
        let nodeW: CGFloat
        let leftYStart:   [CGFloat]
        let leftHeights:  [CGFloat]
        let rightYStart:  [CGFloat]
        let rightHeights: [CGFloat]
        let bands: [Band]
    }

    var body: some View {
        GeometryReader { geo in
            let layout = computeLayout(width: geo.size.width, height: geo.size.height)
            ZStack {
                ForEach(layout.bands) { b in
                    SankeyBandShape(
                        startX: layout.leftX + layout.nodeW,
                        startYTop: b.startYTop,
                        startHeight: b.startHeight,
                        endX: layout.rightX,
                        endYTop: b.endYTop,
                        endHeight: b.endHeight,
                        color: income[b.i].tone.text(scheme).opacity(0.35)
                    )
                }
                ForEach(0..<income.count, id: \.self) { i in
                    nodeRect(x: layout.leftX, y: layout.leftYStart[i],
                             width: layout.nodeW, height: layout.leftHeights[i],
                             color: income[i].tone.text(scheme),
                             label: income[i].name, amount: income[i].amount, isLeft: true)
                }
                ForEach(0..<outgo.count, id: \.self) { i in
                    nodeRect(x: layout.rightX, y: layout.rightYStart[i],
                             width: layout.nodeW, height: layout.rightHeights[i],
                             color: outgo[i].tone.text(scheme),
                             label: outgo[i].name, amount: outgo[i].amount, isLeft: false)
                }
            }
        }
    }

    private func computeLayout(width w: CGFloat, height h: CGFloat) -> Layout {
        let nodeW: CGFloat = 16
        let leftX: CGFloat = 0
        let rightX: CGFloat = w - nodeW
        let gap: CGFloat = 8

        let totalIncome = income.map { ($0.amount as NSDecimalNumber).doubleValue }.reduce(0, +)
        let totalOutgo  = outgo.map  { ($0.amount as NSDecimalNumber).doubleValue }.reduce(0, +)
        guard totalIncome > 0, totalOutgo > 0 else {
            return Layout(leftX: leftX, rightX: rightX, nodeW: nodeW,
                          leftYStart: [], leftHeights: [],
                          rightYStart: [], rightHeights: [], bands: [])
        }

        let usableLeftH  = h - CGFloat(max(0, income.count - 1)) * gap
        let usableRightH = h - CGFloat(max(0, outgo.count - 1)) * gap

        let leftHeights = income.map {
            CGFloat(($0.amount as NSDecimalNumber).doubleValue / totalIncome) * usableLeftH
        }
        let rightHeights = outgo.map {
            CGFloat(($0.amount as NSDecimalNumber).doubleValue / totalOutgo) * usableRightH
        }

        var leftYStart: [CGFloat] = []; var cur: CGFloat = 0
        for hh in leftHeights { leftYStart.append(cur); cur += hh + gap }
        var rightYStart: [CGFloat] = []; cur = 0
        for hh in rightHeights { rightYStart.append(cur); cur += hh + gap }

        var bands: [Band] = []
        var leftSubOffset:  [CGFloat] = Array(repeating: 0, count: income.count)
        var rightSubOffset: [CGFloat] = Array(repeating: 0, count: outgo.count)
        for i in 0..<income.count {
            for j in 0..<outgo.count {
                let outFrac = (outgo[j].amount as NSDecimalNumber).doubleValue / totalOutgo
                let inFrac  = (income[i].amount as NSDecimalNumber).doubleValue / totalIncome
                let bandStartH = leftHeights[i] * CGFloat(outFrac)
                let bandEndH   = rightHeights[j] * CGFloat(inFrac)
                bands.append(Band(
                    i: i, j: j,
                    startYTop: leftYStart[i] + leftSubOffset[i],
                    startHeight: bandStartH,
                    endYTop: rightYStart[j] + rightSubOffset[j],
                    endHeight: bandEndH
                ))
                leftSubOffset[i]  += bandStartH
                rightSubOffset[j] += bandEndH
            }
        }
        return Layout(
            leftX: leftX, rightX: rightX, nodeW: nodeW,
            leftYStart: leftYStart, leftHeights: leftHeights,
            rightYStart: rightYStart, rightHeights: rightHeights,
            bands: bands
        )
    }

    @ViewBuilder
    private func nodeRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
                          color: Color, label: String, amount: Decimal, isLeft: Bool) -> some View {
        ZStack(alignment: isLeft ? .leading : .trailing) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: width, height: max(8, height))
                .position(x: x + width / 2, y: y + height / 2)
            VStack(alignment: isLeft ? .leading : .trailing, spacing: 1) {
                Text(label)
                    .font(.custom("PingFangSC-Semibold", size: 11))
                    .foregroundStyle(Color.inkPrimary)
                Text("¥\((amount as NSDecimalNumber).intValue)")
                    .font(.system(size: 10, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.inkTertiary)
            }
            .position(
                x: isLeft ? x + width + 36 : x - 36,
                y: y + height / 2
            )
        }
    }
}

/// 单条流量带（贝塞尔曲线）。
struct SankeyBandShape: View {
    let startX: CGFloat
    let startYTop: CGFloat
    let startHeight: CGFloat
    let endX: CGFloat
    let endYTop: CGFloat
    let endHeight: CGFloat
    let color: Color

    var body: some View {
        Path { p in
            let mid = (startX + endX) / 2
            p.move(to: CGPoint(x: startX, y: startYTop))
            p.addCurve(to: CGPoint(x: endX, y: endYTop),
                       control1: CGPoint(x: mid, y: startYTop),
                       control2: CGPoint(x: mid, y: endYTop))
            p.addLine(to: CGPoint(x: endX, y: endYTop + endHeight))
            p.addCurve(to: CGPoint(x: startX, y: startYTop + startHeight),
                       control1: CGPoint(x: mid, y: endYTop + endHeight),
                       control2: CGPoint(x: mid, y: startYTop + startHeight))
            p.closeSubpath()
        }
        .fill(color)
    }
}
