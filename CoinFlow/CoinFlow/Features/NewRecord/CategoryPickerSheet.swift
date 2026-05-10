//  CategoryPickerSheet.swift
//  CoinFlow · M3.2 · §5.5.10
//
//  分类选择 sheet：3 列网格，按 sort_order 展示，选中即关闭。

import SwiftUI

struct CategoryPickerSheet: View {

    let categories: [Category]
    let selectedId: String?
    let onSelect: (Category) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: NotionTheme.space5),
        GridItem(.flexible(), spacing: NotionTheme.space5),
        GridItem(.flexible(), spacing: NotionTheme.space5)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appSheetCanvas.ignoresSafeArea()
                ScrollView {
                    LazyVGrid(columns: columns, spacing: NotionTheme.space5) {
                        ForEach(categories) { cat in
                            cell(cat)
                                .onTapGesture {
                                    onSelect(cat)
                                    dismiss()
                                }
                        }
                    }
                    .padding(NotionTheme.space5)
                }
            }
            .navigationTitle("选择分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .font(NotionFont.body())
                        .foregroundStyle(Color.inkPrimary)
                }
            }
        }
    }

    private func cell(_ cat: Category) -> some View {
        let selected = cat.id == selectedId
        return VStack(spacing: NotionTheme.space3) {
            ZStack {
                RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                    .fill(Color.hoverBg)
                    .frame(width: 48, height: 48)
                Image(systemName: cat.icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.inkSecondary)
            }
            Text(cat.name)
                .font(NotionFont.small())
                .foregroundStyle(selected ? Color.accentBlue : Color.inkPrimary)
                .lineLimit(1)
        }
        .padding(.vertical, NotionTheme.space5)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                .stroke(selected ? Color.accentBlue : Color.clear,
                        lineWidth: selected ? 1.5 : 0)
        )
    }
}
