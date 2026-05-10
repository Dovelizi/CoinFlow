//  RecordChangeNotifier.swift
//  CoinFlow · M3.2
//
//  本地 record 表变更通知。Repository 在 insert/update/delete 后 broadcast，
//  ViewModel 监听后从 Repository 重新 list（不传具体 Record 内容，避免泄露 Decimal/Date 等）。
//
//  设计：
//  - 简单 NotificationCenter，避免引入 Combine PassthroughSubject 的全局生命周期
//  - VM 在 init 订阅，deinit 退订，由 SwiftUI 生命周期管理
//  - 多 VM 监听同一通知 OK

import Foundation

extension Notification.Name {
    /// record 表的任意变更（insert / update / delete）。
    /// userInfo: ["recordIds": [String]] 可选（批量）；不强求精准，VM 收到通知就 reload。
    static let recordsDidChange = Notification.Name("CoinFlow.recordsDidChange")
}

enum RecordChangeNotifier {
    static func broadcast(recordIds: [String] = []) {
        NotificationCenter.default.post(
            name: .recordsDidChange,
            object: nil,
            userInfo: recordIds.isEmpty ? nil : ["recordIds": recordIds]
        )
    }
}
