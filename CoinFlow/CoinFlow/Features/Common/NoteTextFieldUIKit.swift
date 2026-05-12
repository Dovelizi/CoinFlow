//  NoteTextFieldUIKit.swift
//  CoinFlow · 备注输入 UIKit 包装
//
//  背景：
//   备注是多行可输入文本（中文/字母/标点 default 键盘没有「完成」键），
//   且 SwiftUI TextField 不支持原生 inputAccessoryView。
//   用 UIViewRepresentable 包 UITextView，挂上和金额一致的 inputAccessoryView，
//   全应用键盘交互统一。
//
//  设计：
//   - 行为对齐 SwiftUI TextField(axis: .vertical, lineLimit: minLines...maxLines)：
//     按内容自适应高度，到 maxLines 后内部滚动
//   - 占位符自绘（UITextView 无原生 placeholder）
//   - 失焦回调对齐 RecordDetailSheet 的 commit 语义

import SwiftUI
import UIKit

struct NoteTextFieldUIKit: UIViewRepresentable {

    @Binding var text: String

    var placeholder: String = ""
    var font: UIFont = UIFont.systemFont(ofSize: 16)
    var textColor: UIColor = .label
    var placeholderColor: UIColor = .tertiaryLabel
    /// 最少显示行数（决定最小高度）
    var minLines: Int = 2
    /// 最多显示行数（超过后内部滚动）
    var maxLines: Int = 5

    /// 焦点变化回调（true=获焦，false=失焦）
    var onFocusChange: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = font
        tv.textColor = textColor
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.isScrollEnabled = false   // 自适应高度；超过 maxLines 时再开启
        tv.text = text
        // 中文键盘候选条右下角图标：返回键样式改为「完成」（替代"⏎换行"图标）。
        // 配合 Coordinator.shouldChangeTextIn 拦截 "\n" → resignFirstResponder，
        // 让"完成"图标的按下行为真的等于"收键盘"，与全局键盘 toolbar 的「确认」语义一致。
        tv.returnKeyType = .done

        // 占位符 label
        let ph = UILabel()
        ph.font = font
        ph.textColor = placeholderColor
        ph.text = placeholder
        ph.numberOfLines = 1
        ph.translatesAutoresizingMaskIntoConstraints = false
        tv.addSubview(ph)
        NSLayoutConstraint.activate([
            ph.leadingAnchor.constraint(equalTo: tv.leadingAnchor),
            ph.topAnchor.constraint(equalTo: tv.topAnchor),
            ph.trailingAnchor.constraint(lessThanOrEqualTo: tv.trailingAnchor),
        ])
        ph.isHidden = !text.isEmpty
        context.coordinator.placeholderLabel = ph

        // ⚠️ 不挂 inputAccessoryView：
        //   中文输入法激活时，键盘顶部会出现系统候选条（"我 你 这个 是 ..."）。
        //   inputAccessoryView 紧贴键盘顶部，会被候选条挤到候选条上方独立成一条；
        //   由于 toolbar 内左侧 flexibleSpace + 右侧"确认"按钮的布局，视觉上就是
        //   一个漂浮在候选条上方的蓝色"确认"小气泡——这正是用户反馈想要消除的视觉冗余。
        //
        //   方案：文本输入靠 returnKeyType = .done 让中文候选条右下角图标变"完成"，
        //   配合 Coordinator.shouldChangeTextIn 拦截 \n → resignFirstResponder
        //   即可收键盘。功能等价但不再产生独立气泡。
        //
        //   注：金额输入（AmountTextFieldUIKit）走 .decimalPad，没有候选条，也没有
        //   return 键，那里依然需要保留 inputAccessoryView 作为唯一收键盘入口。

        // 高度约束：最小 minLines 行高，UIKit 会按 intrinsicContentSize 自适应
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        context.coordinator.placeholderLabel?.isHidden = !uiView.text.isEmpty
        context.coordinator.applyScrollPolicy(uiView)
    }

    /// SwiftUI 询问理想高度时，按 minLines~maxLines 给一个范围
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let lineH = font.lineHeight
        let minH = ceil(lineH * CGFloat(minLines))
        let maxH = ceil(lineH * CGFloat(maxLines))
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let h = min(max(fitting.height, minH), maxH)
        return CGSize(width: width, height: h)
    }

    final class Coordinator: NSObject, UITextViewDelegate {

        var parent: NoteTextFieldUIKit
        weak var placeholderLabel: UILabel?

        init(_ parent: NoteTextFieldUIKit) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            if parent.text != textView.text {
                parent.text = textView.text
            }
            placeholderLabel?.isHidden = !textView.text.isEmpty
            applyScrollPolicy(textView)
            // 高度变化触发 SwiftUI 重新布局
            textView.invalidateIntrinsicContentSize()
        }

        /// 拦截 return 键：returnKeyType = .done 时，按下"完成"应当 = 收键盘，
        /// 而不是插入换行（多行备注的换行需求由内容自然滚动承载，不需要用户主动按 return）。
        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            if text == "\n" {
                textView.resignFirstResponder()
                return false
            }
            return true
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChange?(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChange?(false)
        }

        /// 内容超过 maxLines 时打开内部滚动；否则保持自适应
        func applyScrollPolicy(_ textView: UITextView) {
            let lineH = parent.font.lineHeight
            let maxH = ceil(lineH * CGFloat(parent.maxLines))
            let fitting = textView.sizeThatFits(
                CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
            )
            textView.isScrollEnabled = fitting.height > maxH
        }
    }
}
