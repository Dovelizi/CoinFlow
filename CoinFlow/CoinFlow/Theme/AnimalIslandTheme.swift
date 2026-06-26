//  AnimalIslandTheme.swift
//  CoinFlow · 第 4 主题「Animal Island」（动物森友会风格）
//
//  设计语言核心：温暖大地色系 + 大圆角 pill 形 + 游戏按键立体感 + 柔和动效。
//  所有 token 从 animal-island-ui-style SKILL.md 精确翻译为 SwiftUI 等价物。
//
//  背景策略：Web demo 使用 nature SVG/JPG 纹理（home_bg.svg / content_bg_pc.jpg），
//  iOS 端无法加载这些资源，改用从上到下"草绿→奶油白"的暖色渐变，
//  模拟 Animal Island 游戏室外地面的绿意 + 奶油阳光感。

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
    // iOS 移动端微调：比 web spec 暗 ~8%，补偿户外阅读和小屏对比度需求
    static let textPrimary = Color(hex: "#6a4020")   // web: #794f27 → iOS: 暗一档，保证移动端可读
    static let textBody = Color(hex: "#5c4332")      // web: #725d42 → iOS: 暗化
    static let textSecondary = Color(hex: "#7d6e58")  // web: #9f927d → iOS: 暗化以通过 WCAG AA
    static let textMuted = Color(hex: "#6b5a45")       // web: #8a7b66 → iOS: 暗化
    static let textDisabled = Color(hex: "#b0a590")    // web: #c4b89e → iOS: 微暗

    // MARK: 背景
    // 色阶：bgGrass（草绿顶）→ bgWarm（暖绿中）→ bgCanvas（奶油底 / 末端始终可读）
    static let bgGrass = Color(hex: "#90c695")         // 与 demo 的 #7DC395 同族，微调更柔和
    static let bgWarm = Color(hex: "#e8e4d0")          // 暖绿过渡
    static let bgCanvas = Color(hex: "#f8f8f0")        // 奶油白（保留 spec；渐变底部会与此融合）
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
    static let sidebarActiveBg = Color(hex: "#B7C6E5")
    static let sidebarHoverBg = Color(hex: "#d6dff0")

    // MARK: 3D 游戏阴影色
    static let shadowBtn = Color(hex: "#bdaea0")
    static let shadowInput = Color(hex: "#d4c9b4")
    static let shadowSwitchOn = Color(hex: "#5a9e1e")

    // MARK: 柔和暖调 shadow（SKILL §1 阴影节）
    /// rgba(61, 52, 40, ...) — 所有 card / default-btn / pill 的 shadow 底色
    static let shadowWarm = Color(red: 61/255, green: 52/255, blue: 40/255)
    /// 0 2px 4px 0 rgba(61,52,40,0.06) — default-btn 静止 / subtle card
    static let shadowSm = Color(red: 61/255, green: 52/255, blue: 40/255).opacity(0.06)
    /// 0 3px 10px 0 rgba(61,52,40,0.10) — card 浮层 / default-btn hover
    static let shadowBase = Color(red: 61/255, green: 52/255, blue: 40/255).opacity(0.10)
    /// 0 8px 24px 0 rgba(61,52,40,0.14) — Modal / 大浮层
    static let shadowLg = Color(red: 61/255, green: 52/255, blue: 40/255).opacity(0.14)

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
    static var aiBgSecondary: Color { AnimalIslandTheme.bgSecondary }
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

// MARK: - 全屏背景（nature gradient：草绿 → 暖绿 → 奶油白）

struct AnimalIslandBackground: View {
    var kind: LGAPageKind = .default

    var body: some View {
        // 渐变：顶部从草地绿起始，经暖绿过渡，底部落在奶油白。
        // stop 0=草绿(0%) → stop 0.35=暖绿(35%) → stop 1=奶油(100%)
        // 这样卡片/文字所在的屏幕主体区域背景都是高可读性的浅色暖调。
        LinearGradient(
            stops: [
                .init(color: AnimalIslandTheme.bgGrass, location: 0.0),
                .init(color: AnimalIslandTheme.bgWarm, location: 0.35),
                .init(color: AnimalIslandTheme.bgCanvas, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
