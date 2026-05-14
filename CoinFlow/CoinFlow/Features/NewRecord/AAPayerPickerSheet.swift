//  AAPayerPickerSheet.swift
//  CoinFlow · M12 — AA 流水支付人选择器
//
//  - 列出当前 AA 账本下所有成员（"我"在首位）
//  - 点选某成员 → 写回 vm.selectedPayerMemberId 后关闭
//  - 底部输入行：输入新成员昵称 → vm.addNewPayer（即时落库 aa_member）→ 关闭
//
//  设计原则：与 AAMemberManageSection 的添加体验对齐（去重规则一致：1–20 字、活动行同名复用）
//  入口：NewRecordModal 选中 AA 账本后出现"支付人"行 → 点击呼出本 sheet

import SwiftUI

struct AAPayerPickerSheet: View {

    @ObservedObject var vm: NewRecordViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var newName: String = ""
    @State private var addError: String? = nil

    private var trimmedName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdd: Bool {
        !trimmedName.isEmpty && trimmedName.count <= 20 &&
        !vm.availablePayers.contains(where: { $0.name == trimmedName })
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: NotionTheme.space5) {
                // 头部说明
                Text("选择本笔流水的实际支付人。结算时系统会按各成员实付金额自动算差额。")
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.horizontal, NotionTheme.space5)
                    .padding(.top, NotionTheme.space3)

                // 成员列表
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(vm.availablePayers) { m in
                            payerRow(m)
                            if m.id != vm.availablePayers.last?.id {
                                Rectangle()
                                    .fill(Color.divider)
                                    .frame(height: NotionTheme.borderWidth)
                                    .padding(.leading, 48)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                            .fill(Color.hoverBg.opacity(0.5))
                    )
                    .padding(.horizontal, NotionTheme.space5)
                }

                // 底部添加新成员
                VStack(alignment: .leading, spacing: NotionTheme.space3) {
                    HStack {
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundStyle(Color.inkTertiary)
                        TextField("新增成员（1–20 字）", text: $newName)
                            .submitLabel(.done)
                            .onSubmit { tryAddAndPick() }
                        Button {
                            tryAddAndPick()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(canAdd ? Color.accentBlue : Color.inkTertiary)
                        }
                        .disabled(!canAdd)
                        .buttonStyle(.plain)
                    }
                    .padding(NotionTheme.space5)
                    .background(
                        RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                            .fill(Color.hoverBg)
                    )
                    if let err = addError {
                        Text(err)
                            .font(NotionFont.micro())
                            .foregroundStyle(Color.dangerRed)
                    }
                }
                .padding(.horizontal, NotionTheme.space5)
                .padding(.bottom, NotionTheme.space5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedSheetSurface()
            .navigationTitle("支付人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func payerRow(_ m: AAMember) -> some View {
        let selected = vm.selectedPayerMemberId == m.id
        let isMe = AAOwner.isOwnerMember(m)
        return Button {
            Haptics.select()
            vm.selectedPayerMemberId = m.id
            dismiss()
        } label: {
            HStack(spacing: NotionTheme.space5) {
                Text(m.avatarEmoji ?? (isMe ? "🙋" : "👤"))
                    .font(.system(size: 22))
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(m.name)
                            .font(NotionFont.body())
                            .foregroundStyle(Color.inkPrimary)
                        if isMe {
                            Text("默认")
                                .font(NotionFont.micro())
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.accentBlue)
                                )
                        }
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentBlue)
                }
            }
            .padding(NotionTheme.space5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tryAddAndPick() {
        let name = trimmedName
        guard !name.isEmpty else { return }
        if name.count > 20 { addError = "昵称最长 20 字"; return }
        if vm.availablePayers.contains(where: { $0.name == name }) {
            addError = "该昵称已存在"; return
        }
        if vm.addNewPayer(name: name) != nil {
            newName = ""
            addError = nil
            dismiss()
        } else {
            addError = "添加失败，请重试"
        }
    }
}
