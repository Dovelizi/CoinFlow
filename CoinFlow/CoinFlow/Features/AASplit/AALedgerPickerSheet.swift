//  AALedgerPickerSheet.swift
//  CoinFlow · M11 — 新建流水时的 AA 账本选择器
//
//  - 仅展示 aaStatus = recording 的 AA 账本（按 created_at DESC）
//  - 空态时引导用户跳到创建 Sheet（AASplitCreateSheet）
//  - 用户选中后 onPick 回调；点"切回个人账户"传 nil

import SwiftUI

struct AALedgerPickerSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var ledgers: [Ledger] = []
    @State private var loadError: String?
    @State private var showCreate: Bool = false

    /// 当前已选 AA 账本（用于高亮）
    let currentSelection: Ledger?
    /// 选中回调；传 nil 表示"切回个人账户"
    let onPick: (Ledger?) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: NotionTheme.space5) {
                    headerCard
                    personalRow
                    if ledgers.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: NotionTheme.space3) {
                            ForEach(ledgers) { ledger in
                                aaRow(ledger)
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
            .navigationTitle("选择账本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .themedSheetSurface()
            .onAppear { reload() }
            .sheet(isPresented: $showCreate) {
                // 任务 5 创建 AASplitCreateSheet 后，此处由其接管。
                // 过渡阶段允许、为避免编译失败，这里使用轻量版 placeholder，
                // 任务 5 会统一替换为 AASplitCreateSheet。
                AASplitCreateSheet(onCreated: { _ in
                    showCreate = false
                    reload()
                })
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: - 子视图

    private var headerCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.accentPurple)
            Text("仅可选择「分账记录中」状态的 AA 账本")
                .font(NotionFont.small())
                .foregroundStyle(Color.inkSecondary)
            Spacer(minLength: 0)
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .fill(Color.accentPurple.opacity(0.10))
        )
    }

    private var personalRow: some View {
        Button {
            Haptics.select()
            onPick(nil)
            dismiss()
        } label: {
            HStack(spacing: NotionTheme.space5) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("个人账户")
                        .font(NotionFont.bodyBold())
                        .foregroundStyle(Color.inkPrimary)
                    Text("默认我的账本")
                        .font(NotionFont.small())
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer()
                if currentSelection == nil {
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

    private func aaRow(_ ledger: Ledger) -> some View {
        Button {
            Haptics.select()
            onPick(ledger)
            dismiss()
        } label: {
            HStack(spacing: NotionTheme.space5) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentPurple)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ledger.name)
                        .font(NotionFont.bodyBold())
                        .foregroundStyle(Color.inkPrimary)
                    Text("分账记录中")
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.accentBlue)
                }
                Spacer()
                if currentSelection?.id == ledger.id {
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

    private var emptyState: some View {
        VStack(spacing: NotionTheme.space5) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(Color.inkTertiary)
            Text("还没有「分账记录中」的 AA 账本")
                .font(NotionFont.body())
                .foregroundStyle(Color.inkSecondary)
            Button {
                showCreate = true
            } label: {
                Text("立即创建分账")
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

    private func reload() {
        do {
            ledgers = try SQLiteLedgerRepository.shared
                .listAA(status: .recording, includeArchived: false)
            loadError = nil
        } catch {
            ledgers = []
            loadError = "加载失败：\(error.localizedDescription)"
        }
    }
}
