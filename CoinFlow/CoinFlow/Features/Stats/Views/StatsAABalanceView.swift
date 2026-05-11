//  StatsAABalanceView.swift
//  CoinFlow · V2 Stats · AA 账本结算
//
//  设计基线：design/screens/05-stats/aa-balance-light.png（实际图是 main 命名错位）+ Preview 实现
//  - 顶部"我应付/我应收"hero（红 / 绿大数字）
//  - 总开支/应分摊/已支付三栏
//  - 结算明细列表（成员头像 + 角色 + 应收/应付）
//  - 消费时间轴（垂直线 + 圆点节点 + 单条事件）
//
//  数据：扫描 record.payerUserId / participants / ledgerType=ledger 来识别 AA 账本。
//        当前 M1-M7 主线 Ledger 仅支持 personal，AA 字段虽建表但无 UI 入口写入。
//        所以本视图统一显示"暂无 AA 账本"占位 + V2 banner，避免假数据误导用户。

import SwiftUI

struct StatsAABalanceView: View {
    @StateObject private var vm = StatsViewModel()
    @Environment(\.colorScheme) private var scheme
    @State private var showAddMember = false

    /// 是否存在任何带 participants 的 record（AA 入口已经被使用过）。
    private var hasAARecords: Bool {
        vm.allRecords.contains(where: {
            ($0.participants?.count ?? 0) > 0
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            StatsSubNavBar(title: "AA 账本",
                           subtitle: hasAARecords ? "本月共享账单" : "等待启用",
                           trailingIcon: "person.badge.plus",
                           trailingAction: { showAddMember = true },
                           trailingAccessibility: "添加 AA 成员")
            ScrollView {
                VStack(spacing: NotionTheme.space7) {
                    v2Banner
                    if hasAARecords {
                        aaContent
                    } else {
                        emptyContent
                    }
                }
                .padding(.horizontal, NotionTheme.space5)
                .padding(.top, NotionTheme.space6)
                .padding(.bottom, NotionTheme.space9)
            }
        }
        .background(ThemedBackgroundLayer(kind: .stats))
        .navigationBarHidden(true)
        .onAppear { vm.reload() }
        .sheet(isPresented: $showAddMember) {
            AAMemberAddSheet()
        }
    }

    private var v2Banner: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.accentPurple)
            VStack(alignment: .leading, spacing: 2) {
                Text("AA 账本（多人共享）正在路上")
                    .font(.custom("PingFangSC-Semibold", size: 12))
                    .foregroundStyle(Color.inkPrimary)
                Text("V2 将开放：创建 AA 账本 / 添加成员 / 自动结算")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                .fill(Color.accentPurple.opacity(0.12))
        )
    }

    private var emptyContent: some View {
        StatsEmptyState(title: "还没有 AA 账本记录",
                        subtitle: "V2 上线后，您可以为旅游 / 聚餐等场景创建多人共享账本，自动计算每人应分摊金额")
            .frame(height: 320)
    }

    private var aaContent: some View {
        // hasAARecords 路径仅做最简骨架，等待 V2 真实数据流；不构造伪数据
        VStack(spacing: NotionTheme.space5) {
            let aaRecords = vm.allRecords.filter { ($0.participants?.count ?? 0) > 0 }
            let total = aaRecords.map(\.amount).reduce(Decimal(0), +)
            VStack(spacing: 4) {
                Text("总开支")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
                Text("¥" + StatsFormat.intGrouped(total))
                    .font(.system(size: 38, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(NotionColor.purple.text(scheme))
                Text("\(aaRecords.count) 笔 · 等待 V2 结算引擎")
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(NotionTheme.space5)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusCard)
                    .fill(Color.hoverBg.opacity(0.5))
            )
        }
    }
}

// MARK: - 添加 AA 成员 Sheet
//
// 当前阶段（M1-M7）AA 账本字段虽建表但无完整数据流，无法真正"添加成员"并落库。
// "简洁优先"：sheet 内只做"V2 内测预约"占位 + 演示性输入框，避免假数据/假交互。
// 用户填了昵称会被保存到 UserDefaults 作为下次默认值，等 V2 上线时无缝迁移。

private struct AAMemberAddSheet: View {
    @AppStorage("aa.preview.nicknames") private var nicknames: String = ""
    @State private var input: String = ""
    @Environment(\.dismiss) private var dismiss

    private var savedList: [String] {
        nicknames
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.accentBlue)
                        Text("AA 账本将在 V2 开放：创建账本 / 邀请成员 / 自动结算。先收集您的常用 AA 伙伴，V2 上线后会自动同步。")
                            .font(NotionFont.small())
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("V2 即将上线")
                }

                Section("添加常用 AA 伙伴") {
                    HStack {
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundStyle(Color.inkTertiary)
                        TextField("输入昵称", text: $input)
                            .submitLabel(.done)
                            .onSubmit { addNickname() }
                        Button {
                            addNickname()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(input.trimmingCharacters(in: .whitespaces).isEmpty
                                                 ? Color.inkTertiary
                                                 : Color.accentBlue)
                        }
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if !savedList.isEmpty {
                    Section("已添加（\(savedList.count) 人）") {
                        ForEach(savedList, id: \.self) { name in
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(Color.accentPurple)
                                Text(name)
                                Spacer()
                                Button {
                                    remove(name)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(Color.inkTertiary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("AA 成员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func addNickname() {
        let name = input.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var arr = savedList
        guard !arr.contains(name) else {
            input = ""
            return
        }
        arr.append(name)
        nicknames = arr.joined(separator: ",")
        input = ""
    }

    private func remove(_ name: String) {
        let arr = savedList.filter { $0 != name }
        nicknames = arr.joined(separator: ",")
    }
}
