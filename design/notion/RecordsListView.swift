// RecordsListView.swift  (v2 — Notion-faithful, dark-default, PingFang)
//
// 重做要点（针对 v1 的 5 条反馈）：
//   1. 去掉彩色 callout 卡 → 改为 Notion-true 的 inline stats（极简灰阶 + 仅金额上色）
//   2. Icon 风格统一为细线条 1.5px（SF Symbols `.regular` weight 模拟 Phosphor；W3 切真实 Phosphor SPM）
//   3. 字体改为 PingFang SC（系统中文字体），字号 + 字重 + status color 表达层次
//   4. 段头新增视图切换器：List（平铺）/ Stack（扑克叠）/ Grid（2 列网格）
//   5. 默认深色，浅色仅作为 Preview 对照
//
// Token 仍引用 NotionTheme.swift + NotionTheme+Aliases.swift；本文件零裸 hex（除 NotionColor 内部）

import SwiftUI

// MARK: - 数据模型（与 §3.1 record 表对齐，未变）

struct RecordRow: Identifiable, Hashable {
    let id: String
    let categoryName: String
    let categoryIcon: String        // SF Symbol（W3 → Phosphor name）
    let categoryColor: NotionColor
    let amount: Decimal
    let direction: Direction
    let note: String
    let occurredAt: Date
    let source: Source
    let syncStatus: SyncStatus
    let isAA: Bool
}

enum Direction { case expense, income }

enum Source: String {
    case manual      = "手动"
    case ocrVision   = "本地OCR"
    case ocrAPI      = "OCR-API"
    case ocrLLM      = "大模型"
    case voiceLocal  = "本地语音"
    case voiceCloud  = "云端语音"
}

enum SyncStatus { case pending, syncing, synced, failed, dead }

enum NotionColor: String, CaseIterable {
    case `default`, gray, brown, orange, yellow, green, blue, purple, pink, red

    func text(_ scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.default, _):       return .inkPrimary
        case (.gray, .light):     return Color(hex: "787774"); case (.gray, .dark):     return Color(hex: "9B9A97")
        case (.brown, .light):    return Color(hex: "9F6B53"); case (.brown, .dark):    return Color(hex: "BA856F")
        case (.orange, .light):   return Color(hex: "D9730D"); case (.orange, .dark):   return Color(hex: "C77D48")
        case (.yellow, .light):   return Color(hex: "CB912F"); case (.yellow, .dark):   return Color(hex: "CA9849")
        case (.green, .light):    return Color(hex: "448361"); case (.green, .dark):    return Color(hex: "529E72")
        case (.blue, .light):     return Color(hex: "337EA9"); case (.blue, .dark):     return Color(hex: "5E87C9")
        case (.purple, .light):   return Color(hex: "9065B0"); case (.purple, .dark):   return Color(hex: "9D68D3")
        case (.pink, .light):     return Color(hex: "C14C8A"); case (.pink, .dark):     return Color(hex: "D15796")
        case (.red, .light):      return Color(hex: "D44C47"); case (.red, .dark):      return Color(hex: "DF5452")
        @unknown default:         return .inkPrimary
        }
    }

    func background(_ scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.default, _):     return .clear
        case (.gray, .light):   return Color(hex: "787774", alpha: 0.20); case (.gray, .dark):   return Color(hex: "9B9A97", alpha: 0.16)
        case (.brown, .light):  return Color(hex: "8C2E00", alpha: 0.20); case (.brown, .dark):  return Color(hex: "BA856F", alpha: 0.16)
        case (.orange, .light): return Color(hex: "F55D00", alpha: 0.20); case (.orange, .dark): return Color(hex: "C77D48", alpha: 0.16)
        case (.yellow, .light): return Color(hex: "E9A800", alpha: 0.20); case (.yellow, .dark): return Color(hex: "CA9849", alpha: 0.16)
        case (.green, .light):  return Color(hex: "00876B", alpha: 0.20); case (.green, .dark):  return Color(hex: "529E72", alpha: 0.16)
        case (.blue, .light):   return Color(hex: "0078DF", alpha: 0.20); case (.blue, .dark):   return Color(hex: "5E87C9", alpha: 0.16)
        case (.purple, .light): return Color(hex: "6724DE", alpha: 0.20); case (.purple, .dark): return Color(hex: "9D68D3", alpha: 0.16)
        case (.pink, .light):   return Color(hex: "DD0081", alpha: 0.20); case (.pink, .dark):   return Color(hex: "D15796", alpha: 0.16)
        case (.red, .light):    return Color(hex: "FF001A", alpha: 0.20); case (.red, .dark):    return Color(hex: "DF5452", alpha: 0.16)
        @unknown default:       return .clear
        }
    }
}

