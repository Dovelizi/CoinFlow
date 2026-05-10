//  CategoryIconLibraryTests.swift
//  CoinFlow · 图标库存在性回归
//
//  目的：CategoryIconLibrary 每个 systemName 必须能 UIImage(systemName:) 加载
//        否则 SwiftUI Image(systemName:) 渲染时会报 console warning 并显示空白。
//  这条 test 在加新图标时充当 trip wire——加错名直接红屏。

import XCTest
import UIKit
@testable import CoinFlow

final class CategoryIconLibraryTests: XCTestCase {

    func test_all_icons_exist_in_system_symbol_set() {
        var missing: [String] = []
        for icon in CategoryIconLibrary.allIcons {
            if UIImage(systemName: icon.systemName) == nil {
                missing.append(icon.systemName)
            }
        }
        XCTAssertTrue(missing.isEmpty, """
            发现 \(missing.count) 个不存在的 SF Symbol：
            \(missing.map { "  - \($0)" }.joined(separator: "\n"))
            """)
    }

    func test_preset_upgrades_exist_in_system_symbol_set() {
        var missing: [String] = []
        for (presetId, name) in CategoryIconLibrary.presetIconUpgrades {
            if UIImage(systemName: name) == nil {
                missing.append("\(presetId) → \(name)")
            }
        }
        XCTAssertTrue(missing.isEmpty, """
            preset upgrade 表里有不存在的 SF Symbol：
            \(missing.map { "  - \($0)" }.joined(separator: "\n"))
            """)
    }

    func test_default_icon_name_exists() {
        XCTAssertNotNil(UIImage(systemName: CategoryIconLibrary.defaultIconName))
    }

    func test_all_groups_nonempty() {
        for g in CategoryIconLibrary.groups {
            XCTAssertFalse(g.icons.isEmpty, "组「\(g.title)」不能为空")
        }
    }

    func test_search_chinese_alias_hits() {
        // 中文别名搜索：搜"咖啡"必须命中至少一个
        let hits = CategoryIconLibrary.search("咖啡")
        XCTAssertNotNil(hits)
        XCTAssertFalse(hits?.isEmpty ?? true)
    }

    func test_search_empty_returns_nil() {
        XCTAssertNil(CategoryIconLibrary.search(""))
        XCTAssertNil(CategoryIconLibrary.search("   "))
    }

    func test_search_unknown_returns_empty_not_nil() {
        XCTAssertEqual(CategoryIconLibrary.search("zzz_no_such_thing")?.isEmpty, true)
    }
}
