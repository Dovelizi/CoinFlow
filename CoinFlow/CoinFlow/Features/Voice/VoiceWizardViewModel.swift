//  VoiceWizardViewModel.swift
//  CoinFlow · M5 · §7.5.5 逐笔向导状态机
//
//  状态：idle → recording → asr → parsing → wizard → summary
//  失败分支：permissionDenied / asrFailed / parseFailed → manual（兜底 1 笔空白）
//
//  设计：单 VM 管理整个语音会话的生命周期（一次录音 = 一个 VM 实例）；
//  UI 层 VoiceWizardContainerView 按 state 切换子视图；
//  voice_session 在进入 asr 阶段首次 INSERT，每个状态切换 UPDATE。

import Foundation
import SwiftUI
import Speech

@MainActor
final class VoiceWizardViewModel: ObservableObject {

    // MARK: - State

    enum Phase: Equatable {
        case idle
        case recording
        case asr                          // 录音完成，转写中
        case parsing                      // 转写完成，LLM 解析中
        case wizard                       // 逐笔向导（观察 currentIndex / bills）
        case summary                      // 汇总：N 笔确认 / M 笔放弃
        case manual                       // 兜底：解析全失败，单笔手动输入
        case failed(String)               // 权限/底层失败
    }

    // MARK: - Published

    @Published private(set) var phase: Phase = .idle

    @Published private(set) var bills: [ParsedBill] = []
    @Published var currentIndex: Int = 0

    /// 当前笔的编辑态（Published 以驱动表单 two-way 绑定）
    @Published var currentBill: ParsedBill = .empty(required: ["amount","occurred_at","direction"])

    // M7 修复问题 4：旧的 confirmedBills/skippedBills 数组改由 ids + bills 派生
    // （见下方 confirmedIds/skippedIds + confirmedBillsDerived/skippedBillsDerived）

    @Published private(set) var asrText: String = ""
    @Published private(set) var asrConfidence: Double = 0
    @Published private(set) var usedEngine: ASREngine = .speechLocal

    @Published private(set) var sessionId: String = UUID().uuidString

    /// M11+：本次语音会话目标账本。nil = 个人账户（默认）；非 nil = AA 账本，
    /// 该会话所有 confirmed bills 入库时统一使用该 ledger.id。
    /// VoiceWizardStepView 顶部"账本"行点击弹 AALedgerPickerSheet 修改此值。
    @Published var selectedAALedger: Ledger?

    // MARK: - Deps

    private let audioRecorder = AudioRecorder()
    private let router = ASRRouter.shared
    private let parser = BillsLLMParser()
    private let repo = SQLiteVoiceSessionRepository.shared
    private let recordRepo = SQLiteRecordRepository.shared

    /// 必填字段：M6 起读 user_settings(`voice.required_fields`)；缺省回退到 amount/occurred_at/direction
    var requiredFields: [String] {
        let stored: [String]? = SQLiteUserSettingsRepository.shared
            .getJSON(key: SettingsKey.voiceRequiredFields, as: [String].self)
        return stored ?? ["amount", "occurred_at", "direction"]
    }

    /// 分类白名单。Key = `"{kind}|{name}"`（如 `"expense|餐饮"`）避免 expense/income
    /// 同名分类冲突；另外维护 `nameToExpense` / `nameToIncome` 供按方向查找。
    private(set) var categoryByKindAndName: [String: Category] = [:]

    /// 返回所有分类名（去重；用于 parser 的 allowedCategories 词典匹配）。
    func allowedCategoryNames() -> [String] {
        var set = Set<String>()
        for c in categoryByKindAndName.values { set.insert(c.name) }
        return Array(set)
    }

    /// 根据方向 + 名字找到具体 Category（confirmCurrent 入库时用）。
    func resolveCategory(direction: BillDirection, name: String) -> Category? {
        let kind: CategoryKind = direction == .expense ? .expense : .income
        return categoryByKindAndName["\(kind.rawValue)|\(name)"]
    }

