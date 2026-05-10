//  InteractivePopEnabler.swift
//  CoinFlow · 修复 NavigationStack + navigationBarHidden 下左缘返回手势失效
//
//  iOS 系统的 UINavigationController.interactivePopGestureRecognizer 默认
//  会在 navigationBar 被隐藏时失效（Apple 已知行为）。
//  做法：在 NavigationStack 根视图挂一个 0 尺寸的 UIViewController，
//  通过 parent chain 找到宿主 UINavigationController，清空手势 delegate，
//  使系统重新允许"栈深度>=1 时左缘滑动返回"。

import SwiftUI
import UIKit

/// 在需要启用左缘返回手势的 NavigationStack 根视图附加 `.enableInteractivePop()`
extension View {
    func enableInteractivePop() -> some View {
        self.background(InteractivePopEnabler())
    }
}

private struct InteractivePopEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { Holder() }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private final class Holder: UIViewController {
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        // 向上查找 UINavigationController
        var node: UIViewController? = parent
        while node != nil {
            if let nav = node as? UINavigationController {
                nav.interactivePopGestureRecognizer?.delegate = nil
                nav.interactivePopGestureRecognizer?.isEnabled = true
                return
            }
            node = node?.parent
        }
    }
}
