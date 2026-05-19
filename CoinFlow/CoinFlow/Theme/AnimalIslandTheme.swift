//  AnimalIslandTheme.swift
//  CoinFlow · 第 4 主题「Animal Island」（动物森友会风格）
//
//  设计语言核心：温暖大地色系 + 大圆角 pill 形 + 游戏按键立体感 + 柔和动效。
//  所有 token 从 animal-island-ui-style SKILL.md 精确翻译为 SwiftUI 等价物。

import SwiftUI

// MARK: - Animal Island 设计令牌

enum AnimalIslandTheme {

    // MARK: 圆角
    static let radiusSM: CGFloat = 12
    static let radiusMD: CGFloat = 18
    static let radiusLG: CGFloat = 24
    static let radiusPill: CGFloat = 50

    // MARK: 间距（与 NotionTheme 对齐避免布局跳动）
    static let spaceXS: CGFloat = 4
    static let spaceSM: CGFloat = 8
    static let spaceMD: CGFloat = 12
    static let spaceLG: CGFloat = 16
    static let spaceXL: CGFloat = 24

    // MARK: 主色（薄荷青绿）
    static let primaryColor = Color(hex: "#19c8b9")
    static let primaryHover = Color(hex: "#3dd4c6")
    static let primaryActive = Color(hex: "#11a89b")
    static let primaryBg = Color(hex: "#e6f9f6")

    // MARK: 文字（温暖棕色系）
    static let textPrimary = Color(hex: "#794f27")
    static let textBody = Color(hex: "#725d42")
    static let textSecondary = Color(hex: "#9f927d")
    static let textMuted = Color(hex: "#8a7b66")
    static let textDisabled = Color(hex: "#c4b89e")

    // MARK: 背景（奶油米白）
    static let bgCanvas = Color(hex: "#f8f8f0")
    static let bgContent = Color(red: 247/255, green: 243/255, blue: 223/255)
    static let bgSecondary = Color(hex: "#f0e8d8")
    static let bgDisabled = Color(hex: "#f0ece2")
    static let bgInput = Color(red: 247/255, green: 243/255, blue: 223/255)
    static let bgInputDisabled = Color(hex: "#ece8dc")

    // MARK: 边框
    static let borderColor = Color(hex: "#9f927d")
    static let borderLight = Color(hex: "#c4b89e")
    static let borderHover = Color(hex: "#a89878")

    // MARK: 状态色
    static let success = Color(hex: "#6fba2c")
    static let successActive = Color(hex: "#5a9e1e")
    static let warning = Color(hex: "#f5c31c")
    static let warningActive = Color(hex: "#dba90e")
    static let error = Color(hex: "#e05a5a")
    static let errorActive = Color(hex: "#c94444")

    // MARK: 游戏特殊色
    static let focusYellow = Color(hex: "#ffcc00")
    static let focusYellowDark = Color(hex: "#e0b800")

    // MARK: 3D 游戏阴影色
    static let shadowBtn = Color(hex: "#bdaea0")
    static let shadowInput = Color(hex: "#d4c9b4")
    static let shadowSwitchOn = Color(hex: "#5a9e1e")

    // MARK: 动效
    static let animDefault = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.25)
    static let animFast = Animation.easeInOut(duration: 0.15)
    static let animSlow = Animation.easeInOut(duration: 0.3)
}

// MARK: - Color 扩展别名

extension Color {
    static var aiTextPrimary: Color { AnimalIslandTheme.textPrimary }
    static var aiTextBody: Color { AnimalIslandTheme.textBody }
    static var aiTextSecondary: Color { AnimalIslandTheme.textSecondary }
    static var aiTextMuted: Color { AnimalIslandTheme.textMuted }
    static var aiTextDisabled: Color { AnimalIslandTheme.textDisabled }
    static var aiBgCanvas: Color { AnimalIslandTheme.bgCanvas }
    static var aiBgContent: Color { AnimalIslandTheme.bgContent }
    static var aiBgDisabled: Color { AnimalIslandTheme.bgDisabled }
    static var aiBorderLight: Color { AnimalIslandTheme.borderLight }
    static var aiBorderColor: Color { AnimalIslandTheme.borderColor }
    static var aiFocusYellow: Color { AnimalIslandTheme.focusYellow }
    static var aiPrimary: Color { AnimalIslandTheme.primaryColor }
    static var aiPrimaryBg: Color { AnimalIslandTheme.primaryBg }
    static var aiSuccess: Color { AnimalIslandTheme.success }
    static var aiError: Color { AnimalIslandTheme.error }
    static var aiShadowBtn: Color { AnimalIslandTheme.shadowBtn }
    static var aiShadowInput: Color { AnimalIslandTheme.shadowInput }
}

// MARK: - 全屏背景

struct AnimalIslandBackground: View {
    var kind: LGAPageKind = .default

    var body: some View {
        AnimalIslandTheme.bgCanvas
            .ignoresSafeArea()
    }
}
