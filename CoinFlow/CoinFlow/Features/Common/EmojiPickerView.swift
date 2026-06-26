//  EmojiPickerView.swift
//  CoinFlow · 通用 emoji 选择器
//
//  使用：
//   EmojiPickerView(selected: $emoji)
//
//  特性：
//  - 48 个常用封面 emoji（旅行/餐饮/购物/生活/娱乐/运动/工作/其他）
//  - 支持自定义：右侧输入框可输入任意 emoji
//  - 8 列网格 + 选中高亮

import SwiftUI

struct EmojiPickerView: View {

    @Binding var selected: String

    static let presets: [String] = [
        // 旅行
        "✈️", "🏖️", "🏔️", "🗺️", "🏯", "🎢",
        // 餐饮
        "🍜", "🍣", "🥘", "🍕", "☕", "🍰",
        // 购物
        "🛍️", "👗", "👟", "💄", "📱", "🎁",
        // 生活
        "🏠", "🛋️", "🚗", "💡", "🔧", "🏥",
        // 娱乐
        "🎬", "🎮", "🎵", "📚", "🎨", "🎤",
        // 运动
        "💪", "🏃", "🚴", "🏊", "⚽", "🧘",
        // 工作
        "💼", "💻", "📊", "🤝", "📝", "🔍",
        // 其他
        "💰", "🎓", "🐱", "🌸", "🎉", "❤️"
    ]
    static let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            HStack(spacing: 4) {
                Text("封面")
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
                Spacer()
                Text("自定义")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
                TextField("😊", text: customBinding)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 20))
                    .frame(width: 44, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.hoverBg)
                    )
            }
            LazyVGrid(columns: Self.columns, spacing: 8) {
                ForEach(Self.presets, id: \.self) { e in
                    Button {
                        Haptics.select()
                        selected = e
                    } label: {
                        Text(e)
                            .font(.system(size: 24))
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selected == e ? Color.accentBlue.opacity(0.18) : Color.hoverBg)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(selected == e ? Color.accentBlue : Color.clear, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var customBinding: Binding<String> {
        Binding(
            get: { selected },
            set: { new in
                let t = new.trimmingCharacters(in: .whitespaces)
                if let first = t.first { selected = String(first) }
                else if t.isEmpty { selected = "💰" }
            }
        )
    }
}
