//  SummaryFloatingCard.swift
//  CoinFlow · M10-Fix3 · 总结浮窗（swift-markdown-ui 渲染）
//
//  视觉契约（用户决策）：
//  - 半透明黑底全屏遮罩（点击外侧关闭）
//  - 居中卡片：四边等宽 padding 24pt
//  - 卡片自带圆角 20pt + 阴影
//  - 内容垂直滚动；最大高度 = 屏高 - 96pt
//  - 用 swift-markdown-ui 渲染 LLM 输出的 GFM Markdown（表格/列表/强调/引用/emoji 全支持）
//  - 自定义 Theme 对齐 Notion 设计 token（PingFangSC + accentBlue 链接 + Notion.border 表格）
//
//  布局：
//  - 头部（非滚动）：周期标题 + 关闭 ✕
//  - 元数据行：日期范围 / 笔数 / LLM model
//  - 滚动内容：Markdown 渲染区
//  - 底部（非滚动）：如果有飞书 URL 展示"在飞书中打开"按钮

import SwiftUI
import MarkdownUI

struct SummaryFloatingCard: View {

    let summary: BillsSummary
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            cardContent
                .padding(.horizontal, 24)
                .padding(.vertical, 48)
        }
        .transition(.opacity)
    }

    private var cardContent: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, NotionTheme.space5)
                .padding(.top, NotionTheme.space5)
                .padding(.bottom, NotionTheme.space3)

            Divider()

            ScrollView {
                // MarkdownUI 渲染 LLM 输出
                Markdown(summary.summaryText)
                    .markdownTheme(Self.coinflowMarkdownTheme)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(NotionTheme.space5)
            }
        }
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.border, lineWidth: NotionTheme.borderWidth)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 30, x: 0, y: 12)
    }

    /// 浮窗外层大卡背景：
    /// - liquidGlass：`.ultraThinMaterial` 真玻璃，滑出底层玻璃背景 + dim 黑遮罩
    /// - notion / darkLiquid：维持 `Color.canvasBG` 以套历史行为
    @ViewBuilder
    private var cardBackground: some View {
        if LGAThemeStore.shared.kind == .liquidGlass {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        } else {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.canvasBG)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: NotionTheme.space3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(periodTitle)
                    .font(NotionFont.h2())
                    .foregroundStyle(Color.inkPrimary)
                Text(metaLine)
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 32, height: 32)
                    .background(closeButtonBackground)
            }
            .accessibilityLabel("关闭总结浮窗")
        }
    }

    /// 关闭 ✕ 圆按钮背景：避免与外层 `.ultraThinMaterial` 双层叠加，
    /// liquidGlass 下用半透白 `Color.white.opacity(0.10)` 代替玻璃感
    @ViewBuilder
    private var closeButtonBackground: some View {
        if LGAThemeStore.shared.kind == .liquidGlass {
            Circle().fill(Color.white.opacity(0.10))
                .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
        } else {
            Circle().fill(Color.surfaceOverlay)
        }
    }

    private var periodTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = .current
        switch summary.periodKind {
        case .week:
            f.dateFormat = "yyyy 年第 w 周"
            return f.string(from: summary.periodStart) + " 周报"
        case .month:
            f.dateFormat = "yyyy 年 M 月"
            return f.string(from: summary.periodStart) + " 月报"
        case .year:
            f.dateFormat = "yyyy 年"
            return f.string(from: summary.periodStart) + " 年报"
        }
    }

    private var metaLine: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = .current
        f.dateFormat = "yyyy.MM.dd"
        return "\(f.string(from: summary.periodStart)) — \(f.string(from: summary.periodEnd)) · \(summary.recordCount) 笔 · \(summary.llmProvider)"
    }
}

// MARK: - 自定义 Notion 风 Markdown Theme

private extension SummaryFloatingCard {

