//  KeyboardAccessoryToolbar.swift
//  CoinFlow · 键盘 inputAccessoryView 统一工厂
//
//  背景：
//   .decimalPad 键盘没有 return/done 键，必须靠 inputAccessoryView 提供收起入口；
//   备注的多行 UITextView 也需要相同的「完成」按钮统一交互。
//
//   使用 UITextField/UITextView 自带的 inputAccessoryView 是 iOS 系统级机制：
//   - 由 UIKit 自动定位在键盘正上方
//   - 不依赖任何 SwiftUI 坐标系/sheet 容器/NavigationStack 嵌套
//   - 任何 iOS 版本下都稳定
//
//  使用：
//      tf.inputAccessoryView = KeyboardAccessoryToolbar.make(
//          target: coordinator,
//          action: #selector(Coordinator.dismissKeyboard)
//      )

import UIKit

enum KeyboardAccessoryToolbar {

    /// 生成一个含右对齐「确认」按钮的 UIToolbar，作为 inputAccessoryView 使用。
    ///
    /// 视觉规范（与系统蓝色 return key 对齐）：
    /// - 文案：「确认」（语义上等价于 SwiftUI 的 .submitLabel(.done) 在中文系统的「完成」，
    ///        但项目内统一用「确认」二字，让用户视觉一致）
    /// - 颜色：系统蓝（与文本框 return key 同色，让用户感知“这是同类提交按钮”）
    /// - 字重：semibold，比左侧普通按钮更突出，承担主操作角色
    ///
    /// - Parameters:
    ///   - target: 「确认」按钮事件接收者（一般是 UIViewRepresentable 的 Coordinator）
    ///   - action: 选择子，在 target 上必须是 @objc 方法
    static func make(target: Any?, action: Selector) -> UIToolbar {
        let bar = UIToolbar()
        bar.barStyle = .default
        bar.isTranslucent = true
        bar.sizeToFit()
        let flex = UIBarButtonItem(
            barButtonSystemItem: .flexibleSpace,
            target: nil, action: nil
        )
        let confirm = UIBarButtonItem(
            title: "确认",
            style: .done,
            target: target,
            action: action
        )
        // 蓝色 + semibold，与系统 return key 视觉一致
        confirm.tintColor = .systemBlue
        confirm.setTitleTextAttributes(
            [.font: UIFont.systemFont(ofSize: 16, weight: .semibold),
             .foregroundColor: UIColor.systemBlue],
            for: .normal
        )
        confirm.setTitleTextAttributes(
            [.font: UIFont.systemFont(ofSize: 16, weight: .semibold),
             .foregroundColor: UIColor.systemBlue.withAlphaComponent(0.5)],
            for: .highlighted
        )
        bar.items = [flex, confirm]
        return bar
    }
}