// MARK: - PingFang 字体扩展（替代 NotionTheme.xxx() 中的 Inter）

enum NotionFont {
    static func title()    -> Font { .custom("PingFangSC-Semibold", size: 36) }
    static func h1()       -> Font { .custom("PingFangSC-Semibold", size: 24) }
    static func h2()       -> Font { .custom("PingFangSC-Medium",   size: 20) }
    static func h3()       -> Font { .custom("PingFangSC-Medium",   size: 17) }
    static func body()     -> Font { .custom("PingFangSC-Regular",  size: 15) }
    static func bodyBold() -> Font { .custom("PingFangSC-Medium",   size: 15) }
    static func small()    -> Font { .custom("PingFangSC-Regular",  size: 13) }
    static func micro()    -> Font { .custom("PingFangSC-Regular",  size: 11) }
    /// 数字专用——金额永远等宽便于纵向对齐
    static func amount(size: CGFloat = 15) -> Font {
        .system(size: size, weight: .medium, design: .rounded).monospacedDigit()
    }
    static func amountBold(size: CGFloat = 15) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }
}

// MARK: - 视图切换枚举

enum RecordsLayout: String, CaseIterable {
    case list, stack, grid

    var iconName: String {
        switch self {
        case .list:  return "list.bullet"
        case .stack: return "rectangle.stack"
        case .grid:  return "square.grid.2x2"
        }
    }

    var label: String {
        switch self {
        case .list:  return "平铺"
        case .stack: return "堆叠"
        case .grid:  return "网格"
        }
    }
}

// MARK: - 顶部 Inline Stats（去掉彩色 callout，回归 Notion 的纯文本 + 灰阶）

struct MonthSummary {
    let monthLabel: String
    let expense:    Decimal
    let income:     Decimal
    var balance:    Decimal { income - expense }
}

struct InlineStatsBar: View {
    let summary: MonthSummary
    @Environment(\.colorScheme) var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            statItem(label: "支出", amount: summary.expense, tone: .red)
            verticalSeparator
            statItem(label: "收入", amount: summary.income,  tone: .green)
            verticalSeparator
            statItem(label: "结余", amount: summary.balance, tone: summary.balance >= 0 ? .default : .red)
        }
    }

    /// 三段等宽分布（避免某一段金额过长把其他段挤压换行）
    private func statItem(label: String, amount: Decimal, tone: NotionColor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(NotionFont.micro())
                .foregroundColor(.inkTertiary)
            Text(formatted(amount))
                .font(NotionFont.amountBold(size: 17))            // 18 → 17，留余量
                .foregroundColor(tone == .default ? .inkPrimary : tone.text(scheme))
                .lineLimit(1)                                      // 强制单行，防换行
                .minimumScaleFactor(0.7)                           // 万一极长金额则等比缩小
        }
        .frame(maxWidth: .infinity, alignment: .leading)           // 三段等分剩余宽度
    }

    private var verticalSeparator: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(width: 1, height: 28)
            .padding(.horizontal, NotionTheme.space5)              // 改为左右各 12pt 对称分隔
    }

    /// 不展示末尾 0：12500.00 → "12,500"；3245.80 → "3,245.8"；0.05 → "0.05"
    private func formatted(_ d: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        let s = f.string(from: d as NSDecimalNumber) ?? "0"
        return "¥" + s
    }
}