    /// 对齐项目 Notion 设计 token：
    /// - 正文：15pt inkPrimary
    /// - 标题：h2/h3 字号 + Semibold
    /// - 链接：accentBlue
    /// - 表格：border 描边、surfaceOverlay 斑马纹（手工 overlay 实现）
    /// - 引用：左侧 3pt accentBlue 竖条
    /// - 代码片段：bgCodeInline 背景
    ///
    /// 注：MarkdownUI 的 `ForegroundColor` / `BackgroundColor` 接受 SwiftUI.Color，
    /// 表格斑马纹 / 边框没有专用 DSL，在 `tableCell` 内用 background+border 自行绘制。
    static var coinflowMarkdownTheme: Theme {
        Theme()
            // 正文段落
            .text {
                FontSize(15)
                ForegroundColor(.inkPrimary)
            }
            .paragraph { configuration in
                configuration.label
                    .lineSpacing(6)
                    .markdownMargin(top: 0, bottom: 12)
            }
            // 标题
            .heading1 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(24)
                    }
                    .markdownMargin(top: 16, bottom: 12)
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(20)
                    }
                    .markdownMargin(top: 16, bottom: 10)
            }
            .heading3 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(17)
                    }
                    .markdownMargin(top: 14, bottom: 8)
            }
            // 强调
            .strong {
                FontWeight(.semibold)
            }
            .emphasis {
                FontStyle(.italic)
            }
            // 链接
            .link {
                ForegroundColor(.accentBlue)
                UnderlineStyle(.single)
            }
            // 内联代码
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.92))
                BackgroundColor(.bgCodeInline)
                ForegroundColor(.inkPrimary)
            }
            // 引用块：左侧竖线 + 柔色次要色
            .blockquote { configuration in
                HStack(alignment: .top, spacing: 12) {
                    Rectangle()
                        .fill(Color.accentBlue)
                        .frame(width: 3)
                    configuration.label
                        .foregroundStyle(Color.inkSecondary)
                        .padding(.vertical, 4)
                }
                .padding(.vertical, 4)
                .markdownMargin(top: 8, bottom: 12)
            }
            // 列表项
            .listItem { configuration in
                configuration.label
                    .markdownMargin(top: 0, bottom: 4)
            }
            // 分割线
            .thematicBreak {
                Divider()
                    .background(Color.border)
                    .markdownMargin(top: 16, bottom: 16)
            }
            // 表格：整体外边框
            .table { configuration in
                configuration.label
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.border, lineWidth: NotionTheme.borderWidth)
                    )
                    .markdownMargin(top: 12, bottom: 12)
            }
            // 表格单元格：row=0 是表头加粗 + 底色；偶数行淡色斑马纹
            //
            // liquidGlass 主题下：为避免与外层玻璃卡的 `.ultraThinMaterial` 双层模糊（叠加效果不可预测且能耗），
            // 改用半透白叠加：表头 10%、斑马纹 4%，能创造与玻璃类似的"柔光层"观感。
            // notion / darkLiquid 主题下：维持原 `Color.surfaceOverlay` 行为。
            .tableCell { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(14)
                        if configuration.row == 0 {
                            FontWeight(.semibold)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Self.tableCellBackground(row: configuration.row))
                    .overlay(
                        Rectangle()
                            .stroke(Color.border.opacity(0.6), lineWidth: NotionTheme.borderWidth)
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
    }

    /// 表格单元格背景解析（按主题分支）
    @ViewBuilder
    static func tableCellBackground(row: Int) -> some View {
        if LGAThemeStore.shared.kind == .liquidGlass {
            if row == 0 {
                Color.white.opacity(0.10)
            } else if row % 2 == 0 {
                Color.white.opacity(0.04)
            } else {
                Color.clear
            }
        } else {
            if row == 0 {
                Color.surfaceOverlay
            } else if row % 2 == 0 {
                Color.surfaceOverlay.opacity(0.4)
            } else {
                Color.clear
            }
        }
    }
}
