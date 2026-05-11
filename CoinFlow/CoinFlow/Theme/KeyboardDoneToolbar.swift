//  KeyboardDoneToolbar.swift
//  CoinFlow · 键盘工具栏统一入口
//
//  实现要点（v4，视图局部坐标手算）：
//   - 关闭 content 自身的键盘安全区自动避让（`.ignoresSafeArea(.keyboard, edges: .bottom)`），
//     不让 SwiftUI 把 content（含底部按钮条）推上键盘
//   - 用 GeometryReader 在 background 里读**视图底部到 window 底部的 global Y**，
//     然后 `keyboardHeight = max(0, viewMaxY - keyboardFrame.minY)`——
//     即"视图自身底部需要上推多少像素才能贴到键盘顶"
//   - 无论视图是全屏 sheet、`.presentationDetents` 半屏 sheet、fullScreenCover，
//     还是 NavigationStack 内子页，算出来的值都等于视图下边缘到键盘顶的真实距离
//
//  v3 失败原因（记录教训）：
//   v3 用 `currentWindowHeight() - endFrame.origin.y`。在 `.presentationDetents`
//   sheet 里，sheet 容器 ≠ window——算出的 kbVisible 过大，
//   既把 doneBar 推过头（盖住内容），又与 `.ignoresSafeArea(.keyboard)` 行为打架，
//   SwiftUI 额外把 bottomBar 推到键盘上方。OCR 页（sheet 无 detents，容器 = window）
//   恰好规避了这个差。
//
//  使用：在 sheet / 视图最外层调用 `.keyboardDoneToolbar()` 即可。

import SwiftUI
import UIKit

private struct KeyboardDoneToolbarModifier: ViewModifier {

    /// 键盘顶在 window 坐标系中的 Y（>=0，键盘隐藏时 = 视图底部 Y，相当于 keyboardHeight=0）
    @State private var keyboardTopY: CGFloat = .greatestFiniteMagnitude
    /// 视图底部在 window 坐标系中的 Y（由 GeometryReader 实时测得）
    @State private var viewBottomY: CGFloat = 0

    private let frameChange = NotificationCenter.default
        .publisher(for: UIResponder.keyboardWillChangeFrameNotification)
    private let willHide = NotificationCenter.default
        .publisher(for: UIResponder.keyboardWillHideNotification)

    /// 视图底部需要向上挪多少才能贴到键盘顶；键盘没遮到视图时 = 0
    private var keyboardHeight: CGFloat {
        max(0, viewBottomY - keyboardTopY)
    }

    func body(content: Content) -> some View {
        content
            // 关键：关闭 content 自身的键盘安全区自动避让，让布局只靠 overlay 手算。
            // 这样"已自己加 ignoresSafeArea 的页面"和"没加的页面"行为统一。
            .ignoresSafeArea(.keyboard, edges: .bottom)
            // 用 background + GeometryReader 实时读视图底部的 global Y。
            // 放 background 比 overlay 更安全：不参与布局，且在所有父容器（sheet/detents/
            // NavigationStack）下都能得到视图的真实 global frame。
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            viewBottomY = geo.frame(in: .global).maxY
                        }
                        .onChange(of: geo.frame(in: .global).maxY) { newValue in
                            viewBottomY = newValue
                        }
                }
            )
            .overlay(alignment: .bottom) {
                if keyboardHeight > 0 {
                    doneBar
                        .padding(.bottom, keyboardHeight)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onReceive(frameChange) { note in
                guard let endFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
                let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.22
                withAnimation(.easeInOut(duration: duration)) {
                    keyboardTopY = endFrame.origin.y
                }
            }
            .onReceive(willHide) { note in
                let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.22
                withAnimation(.easeInOut(duration: duration)) {
                    // 键盘收起：把 keyboardTopY 推到 greatestFiniteMagnitude，keyboardHeight=0
                    keyboardTopY = .greatestFiniteMagnitude
                }
            }
    }

    /// 自绘 toolbar：右对齐「完成」按钮 + 顶部分隔线
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
            .buttonStyle(.pressableSoft)
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
    /// 后者在 sheet/navigation 嵌套下不稳定。
    func keyboardDoneToolbar() -> some View {
        modifier(KeyboardDoneToolbarModifier())
    }
}
