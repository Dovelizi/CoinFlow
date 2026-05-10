//  KeyboardDoneToolbar.swift
//  CoinFlow · 键盘工具栏统一入口
//
//  背景：SwiftUI 原生 `.toolbar { ToolbarItemGroup(placement: .keyboard) }` 在
//  sheet + presentationDetents + NavigationStack + 多 TextField 场景下存在
//  已知不稳定问题（时有时无 / 切换字段后消失 / 重复显示）。
//  参考：https://livsycode.com/swiftui/how-to-fix-toolbar-issues-in-swiftui-when-using-the-keyboard/
//
//  解决方案：放弃 `.toolbar`，改用 `.safeAreaInset(edge: .bottom)` + 键盘通知自绘。
//  - 键盘将要显示时：isKeyboardShown = true → toolbar 出现
//  - 键盘将要隐藏时：isKeyboardShown = false → toolbar 消失
//  - 点击「完成」：通过 `resignFirstResponder` 全局收起第一响应者（与焦点枚举无关）
//
//  使用：在 sheet / 视图的最外层调用 `.keyboardDoneToolbar()` 即可，
//  对视图层级里任意 TextField 的任意焦点都生效，且不会出现重复或遗漏。

import SwiftUI
import UIKit

private struct KeyboardDoneToolbarModifier: ViewModifier {

    @State private var isKeyboardShown: Bool = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if isKeyboardShown {
                    doneBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillShowNotification)) { _ in
                // 轻微延迟，让键盘动画与 toolbar 出现对齐，避免"先弹起再补位"
                withAnimation(.easeInOut(duration: 0.2)) {
                    isKeyboardShown = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardShown = false
            }
    }

    /// 自绘 toolbar：一个右对齐的「完成」按钮 + 顶部分隔线
    /// 点击时向第一响应者发 `resignFirstResponder`，由系统全局收起键盘；
    /// 这种做法与视图层级里具体用的 @FocusState 无关，避免了绑定不上的问题。
    private var doneBar: some View {
        HStack {
            Spacer()
            Button {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            } label: {
                Text("完成")
                    .font(.custom("PingFangSC-Semibold", size: 15))
                    .foregroundStyle(Color.accentBlue)
                    .padding(.horizontal, NotionTheme.space5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("收起键盘")
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(
            Color(UIColor.systemBackground)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.divider)
                        .frame(height: 0.5)
                }
        )
    }
}

extension View {
    /// 在视图底部叠加一个随键盘出现/消失的「完成」工具栏。
    /// 替代 `.toolbar { ToolbarItemGroup(placement: .keyboard) }`——
    /// 原生 API 在 sheet/navigation 嵌套下不稳定，此方案用 safeAreaInset + 键盘通知稳定实现。
    func keyboardDoneToolbar() -> some View {
        modifier(KeyboardDoneToolbarModifier())
    }
}
