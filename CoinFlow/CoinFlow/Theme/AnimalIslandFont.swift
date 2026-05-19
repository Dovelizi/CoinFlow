//  AnimalIslandFont.swift
//  CoinFlow · Animal Island 主题字体
//
//  对标 Nunito（拉丁圆体）+ Noto Sans SC / Zen Maru Gothic（中日）。
//  首版用系统 .rounded 降级，后续可打包 Nunito .ttf 替换。

import SwiftUI

enum AnimalIslandFont {

    /// 主标题：weight 700
    static func title() -> Font {
        .system(size: 36, weight: .bold, design: .rounded)
    }

    /// H1：weight 600
    static func h1() -> Font {
        .system(size: 24, weight: .semibold, design: .rounded)
    }

    /// H2：weight 600
    static func h2() -> Font {
        .system(size: 20, weight: .semibold, design: .rounded)
    }

    /// H3：weight 500
    static func h3() -> Font {
        .system(size: 17, weight: .medium, design: .rounded)
    }

    /// 正文：weight 500
    static func body() -> Font {
        .system(size: 15, weight: .medium, design: .rounded)
    }

    /// 小字：weight 400
    static func small() -> Font {
        .system(size: 13, weight: .regular, design: .rounded)
    }

    /// 微小字：weight 400
    static func micro() -> Font {
        .system(size: 11, weight: .regular, design: .rounded)
    }

    /// 数字强调（金额/时间）：weight 900
    static func amount(size: CGFloat = 15) -> Font {
        .system(size: size, weight: .black, design: .rounded).monospacedDigit()
    }

    /// 按钮文字：weight 600
    static func buttonLabel(size: CGFloat = 14) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}
