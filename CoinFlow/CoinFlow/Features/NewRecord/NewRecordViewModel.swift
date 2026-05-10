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

    /// 业务硬上限：1 亿（避免 LLM / OCR 误判天价账单 + 防止误输入）。
    /// 实际校验逻辑统一在 `AmountInputGate`；这里仅保留向后兼容引用。
    static let amountHardLimit: Decimal = AmountInputGate.hardLimit

    // MARK: - Published

    /// 金额输入框文本（**只读绑定**用 `$vm.amountText`，写入必须走 `applyAmountInput(_:)`）。
    ///
    /// 设计：所有写入经 `AmountInputGate.evaluate` 统一校验（与 RecordDetail/
    /// VoiceWizard/CaptureConfirm 共用同一份规则）。SwiftUI `TextField` 路径下
    /// `@Published.didSet` 不可靠，故 View 层用自定义 Binding 调用 applyAmountInput。
    @Published var amountText: String = ""

    /// 拦截原因别名（内部仍用 `AmountClampReason`，对外类型来自 Gate）
    typealias AmountClampReason = AmountInputGate.ClampReason

    /// 最近一次拦截原因，与 `amountClampedAt` 同步刷新。UI 据此分流文案。
    @Published private(set) var amountClampReason: AmountClampReason?

    /// 最近一次拦截时间戳；UI 通过 `amountClampedHintVisible` 判断是否显示提示
    @Published private(set) var amountClampedAt: Date?

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
        // 业务上限 1 亿（amountText.didSet 已实时拦截超额输入；此处兜底校验）
        guard d <= Self.amountHardLimit else { return nil }
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
        // didSet 已实时截断，正常用户不会触发此分支；
        // 仅当外部代码（OCR/LLM 自动填充）绕过 didSet 写超额值时才作为兜底提示
        if let d = Decimal(string: trimmed), d > Self.amountHardLimit { return "金额超过上限（1 亿）" }
        return nil
    }

    /// "已达上限"轻提示是否当前可见。拦截后保留 2 秒。
    /// view 层可监听 `amountClampedAt` 做动画进出。
    var amountClampedHintVisible: Bool {
        guard let t = amountClampedAt else { return false }
        return Date().timeIntervalSince(t) < 2.0
    }

    /// 是否处于金额错误展示态（驱动红 stroke + 红字）
    var isAmountInError: Bool {
        attemptedSave && amountValidationMessage != nil
    }

    /// M7-Fix14：金额输入失焦时标记 attemptedSave，使得校验态立即生效
    func markAmountAttempted() {
        attemptedSave = true
    }

    // MARK: - Amount input gate（统一调用 AmountInputGate）
    //
    // 所有写入 amountText 的代码都必须经此函数。规则定义见 AmountInputGate.swift，
    // 与 RecordDetailViewModel / VoiceWizardStepView / CaptureConfirmView 共用同一份。

    /// View 层金额写入入口（SwiftUI Binding 路径用）。
    /// **注意**：UIKit AmountTextFieldUIKit 已经在 UITextFieldDelegate 层硬拦截，
    /// 接受时通过 editingChanged 直接写 amountText（不经此函数），拒绝时调
    /// `handleClamp(_:)`。此函数仅在 OCR 自动填充等"非用户键入"路径使用。
    @discardableResult
    func applyAmountInput(_ raw: String) -> Bool {
        switch AmountInputGate.evaluate(raw) {
        case .accept(let cleaned):
            if amountText != cleaned { amountText = cleaned }
            return true
        case .reject(let reason):
            handleClamp(reason)
            return false
        }
    }

    /// UIKit 层硬拦截后的反馈入口（公开供 AmountTextFieldUIKit 调用）。
    /// 记录原因 + 时间戳 + 轻震动，View 层据此显示红字 + 彩蛋 toast。
    func handleClamp(_ reason: AmountClampReason) {
        amountClampReason = reason
        amountClampedAt = Date()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