// MARK: - List 视图：单条流水行（Notion list-view + block hover gutter）

struct RecordListRow: View {
    let row: RecordRow
    @Environment(\.colorScheme) var scheme
    @State private var hovered = false

    var body: some View {
        HStack(spacing: NotionTheme.space5) {
            // Phosphor 风格图标：1.5pt 细线 + 灰阶徽章（不再是高饱和色块）
            ZStack {
                RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                    .fill(Color.hoverBg)
                Image(systemName: row.categoryIcon)
                    .font(.system(size: 16, weight: .regular))   // .regular = 细线，模拟 Phosphor
                    .foregroundColor(.inkSecondary)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.categoryName)
                        .font(NotionFont.bodyBold())
                        .foregroundColor(.inkPrimary)
                        .lineLimit(1)

                    if row.source != .manual {
                        Text(row.source.rawValue)
                            .font(NotionFont.micro())
                            .foregroundColor(.inkTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.hoverBg)
                            .cornerRadius(NotionTheme.radiusSM)
                    }
                    if row.syncStatus != .synced { syncStatusDot }
                    if row.isAA {
                        Image(systemName: "person.2")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.inkTertiary)
                    }
                }
                if !row.note.isEmpty {
                    Text(row.note)
                        .font(NotionFont.small())
                        .foregroundColor(.inkSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: NotionTheme.space5)

            Text(formattedAmount)
                .font(NotionFont.amount(size: 15))
                .foregroundColor(amountColor)
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 10)
        .background(hovered ? Color.hoverBg : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(NotionTheme.animDefault, value: hovered)
    }

    private var syncStatusDot: some View {
        let color: Color = {
            switch row.syncStatus {
            case .pending:  return NotionColor.yellow.text(scheme)
            case .syncing:  return NotionColor.blue.text(scheme)
            case .failed,
                 .dead:     return NotionColor.red.text(scheme)
            case .synced:   return NotionColor.green.text(scheme)
            }
        }()
        return Circle().fill(color).frame(width: 5, height: 5)
    }

    private var formattedAmount: String {
        let prefix = row.direction == .expense ? "-" : "+"
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0; f.maximumFractionDigits = 2
        return "\(prefix)¥" + (f.string(from: row.amount as NSDecimalNumber) ?? "0.00")
    }

    private var amountColor: Color {
        row.direction == .expense
            ? NotionColor.red.text(scheme)
            : NotionColor.green.text(scheme)
    }
}

// MARK: - Stack 视图（扑克牌叠：按金额降序，hover/tap 顶部卡片向上展开露出下层）

struct RecordStackView: View {
    let rows: [RecordRow]                     // 同一天的多笔，已按金额降序传入
    @State private var expandedID: String?    // 当前被"提起"展开的卡片
    @Environment(\.colorScheme) var scheme

