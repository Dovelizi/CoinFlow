//  DefaultSeeder.swift
//  CoinFlow · M3.1
//
//  首次启动播种：
//  - 1 个默认账本「我的账本」（personal / 本地时区）
//  - 14 个预设分类（§10.4）：
//    * 支出 8 个：餐饮 / 交通 / 购物 / 居住 / 娱乐 / 医疗 / 教育 / 其他
//    * 收入 6 个：工资 / 奖金 / 转账 / 退款 / 理财 / 其他
//  - 所有预设分类 `is_preset = true`（不可删）
//
//  幂等：
//  - 默认账本 id 固定 `"default-ledger"`；已存在则跳过
//  - 每个预设分类 id 按命名规则 `preset-<kind>-<slug>` 固定；已存在则跳过
//
//  本 seeder 不做 schema 升级；用户后续自定义的分类不会被重置。

import Foundation

enum DefaultSeeder {

    /// 默认账本的固定 id。所有「未指定账本」的流水都归属于此。
    static let defaultLedgerId = "default-ledger"

    struct PresetCategory {
        let id: String
        let name: String
        let kind: CategoryKind
        let icon: String
        let colorHex: String
        let sortOrder: Int
    }

    static let presets: [PresetCategory] = [
        // 支出（sortOrder 1..8）
        .init(id: "preset-expense-food",      name: "餐饮", kind: .expense,
              icon: "fork.knife",             colorHex: "#FF9500", sortOrder: 1),
        .init(id: "preset-expense-transit",   name: "交通", kind: .expense,
              icon: "car.fill",               colorHex: "#007AFF", sortOrder: 2),
        .init(id: "preset-expense-shopping",  name: "购物", kind: .expense,
              icon: "bag.fill",               colorHex: "#FF2D55", sortOrder: 3),
        .init(id: "preset-expense-housing",   name: "居住", kind: .expense,
              icon: "house.fill",             colorHex: "#34C759", sortOrder: 4),
        .init(id: "preset-expense-fun",       name: "娱乐", kind: .expense,
              icon: "gamecontroller.fill",    colorHex: "#AF52DE", sortOrder: 5),
        .init(id: "preset-expense-medical",   name: "医疗", kind: .expense,
              icon: "cross.case.fill",        colorHex: "#FF3B30", sortOrder: 6),
        .init(id: "preset-expense-edu",       name: "教育", kind: .expense,
              icon: "book.fill",              colorHex: "#5856D6", sortOrder: 7),
        .init(id: "preset-expense-other",     name: "其他", kind: .expense,
              icon: "ellipsis.circle",        colorHex: "#8E8E93", sortOrder: 99),
        // 收入（sortOrder 1..6）
        .init(id: "preset-income-salary",     name: "工资", kind: .income,
              icon: "dollarsign.circle.fill", colorHex: "#34C759", sortOrder: 1),
        .init(id: "preset-income-bonus",      name: "奖金", kind: .income,
              icon: "gift.fill",              colorHex: "#FF9500", sortOrder: 2),
        .init(id: "preset-income-transfer",   name: "转账", kind: .income,
              icon: "arrow.left.arrow.right", colorHex: "#007AFF", sortOrder: 3),
        .init(id: "preset-income-refund",     name: "退款", kind: .income,
              icon: "arrow.uturn.backward",   colorHex: "#AF52DE", sortOrder: 4),
        .init(id: "preset-income-invest",     name: "理财", kind: .income,
              icon: "chart.line.uptrend.xyaxis", colorHex: "#5856D6", sortOrder: 5),
        .init(id: "preset-income-other",      name: "其他", kind: .income,
              icon: "ellipsis.circle",        colorHex: "#8E8E93", sortOrder: 99)
    ]

    /// 执行一次播种。幂等：重复调用只补齐缺失项，不覆盖用户数据。
    @discardableResult
    static func seedIfNeeded() throws -> SeedResult {
        var result = SeedResult(ledgerCreated: false, categoriesAdded: 0)

        // 1. 默认账本
        let ledgerRepo = SQLiteLedgerRepository.shared
        if try ledgerRepo.find(id: defaultLedgerId) == nil {
            let ledger = Ledger(
                id: defaultLedgerId,
                name: "我的账本",
                type: .personal,
                firestorePath: nil,
                createdAt: Date(),
                timezone: TimeZone.current.identifier,
                archivedAt: nil,
                deletedAt: nil
            )
            try ledgerRepo.insert(ledger)
            result.ledgerCreated = true
        }

        // 2. 预设分类
        let catRepo = SQLiteCategoryRepository.shared
        for p in presets {
            if try catRepo.find(id: p.id) == nil {
                let cat = Category(
                    id: p.id,
                    name: p.name,
                    kind: p.kind,
                    icon: p.icon,
                    colorHex: p.colorHex,
                    parentId: nil,
                    sortOrder: p.sortOrder,
                    isPreset: true,
                    deletedAt: nil
                )
                try catRepo.insert(cat)
                result.categoriesAdded += 1
            }
        }
        return result
    }

    struct SeedResult {
        var ledgerCreated: Bool
        var categoriesAdded: Int
    }
}
