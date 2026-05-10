//  RecordDetailViewModel.swift
//  CoinFlow · M3.3 · §5.5.9
//
//  详情/编辑 VM：
//  - 可编辑：金额 / 分类 / 备注（核心 3 项，§5.5.9 字段编辑约束）
//  - 不可编辑：发生时间 / 来源 / 同步状态 / 账本（只读元信息）
//  - 实时保存：失焦/选中分类即触发 commit；保存失败保持 sheet 打开

import Foundation
import SwiftUI

@MainActor
final class RecordDetailViewModel: ObservableObject {

    // MARK: - Published

    @Published var amountText: String
    @Published var note: String
    @Published var selectedCategory: Category?
    @Published private(set) var availableCategories: [Category] = []
    @Published private(set) var saveError: String?

    // MARK: - Immutable refs

    let original: Record

    // MARK: - Init

    init(record: Record) {
        self.original = record
        self.amountText = AmountFormatter.display(record.amount)
        self.note = record.note ?? ""
        loadCategoryAndDirection()
    }

    private func loadCategoryAndDirection() {
        // 拿当前分类
        if let cat = try? SQLiteCategoryRepository.shared.find(id: original.categoryId) {
            selectedCategory = cat
            // 加载同方向所有分类供切换
            if let cats = try? SQLiteCategoryRepository.shared
                .list(kind: cat.kind, includeDeleted: false) {
                availableCategories = cats
            }
        }
    }

    // MARK: - Computed

    var direction: CategoryKind { selectedCategory?.kind ?? .expense }

    var parsedAmount: Decimal? {
        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let d = Decimal(string: trimmed), d > 0 else { return nil }
        return d
    }

    /// 元信息只读展示
    var occurredAtDisplay: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: original.occurredAt)
    }

    var sourceDisplay: String {
        switch original.source {
        case .manual:      return "手动"
        case .ocrVision:   return "本地 OCR"
        case .ocrAPI:      return "OCR API"
        case .ocrLLM:      return "大模型 OCR"
        case .voiceLocal:  return "本地语音"
        case .voiceCloud:  return "云端语音"
        }
    }

    var syncDisplay: String {
        switch original.syncStatus {
        case .pending:  return "待同步"
        case .syncing:  return "同步中"
        case .synced:   return "已同步"
        case .failed:   return "同步失败"
        }
    }

    // MARK: - Commits

    /// 任意字段变更后触发；将组装新 Record 并 update。
    /// 任何编辑都重置 syncStatus = .pending（与 §5.5.9 实时保存机制对齐）。
    func commit() {
        guard let amount = parsedAmount,
              let cat = selectedCategory else {
            saveError = "金额或分类无效"
            return
        }
        var updated = original
        updated.amount = amount
        updated.categoryId = cat.id
        updated.note = note.isEmpty ? nil : note
        updated.syncStatus = .pending
        updated.syncAttempts = 0
        updated.lastSyncError = nil
        updated.updatedAt = Date()
        do {
            try SQLiteRecordRepository.shared.update(updated)
            saveError = nil
            SyncTrigger.fire(reason: "recordDetail.save")
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// 选择分类（包括跨方向？M3.3 仅同方向切换；跨方向需要先用「删除+重建」表达）
    func selectCategory(_ cat: Category) {
        selectedCategory = cat
        commit()
    }

    /// 删除。
    /// - Parameter localOnly:
    ///   - `false`（默认 · "都删除"）：软删 → `deleted_at = now` + `sync_status = pending`，
    ///     SyncQueue 会把"带 deletedAt 的 doc"推送到飞书，飞书行 `deleted=true` 达成云端清理。
    ///   - `true`（"仅删除本地"）：物理删除本地行，飞书不动。
    ///     ⚠️ 下次从飞书手动拉取时，该 id 会被重新 INSERT 回本地——用户自担。
    func delete(localOnly: Bool = false) {
        do {
            if localOnly {
                try SQLiteRecordRepository.shared.hardDelete(id: original.id)
                // 不触发 SyncTrigger：飞书那条保持原样
            } else {
                try SQLiteRecordRepository.shared.delete(id: original.id)
                SyncTrigger.fire(reason: "recordDetail.delete")
            }
        } catch {
            saveError = error.localizedDescription
        }
    }
}