    private let cardHeight: CGFloat = 64
    private let stackedOffset: CGFloat = 8    // 默认每张卡偏移
    private let expandedOffset: CGFloat = 72  // 展开后每张卡偏移

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                cardView(for: row, index: idx)
                    .offset(y: yOffset(for: idx))
                    .zIndex(Double(rows.count - idx))
                    .onTapGesture {
                        withAnimation(NotionTheme.animDefault) {
                            expandedID = expandedID == row.id ? nil : row.id
                        }
                    }
            }
        }
        .frame(height: stackTotalHeight)
        .padding(.horizontal, NotionTheme.space5)
        .animation(NotionTheme.animDefault, value: expandedID)
    }

    private var stackTotalHeight: CGFloat {
        // 默认（未展开）：第一张全显 + 后续每张露 stackedOffset
        if expandedID == nil {
            return cardHeight + CGFloat(max(rows.count - 1, 0)) * stackedOffset
        }
        // 展开：每张全显
        return cardHeight + CGFloat(max(rows.count - 1, 0)) * expandedOffset
    }

    private func yOffset(for index: Int) -> CGFloat {
        let unit: CGFloat = expandedID == nil ? stackedOffset : expandedOffset
        return CGFloat(index) * unit
    }

    @ViewBuilder
    private func cardView(for row: RecordRow, index: Int) -> some View {
        HStack(spacing: NotionTheme.space5) {
            ZStack {
                RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                    .fill(Color.hoverBg)
                Image(systemName: row.categoryIcon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.inkSecondary)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.categoryName)
                    .font(NotionFont.bodyBold())
                    .foregroundColor(.inkPrimary)
                if !row.note.isEmpty {
                    Text(row.note)
                        .font(NotionFont.small())
                        .foregroundColor(.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(formatAmount(row))
                .font(NotionFont.amountBold(size: 16))
                .foregroundColor(row.direction == .expense
                                 ? NotionColor.red.text(scheme)
                                 : NotionColor.green.text(scheme))
        }
        .padding(.horizontal, NotionTheme.space6)
        .frame(height: cardHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusXL)
                .fill(Color.surfaceOverlay)
                .overlay(
                    RoundedRectangle(cornerRadius: NotionTheme.radiusXL)
                        .stroke(Color.border, lineWidth: 1)
                )
        )
    }

    private func formatAmount(_ row: RecordRow) -> String {
        let prefix = row.direction == .expense ? "-" : "+"
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0; f.maximumFractionDigits = 2
        return "\(prefix)¥" + (f.string(from: row.amount as NSDecimalNumber) ?? "0.00")
    }
}

// MARK: - Grid 视图：2 列方卡（Notion Database Gallery 风格）

struct RecordGridView: View {
    let rows: [RecordRow]
    @Environment(\.colorScheme) var scheme
    private let columns = [GridItem(.flexible(), spacing: NotionTheme.space5),
                           GridItem(.flexible(), spacing: NotionTheme.space5)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: NotionTheme.space5) {
            ForEach(rows) { row in
                gridCard(for: row)
            }
        }
        .padding(.horizontal, NotionTheme.space5)
    }

    @ViewBuilder
    private func gridCard(for row: RecordRow) -> some View {
        VStack(alignment: .leading, spacing: NotionTheme.space4) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                        .fill(Color.hoverBg)
                    Image(systemName: row.categoryIcon)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.inkSecondary)
                }
                .frame(width: 28, height: 28)
                Spacer()
                if row.source != .manual {
                    Text(row.source.rawValue)
                        .font(NotionFont.micro())
                        .foregroundColor(.inkTertiary)
                }
            }
            Text(formatAmount(row))
                .font(NotionFont.amountBold(size: 22))
                .foregroundColor(row.direction == .expense
                                 ? NotionColor.red.text(scheme)
                                 : NotionColor.green.text(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.categoryName)
                    .font(NotionFont.body())
                    .foregroundColor(.inkPrimary)
                if !row.note.isEmpty {
                    Text(row.note)
                        .font(NotionFont.small())
                        .foregroundColor(.inkSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(NotionTheme.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusXL)
                .fill(Color.surfaceOverlay)
                .overlay(
                    RoundedRectangle(cornerRadius: NotionTheme.radiusXL)
                        .stroke(Color.border, lineWidth: 1)
                )
        )
    }

    private func formatAmount(_ row: RecordRow) -> String {
        let prefix = row.direction == .expense ? "-" : "+"
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0; f.maximumFractionDigits = 2
        return "\(prefix)¥" + (f.string(from: row.amount as NSDecimalNumber) ?? "0.00")
    }
}

// MARK: - 段头 + 视图切换器（每天独立切换）

struct DayGroupHeader: View {
    let date: Date
    let dayTotal: Decimal
    @Binding var layout: RecordsLayout

