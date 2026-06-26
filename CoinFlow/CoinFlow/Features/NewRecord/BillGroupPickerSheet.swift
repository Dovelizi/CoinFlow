//  BillGroupPickerSheet.swift
//  CoinFlow · M13 · 账单分组选择器
//
//  UI 与交互逻辑与 AALedgerPickerSheet 保持一致。

import SwiftUI

struct BillGroupPickerSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var groups: [BillGroup] = []
    @State private var loadError: String?
    @State private var showCreate: Bool = false

    let selectedId: String?
    let onSelect: (BillGroup) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: NotionTheme.space5) {
                    headerCard
                    defaultRow
                    if groups.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: NotionTheme.space3) {
                            ForEach(groups) { group in
                                groupRow(group)
                            }
                        }
                    }
                    if let err = loadError {
                        Text(err)
                            .font(NotionFont.small())
                            .foregroundStyle(Color.dangerRed)
                    }
                }
                .padding(NotionTheme.space5)
            }
            .navigationTitle("账单分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .themedSheetSurface()
            .onAppear { reload() }
            .sheet(isPresented: $showCreate) {
                BillGroupCreateSheet(onCreated: { group in
                    showCreate = false
                    reload()
                    onSelect(group)
                    dismiss()
                })
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: - 子视图

    private var headerCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.accentBlue)
            Text("流水默认归入「日常消费」；可创建自定义分组区分不同消费事件")
                .font(NotionFont.small())
                .foregroundStyle(Color.inkSecondary)
            Spacer(minLength: 0)
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .fill(Color.accentBlue.opacity(0.10))
        )
    }

    private var defaultRow: some View {
        Button {
            Haptics.select()
            if let dg = try? SQLiteBillGroupRepository.shared.find(id: DefaultSeeder.defaultBillGroupId) {
                onSelect(dg)
            }
            dismiss()
        } label: {
            HStack(spacing: NotionTheme.space5) {
                Text("💰")
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text("日常消费")
                        .font(NotionFont.bodyBold())
                        .foregroundStyle(Color.inkPrimary)
                    Text("默认分组，不可删除")
                        .font(NotionFont.small())
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer()
                if selectedId == DefaultSeeder.defaultBillGroupId {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentBlue)
                }
            }
            .padding(NotionTheme.space5)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                    .fill(Color.hoverBg)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func groupRow(_ group: BillGroup) -> some View {
        Button {
            Haptics.select()
            onSelect(group)
            dismiss()
        } label: {
            HStack(spacing: NotionTheme.space5) {
                Text(group.emoji)
                    .font(.system(size: 18))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(NotionFont.bodyBold())
                        .foregroundStyle(Color.inkPrimary)
                    if let note = group.note, !note.isEmpty {
                        Text(note)
                            .font(NotionFont.micro())
                            .foregroundStyle(Color.inkSecondary)
                            .lineLimit(1)
                    } else {
                        Text("自定义分组")
                            .font(NotionFont.micro())
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
                Spacer()
                if selectedId == group.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentBlue)
                }
            }
            .padding(NotionTheme.space5)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                    .fill(Color.hoverBg)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            if !group.isDefault {
                Button("删除", role: .destructive) {
                    try? SQLiteBillGroupRepository.shared.delete(id: group.id)
                    reload()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: NotionTheme.space5) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 32))
                .foregroundStyle(Color.inkTertiary)
            Text("还没有自定义账单分组")
                .font(NotionFont.body())
                .foregroundStyle(Color.inkSecondary)
            Button {
                showCreate = true
            } label: {
                Text("创建账单分组")
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, NotionTheme.space6)
                    .padding(.vertical, NotionTheme.space3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentBlue)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NotionTheme.space7)
    }

    // MARK: - 数据

    private func reload() {
        do {
            var all = try SQLiteBillGroupRepository.shared.list(includeDeleted: false)
            all.removeAll { $0.isDefault }
            groups = all.sorted { $0.sortOrder < $1.sortOrder }
            loadError = nil
        } catch {
            groups = []
            loadError = "加载失败：\(error.localizedDescription)"
        }
    }
}
