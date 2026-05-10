//  NotionFont.swift
//  CoinFlow · M3.2
//
//  中文字体统一为 PingFang SC（B9 基线，§5.5.2）。
//  金额数字用 SF Rounded + monospacedDigit 保证纵向对齐。
//
//  这里**不**用 NotionTheme 里的 Inter（那是设计系统英文 emitter 的产物）；
//  本 App 是中文优先，全用 PingFangSC 显式声明字重避免回退到系统默认。

import SwiftUI
import UIKit

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

    /// UIKit 等价（金额加粗 · monospaced 数字 · rounded design）。
    /// 供 AmountTextFieldUIKit 使用——SwiftUI Font 无法直接转 UIFont，必须分别声明。
    static func amountBoldUIKit(size: CGFloat = 15) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .semibold)
        let descriptor = base.fontDescriptor
            .withDesign(.rounded)?
            .addingAttributes([
                .featureSettings: [
                    [
                        UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                        UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
                    ]
                ]
            ])
        if let d = descriptor {
            return UIFont(descriptor: d, size: size)
        }
        return base
    }

    /// UIKit 等价 body 字体（PingFangSC-Regular 15pt，与 SwiftUI body() 对齐）。
    /// 供 NoteTextFieldUIKit 使用——UITextView 需要 UIFont 而非 SwiftUI Font。
    static func bodyUIKit(size: CGFloat = 15) -> UIFont {
        UIFont(name: "PingFangSC-Regular", size: size)
            ?? UIFont.systemFont(ofSize: size)
    }
}