    var body: some View {
        HStack(alignment: .center) {
            Text(displayLabel)
                .font(NotionFont.h3())
                .foregroundColor(.inkPrimary)

            Spacer()

            Text("¥" + formatted(dayTotal))
                .font(NotionFont.amount(size: 13))
                .foregroundColor(.inkTertiary)

            // 视图切换 Segmented：3 个细线图标
            HStack(spacing: 0) {
                ForEach(RecordsLayout.allCases, id: \.self) { l in
                    Button { withAnimation(NotionTheme.animDefault) { layout = l } } label: {
                        Image(systemName: l.iconName)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(layout == l ? .inkPrimary : .inkTertiary)
                            .frame(width: 28, height: 24)
                            .background(layout == l ? Color.hoverBg : .clear)
                            .cornerRadius(NotionTheme.radiusSM)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                    .stroke(Color.border, lineWidth: 1)
            )
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.top, NotionTheme.space7)
        .padding(.bottom, NotionTheme.space4)
    }

    private var displayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日 EEEE"
        return f.string(from: date)
    }

    private func formatted(_ d: Decimal) -> String {
        let f = NumberFormatter(); f.minimumFractionDigits = 0; f.maximumFractionDigits = 2
        return f.string(from: d as NSDecimalNumber) ?? "0.00"
    }
}

// MARK: - 主页面

struct RecordsListView: View {
    let summary: MonthSummary
    let groupedRecords: [(date: Date, rows: [RecordRow])]

    @State private var query: String = ""
    @State private var showSearch: Bool = false
    @State private var showMonthPicker: Bool = false
    @State private var layoutByDate: [String: RecordsLayout] = [:]
    /// 点击行后弹出详情 sheet 的目标记录；nil 表示未弹出
    @State private var detailRow: RecordRow? = nil

    var body: some View {
        VStack(spacing: 0) {
            navigationBar                     // 自定义 iOS-style nav（不依赖 NavigationStack 的 toolbar，便于精准控制视觉）
            if showSearch { searchBarInline } // 搜索激活后才出现，与 nav 等宽

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    InlineStatsBar(summary: summary)
                        .padding(.horizontal, NotionTheme.space5)
                        .padding(.top, NotionTheme.space5)
                        .padding(.bottom, NotionTheme.space2)

                    if groupedRecords.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(groupedRecords, id: \.date) { group in
                                let key = isoKey(group.date)
                                let binding = Binding<RecordsLayout>(
                                    get: { layoutByDate[key] ?? .list },
                                    set: { layoutByDate[key] = $0 }
                                )
                                DayGroupHeader(date: group.date,
                                               dayTotal: dayExpenseTotal(group.rows),
                                               layout: binding)

                                switch binding.wrappedValue {
                                case .list:
                                    ForEach(group.rows) { row in
                                        RecordListRow(row: row)
                                            .contentShape(Rectangle())
                                            .onTapGesture { detailRow = row }
                                        Divider().background(Color.divider)
                                            .padding(.leading, NotionTheme.space5 + 28 + NotionTheme.space5)
                                    }
                                case .stack:
                                    let sorted = group.rows.sorted { $0.amount > $1.amount }
                                    RecordStackView(rows: sorted)
                                        .padding(.vertical, NotionTheme.space4)
                                case .grid:
                                    RecordGridView(rows: group.rows)
                                        .padding(.vertical, NotionTheme.space4)
                                }
                            }
                        }
                        .padding(.top, NotionTheme.space2)
                    }

