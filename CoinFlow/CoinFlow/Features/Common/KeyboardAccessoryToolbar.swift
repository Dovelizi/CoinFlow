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

    /// 生成一个含右对齐「完成」按钮的 UIToolbar，作为 inputAccessoryView 使用。
    /// - Parameters:
    ///   - target: 「完成」按钮事件接收者（一般是 UIViewRepresentable 的 Coordinator）
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
        let done = UIBarButtonItem(
            title: "完成",
            style: .done,
            target: target,
            action: action
        )
        bar.items = [flex, done]
        return bar
    }
}
