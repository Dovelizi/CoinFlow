//  RecordsLayout.swift
//  CoinFlow · M3.3
//
//  原 .stack 已废弃移除（实测视觉效果不佳）。仅保留 list / grid。

import SwiftUI

enum RecordsLayout: String, CaseIterable {
    case list, grid

    var iconName: String {
        switch self {
        case .list:  return "list.bullet"
        case .grid:  return "square.grid.2x2"
        }
    }
}