                    Color.clear.frame(height: NotionTheme.space9)
                }
                .frame(maxWidth: NotionTheme.editorMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.canvasBG.ignoresSafeArea())
        .sheet(item: $detailRow) { row in
            RecordDetailSheet(initial: row, onCommit: { _ in /* TODO: 写 SQLite + 入同步队列 */ })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: 自定义 NavigationBar（44pt 高，左中右三段 — 中间双行 title+subtitle）

    private var navigationBar: some View {
        ZStack {
            // 中间：双行 title + subtitle（绝对居中，独立于左右按钮宽度）
            VStack(spacing: 1) {
                Text(monthShortLabel)
                    .font(.custom("PingFangSC-Semibold", size: 17))
                    .foregroundColor(.inkPrimary)
                navSubtitle
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 0) {
                // 左：日历图标 + chevron（点击弹月历）
                Button { withAnimation(NotionTheme.animDefault) { showMonthPicker.toggle() } } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "calendar")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.inkPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.inkSecondary)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 36)
                    .background(showMonthPicker ? Color.hoverBg : Color.clear)
                    .cornerRadius(NotionTheme.radiusMD)
                }
                .buttonStyle(.plain)

                Spacer()

                // 右：搜索 + 新建（icon-only，44pt 触达区）
                HStack(spacing: NotionTheme.space2) {
                    navIconButton(systemName: "magnifyingglass", active: showSearch) {
                        withAnimation(NotionTheme.animDefault) { showSearch.toggle() }
                    }
                    navIconButton(systemName: "plus", active: false) { /* TODO: Slash menu */ }
                }
            }
        }
        .padding(.horizontal, NotionTheme.space4)
        .frame(height: 44)
        .background(Color.canvasBG)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.divider).frame(height: 0.5)
        }
        .overlay(alignment: .topLeading) {
            if showMonthPicker { monthPickerPopover.offset(x: NotionTheme.space4, y: 44 + 4) }
        }
    }

    /// nav 中间副标：仅文字「xx 收支记录」，金额留给下方 InlineStatsBar 详细展示
    private var navSubtitle: some View {
        Text("\(monthShortLabel)收支记录")
            .font(.custom("PingFangSC-Regular", size: 11))
            .foregroundColor(.inkTertiary)
    }

    @ViewBuilder
    private func navIconButton(systemName: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(.inkPrimary)
                .frame(width: 36, height: 36)
                .background(active ? Color.hoverBg : Color.clear)
                .cornerRadius(NotionTheme.radiusMD)
        }
        .buttonStyle(.plain)
    }

    // MARK: 搜索条（激活后内联出现于 nav 下方）

    private var searchBarInline: some View {
        HStack(spacing: NotionTheme.space3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.inkTertiary)
            TextField("搜索备注 / 分类 / 金额", text: $query)
                .font(NotionFont.body())
                .textFieldStyle(.plain)
                .foregroundColor(.inkPrimary)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.inkTertiary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, NotionTheme.space4)
        .padding(.vertical, 8)
        .background(Color.hoverBg)
        .cornerRadius(NotionTheme.radiusLG)
        .padding(.horizontal, NotionTheme.space4)
        .padding(.vertical, NotionTheme.space3)
        .background(Color.canvasBG)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.divider).frame(height: 0.5)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: 月份 picker popover（截图态，演示视觉）

    private var monthPickerPopover: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space2) {
            Text("2026")
                .font(NotionFont.micro())
                .foregroundColor(.inkTertiary)
                .padding(.horizontal, NotionTheme.space4)
                .padding(.top, NotionTheme.space3)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(56), spacing: 4), count: 4), spacing: 4) {
                ForEach(1...12, id: \.self) { m in
                    let isCurrent = m == 5
                    Text("\(m) 月")
                        .font(NotionFont.small())
                        .foregroundColor(isCurrent ? .white : .inkPrimary)
                        .frame(width: 56, height: 32)
                        .background(isCurrent ? Color.accentBlue : Color.clear)
                        .cornerRadius(NotionTheme.radiusMD)
                }
            }
            .padding(NotionTheme.space2)
        }
        .frame(width: 248)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusXL)
                .fill(Color.surfaceOverlay)
                .overlay(
                    RoundedRectangle(cornerRadius: NotionTheme.radiusXL)
                        .stroke(Color.border, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 16, y: 4)   // popover 是 §5.5 唯一允许 shadow 的元素
        .zIndex(100)
    }

    private var monthShortLabel: String {
        // 输入是 "2026 年 5 月"，截短为 "5 月"
        if let m = summary.monthLabel.split(separator: " ").last {
            return String(m)
        }
        return summary.monthLabel
    }

    // MARK: 空状态

    private var emptyState: some View {
        VStack(spacing: NotionTheme.space5) {
            Text("暂无流水")
                .font(NotionFont.body()).foregroundColor(.inkTertiary)
            Text("按住首页「按住说话」按钮，或敲背面截图记账")
                .font(NotionFont.small()).foregroundColor(.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NotionTheme.space10)
    }

    private func dayExpenseTotal(_ rows: [RecordRow]) -> Decimal {
        rows.filter { $0.direction == .expense }.map(\.amount).reduce(0, +)
    }

    private func isoKey(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}

// MARK: - hex helper

private extension Color {
    init(hex: String, alpha: Double = 1) {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        self = Color(.sRGB,
                     red:   Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8)  & 0xFF) / 255,
                     blue:  Double(v         & 0xFF) / 255,
                     opacity: alpha)
    }
}

