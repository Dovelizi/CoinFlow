//  MerchantBrand.swift
//  CoinFlow · M7-Fix13 商户品牌图标识别
//
//  根据 OCR rawText / merchant 名称启发式匹配支付品牌（微信支付 / 支付宝 / 银行 / 美团 / 大众点评 等），
//  返回对应 SF Symbol 图标 + 品牌色，在 CaptureConfirmView.merchantRow 展示。
//
//  新增品牌：往 patterns 数组追加一项即可。

import SwiftUI

struct MerchantBrand {
    let name: String      // 展示名（如 "微信支付"）
    let icon: String      // SF Symbol
    let color: Color      // 品牌色

    /// 启发式从 rawText / merchantName 中识别品牌；无匹配返回通用 building.2
    static func detect(from rawText: String, merchant: String? = nil) -> MerchantBrand {
        let haystack = (rawText + " " + (merchant ?? "")).lowercased()
        for brand in patterns {
            for kw in brand.keywords where haystack.contains(kw.lowercased()) {
                return brand.brand
            }
        }
        return MerchantBrand(name: "商户", icon: "building.2", color: .inkSecondary)
    }

    /// 品牌模式 — 顺序 = 匹配优先级。
    /// SF Symbol 在没有官方品牌 icon 时选语义相近的；可升级为 bundle 内 PNG 资源
    private struct Pattern {
        let brand: MerchantBrand
        let keywords: [String]
    }

    private static let patterns: [Pattern] = [
        Pattern(
            brand: MerchantBrand(
                name: "微信支付",
                icon: "message.fill",                    // 语义近似（绿色气泡）
                color: Color(red: 0.08, green: 0.73, blue: 0.29)  // 微信绿 #14BA4B
            ),
            keywords: ["微信支付", "wechat pay", "wechatpay", "微信"]
        ),
        Pattern(
            brand: MerchantBrand(
                name: "支付宝",
                icon: "a.circle.fill",                   // 语义近似（字母 a）
                color: Color(red: 0.00, green: 0.64, blue: 0.94)  // 支付宝蓝 #00A3EF
            ),
            keywords: ["支付宝", "alipay", "蚂蚁"]
        ),
        Pattern(
            brand: MerchantBrand(
                name: "抖音",
                icon: "music.note",
                color: Color(red: 0.00, green: 0.00, blue: 0.00)  // 抖音黑 #000000
            ),
            keywords: ["抖音", "douyin", "抖音月付", "抖音支付"]
        ),
        Pattern(
            brand: MerchantBrand(
                name: "银行卡",
                icon: "creditcard.fill",
                color: Color(red: 0.87, green: 0.18, blue: 0.23)  // 中国红 #DE2E3A
            ),
            keywords: ["银行", "bank", "信用卡", "储蓄卡", "借记卡"]
        ),
        Pattern(
            brand: MerchantBrand(
                name: "美团",
                icon: "bag.fill",
                color: Color(red: 1.00, green: 0.78, blue: 0.02)  // 美团黄 #FFC700
            ),
            keywords: ["美团", "meituan"]
        ),
        Pattern(
            brand: MerchantBrand(
                name: "大众点评",
                icon: "star.fill",
                color: Color(red: 1.00, green: 0.44, blue: 0.08)  // 点评橙 #FF7014
            ),
            keywords: ["大众点评", "点评"]
        ),
        Pattern(
            brand: MerchantBrand(
                name: "滴滴出行",
                icon: "car.fill",
                color: Color(red: 1.00, green: 0.46, blue: 0.00)  // 滴滴橙 #FF7500
            ),
            keywords: ["滴滴", "didi"]
        ),
        Pattern(
            brand: MerchantBrand(
                name: "京东",
                icon: "shippingbox.fill",
                color: Color(red: 0.90, green: 0.13, blue: 0.13)  // 京东红 #E2231A
            ),
            keywords: ["京东", "jd.com", "jingdong"]
        ),
        Pattern(
            brand: MerchantBrand(
                name: "淘宝天猫",
                icon: "cart.fill",
                color: Color(red: 1.00, green: 0.33, blue: 0.00)  // 淘宝橙 #FF5500
            ),
            keywords: ["淘宝", "taobao", "天猫", "tmall"]
        ),
        Pattern(
            brand: MerchantBrand(
                name: "苹果",
                icon: "applelogo",
                color: Color.inkPrimary
            ),
            keywords: ["apple", "app store", "itunes"]
        ),
    ]
}
