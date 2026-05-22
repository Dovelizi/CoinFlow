// NotionTheme+Aliases.swift
//
// 桥接层：把 gen_tokens.py 生成的 snake_case 名字暴露为 camelCase，
// 让 RecordsListView.swift 能直接使用「Color.inkPrimary」这种符合 Swift 命名规范的写法。
//
// 这里有意不修改 NotionTheme.swift（脚本生成物，禁止手改）。
// 后续 gen_tokens.py 的 swiftui emitter 修复 camelCase 后，本文件可整体删除。
//
// Theme bridging (Animal Island): 当用户选择 Animal Island 主题时，
// 所有 ink/hover/surface token 自动切换为动森暖色调，无需逐文件修改。

import SwiftUI

// MARK: - Color aliases (snake → camel) · 主题感知桥接

extension Color {
    // MARK: Canvas / 根背景
    static var canvasBG: Color {
        if LGAThemeRuntime.isAnimalIsland { return AnimalIslandTheme.bgCanvas }
        return .canvas_bg
    }
    static var sidebarBG: Color {
        if LGAThemeRuntime.isAnimalIsland { return AnimalIslandTheme.bgSecondary }
        return .sidebar_bg
    }
    static var surfaceOverlay: Color {
        if LGAThemeRuntime.isAnimalIsland { return AnimalIslandTheme.bgContent }
        return .surface_overlay
    }

    // MARK: 文字色
    static var inkPrimary: Color {
        if LGAThemeRuntime.isAnimalIsland { return AnimalIslandTheme.textPrimary }
        return .text_primary
    }
    static var inkSecondary: Color {
        if LGAThemeRuntime.isAnimalIsland { return AnimalIslandTheme.textSecondary }
        return .text_secondary
    }
    static var inkTertiary: Color {
        if LGAThemeRuntime.isAnimalIsland { return AnimalIslandTheme.textMuted }
        return .text_tertiary
    }
    static var inkDisabled: Color {
        if LGAThemeRuntime.isAnimalIsland { return AnimalIslandTheme.textDisabled }
        return .text_disabled
    }

    // MARK: 表面 / 悬浮色
    static var hoverBg: Color {
        if LGAThemeRuntime.isAnimalIsland { return AnimalIslandTheme.bgContent.opacity(0.7) }
        return .hover_bg
    }
    static var hoverBgStrong: Color {
        if LGAThemeRuntime.isAnimalIsland { return AnimalIslandTheme.bgSecondary }
        return .hover_bg_strong
    }
    static var selectedBg: Color {
        if LGAThemeRuntime.isAnimalIsland { return AnimalIslandTheme.primaryBg }
        return .selected_bg
    }

    // `.divider` / `.border` — 保持 Notion 原义（AI 主题下自然降级，border 对比度足够）
    static var accentBlue: Color {
        if LGAThemeRuntime.isAnimalIsland { return AnimalIslandTheme.primaryColor }
        return .accent_blue
    }
    static var accentBlueBG: Color {
        if LGAThemeRuntime.isAnimalIsland { return AnimalIslandTheme.primaryBg }
        return .accent_blue_bg
    }
    static var textCode:        Color { .text_code }
    static var bgCodeInline:    Color { .bg_code_inline }

    // MARK: - 语义状态色（M6+ 设计严格对照引入）
    // 与 SymbolColor.swift 中现有 hex 字面量保持值一致，作为 token 化迁移目标。
    static let dangerRed:       Color = Color(hex: "#DF5452")
    static let statusSuccess:   Color = Color(hex: "#448361")
    static let statusWarning:   Color = Color(hex: "#CA9849")
    static let statusError:     Color = Color(hex: "#D44C47")

    // MARK: - 设计稿专用 accent 扩展（CaptureConfirm engine banner 三色区分）
    static let accentPurple:    Color = Color(hex: "#7C5BC2")
    static let accentGold:      Color = Color(hex: "#CA9849")
}

// MARK: - NotionTheme layout aliases

extension NotionTheme {
    static let editorMaxWidth:        CGFloat = NotionTheme.editor_max_width
    static let sidebarWidth:          CGFloat = NotionTheme.sidebar_width
    static let sidebarWidthCollapsed: CGFloat = NotionTheme.sidebar_width_collapsed
    static let topbarHeight:          CGFloat = NotionTheme.topbar_height
    static let blockGutter:           CGFloat = NotionTheme.block_gutter

    /// Page icon size token (SKILL 中是 28pt; gen_tokens.py 当前未导出 icon scale，先在此手填)
    static let iconPage: CGFloat = 28

    /// Hairline / border stroke 宽度 token。Notion 参考实现统一 0.5pt。
    /// 未来 gen_tokens.py emitter 若导出 stroke scale，可从此处迁回 NotionTheme.swift 并删除。
    static let borderWidth: CGFloat = 0.5

    /// 业务卡片圆角 token（KPI 卡 / 入口卡 / 字段组卡 / 缩略图卡）。
    /// gen_tokens.py 当前 radiusLG=6 / radiusXL=8 偏小，业务侧需 12pt / 14pt。
    static let radiusCard:   CGFloat = 12
    static let radiusCardLG: CGFloat = 14
}
