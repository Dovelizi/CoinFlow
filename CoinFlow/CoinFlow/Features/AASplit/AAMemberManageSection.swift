//  AAMemberManageSection.swift
//  CoinFlow · M11 — 结算阶段·成员管理
//
//  功能：
//  - 列表展示成员（昵称 + emoji + 应付小计）
//  - "+ 添加成员"输入框（1–20 字、同账本去重、@AppStorage 历史昵称建议）
//  - 长按"修改昵称"和"删除"
//    - 无关联：直接软删
//    - 有关联：弹确认 + 重算
//    - 已支付：删除按钮置灰

import SwiftUI

struct AAMemberManageSection: View {

    @ObservedObject var vm: AASplitDetailViewModel
    @AppStorage("aa.preview.nicknames") private var nicknamesRaw: String = ""

    @State private var newName: String = ""
    @State private var showRenameAlert: Bool = false
    @State private var renameTarget: AAMember? = nil
    @State private var renameInput: String = ""
    @State private var deleteConfirm: AAMember? = nil
    @State private var deleteUsedCount: Int = 0
    @State private var addError: String? = nil

    private var nicknameSuggestions: [String] {
        nicknamesRaw.split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { sug in !vm.members.contains(where: { $0.name == sug }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space5) {
            HStack {
                Text("分账成员")
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
                Text("\(vm.members.count) 人")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
            }

            // 添加输入行
            HStack {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(Color.inkTertiary)
                TextField("输入成员昵称（1–20 字）", text: $newName)
                    .submitLabel(.done)
                    .onSubmit { tryAdd() }
                Button {
                    tryAdd()
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

            // 历史昵称建议
            if !nicknameSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: NotionTheme.space3) {
                        ForEach(nicknameSuggestions, id: \.self) { name in
                            Button {
                                Haptics.select()
                                addMemberDirectly(name: name)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 9))
                                    Text(name)
                                        .font(NotionFont.micro())
                                }
                                .foregroundStyle(Color.accentBlue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.accentBlue.opacity(0.10))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // 成员列表
            if vm.members.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.statusWarning)
                    Text("结算阶段必须至少添加 1 位成员")
                        .font(NotionFont.small())
                        .foregroundStyle(Color.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(NotionTheme.space5)
                .background(
                    RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                        .fill(Color.statusWarning.opacity(0.10))
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(vm.members) { m in
                        memberRow(m)
                        if m.id != vm.members.last?.id {
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
            }
        }
        .alert("修改昵称",
               isPresented: $showRenameAlert,
               presenting: renameTarget) { target in
            TextField("昵称", text: $renameInput)
            Button("取消", role: .cancel) {}
            Button("保存") {
                try? vm.renameMember(id: target.id, name: renameInput)
            }
        } message: { _ in Text("1–20 字") }
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: Binding(
                get: { deleteConfirm != nil },
                set: { if !$0 { deleteConfirm = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleteConfirm
        ) { target in
            Button("删除", role: .destructive) {
                try? vm.deleteMember(id: target.id)
                try? vm.recomputeShares()
                deleteConfirm = nil
            }
            Button("取消", role: .cancel) { deleteConfirm = nil }
        } message: { _ in
            Text(deleteUsedCount == 0
                 ? "确定要删除该成员？"
                 : "该成员参与了 \(deleteUsedCount) 笔流水的分摊，删除后会自动重新分摊。")
        }
    }

    private var deleteDialogTitle: String {
        deleteConfirm.map { "删除 \($0.name)？" } ?? "删除？"
    }

    private var trimmedName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdd: Bool {
        !trimmedName.isEmpty && trimmedName.count <= 20 &&
        !vm.members.contains(where: { $0.name == trimmedName })
    }

    private func tryAdd() {
        let name = trimmedName
        guard !name.isEmpty else { return }
        if name.count > 20 { addError = "昵称最长 20 字"; return }
        if vm.members.contains(where: { $0.name == name }) {
            addError = "该昵称已存在"; return
        }
        addMemberDirectly(name: name)
        newName = ""
        addError = nil
    }

    private func addMemberDirectly(name: String) {
        do {
            try vm.addMember(name: name)
            // 添加新成员后默认全员均分（重算 share）
            try vm.recomputeShares()
        } catch {
            addError = error.localizedDescription
        }
    }

    private func memberRow(_ m: AAMember) -> some View {
        let owe = vm.owe(of: m.id)
        let isPaid = m.status == .paid
        return HStack(spacing: NotionTheme.space5) {
            Text(m.avatarEmoji ?? "👤")
                .font(.system(size: 22))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name)
                    .font(NotionFont.body())
                    .foregroundStyle(Color.inkPrimary)
                Text(isPaid ? "已支付" : "应付 ¥\(StatsFormat.decimalGrouped(owe))")
                    .font(NotionFont.micro())
                    .foregroundStyle(isPaid ? Color.statusSuccess : Color.inkSecondary)
            }
            Spacer()
            Menu {
                Button {
                    renameTarget = m
                    renameInput = m.name
                    showRenameAlert = true
                } label: {
                    Label("修改昵称", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    if isPaid {
                        // 已支付：先弹提示，要求先撤销支付确认
                        addError = "该成员已确认支付，请先撤销支付状态再删除"
                    } else {
                        deleteUsedCount = vm.shares
                            .filter { $0.memberId == m.id && $0.deletedAt == nil }
                            .count
                        deleteConfirm = m
                    }
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(isPaid)
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
        }
        .padding(NotionTheme.space5)
    }
}
