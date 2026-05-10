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
                           trailingIcon: "person.badge.plus")
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
