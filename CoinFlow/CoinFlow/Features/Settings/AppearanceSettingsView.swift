//  AppearanceSettingsView.swift
//  CoinFlow · 主题与颜色详情页
//
//  合并「外观主题切换」+「金额颜色切换」+「真实效果预览」。
//  入口：SettingsView → 主题与颜色 → push 进入本页。
//
//  结构：
//    1. 预览卡片（Home hero 月度净额 + 当日合计段头 + 3 笔流水小卡）
//       所有颜色通过 @EnvironmentObject AmountTintStore / @ObservedObject themeStore
//       响应式联动，切换 palette / 主题即刻生效。
//    2. 主题段：Dark Notion / Dark Liquid 两卡并排（复用 SettingsView 原样式）
//    3. 金额颜色段：5 套 palette 列表（单选圆点 + 当前色样预览）

import SwiftUI

struct AppearanceSettingsView: View {

    @EnvironmentObject private var amountTint: AmountTintStore
    @ObservedObject private var themeStore = LGAThemeStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            ThemedBackgroundLayer(kind: .settings)
            ScrollView {
                VStack(spacing: NotionTheme.space6) {
                    previewCard
                    themeSection
                    paletteSection
                }
                .padding(NotionTheme.space5)
                .padding(.bottom, NotionTheme.space9)
            }
        }
        .navigationTitle("主题与颜色")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 预览卡片（Home hero + 当日合计 + 3 笔流水）

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Home hero 月度净额
            VStack(spacing: 4) {
                Text("本月净增")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("¥")
                        .font(.system(size: 42 * AmountSymbolStyle.symbolScale, weight: .bold, design: .rounded))
                        .foregroundStyle(amountTint.incomeColor)
                    Text("4,937")
                        .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(amountTint.incomeColor)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, NotionTheme.space5)

            // 极淡 divider
            Rectangle().fill(Color.divider).frame(height: NotionTheme.borderWidth)

            // 当日合计段头
            HStack {
                Text("今天 · 周日")
                    .font(NotionFont.h3())
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
                Text("¥63")
                    .font(NotionFont.amount(size: 13))
                    .foregroundStyle(amountTint.expenseColor)
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.vertical, NotionTheme.space4)

            // 3 笔流水行
            previewRow(icon: "dollarsign.circle.fill", iconColor: amountTint.incomeColor,
                       title: "工资代发", subtitle: "工资 · 微信",
                       amount: "¥5,000", amountColor: amountTint.incomeColor)
            rowDivider
            previewRow(icon: "car.fill", iconColor: Color(hex: "#007AFF"),
                       title: "滴滴打车", subtitle: "交通 · 微信",
                       amount: "¥38", amountColor: amountTint.expenseColor)
            rowDivider
            previewRow(icon: "cup.and.saucer.fill", iconColor: Color(hex: "#D9730D"),
                       title: "瑞幸咖啡", subtitle: "餐饮 · 微信",
                       amount: "¥25", amountColor: amountTint.expenseColor)
        }
        .cardSurface(cornerRadius: 14)
    }

    @ViewBuilder
    private func previewRow(icon: String,
                            iconColor: Color,
                            title: String,
                            subtitle: String,
                            amount: String,
                            amountColor: Color) -> some View {
        HStack(spacing: NotionTheme.space4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.15))
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(iconColor)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(NotionFont.body())
                    .foregroundStyle(Color.inkPrimary)
                Text(subtitle)
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
            }
            Spacer()
            Text(amount)
                .font(NotionFont.amount(size: 14))
                .foregroundStyle(amountColor)
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, NotionTheme.space3)
    }

    private var rowDivider: some View {
        Rectangle().fill(Color.divider)
            .frame(height: NotionTheme.borderWidth)
            .padding(.leading, NotionTheme.space5 + 32 + NotionTheme.space4)
    }

    // MARK: - 主题段

    private var themeSection: some View {
        SettingsSection(title: "外观", icon: "paintpalette", wrapInCard: false) {
            VStack(spacing: NotionTheme.space4) {
                themeCard(
                    kind: .notion,
                    title: "Dark Notion",
                    subtitle: "实色扁平·遵循 Notion 设计语言",
                    iconSystemName: "square.grid.2x2"
                )
                themeCard(
                    kind: .darkLiquid,
                    title: "Dark Liquid",
                    subtitle: "深炭灰实色·低干扰阅读",
                    iconSystemName: "moon.fill"
                )
                themeCard(
                    kind: .liquidGlass,
                    title: "Liquid Glass",
                    subtitle: "iOS 26 真·液态玻璃·跟随系统亮暗",
                    iconSystemName: "sparkles"
                )
            }
        }
    }

    @ViewBuilder
    private func themeCard(kind: AppTheme,
                           title: String,
                           subtitle: String,
                           iconSystemName: String) -> some View {
        let isSelected = themeStore.kind == kind
        let isCurrentLGA = themeStore.kind == .darkLiquid
        let radius: CGFloat = 14

        Button {
            themeStore.setKind(kind, animated: true)
        } label: {
            HStack(spacing: NotionTheme.space5) {
                // 左侧图标
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(themeIconBackground(for: kind))
                    Image(systemName: iconSystemName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(themeIconForeground(for: kind))
                }
                .frame(width: 40, height: 40)

                // 中间文本
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.custom("PingFangSC-Semibold", size: 16))
                        .foregroundStyle(isCurrentLGA ? Color.white : Color.inkPrimary)
                    Text(subtitle)
                        .font(NotionFont.small())
                        .foregroundStyle(
                            isCurrentLGA ? LGATheme.textSecondary : Color.inkSecondary
                        )
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                // 右侧选中态
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(LGATheme.accentSelection)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Color.inkTertiary)
                }
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.vertical, NotionTheme.space5)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(isCurrentLGA
                          ? LGATheme.cardFill
                          : (isSelected
                             ? LGATheme.accentSelection.opacity(0.08)
                             : Color.surfaceOverlay))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        isSelected ? LGATheme.accentSelection : Color.border,
                        lineWidth: isSelected ? 1.0 : NotionTheme.borderWidth
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) 主题\(isSelected ? "，已选中" : "")")
    }

    /// 主题卡片左侧图标背景色
    private func themeIconBackground(for kind: AppTheme) -> Color {
        switch kind {
        case .notion:       return Color.accentBlue.opacity(0.12)
        case .darkLiquid:   return Color.black.opacity(0.85)
        case .liquidGlass:
            // Liquid Glass 用 accent + 紫的混合，呼应玻璃折射感
            return Color(red: 0.36, green: 0.42, blue: 0.95).opacity(0.85)
        }
    }

    /// 主题卡片左侧图标前景色
    private func themeIconForeground(for kind: AppTheme) -> Color {
        switch kind {
        case .notion:       return Color.accentBlue
        case .darkLiquid:   return Color.white
        case .liquidGlass:  return Color.white
        }
    }

    // MARK: - 金额颜色段

    private var paletteSection: some View {
        SettingsSection(title: "金额颜色", icon: "paintpalette.fill") {
            VStack(spacing: 0) {
                ForEach(Array(AmountPalette.allCases.enumerated()), id: \.element.id) { idx, palette in
                    paletteRow(palette: palette, isSelected: amountTint.palette == palette)
                    if idx < AmountPalette.allCases.count - 1 {
                        Rectangle().fill(Color.divider)
                            .frame(height: NotionTheme.borderWidth)
                            .padding(.leading, NotionTheme.space5 + 48 + NotionTheme.space4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func paletteRow(palette: AmountPalette, isSelected: Bool) -> some View {
        let income = Color(hex: palette.incomeHex)
        let expense = Color(hex: palette.expenseHex)
        Button {
            amountTint.setPalette(palette)
        } label: {
            HStack(spacing: NotionTheme.space4) {
                // 左：两色预览片
                HStack(spacing: 4) {
                    Circle().fill(income).frame(width: 16, height: 16)
                    Circle().fill(expense).frame(width: 16, height: 16)
                }
                .padding(.horizontal, 8)
                .frame(width: 48, alignment: .leading)

                // 中：名称 + 副标题
                VStack(alignment: .leading, spacing: 2) {
                    Text(palette.displayName)
                        .font(NotionFont.body())
                        .foregroundStyle(Color.inkPrimary)
                    Text(palette.subtitle)
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.inkTertiary)
                }

                Spacer()

                // 右：选中态图标
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(income)
                        .frame(width: 24)
                } else {
                    Color.clear.frame(width: 24)
                }
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(palette.displayName)，\(palette.subtitle)\(isSelected ? "，已选中" : "")")
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
    .environmentObject(AmountTintStore.shared)
    .preferredColorScheme(.dark)
}
#endif
