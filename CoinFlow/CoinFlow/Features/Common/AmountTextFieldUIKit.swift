//  AmountTextFieldUIKit.swift
//  CoinFlow · 金额输入硬拦截组件
//
//  背景：
//   SwiftUI 原生 TextField + 自定义 Binding 在快速输入时存在根本性漏洞——
//   - 用户连续按键时，UITextField 内部先把字符提交到字符串
//   - 然后 SwiftUI binding 的 set 才被调用
//   - 即使 set 中拒绝写回 vm.amountText，UITextField 内部显示已经包含新字符
//   - 下一次按键又基于"已被拒绝但 UI 仍在"的字符串叠加，导致：
//       a. 数值能突破 1 亿（连按很快时）
//       b. 小数能输到 3+ 位
//       c. 整数能输到 10+ 位
//
//  解决：用 UIViewRepresentable 包 UITextField，实现 UITextFieldDelegate 的
//  shouldChangeCharactersIn 在 UIKit 层硬拦截——返回 false 时字符根本不会
//  进入 UITextField，从源头杜绝 UI/state 不一致。
//
//  设计：
//   - 校验仍走 AmountInputGate.evaluate（与 SwiftUI 路径同源）
//   - 拒绝时回调 onClamp(reason) 让上层触发震动 + 红字 + 彩蛋 toast
//   - 接受时把清洗后的字符串通过 binding 写回 vm
//
//  使用：
//     AmountTextFieldUIKit(
//         text: $vm.amountText,
//         placeholder: "0",
//         font: .systemFont(ofSize: 44, weight: .bold),
//         textColor: .systemRed,
//         alignment: .center,
//         onClamp: { reason in /* 弹 toast */ }
//     )

import SwiftUI
import UIKit

struct AmountTextFieldUIKit: UIViewRepresentable {

    @Binding var text: String

    /// 占位符（用 attributedPlaceholder 配合主色透明度渲染）
    var placeholder: String = "0"

    /// 字体（金额巨字一般 44pt bold）
    var font: UIFont = UIFont.systemFont(ofSize: 44, weight: .bold)

    /// 文本色
    var textColor: UIColor = .label

    /// 占位符色
    var placeholderColor: UIColor = .tertiaryLabel

    /// 对齐方式
    var alignment: NSTextAlignment = .center

    /// 是否启用（false 则不可编辑）
    var isEnabled: Bool = true

    /// 自动聚焦
    var autoFocus: Bool = false

    /// 拦截回调：UIKit 层拒绝某次输入时触发
    var onClamp: ((AmountInputGate.ClampReason) -> Void)? = nil

    /// 焦点变化回调（true=获焦，false=失焦）
    var onFocusChange: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.delegate = context.coordinator
        tf.keyboardType = .decimalPad
        tf.font = font
        tf.textColor = textColor
        tf.textAlignment = alignment
        tf.adjustsFontSizeToFitWidth = true
        tf.minimumFontSize = font.pointSize * 0.5
        tf.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: placeholderColor,
                .font: font,
            ]
        )
        tf.text = text
        tf.isEnabled = isEnabled
        // 让 UITextField 紧贴内容宽度：hugging 高（不愿扩展），compression resistance 高（不愿压缩）。
        // 这样配合 SwiftUI .fixedSize(horizontal: true)，TextField 宽度由 text/placeholder 真实宽度决定，
        // 不会被父 HStack 拉伸成全宽 → ¥ + 数字 整组才能被 Spacer 推到中间居中。
        tf.setContentHuggingPriority(.required, for: .horizontal)
        tf.setContentCompressionResistancePriority(.required, for: .horizontal)
        // 编辑事件 → 通过 coordinator 同步回 binding
        tf.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        if autoFocus {
            DispatchQueue.main.async { tf.becomeFirstResponder() }
        }
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        // 仅在 vm 主动改 text（如 OCR 自动填充 / 切笔同步）时回写到 UITextField；
        // 用户编辑（editingChanged）路径已通过 coordinator 同步过，避免重复 set 导致光标跳到末尾
        if uiView.text != text {
            // 保留光标位置：如果当前是首响应者且新文本较旧文本只是末尾追加 / 截断，
            // 系统会自动维持合理光标；其他场景接受光标重置（OCR 自动填充用户感知不到）
            uiView.text = text
        }
        if uiView.font != font { uiView.font = font }
        if uiView.textColor != textColor { uiView.textColor = textColor }
        if uiView.textAlignment != alignment { uiView.textAlignment = alignment }
        if uiView.isEnabled != isEnabled { uiView.isEnabled = isEnabled }
        // 占位符颜色 / 字体 / 文案变化时刷新 attributedPlaceholder
        let attr = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: placeholderColor,
                .font: font,
            ]
        )
        if uiView.attributedPlaceholder != attr {
            uiView.attributedPlaceholder = attr
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {

        var parent: AmountTextFieldUIKit

        init(_ parent: AmountTextFieldUIKit) {
            self.parent = parent
        }

        /// **核心硬拦截**：UIKit 在字符提交到 UITextField 前先问这个方法。
        /// 返回 false → 字符根本不会进入 textField.text，UI 与 state 永远一致。
        func textField(_ textField: UITextField,
                       shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            // 拼出"如果允许这次输入后"的完整文本
            let current = textField.text ?? ""
            let nsCurrent = current as NSString
            let proposed = nsCurrent.replacingCharacters(in: range, with: string)

            // 走 Gate 校验
            switch AmountInputGate.evaluate(proposed) {
            case .accept(let cleaned):
                // 接受：让 UITextField 自然把字符吃进去；同步 binding
                // 注意：返回 true 时 UIKit 会自己把 string 拼进去，无需手动 set
                // 但 cleaned 可能因为去逗号/去空白与 proposed 不同——少见情况下手动覆盖
                if cleaned != proposed {
                    DispatchQueue.main.async {
                        textField.text = cleaned
                        self.parent.text = cleaned
                    }
                    return false
                }
                // proposed == cleaned：让 UIKit 自然吃字符，binding 由 editingChanged 同步
                return true
            case .reject(let reason):
                parent.onClamp?(reason)
                return false
            }
        }

        @objc func editingChanged(_ textField: UITextField) {
            // UITextField 已接受字符并更新 text 后，把最新文本同步到 binding
            let s = textField.text ?? ""
            if parent.text != s {
                parent.text = s
            }
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onFocusChange?(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.onFocusChange?(false)
        }
    }
}
