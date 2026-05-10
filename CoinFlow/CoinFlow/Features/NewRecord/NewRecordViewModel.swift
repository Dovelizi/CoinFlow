//  NewRecordViewModel.swift
//  CoinFlow · M3.2 · §5.5.10
//
//  新建流水 VM：
//  - 6 字段：amount / direction / category / occurredAt / ledger / note
//  - 「保存」按钮可用性：amount > 0 且分类已选
//  - 确认后写本地 Repository（sync_status=pending），自动入同步队列

import Foundation
import SwiftUI
import UIKit

@MainActor
final class NewRecordViewModel: ObservableObject {

    // MARK: - Published

    @Published var amountText: String = ""
    @Published var direction: CategoryKind = .expense
    @Published var selectedCategory: Category?
    @Published var occurredAt: Date = Date()
    @Published var note: String = ""

    @Published private(set) var saveError: String?
    @Published private(set) var isSaving: Bool = false

    /// 用户至少点击过一次"保存"按钮后置 true。
    /// 用于触发金额为空时的"请输入金额"红字 + 红框（设计稿 error-light.png 行为）。
    @Published private(set) var attemptedSave: Bool = false

    /// 当前方向下的可选分类（带预设和用户自定义）
    @Published private(set) var availableCategories: [Category] = []

    // MARK: - State

    let ledgerId: String

    init(ledgerId: String = DefaultSeeder.defaultLedgerId) {
        self.ledgerId = ledgerId
        loadCategories()
    }

    // MARK: - Direction toggle

    func setDirection(_ k: CategoryKind) {
        direction = k
        loadCategories()
        // 切换方向时如果当前分类不属于新方向，自动清空让用户重选
        if let sel = selectedCategory, sel.kind != k {
            selectedCategory = nil
        }
    }

    // MARK: - Categories

    private func loadCategories() {
        do {
            availableCategories = try SQLiteCategoryRepository.shared
                .list(kind: direction, includeDeleted: false)
            // 默认选中第一个（如果尚未选择）
            if selectedCategory == nil {
                selectedCategory = availableCategories.first
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Validation

    var parsedAmount: Decimal? {
        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let d = Decimal(string: trimmed), d > 0 else { return nil }
        // M7-Fix13：金额上限 1 亿（避免 LLM / OCR 误判天价账单）
        guard d <= 100_000_000 else { return nil }
        return d
    }

    var canSave: Bool {
        parsedAmount != nil && selectedCategory != nil && !isSaving
    }

    var amountValidationMessage: String? {
        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            // 用户尚未尝试保存时不提示；点过保存后空态需提示"请输入金额"
            return attemptedSave ? "请输入金额" : nil
        }
        if Decimal(string: trimmed) == nil { return "金额格式不正确" }
        if let d = Decimal(string: trimmed), d <= 0 { return "金额必须大于 0" }
        if let d = Decimal(string: trimmed), d > 100_000_000 { return "金额超过上限（1 亿）" }
        return nil
    }

    /// 是否处于金额错误展示态（驱动红 stroke + 红字）
    var isAmountInError: Bool {
        attemptedSave && amountValidationMessage != nil
    }

    /// M7-Fix14：金额输入失焦时标记 attemptedSave，使得校验态立即生效
    func markAmountAttempted() {
        attemptedSave = true
    }

    // MARK: - Save

    /// 保存。成功返回新建 Record；失败时 saveError 会被设置并返回 nil。
    /// - Parameter source: 默认 `.manual`；OCR 路径覆盖为 `.ocrVision/.ocrAPI/.ocrLLM`
    /// - Parameter ocrConfidence: OCR 路径的置信度（0~1），仅 source != .manual 时填
    /// - Parameter attachmentImage: M9-Fix4 OCR 截图（CaptureConfirmView 用户开启「保留附件」时传入）
    ///   保存到 Caches 后路径写入 record.attachmentLocalPath，SyncQueue 上传飞书
    /// - Parameter merchantChannel: M9-Fix5 支付渠道（微信/支付宝/抖音/银行/其他），OCR 路径填，手动为 nil
    func save(source: RecordSource = .manual,
              ocrConfidence: Double? = nil,
              attachmentImage: UIImage? = nil,
              merchantChannel: String? = nil) async -> Record? {
        attemptedSave = true
        guard let amount = parsedAmount,
              let category = selectedCategory else {
            saveError = "请填写完整的金额与分类"
            return nil
        }
        isSaving = true
        defer { isSaving = false }

        let now = Date()
        let recordId = UUID().uuidString

        // M9-Fix4：先尝试落盘截图（失败不阻塞保存，仅日志）
        var attachmentPath: String? = nil
        if let img = attachmentImage {
            do {
                attachmentPath = try ScreenshotStore.save(image: img, recordId: recordId)
            } catch {
                NSLog("[CoinFlow] save attachment failed: \(error.localizedDescription)")
            }
        }

        let record = Record(
            id: recordId,
            ledgerId: ledgerId,
            categoryId: category.id,
            amount: amount,
            currency: "CNY",
            occurredAt: occurredAt,
            timezone: TimeZone.current.identifier,
            note: note.isEmpty ? nil : note,
            payerUserId: nil,
            participants: nil,
            source: source,
            ocrConfidence: ocrConfidence,
            voiceSessionId: nil,
            missingFields: nil,
            merchantChannel: merchantChannel,
            syncStatus: .pending,
            remoteId: nil,
            lastSyncError: nil,
            syncAttempts: 0,
            attachmentLocalPath: attachmentPath,
            attachmentRemoteToken: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )

        do {
            try SQLiteRecordRepository.shared.insert(record)
            saveError = nil
            // 触发一次 sync tick + 启动 listener（不阻塞 UI 关闭）
            SyncTrigger.fire(reason: "newRecord.save")
            return record
        } catch {
            saveError = error.localizedDescription
            return nil
        }
    }
}