// MARK: - Preview demo data（internal，给 @main 与预览复用）

extension MonthSummary {
    static let preview = MonthSummary(monthLabel: "2026 年 5 月",
                                      expense: 3245.80, income: 12500.00)
}

extension Array where Element == (date: Date, rows: [RecordRow]) {
    static var preview: [(date: Date, rows: [RecordRow])] {
        let cal = Calendar.current
        let today = Date()
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let twoDays   = cal.date(byAdding: .day, value: -2, to: today)!
        return [
            (today, [
                .init(id: "1", categoryName: "餐饮", categoryIcon: "fork.knife",
                      categoryColor: .orange, amount: 38.50, direction: .expense,
                      note: "便利店午餐", occurredAt: today, source: .ocrVision,
                      syncStatus: .synced, isAA: false),
                .init(id: "2", categoryName: "交通", categoryIcon: "car",
                      categoryColor: .blue, amount: 12.00, direction: .expense,
                      note: "地铁", occurredAt: today, source: .voiceLocal,
                      syncStatus: .pending, isAA: false),
                .init(id: "2b", categoryName: "咖啡", categoryIcon: "cup.and.saucer",
                      categoryColor: .brown, amount: 28.00, direction: .expense,
                      note: "拿铁", occurredAt: today, source: .manual,
                      syncStatus: .synced, isAA: false),
                .init(id: "2c", categoryName: "外卖", categoryIcon: "takeoutbag.and.cup.and.straw",
                      categoryColor: .orange, amount: 45.00, direction: .expense,
                      note: "晚餐", occurredAt: today, source: .voiceCloud,
                      syncStatus: .synced, isAA: false),
            ]),
            (yesterday, [
                .init(id: "3", categoryName: "工资", categoryIcon: "banknote",
                      categoryColor: .green, amount: 12500, direction: .income,
                      note: "5 月工资", occurredAt: yesterday, source: .manual,
                      syncStatus: .synced, isAA: false),
                .init(id: "4", categoryName: "购物", categoryIcon: "bag",
                      categoryColor: .pink, amount: 268.00, direction: .expense,
                      note: "新书", occurredAt: yesterday, source: .ocrLLM,
                      syncStatus: .failed, isAA: false),
            ]),
            (twoDays, [
                .init(id: "5", categoryName: "聚餐", categoryIcon: "person.2",
                      categoryColor: .purple, amount: 460.00, direction: .expense,
                      note: "和小李 AA", occurredAt: twoDays, source: .voiceCloud,
                      syncStatus: .synced, isAA: true),
            ]),
        ]
    }
}

// MARK: - Previews

#Preview("Dark · 默认") {
    NavigationStack { RecordsListView(summary: .preview, groupedRecords: .preview) }
        .preferredColorScheme(.dark)
}

#Preview("Light · 对照") {
    NavigationStack { RecordsListView(summary: .preview, groupedRecords: .preview) }
        .preferredColorScheme(.light)
}
