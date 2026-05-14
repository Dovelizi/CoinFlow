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

    /// M11 AA 分账：用户在新建流水页主动选择的受款 AA 账本（仅接受
    /// `aaStatus = .recording` 的账本。为 nil 时走个人账户（default-ledger）。
    @Published var selectedAALedger: Ledger?

    /// AA 流水的支付人（payer）—— 仅在选中 AA 账本时生效。
    /// - 默认 = "我"（`AAOwner.memberId(in: ledgerId)`）
    /// - 用户可在新建流水页切换为该账本下任一已有成员，或新增成员（输入昵称）
    /// - 保存时写入到 `Record.payerUserId`，供结算阶段反推"谁实际付了多少"
    @Published var selectedPayerMemberId: String?

    /// 当前 AA 账本下可选的 payer 列表（成员表的活动行，"我"必定在首位）
    @Published private(set) var availablePayers: [AAMember] = []

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
        // 若初始 ledgerId 直接就是一个 AA 账本（lockedLedgerId 路径，从 AA 详情页"+ 添加流水"进入），
        // 立即把它当作 selectedAALedger 装载，初始化 payer 列表和默认值（"我"）。
        if let l = try? SQLiteLedgerRepository.shared.find(id: ledgerId), l.type == .aa {
            self.selectedAALedger = l
            refreshPayersForCurrentAA()
        }
    }

    /// 当 selectedAALedger 切换或初始化时由 View 层显式调用，刷新 payer 候选列表 + 默认选中"我"。
    /// 若账本下还没有"我"这个成员，临时拼一条虚拟 "我"（id = me-<ledgerId>），保存时再真实落库。
    func refreshPayersForCurrentAA() {
        guard let l = selectedAALedger else {
            availablePayers = []
            selectedPayerMemberId = nil
            return
        }
        let myId = AAOwner.memberId(in: l.id)
        var members = (try? SQLiteAAMemberRepository.shared.list(ledgerId: l.id)) ?? []
        if !members.contains(where: { AAOwner.isOwnerMember($0) }) {
            let now = Date()
            members.insert(AAMember(
                id: myId, ledgerId: l.id, name: "我", avatarEmoji: "🙋",
                status: .pending, paidAt: nil, sortOrder: 0,
                createdAt: now, updatedAt: now, deletedAt: nil
            ), at: 0)
        }
        availablePayers = members
        selectedPayerMemberId = myId
    }

    /// 用户在新建流水页输入新成员昵称作为 payer。立即把该成员落库（aa_member），
    /// 并把 `selectedPayerMemberId` 指向它。同名（活动行）则复用，不重复创建。
    /// - Returns: 新成员或复用成员的 id；昵称非法时返回 nil
    @discardableResult
    func addNewPayer(name rawName: String) -> String? {
        guard let l = selectedAALedger else { return nil }
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 20 else { return nil }
        let existing = (try? SQLiteAAMemberRepository.shared.list(ledgerId: l.id)) ?? []
        if let same = existing.first(where: { $0.name == trimmed && $0.deletedAt == nil }) {
            selectedPayerMemberId = same.id
            availablePayers = existing
            return same.id
        }
        let now = Date()
        let m = AAMember(
            id: UUID().uuidString,
            ledgerId: l.id,
            name: trimmed,
            avatarEmoji: nil,
            status: .pending,
            paidAt: nil,
            sortOrder: existing.count,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        do {
            try SQLiteAAMemberRepository.shared.insert(m)
            // 重新读一遍以拿到最新顺序
            let refreshed = try SQLiteAAMemberRepository.shared.list(ledgerId: l.id)
            availablePayers = refreshed
            selectedPayerMemberId = m.id
            return m.id
        } catch {
            saveError = error.localizedDescription
            return nil
        }
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
    /// 记录原因 + 时间戳，View 层据此显示红字 + 彩蛋 toast。
    /// 用户偏好：点击交互不需要震动。
    func handleClamp(_ reason: AmountClampReason) {
        amountClampReason = reason
        amountClampedAt = Date()
        Haptics.tap()
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

        // M11 AA 分账：选中 AA 账本时覆盖 ledgerId 与 payerUserId。
        // payerUserId 写入 AAMember.id：默认是 me-<ledgerId>（"我"在该账本下的成员 id），
        // 用户可在 UI 上切换为账本下其他成员，或新增成员（输入昵称即时落库）。
        let resolvedLedgerId: String = selectedAALedger?.id ?? self.ledgerId
        var resolvedPayerUserId: String? = nil
        if let aa = selectedAALedger {
            let myId = AAOwner.memberId(in: aa.id)
            let pid = selectedPayerMemberId ?? myId
            // 若 payer = "我" 但"我"还没作为成员落库，先补一条 me-<ledgerId>，保证
            // payerUserId 永远是一条真实存在的 aa_member.id（结算阶段反推成员靠它）。
            if pid == myId {
                let existing = (try? SQLiteAAMemberRepository.shared.list(ledgerId: aa.id)) ?? []
                if !existing.contains(where: { AAOwner.isOwnerMember($0) }) {
                    let me = AAMember(
                        id: myId, ledgerId: aa.id, name: "我", avatarEmoji: "🙋",
                        status: .pending, paidAt: nil, sortOrder: 0,
                        createdAt: now, updatedAt: now, deletedAt: nil
                    )
                    try? SQLiteAAMemberRepository.shared.insert(me)
                }
            }
            resolvedPayerUserId = pid
        }

        let record = Record(
            id: recordId,
            ledgerId: resolvedLedgerId,
            categoryId: category.id,
            amount: amount,
            currency: "CNY",
            occurredAt: occurredAt,
            timezone: TimeZone.current.identifier,
            note: note.isEmpty ? nil : note,
            payerUserId: resolvedPayerUserId,
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
            aaSettlementId: nil,
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
