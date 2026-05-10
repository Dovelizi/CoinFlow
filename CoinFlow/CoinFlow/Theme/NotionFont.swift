//  NotionFont.swift
//  CoinFlow · M3.2
//
//  中文字体统一为 PingFang SC（B9 基线，§5.5.2）。
//  金额数字用 SF Rounded + monospacedDigit 保证纵向对齐。
//
//  这里**不**用 NotionTheme 里的 Inter（那是设计系统英文 emitter 的产物）；
//  本 App 是中文优先，全用 PingFangSC 显式声明字重避免回退到系统默认。

import SwiftUI

enum NotionFont {
    static func title()    -> Font { .custom("PingFangSC-Semibold", size: 36) }
    static func h1()       -> Font { .custom("PingFangSC-Semibold", size: 24) }
    static func h2()       -> Font { .custom("PingFangSC-Medium",   size: 20) }
    static func h3()       -> Font { .custom("PingFangSC-Medium",   size: 17) }
    static func body()     -> Font { .custom("PingFangSC-Regular",  size: 15) }
    static func bodyBold() -> Font { .custom("PingFangSC-Medium",   size: 15) }
    static func small()    -> Font { .custom("PingFangSC-Regular",  size: 13) }
    static func micro()    -> Font { .custom("PingFangSC-Regular",  size: 11) }

    /// 金额专用：永远等宽数字便于纵向对齐
    static func amount(size: CGFloat = 15) -> Font {
        .system(size: size, weight: .medium, design: .rounded).monospacedDigit()
    }
    static func amountBold(size: CGFloat = 15) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }
}
