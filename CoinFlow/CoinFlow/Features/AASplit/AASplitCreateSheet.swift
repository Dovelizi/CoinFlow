//  AASplitCreateSheet.swift
//  CoinFlow · M11 — AA 分账创建 Sheet
//
//  字段：
//  - 分账名称（必填，1–30 字）
//  - 备注（可选，≤140 字）
//  - 封面 emoji（可选，单个 emoji 字符）

import SwiftUI

struct AASplitCreateSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var note: String = ""
    @State private var emoji: String = "💰"
    @State private var saving: Bool = false
    @State private var saveError: String?

    /// 创建成功回调（携带新建的 Ledger）。
    let onCreated: (Ledger) -> Void

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && trimmedName.count <= 30 && !saving
    }

    private static let emojiPalette: [String] = [
        "💰", "🍜", "🛫", "🍻", "🎉", "🏖️", "🎂", "🛍️",
        "🚗", "🏠", "🎬", "🎮", "📚", "💼", "🥂", "🍱"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NotionTheme.space6) {
                    // 名称
                    VStack(alignment: .leading, spacing: NotionTheme.space3) {
                        Text("分账名称")
                            .font(NotionFont.small())
                            .foregroundStyle(Color.inkSecondary)
                        TextField("如：7月泰国旅行", text: $name)
                            .textFieldStyle(.plain)
                            .font(NotionFont.body())
                            .foregroundStyle(Color.inkPrimary)
                            .padding(NotionTheme.space5)
                            .background(
                                RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                                    .fill(Color.hoverBg)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                                    .stroke(nameError ? Color.dangerRed : Color.clear, lineWidth: 1)
                            )
                        if let msg = nameValidationMessage {
                            Text(msg)
                                .font(NotionFont.micro())
                                .foregroundStyle(Color.dangerRed)
                        } else {
                            Text("\(trimmedName.count)/30")
                                .font(NotionFont.micro())
                                .foregroundStyle(Color.inkTertiary)
                        }
                    }

                    // emoji
                    VStack(alignment: .leading, spacing: NotionTheme.space3) {
                        Text("封面")
                            .font(NotionFont.small())
                            .foregroundStyle(Color.inkSecondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                            ForEach(Self.emojiPalette, id: \.self) { e in
                                Button {
                                    Haptics.select()
                                    emoji = e
                                } label: {
                                    Text(e)
                                        .font(.system(size: 24))
                                        .frame(width: 36, height: 36)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(emoji == e ? Color.accentBlue.opacity(0.18) : Color.hoverBg)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(emoji == e ? Color.accentBlue : Color.clear, lineWidth: 1.5)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // 备注
                    VStack(alignment: .leading, spacing: NotionTheme.space3) {
                        Text("备注（可选）")
                            .font(NotionFont.small())
                            .foregroundStyle(Color.inkSecondary)
                        TextField("一段话描述本次分账", text: $note, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(NotionFont.body())
                            .foregroundStyle(Color.inkPrimary)
                            .lineLimit(2...5)
                            .padding(NotionTheme.space5)
                            .background(
                                RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                                    .fill(Color.hoverBg)
                            )
                        Text("\(note.count)/140")
                            .font(NotionFont.micro())
                            .foregroundStyle(note.count > 140 ? Color.dangerRed : Color.inkTertiary)
                    }

                    if let err = saveError {
                        Text(err)
                            .font(NotionFont.small())
                            .foregroundStyle(Color.dangerRed)
                    }
                }
                .padding(NotionTheme.space5)
            }
            .navigationTitle("新建 AA 分账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        if saving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("创建").fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .themedSheetSurface()
        }
    }

    private var nameError: Bool { nameValidationMessage != nil }

    private var nameValidationMessage: String? {
        if trimmedName.isEmpty && !name.isEmpty { return "请输入分账名称" }
        if trimmedName.count > 30 { return "名称最长 30 字" }
        return nil
    }

    private func save() {
        guard canSave else { return }
        if note.count > 140 { saveError = "备注不能超过 140 字"; return }
        saving = true
        saveError = nil
        do {
            let ledger = try AASplitService.shared.createSplit(
                name: trimmedName,
                emoji: emoji,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            saving = false
            Haptics.success()
            onCreated(ledger)
            dismiss()
        } catch {
            saving = false
            saveError = error.localizedDescription
            Haptics.error()
        }
    }
}
