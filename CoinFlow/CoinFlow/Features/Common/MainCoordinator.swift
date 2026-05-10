//  MainCoordinator.swift
//  CoinFlow · M7 · [G2] 全局入口链路
//
//  职责：在不同 tab 之间传递「用户想发起某个入口动作」的意图。
//  典型场景：
//    - HomeMainView 点击截图记账卡 → 切 records tab → RecordsListView 消费 pendingAction 自动弹 PhotosPicker
//    - HomeMainView 点击语音记账卡 → 切 records tab → RecordsListView 自动弹录音 sheet
//    - HomeMainView 长按截图卡 → ActionSheet 选「从相册选择」→ 同上路径
//
//  设计原则：
//  - ObservableObject 但仅一个 pendingAction @Published；消费方消费即清空
//  - 不做业务逻辑，只做意图传递；所有逻辑仍在 HomeMainView / RecordsListView 内部

import Foundation
import SwiftUI

/// 从 Home 等其他页面发来的意图，由 RecordsListView 在 onAppear / onChange 时消费
enum MainAction: Equatable {
    /// 触发截图识别（PhotosPicker）
    case photoPicker
    /// 触发语音记账（录音 sheet）
    case voiceRecord
    /// 触发手动新建
    case newManualRecord
}

@MainActor
final class MainCoordinator: ObservableObject {
    /// 待消费的动作。消费后立即置 nil。
    @Published var pendingAction: MainAction?

    /// 发起截图识别：HomeMainView 点击「截图记账」卡或 ActionSheet「从相册选择」
    func triggerPhotoPicker() {
        pendingAction = .photoPicker
    }

    /// 发起语音记账：HomeMainView 点击「语音记账」卡
    func triggerVoiceRecording() {
        pendingAction = .voiceRecord
    }

    /// 发起手动新建
    func triggerNewRecord() {
        pendingAction = .newManualRecord
    }

    /// 消费方调用；只在当前 action 匹配时 clear，避免并发覆盖
    func consume(_ action: MainAction) {
        if pendingAction == action { pendingAction = nil }
    }
}
