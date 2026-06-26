//  BillGroupCreateSheet.swift
//  CoinFlow · M13 · 账单分组创建 Sheet
//
//  UI 与交互逻辑与 AASplitCreateSheet 保持一致。

import SwiftUI

struct BillGroupCreateSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var note: String = ""
    @State private var emoji: String = "💰"
    @State private var saving: Bool = false
    @State private var saveError: String?

    let onCreated: (BillGroup) -> Void

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && trimmedName.count <= 20 && !saving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NotionTheme.space6) {
                    nameField
                    emojiPicker
                    noteField
                    if let err = saveError {
                        Text(err)
                            .font(NotionFont.small())
                            .foregroundStyle(Color.dangerRed)
                    }
                }
                .padding(NotionTheme.space5)
            }
            .navigationTitle("新建账单分组")
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

    // MARK: - 名称

    private var nameField: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            Text("分组名称")
                .font(NotionFont.small())
                .foregroundStyle(Color.inkSecondary)
            TextField("如：云南旅游", text: $name)
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
                Text("\(trimmedName.count)/20")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
            }
        }
    }

    private var nameError: Bool { nameValidationMessage != nil }

    private var nameValidationMessage: String? {
        if trimmedName.isEmpty && !name.isEmpty { return "请输入分组名称" }
        if trimmedName.count > 20 { return "名称最长 20 字" }
        return nil
    }

    // MARK: - 封面

    private var emojiPicker: some View {
        EmojiPickerView(selected: $emoji)
    }

    // MARK: - 备注

    private var noteField: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            Text("备注（可选）")
                .font(NotionFont.small())
                .foregroundStyle(Color.inkSecondary)
            TextField("一段话描述本次消费事件", text: $note, axis: .vertical)
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
    }

    // MARK: - Save

    private func save() {
        guard canSave else { return }
        if note.count > 140 { saveError = "备注不能超过 140 字"; return }
        saving = true
        saveError = nil
        let group = BillGroup(
            id: UUID().uuidString,
            name: trimmedName,
            emoji: emoji,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines),
            sortOrder: 0,
            isDefault: false,
            createdAt: Date(),
            updatedAt: Date(),
            deletedAt: nil
        )
        do {
            try SQLiteBillGroupRepository.shared.insert(group)
            saving = false
            Haptics.success()
            onCreated(group)
            dismiss()
        } catch {
            saving = false
            saveError = error.localizedDescription
            Haptics.error()
        }
    }
}
