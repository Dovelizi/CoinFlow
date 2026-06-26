//  NotionFont.swift
//  CoinFlow · M3.2 → Animal Island 字体桥接
//
//  默认：PingFang SC（中文优先，显式字重）。
//  Animal Island 主题激活时：自动切换到系统 .rounded 圆体（对标 Nunito + Noto Sans SC），
//  数字使用 900 weight 强调（对标 SKILL 时钟数字风格）。

import SwiftUI
import UIKit

enum NotionFont {

    // MARK: - 主题感知字体桥接

    /// Animal Island 主题激活时返回圆体卡通字体，否则回退 PingFang SC。
    private static var useAI: Bool { LGAThemeStore.shared.kind == .animalIsland }

    static func title()    -> Font { useAI ? .system(size: 36, weight: .bold,      design: .rounded) : .custom("PingFangSC-Semibold", size: 36) }
    static func h1()       -> Font { useAI ? .system(size: 24, weight: .semibold,  design: .rounded) : .custom("PingFangSC-Semibold", size: 24) }
    static func h2()       -> Font { useAI ? .system(size: 20, weight: .semibold,  design: .rounded) : .custom("PingFangSC-Medium",   size: 20) }
    static func h3()       -> Font { useAI ? .system(size: 17, weight: .medium,    design: .rounded) : .custom("PingFangSC-Medium",   size: 17) }
    static func body()     -> Font { useAI ? .system(size: 15, weight: .medium,    design: .rounded) : .custom("PingFangSC-Regular",  size: 15) }
    static func bodyBold() -> Font { useAI ? .system(size: 15, weight: .semibold,  design: .rounded) : .custom("PingFangSC-Medium",   size: 15) }
    static func small()    -> Font { useAI ? .system(size: 13, weight: .regular,   design: .rounded) : .custom("PingFangSC-Regular",  size: 13) }
    static func micro()    -> Font { useAI ? .system(size: 11, weight: .regular,   design: .rounded) : .custom("PingFangSC-Regular",  size: 11) }

    /// 金额专用：永远等宽数字便于纵向对齐。
    /// AI 主题使用 900 weight（对标 SKILL 时钟数字强调）。
    static func amount(size: CGFloat = 15) -> Font {
        let w: Font.Weight = useAI ? .black : .medium
        return .system(size: size, weight: w, design: .rounded).monospacedDigit()
    }
    static func amountBold(size: CGFloat = 15) -> Font {
        let w: Font.Weight = useAI ? .black : .semibold
        return .system(size: size, weight: w, design: .rounded).monospacedDigit()
    }

    /// UIKit 等价（金额加粗 · monospaced 数字 · rounded design）。
    static func amountBoldUIKit(size: CGFloat = 15) -> UIFont {
        let weight: UIFont.Weight = useAI ? .black : .semibold
        let base = UIFont.systemFont(ofSize: size, weight: weight)
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

    /// UIKit 等价 body 字体。
    /// AI 主题下使用 rounded 系统字体；默认 PingFangSC。
    static func bodyUIKit(size: CGFloat = 15) -> UIFont {
        if useAI {
            return UIFont.systemFont(ofSize: size, weight: .medium)
                .fontDescriptor.withDesign(.rounded)
                .map { UIFont(descriptor: $0, size: size) }
                ?? UIFont.systemFont(ofSize: size)
        }
        return UIFont(name: "PingFangSC-Regular", size: size)
            ?? UIFont.systemFont(ofSize: size)
    }
}