    // MARK: - Public: wiring

    /// 暴露 AudioRecorder 供 UI 直接读 level/isRecording（@ObservedObject 透传）
    var recorder: AudioRecorder { audioRecorder }

    /// M7-Fix5：用户松开早于 startRecording 完成时置 true；startRecording 结束会看到此标志立即转入停止
    private var pendingStopRequested: Bool = false
    /// 取消请求：用户松开早于 startRecording 完成 + 已左滑取消 → startRecording 完成后直接 cancel
    private var pendingCancelRequested: Bool = false

    // MARK: - Start / Stop

    /// 请求权限 + 开启录音。失败时 phase = .failed(reason)
    func startRecording() async {
        pendingStopRequested = false
        pendingCancelRequested = false
        // 1. 麦克风权限
        let micOK = await AudioRecorder.requestMicrophonePermission()
        guard micOK else {
            phase = .failed("麦克风权限被拒绝，请在 设置 → CoinFlow 中开启")
            return
        }
        // 2. Speech 权限
        let speechStatus = await LocalASRBackend.requestAuthorization()
        guard speechStatus == .authorized else {
            phase = .failed("语音识别权限被拒绝，请在 设置 → CoinFlow 中开启")
            return
        }
        // 3. 准备分类白名单（支出 + 收入）
        loadCategoryWhitelist()
        // 4. 重置状态
        sessionId = UUID().uuidString
        bills = []
        confirmedIds = []
        skippedIds = []
        currentIndex = 0
        asrText = ""
        asrConfidence = 0
        // 5. 开录
        do {
            try audioRecorder.start()
            phase = .recording
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        // M7-Fix5：如果用户在权限/启动过程中已松开（pendingStop/Cancel），立刻响应
        if pendingCancelRequested {
            pendingCancelRequested = false
            pendingStopRequested = false
            cancelRecording()
            return
        }
        if pendingStopRequested {
            pendingStopRequested = false
            await stopRecordingAndProcess()
            return
        }
    }

    /// 用户松手结束录音。触发 ASR → LLM → 进入向导。
    func stopRecordingAndProcess() async {
        // M7-Fix5：如果 startRecording 还没完成（phase 仍是 idle），标记 pending
        // 等 startRecording 完成后会自动调用 stopRecordingAndProcess
        if phase == .idle {
            pendingStopRequested = true
            return
        }
        guard phase == .recording else { return }
        let stopResult: (url: URL, duration: TimeInterval)
        do {
            stopResult = try audioRecorder.stop()
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        // 1. INSERT voice_session（recording → asr_done 的过渡）
        let startedAt = audioRecorder.startedAt ?? Date()
        var session = VoiceSession(
            id: sessionId,
            startedAt: startedAt,
            durationSec: stopResult.duration,
            audioPath: stopResult.url.path,
            asrEngine: .speechLocal,        // 暂定，transcribe 之后回填
            asrText: "",
            asrConfidence: nil,
            parserEngine: nil,
            parserRawJSON: nil,
            parsedCount: 0,
            confirmedCount: 0,
            status: .recording,
            error: nil,
            createdAt: Date()
        )
        try? repo.insert(session)

        // 2. ASR
        phase = .asr
        let routed: ASRRouter.RouteResult
        do {
            routed = try await router.transcribe(audioURL: stopResult.url)
        } catch {
            session.status = .cancelled
            session.error = error.localizedDescription
            try? repo.update(session)
            audioRecorder.cleanup()
            phase = .failed(error.localizedDescription)
            return
        }
        asrText = routed.text
        asrConfidence = routed.confidence
        usedEngine = routed.usedEngine
        session.asrEngine = routed.usedEngine
        session.asrText = routed.text
        session.asrConfidence = routed.confidence
        session.status = .asrDone
        try? repo.update(session)
        // 识别完立即删音频（§7.5.2）
        audioRecorder.cleanup()

        // 3. LLM 解析（LLM 优先，失败自动降级规则）
        phase = .parsing
        let allowed = allowedCategoryNames()
        let parseResult = await parser.parse(
            asrText: routed.text,
            allowedCategories: allowed,
            requiredFields: requiredFields
        )
        let parsed = parseResult.bills
        // M7-Fix12：空账单 = LLM 判定"非账单 / 无金额"或规则引擎未提取出金额
        // → 跳过 wizard，直接进入 failed 态提示用户重试
        guard let firstBill = parsed.first else {
            session.parserEngine = parseResult.engine
            session.parserRawJSON = parseResult.rawJSON
            session.status = .parsed
            try? repo.update(session)
            let hint = routed.text.isEmpty
                ? "未识别到语音内容，请重试"
                : "未识别到账单信息，请重试"
            phase = .failed(hint)
            return
        }
        self.bills = parsed
        self.currentIndex = 0
        self.currentBill = firstBill
        session.parserEngine = parseResult.engine
        session.parsedCount = parsed.count
        session.status = .parsed
        // 审计 JSON：LLM 路径存 LLM 原始 JSON；规则路径存 Swift 侧摘要（M5 沿用）
        if let llmRaw = parseResult.rawJSON {
            session.parserRawJSON = llmRaw
        } else if let jsonData = try? JSONEncoder.pretty.encode(parsed.map(\.debugPayload)),
                  let jsonStr = String(data: jsonData, encoding: .utf8) {
            session.parserRawJSON = jsonStr
        }
        try? repo.update(session)

        phase = .wizard
    }

    /// 左滑取消录音（不跑 ASR，不入库 session）。
    func cancelRecording() {
        // M7-Fix5：如果 startRecording 还没完成，标记 pending，完成后由 startRecording 收尾
        if phase == .idle {
            pendingCancelRequested = true
            return
        }
        if audioRecorder.isRecording { audioRecorder.cancel() }
        phase = .idle
    }

    /// M7-Fix12：从 failed 态点"重试"时重置到 idle，用户可再次按住录音
    func resetToIdle() {
        if audioRecorder.isRecording { audioRecorder.cancel() }
        audioRecorder.cleanup()
        bills = []
        confirmedIds = []
        skippedIds = []
        currentIndex = 0
        asrText = ""
        asrConfidence = 0
        pendingStopRequested = false
        pendingCancelRequested = false
        phase = .idle
    }

    /// M7 修复问题 3：OCR 文本直接驱动向导。
    /// 跳过录音/ASR 阶段，直接把 OCR 识别的 rawText 交给 BillsLLMParser（source=.ocr），
    /// 拿到多笔结构后进入 wizard 阶段。
    /// - Parameters:
    ///   - ocrText: OCR 识别到的完整文本
    ///   - ocrEngine: 用哪个 OCR 档识别的，用于 session 审计（可空）
    func startFromOCRText(_ ocrText: String, ocrEngine: OCREngineKind? = nil) async {
        // 1. 分类白名单
        loadCategoryWhitelist()
        // 2. 重置状态
        sessionId = UUID().uuidString
        bills = []
        confirmedIds = []
        skippedIds = []
        currentIndex = 0
        asrText = ocrText       // 复用 asrText 字段存储来源文本，summary 审计可见
        asrConfidence = 1.0     // OCR 文本本身已是 OCR 置信度标定过的结果
        // 3. 进入 parsing 阶段（UI 显示进度）
        phase = .parsing

        // 4. LLM 解析（source=.ocr）
        let parseResult = await parser.parse(
            asrText: ocrText,
            allowedCategories: allowedCategoryNames(),
            requiredFields: requiredFields,
            source: .ocr
        )
        let parsed = parseResult.bills
        guard let firstBill = parsed.first else {
            phase = .manual
            return
        }
        self.bills = parsed
        self.currentIndex = 0
        self.currentBill = firstBill
        phase = .wizard
    }

    // MARK: - Wizard

    /// 是否允许进入下一笔 = 当前 bill 通过 normalized 校验后 missing 为空。
    var canProceed: Bool {
        let normalized = currentBill.normalizedMissing(
            required: requiredFields,
            allowedCategories: allowedCategoryNames()
        )
        return normalized.missingFields.isEmpty
    }

    /// M7 修复问题 4：每笔标记为"已确认"但**不立即入库**；全部向导结束后在 summary 阶段统一 insert。
    /// 这样支持：1) 已确认的笔可被回编辑 2) 点 progressDot 跳到任意笔 3) summary 前取消整批不会产生遗留脏数据。
    /// 用 `confirmedIds` 记录已确认笔 id；bills 保持原顺序不变。
    @Published private(set) var confirmedIds: Set<String> = []
    @Published private(set) var skippedIds: Set<String> = []

    /// 确认当前笔：仅标记 id + 更新 bills[currentIndex] 为用户编辑后版本，然后 advance。
    /// 入库推迟到 `finalizeAllToDatabase()`（summary 阶段调用）。
    func confirmCurrent(ledgerId: String = DefaultSeeder.defaultLedgerId) async {
        guard canProceed else { return }
        // 提交当前编辑到 bills[i]（实际上 commitCurrentEdits 会做一次，双保险）
        commitCurrentEdits()
        confirmedIds.insert(currentBill.id)
        // 从 skipped 中移除（如果用户之前跳过又回来确认）
        skippedIds.remove(currentBill.id)
        advance()
    }

    /// 放弃当前笔：标记为 skipped；不入库；允许回跳时重新确认。
    func skipCurrent() {
        skippedIds.insert(currentBill.id)
        confirmedIds.remove(currentBill.id)
        advance()
    }

    /// M7 修复问题 4：点击进度点跳到指定 index。允许回跳到已确认或已跳过的笔。
    /// 跳转前先提交当前笔的编辑到 bills 数组，避免丢失。
    func jumpTo(index: Int) {
        guard index >= 0, index < bills.count else { return }
        guard index != currentIndex else { return }
        commitCurrentEdits()
        currentIndex = index
        currentBill = bills[index]
    }

    /// 当前笔修改后回写 bills[currentIndex]（供 UI two-way 绑定使用）。
    func commitCurrentEdits() {
        guard currentIndex < bills.count else { return }
        bills[currentIndex] = currentBill
    }

    /// 指定某个字段为刚被编辑过，重算 currentBill.missingFields（实时驱动 CTA）。
    func recomputeMissing() {
        currentBill = currentBill.normalizedMissing(
            required: requiredFields,
            allowedCategories: allowedCategoryNames()
        )
    }

    /// M7 修复问题 4：summary 阶段统一把所有 confirmed 笔入库。
    /// 失败的笔累计到 session.error，但不阻塞其他笔的入库。
    /// 返回实际成功入库的笔数。
    /// M11+：调用方可显式传入 ledgerId；不传时默认按 selectedAALedger 决定
    ///       （选了 AA → AA 账本 + payerUserId；未选 → 个人 default ledger）。
    @discardableResult
    func finalizeAllToDatabase(ledgerId: String? = nil) -> Int {
        var successCount = 0
        let now = Date()
        // 解析最终入库 ledgerId / payerUserId：
        // 1. 显式传 ledgerId → 用传入值（保留向后兼容）
        // 2. 选了 AA 账本    → 用其 id + payerUserId = 当前用户
        // 3. 默认           → defaultLedgerId
        let resolvedLedgerId: String = ledgerId
            ?? selectedAALedger?.id
            ?? DefaultSeeder.defaultLedgerId
        let resolvedPayerUserId: String? = (selectedAALedger != nil) ? AAOwner.currentUserId : nil
        for bill in bills where confirmedIds.contains(bill.id) {
            guard let amount = bill.amount, amount > 0,
                  let occurredAt = bill.occurredAt,
                  let direction = bill.direction,
                  let catName = bill.categoryName,
                  let category = resolveCategory(direction: direction, name: catName) else {
                bumpSessionError("笔 \(bill.id.prefix(8)) 字段不全，跳过入库")
                continue
            }
            let record = Record(
                id: UUID().uuidString,
                ledgerId: resolvedLedgerId,
                categoryId: category.id,
                amount: amount,
                currency: "CNY",
                occurredAt: occurredAt,
                timezone: TimeZone.current.identifier,
                note: bill.note,
                payerUserId: resolvedPayerUserId,
                participants: nil,
                source: usedEngine == .whisper ? .voiceCloud : .voiceLocal,
                ocrConfidence: nil,
                voiceSessionId: sessionId,
                missingFields: nil,
                syncStatus: .pending,
                remoteId: nil,
                lastSyncError: nil,
                syncAttempts: 0,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil
            )
            do {
                try recordRepo.insert(record)
                successCount += 1
            } catch {
                bumpSessionError("笔 \(bill.id.prefix(8)) 入库失败：\(error.localizedDescription)")
            }
        }
        // session 状态收口
        if var s = try? repo.find(id: sessionId) {
            s.confirmedCount = successCount
            s.status = .completed
            try? repo.update(s)
        }
        return successCount
    }

    // MARK: - Internal

    /// 前进到下一笔（或 summary）。M7 修复问题 4：找到"下一个未处理"的笔；若无 → summary。
    private func advance() {
        // 找到第一个既未 confirmed 也未 skipped 的笔（从当前之后开始；找不到再从头找）
        func firstUnprocessed(startingAfter idx: Int) -> Int? {
            let count = bills.count
            for offset in 1...count {
                let i = (idx + offset) % count
                let b = bills[i]
                if !confirmedIds.contains(b.id) && !skippedIds.contains(b.id) {
                    return i
                }
            }
            return nil
        }
        if let next = firstUnprocessed(startingAfter: currentIndex) {
            currentIndex = next
            currentBill = bills[next]
        } else {
            // 全部处理完 → summary
            phase = .summary
        }
    }

    /// 供 Summary 展示：confirmedBills/skippedBills 从 ids 动态派生
    var confirmedBillsDerived: [ParsedBill] {
        bills.filter { confirmedIds.contains($0.id) }
    }
    var skippedBillsDerived: [ParsedBill] {
        bills.filter { skippedIds.contains($0.id) }
    }

    private func bumpSessionError(_ msg: String) {
        guard var s = try? repo.find(id: sessionId) else { return }
        let prev = s.error ?? ""
        s.error = prev.isEmpty ? msg : prev + " | " + msg
        try? repo.update(s)
    }

    private func loadCategoryWhitelist() {
        let expense = (try? SQLiteCategoryRepository.shared.list(kind: .expense, includeDeleted: false)) ?? []
        let income  = (try? SQLiteCategoryRepository.shared.list(kind: .income,  includeDeleted: false)) ?? []
        // Key = "{kind}|{name}"，避免 expense/income 同名分类冲突
        var map: [String: Category] = [:]
        for c in income  { map["\(CategoryKind.income.rawValue)|\(c.name)"]   = c }
        for c in expense { map["\(CategoryKind.expense.rawValue)|\(c.name)"] = c }
        self.categoryByKindAndName = map
    }
}

// MARK: - JSON 审计 helpers

private extension ParsedBill {
    /// 转成文档 §7.5.3 的 JSON 协议字段（parser_raw_json 存档用）
    var debugPayload: [String: String] {
        var dict: [String: String] = [:]
        if let d = occurredAt {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withFullDate]
            dict["occurred_at"] = f.string(from: d)
        }
        if let a = amount { dict["amount"] = "\(a)" }
        if let dir = direction { dict["direction"] = dir.rawValue }
        if let c = categoryName { dict["category"] = c }
        if let n = note { dict["note"] = n }
        dict["missing_fields"] = missingFields.sorted().joined(separator: ",")
        return dict
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
