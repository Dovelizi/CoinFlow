//  CaptureConfirmView.swift
//  CoinFlow · M7-Fix20 OCR 流程重做
//
//  设计基线：
//    - design/screens/03-capture-confirm/{main,low-confidence-*,loading}-*.png
//
//  M7-Fix20 新流程（废弃原 receipt 入口）：
//    1. 用户上传截图 → 立即弹出本视图，展示骨架屏
//    2. 视图内 task 串行：Vision OCR → BillsLLMParser
//    3. 任一阶段失败 → 顶部红色横幅 + 底部按钮置「重新选择」+ 不可保存
//    4. LLM 成功且金额合理 → 渲染最终表单
//
//  四种状态：
//    - .processing(.ocr / .llm)：骨架屏，navSubtitle = "内容解析中…"
//    - .ocrFailed：红横幅"识别失败 / 请重新上传截图"
//    - .llmFailed：红横幅"识别失败 / 请检查截图是否为账单"
//    - .success(receipt)：正常表单
//
//  入口：仅 init(sourceImage:) —— OCR/LLM 在内部跑

import SwiftUI

struct CaptureConfirmView: View {

    /// M7-Fix20 状态机
    enum Mode: Equatable {
        case processing(phase: Phase)         // OCR 中 / LLM 中
        case ocrFailed                        // OCR 阶段失败
        case llmFailed                        // LLM 阶段失败（含调用错/空账单/金额不合理）
        case success(receipt: ParsedReceipt)  // 完整成功

        enum Phase: Equatable { case ocr, llm }
    }

    let sourceImage: UIImage?
    let onSaved: ((Record) -> Void)?
    let onRetake: (() -> Void)?
    let scrollToBottom: Bool

    @State private var mode: Mode
    @StateObject private var vm: NewRecordViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var showCategoryPicker = false
    @State private var showFullImage = false
    @State private var showTimePicker = false
    @State private var showNoteEditor = false
    /// 键盘焦点枚举（官方最佳实践：单一 FocusState + 外层单一 toolbar）
    private enum Field: Hashable { case amount }
    /// 金额输入框 focus 状态（失焦触发校验）
    @FocusState private var focusedField: Field?
    /// 保留原截图 toggle
    @State private var keepScreenshot: Bool = true
    /// 字段级低置信度判定（保留兼容）
    @State private var perFieldLowConfidence: Set<String> = []

    // MARK: - M7-Fix26 用户确认机制
    /// 商户类型（可编辑；初始从 LLM receipt.merchant 同步；枚举"微信/支付宝/抖音/银行/其他"）
    @State private var merchantType: String?
    /// 商户选择 Menu 展示状态
    @State private var showMerchantMenu: Bool = false
    /// 三个关键字段的『用户已确认』状态
    /// - LLM 成功给出值时初始化为 true（用户可直接保存）
    /// - LLM 未给出值时初始化为 false（显示黄色『待确认』，用户点过/编辑后置 true）
    @State private var amountConfirmed: Bool = false
    @State private var merchantConfirmed: Bool = false
    @State private var categoryConfirmed: Bool = false

    /// 金额拦截彩蛋 toast（与 NewRecordModal/RecordDetailSheet 一致）
    @State private var clampedToastText: String? = nil
    @State private var clampedToastTask: DispatchWorkItem? = nil

    /// 商户可选枚举（顺序 = Menu 展示顺序）
    private let merchantOptions: [String] = ["微信", "支付宝", "抖音", "银行", "其他"]

    /// M7-Fix20 唯一公开入口：传入用户上传的截图，OCR/LLM 在内部异步执行
    init(sourceImage: UIImage,
         scrollToBottom: Bool = false,
         onSaved: ((Record) -> Void)? = nil,
         onRetake: (() -> Void)? = nil) {
        self.sourceImage = sourceImage
        self.scrollToBottom = scrollToBottom
        self.onSaved = onSaved
        self.onRetake = onRetake
        _mode = State(initialValue: .processing(phase: .llm))
        _vm = StateObject(wrappedValue: NewRecordViewModel())
    }

    // MARK: - Derived

    private var currentReceipt: ParsedReceipt? {
        if case .success(let r) = mode { return r }
        return nil
    }

    private var isProcessing: Bool {
        if case .processing = mode { return true }
        return false
    }

    private var isFailed: Bool {
        switch mode {
        case .ocrFailed, .llmFailed: return true
        default: return false
        }
    }

    private var isSuccess: Bool {
        if case .success = mode { return true }
        return false
    }

    /// 兼容旧字段：仅 success 视为 dataReady
    private var dataReady: Bool { isSuccess }

    private var isLowConfidence: Bool {
        guard let r = currentReceipt else { return false }
        return r.confidence < 0.6
    }

    /// 兼容旧字段：原 isLoading 表示骨架屏期；新流程对应 processing
    private var isLoading: Bool { isProcessing }

    private var hasLowConfidenceField: Bool {
        !perFieldLowConfidence.isEmpty || isLowConfidence
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                navigationBar
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: NotionTheme.space6) {
                            // M7-Fix20：失败横幅优先；成功且低置信度才展示黄色横幅
                            if case .ocrFailed = mode {
                                failureBanner(title: "识别失败",
                                              subtitle: "请重新上传截图")
                            } else if case .llmFailed = mode {
                                failureBanner(title: "识别失败",
                                              subtitle: "请检查截图是否为账单")
                            } else if isSuccess && hasLowConfidenceField {
                                lowConfidenceBanner
                            }
                            screenshotCard
                            recognitionCard
                            if isSuccess {
                                noteCard
                                keepScreenshotCard
                                    .id("bottomAnchor")
                            }
                            if let err = vm.saveError {
                                Text(err)
                                    .font(NotionFont.small())
                                    .foregroundStyle(Color.dangerRed)
                            }
                        }
                        .padding(.horizontal, NotionTheme.space5)
                        .padding(.top, NotionTheme.space5)
                        .padding(.bottom, NotionTheme.space9)
                        // M7-Fix21：状态切换淡入，避免 success 时的高度突变 + 闪动
                        .animation(.easeInOut(duration: 0.25), value: mode)
                    }
                    .onAppear {
                        if scrollToBottom, isSuccess {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                withAnimation(.none) {
                                    proxy.scrollTo("bottomAnchor", anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                bottomBar
            }
            clampedToastView
        }
        .themedSheetSurface()
        // 自绘键盘「完成」工具栏（替代原生 .toolbar { .keyboard }）
        .keyboardDoneToolbar()
        // 金额拦截 → 弹彩蛋 toast（仅 overLimit 触发，与 NewRecord/RecordDetail 一致）
        .onChange(of: vm.amountClampedAt) { _ in
            showClampedToast()
        }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(
                categories: vm.availableCategories,
                selectedId: vm.selectedCategory?.id,
                onSelect: {
                    vm.selectedCategory = $0
                    categoryConfirmed = true   // M7-Fix26：用户选过即确认
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTimePicker) {
            timePickerSheet
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNoteEditor) {
            noteEditorSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showFullImage) {
            fullImageOverlay
        }
        .task {
            // M7-Fix20 主流程：OCR → LLM 串行；仅运行一次
            await runRecognitionPipeline()
        }
    }

    // MARK: - Nav bar

    private var navigationBar: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("识别截图")
                    .font(.custom("PingFangSC-Semibold", size: 17))
                    .foregroundStyle(Color.inkPrimary)
                Text(navSubtitle)
                    .font(.custom("PingFangSC-Regular", size: 11))
                    .foregroundStyle(Color.inkTertiary)
            }
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.inkPrimary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
                Spacer()
                Button {
                    onRetake?()
                    dismiss()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("重新识别")
            }
            .padding(.horizontal, NotionTheme.space4)
        }
        .frame(height: 52)
        .background(Color.appSheetCanvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.divider).frame(height: NotionTheme.borderWidth)
        }
    }

    private var navSubtitle: String {
        // M7-Fix20：四态对应不同副标题
        switch mode {
        case .processing:  return "内容解析中…"
        case .ocrFailed:   return "识别失败"
        case .llmFailed:   return "识别失败"
        case .success:     return "请核对后保存"
        }
    }

    // MARK: - Low confidence banner

    private var lowConfidenceBanner: some View {
        HStack(alignment: .top, spacing: NotionTheme.space4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.statusWarning)
            VStack(alignment: .leading, spacing: 2) {
                Text("部分信息识别置信度低")
                    .font(.custom("PingFangSC-Semibold", size: 14))
                    .foregroundStyle(Color.inkPrimary)
                Text("请核对标黄字段后再保存")
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                .fill(Color.statusWarning.opacity(0.15))
        )
    }

    // M7-Fix20：通用失败横幅（OCR 失败 / LLM 失败共用）
    private func failureBanner(title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: NotionTheme.space4) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.dangerRed)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("PingFangSC-Semibold", size: 14))
                    .foregroundStyle(Color.inkPrimary)
                Text(subtitle)
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                .fill(Color.dangerRed.opacity(0.15))
        )
    }

    // MARK: - Screenshot card

    private var screenshotCard: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            HStack(spacing: NotionTheme.space3) {
                Image(systemName: "doc.viewfinder.fill")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.inkTertiary)
                Text("原始截图")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
                Spacer()
                Text(screenshotSourceHint)
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
            }
            .padding(.horizontal, 4)

            ZStack(alignment: .topTrailing) {
                Group {
                    if let img = sourceImage {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Rectangle()
                            .fill(Color.hoverBg)
                            .frame(height: 220)
                            .overlay(
                                Text("（无截图）")
                                    .foregroundStyle(Color.inkTertiary)
                                    .font(NotionFont.small())
                            )
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 280)
                .clipped()
                .cornerRadius(NotionTheme.radiusLG)

                if sourceImage != nil {
                    Button { showFullImage = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 10, weight: .semibold))
                            Text("查看")
                                .font(.custom("PingFangSC-Semibold", size: 11))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .padding(8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("查看原图大图")
                }
            }
        }
    }

    /// 从 rawText 里启发式识别来源（"微信支付" / "支付宝" / "银行"）
    private var screenshotSourceHint: String {
        guard let raw = currentReceipt?.rawText else { return "截图账单" }
        if raw.contains("微信支付") || raw.contains("WeChat") { return "微信支付" }
        if raw.contains("支付宝") || raw.contains("Alipay") { return "支付宝" }
        if raw.contains("银行") || raw.contains("Bank") { return "银行账单" }
        return "截图账单"
    }

    // MARK: - Recognition card（M7-Fix20 四态分发）

    @ViewBuilder
    private var recognitionCard: some View {
        switch mode {
        case .processing(let phase):
            loadingCard(phase: phase == .ocr ? .ocr : .llm)
        case .ocrFailed, .llmFailed:
            // 失败态不展示卡片（仅顶部红色横幅 + 截图卡）；
            // 用空 View 占位避免 ScrollView 高度突变
            EmptyView()
        case .success:
            loadedCard
        }
    }

    private enum LoadingPhase {
        case ocr        // OCR 识别中
        case llm        // 大模型分析中

        var title: String {
            // M7-Fix21：单一阶段（视觉 LLM），统一文案避免切换闪动
            switch self {
            case .ocr: return "正在识别截图…"
            case .llm: return "正在识别截图…"
            }
        }
    }

    private func loadingCard(phase: LoadingPhase) -> some View {
        VStack(spacing: NotionTheme.space5) {
            HStack(spacing: NotionTheme.space3) {
                ProgressView()
                    .scaleEffect(0.85)
                    .tint(Color.inkSecondary)
                Text(phase.title)
                    .font(.custom("PingFangSC-Semibold", size: 14))
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
            }

            VStack(spacing: NotionTheme.space4) {
                ForEach(0..<4, id: \.self) { i in
                    HStack(spacing: NotionTheme.space5) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.hoverBg)
                            .frame(width: 40, height: 12)
                        Spacer()
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.hoverBg)
                            .frame(width: skeletonWidth(i), height: 12)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                .fill(Color.hoverBg.opacity(0.5))
        )
    }

    private func skeletonWidth(_ i: Int) -> CGFloat {
        let widths: [CGFloat] = [120, 180, 90, 140]
        return widths[i % widths.count]
    }

    private var loadedCard: some View {
        VStack(spacing: 0) {
            // 顶部状态条
            HStack(spacing: NotionTheme.space3) {
                if hasLowConfidenceField {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Color.statusWarning)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.statusSuccess)
                }
                Text(hasLowConfidenceField ? "请核对识别结果" : "识别完成")
                    .font(.custom("PingFangSC-Semibold", size: 14))
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
                // M7-Fix14：LLM 增强已在整张 recognitionCard 走骨架屏，此处不再重复展示
            }
            .font(.system(size: 14, weight: .regular))
            .padding(.horizontal, NotionTheme.space5)
            .padding(.vertical, NotionTheme.space4)

            Rectangle().fill(Color.divider).frame(height: NotionTheme.borderWidth)

            // 大金额
            amountBlock
                .padding(.vertical, NotionTheme.space5)

            Rectangle().fill(Color.divider).frame(height: NotionTheme.borderWidth)

            // 字段行
            merchantRow
            innerDivider
            timeRow
            innerDivider
            categoryRow
        }
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                .fill(Color.hoverBg.opacity(0.5))
        )
    }

    // MARK: - Amount block（M7-Fix14 可编辑 + 失焦校验 + 错误红框）

    /// 金额拦截彩蛋 toast（与 NewRecordModal/RecordDetailSheet 行为一致）
    @ViewBuilder
    private var clampedToastView: some View {
        if let text = clampedToastText {
            VStack {
                Spacer()
                Text(text)
                    .font(NotionFont.small())
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.82))
                    )
                    .padding(.bottom, 120)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            .allowsHitTesting(false)
            .zIndex(2000)
        }
    }

    private func showClampedToast() {
        // 仅对 overLimit 触发"小目标"彩蛋；其他原因走红字提示就够了
        guard let reason = vm.amountClampReason,
              AmountInputGate.shouldShowDreamToast(for: reason) else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            clampedToastText = AmountInputGate.dreamToastText
        }
        clampedToastTask?.cancel()
        let task = DispatchWorkItem {
            withAnimation(.easeIn(duration: 0.22)) {
                clampedToastText = nil
            }
        }
        clampedToastTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: task)
    }

    private var amountBlock: some View {
        VStack(spacing: NotionTheme.space2) {
            // M7-Fix17：HStack 整体居中；-¥ / +¥ 小字 + 金额大字自然并排，不强制中央拉伸
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                // 方向胶囊（可点击切换收入/支出）+ 金额前 ¥
                // 不再用 +¥/-¥，方向通过胶囊文案 + 颜色表达，与列表/统计页规范一致
                Button {
                    vm.setDirection(vm.direction == .expense ? .income : .expense)
                } label: {
                    HStack(spacing: 6) {
                        Text(vm.direction == .expense ? "支出" : "收入")
                            .font(.custom("PingFangSC-Semibold", size: 11))
                            .foregroundStyle(amountValidation == .error ? Color.dangerRed : directionColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill((amountValidation == .error ? Color.dangerRed : directionColor).opacity(0.15))
                            )
                        Text("¥")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(amountValidation == .error ? Color.dangerRed : directionColor)
                    }
                }
                .buttonStyle(.plain)

                // 金额 TextField：UIKit AmountTextFieldUIKit 在 delegate 层硬拦截，
                // 与 NewRecord/RecordDetail/VoiceWizard 行为完全一致；
                // 拒绝时 onClamp 触发震动 + UI 红字（vm 已暴露 amountClampReason/At）。
                AmountTextFieldUIKit(
                    text: Binding(
                        get: { vm.amountText },
                        set: { vm.amountText = $0 }
                    ),
                    placeholder: "0",
                    font: NotionFont.amountBoldUIKit(size: 44),
                    textColor: UIColor(amountValidation == .error
                                       ? Color.dangerRed
                                       : (vm.amountText.isEmpty ? Color.inkTertiary : directionColor)),
                    placeholderColor: UIColor(Color.inkTertiary),
                    alignment: .left,
                    onClamp: { reason in vm.handleClamp(reason) },
                    onFocusChange: { isFocused in
                        if isFocused {
                            focusedField = .amount
                            amountConfirmed = true   // M7-Fix26：聚焦即确认
                        } else {
                            focusedField = nil
                            if !vm.amountText.trimmingCharacters(in: .whitespaces).isEmpty {
                                vm.markAmountAttempted()
                            }
                        }
                    }
                )
                .frame(height: 52)
                .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.vertical, NotionTheme.space3)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                    .stroke(amountValidation.borderColor, lineWidth: amountValidation == .none ? 0 : 1.5)
            )

            // 校验/拦截提示文案（拦截红字优先级最高）
            if vm.amountClampedHintVisible, let reason = vm.amountClampReason {
                Text(AmountInputGate.hintText(for: reason))
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.dangerRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, NotionTheme.space5)
                    .transition(.opacity)
            } else if let msg = vm.amountValidationMessage, amountValidation != .none {
                Text(msg)
                    .font(NotionFont.micro())
                    .foregroundStyle(amountValidation == .error ? Color.dangerRed : Color.statusWarning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, NotionTheme.space5)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(vm.direction == .expense ? "支出" : "收入") \(vm.amountText.isEmpty ? "0" : vm.amountText) 元")
        .accessibilityHint("点击编辑金额")
    }

    /// 金额字段校验态
    /// M7-Fix26：未确认（amountConfirmed=false 且字段已有值）→ 黄色 warning；
    /// 字段为空且尝试保存 → 红色 error；不合法值 → 红色 error
    private var amountValidation: FieldValidationState {
        let trimmed = vm.amountText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return vm.isAmountInError ? .error : .none
        }
        if let d = Decimal(string: trimmed) {
            if d <= 0 { return .error }
            if d > 100_000_000 { return .error }
        } else {
            return .error
        }
        // 字段合法但用户尚未确认 → warning
        if !amountConfirmed { return .warning }
        return .none
    }

    private var directionColor: Color {
        vm.direction == .expense ? Color.dangerRed : Color.statusSuccess
    }

    // MARK: - Field rows

    /// M7-Fix14：字段校验态三级
    enum FieldValidationState {
        case none        // 无边框（正常）
        case warning     // 黄边（需核对的 / 用户选过但不确定）
        case error       // 红边（必填未填 / 错误）

        var borderColor: Color {
            switch self {
            case .none:    return .clear
            case .warning: return Color.statusWarning
            case .error:   return Color.dangerRed
            }
        }
    }

    private var merchantRow: some View {
        // M7-Fix26：商户可编辑 —— 点击弹 Menu 选枚举；未确认时黄色警告
        let currentMerchant = merchantType ?? currentReceipt?.merchant
        let brand = MerchantBrand.detect(from: currentReceipt?.rawText ?? "",
                                         merchant: currentMerchant)
        let state: FieldValidationState = {
            if currentMerchant == nil { return .warning }         // 没值 → 黄
            if !merchantConfirmed      { return .warning }         // 未确认 → 黄
            return .none
        }()
        return Menu {
            ForEach(merchantOptions, id: \.self) { opt in
                Button(opt) {
                    merchantType = opt
                    merchantConfirmed = true
                }
            }
        } label: {
            fieldRowLabelContent(
                label: "商户",
                value: currentMerchant ?? "未识别",
                icon: brand.icon,
                iconTint: brand.color,
                state: state,
                tappable: true
            )
        }
        .accessibilityLabel("商户：\(currentMerchant ?? "未识别")")
        .accessibilityHint("点击选择商户类型")
    }

    private var timeRow: some View {
        // 时间 VM 默认当前时间，理论不会"缺失"；低置信度 → warning
        let state: FieldValidationState = {
            if isLowConfidence || perFieldLowConfidence.contains("time") { return .warning }
            return .none
        }()
        return fieldRow(
            label: "时间",
            value: formatDate(vm.occurredAt),
            icon: "calendar",
            state: state,
            tappable: true,
            action: { showTimePicker = true }
        )
    }

    private var categoryRow: some View {
        // M7-Fix26：未选 / 未确认 → warning；已选且已确认 → 正常
        let state: FieldValidationState = {
            if vm.selectedCategory == nil { return vm.attemptedSave ? .error : .warning }
            if !categoryConfirmed         { return .warning }
            return .none
        }()
        return fieldRow(
            label: "分类",
            value: vm.selectedCategory?.name ?? "未选择",
            icon: vm.selectedCategory?.icon ?? "questionmark.circle",
            state: state,
            tappable: true,
            action: { showCategoryPicker = true }
        )
    }

    private func fieldRow(label: String,
                          value: String,
                          icon: String,
                          iconTint: Color? = nil,
                          state: FieldValidationState,
                          tappable: Bool,
                          action: @escaping () -> Void) -> some View {
        let content = fieldRowLabelContent(
            label: label, value: value, icon: icon,
            iconTint: iconTint, state: state, tappable: tappable
        )

        if tappable {
            return AnyView(
                Button(action: action) { content }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(label)：\(value)")
                    .accessibilityHint("点击修改")
            )
        } else {
            return AnyView(content.accessibilityLabel("\(label)：\(value)"))
        }
    }

    /// M7-Fix26：抽出"行内容渲染"逻辑供 Menu label 等复用
    private func fieldRowLabelContent(label: String,
                                      value: String,
                                      icon: String,
                                      iconTint: Color? = nil,
                                      state: FieldValidationState,
                                      tappable: Bool) -> some View {
        HStack(spacing: NotionTheme.space5) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(iconTint ?? Color.inkSecondary)
                .frame(width: 24)
            Text(label)
                .font(NotionFont.body())
                .foregroundStyle(Color.inkSecondary)
            Spacer()
            HStack(spacing: 6) {
                if state == .warning {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.statusWarning)
                } else if state == .error {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.dangerRed)
                }
                Text(value)
                    .font(NotionFont.body())
                    .foregroundStyle(state == .error ? Color.dangerRed : Color.inkPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if tappable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.inkTertiary)
            }
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusMD)
                .stroke(state.borderColor, lineWidth: state == .none ? 0 : 1.5)
                .padding(.horizontal, NotionTheme.space3)
        )
        .contentShape(Rectangle())
    }

    private var innerDivider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(height: NotionTheme.borderWidth)
            .padding(.leading, NotionTheme.space5 + 24 + NotionTheme.space5)
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日 HH:mm"
        return f.string(from: d)
    }

    // MARK: - Note card

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            HStack(spacing: NotionTheme.space3) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.inkTertiary)
                Text("备注")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
                Spacer()
                if !vm.note.isEmpty {
                    Text("\(vm.note.count) 字")
                        .font(NotionFont.micro())
                        .foregroundStyle(Color.inkTertiary)
                }
            }
            .padding(.horizontal, 4)

            Button { showNoteEditor = true } label: {
                HStack(alignment: .top) {
                    Text(vm.note.isEmpty ? "点击添加备注…" : vm.note)
                        .font(NotionFont.body())
                        .foregroundStyle(vm.note.isEmpty ? Color.inkTertiary : Color.inkPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, NotionTheme.space5)
                .padding(.vertical, 14)
                .frame(minHeight: 56, alignment: .top)
                .background(
                    RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                        .fill(Color.hoverBg.opacity(0.5))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(vm.note.isEmpty ? "添加备注" : "编辑备注：\(vm.note)")
        }
    }

    private var noteEditorSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $vm.note)
                    .font(NotionFont.body())
                    .padding(NotionTheme.space5)
                    .scrollContentBackground(.hidden)
                Spacer()
            }
            .navigationTitle("备注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showNoteEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showNoteEditor = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .themedSheetSurface()
    }

    // MARK: - Keep screenshot card

    private var keepScreenshotCard: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            HStack(spacing: NotionTheme.space3) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.inkTertiary)
                Text("附件")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.inkTertiary)
                Spacer()
            }
            .padding(.horizontal, 4)

            HStack(spacing: NotionTheme.space5) {
                Image(systemName: keepScreenshot ? "paperclip" : "paperclip.badge.ellipsis")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("保留原截图")
                        .font(NotionFont.body())
                        .foregroundStyle(Color.inkPrimary)
                    Text(keepScreenshot
                         ? "截图将作为附件保存到此条流水"
                         : "保存后丢弃截图，仅保留识别结果")
                        .font(NotionFont.small())
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                // 自绘 toggle
                Button { keepScreenshot.toggle() } label: {
                    ZStack(alignment: keepScreenshot ? .trailing : .leading) {
                        Capsule()
                            .fill(keepScreenshot ? Color.accentBlue : Color.inkTertiary.opacity(0.35))
                            .frame(width: 44, height: 26)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                            .padding(.horizontal, 2)
                            .shadow(color: Color.black.opacity(0.15), radius: 2, y: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("保留原截图")
                .accessibilityValue(keepScreenshot ? "已开启" : "已关闭")
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                    .fill(Color.hoverBg.opacity(0.5))
            )
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.divider).frame(height: NotionTheme.borderWidth)
            HStack(spacing: NotionTheme.space4) {
                Button {
                    if isFailed {
                        // M7-Fix20：失败态左按钮 = "重新选择"，仅关闭页面回首页
                        onRetake?()
                        dismiss()
                    } else {
                        dismiss()
                    }
                } label: {
                    Text(isFailed ? "重新选择" : "丢弃")
                        .font(.custom("PingFangSC-Semibold", size: 15))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                                .fill(Color.hoverBg)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFailed ? "重新选择" : "丢弃")

                Button {
                    Task { await handleSave() }
                } label: {
                    Text(saveButtonTitle)
                        .font(.custom("PingFangSC-Semibold", size: 15))
                        .foregroundStyle(canSave ? Color.white : Color.inkTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                                .fill(canSave ? Color.accentBlue : Color.hoverBgStrong)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .accessibilityLabel(saveButtonTitle)
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.top, NotionTheme.space4)
            .padding(.bottom, NotionTheme.space5)
        }
        .background(Color.appSheetCanvas)
    }

    private var saveButtonTitle: String {
        switch mode {
        case .processing: return "解析中…"
        case .ocrFailed:  return "无法保存"
        case .llmFailed:  return "无法保存"
        case .success:    return hasLowConfidenceField ? "核对后保存" : "保存到流水"
        }
    }

    private var canSave: Bool {
        guard isSuccess else { return false }
        guard vm.canSave else { return false }
        // M7-Fix26：金额 / 商户 / 分类三项都需用户确认（点过/选过/编辑过）
        return amountConfirmed && merchantConfirmed && categoryConfirmed
    }

    @MainActor
    private func handleSave() async {
        guard case .success(let r) = mode else { return }
        // M9-Fix5：渠道单独成列，不再拼进 note 前缀
        // M9-Fix4：keepScreenshot 开启时把原图传给 VM，VM 落盘 + SyncQueue 上传飞书附件
        let attachment: UIImage? = keepScreenshot ? sourceImage : nil
        let channel = (merchantType?.isEmpty == false) ? merchantType : nil
        if let saved = await vm.save(source: .ocrVision,
                                      ocrConfidence: r.confidence,
                                      attachmentImage: attachment,
                                      merchantChannel: channel) {
            onSaved?(saved)
            dismiss()
        }
    }

    // MARK: - Time picker sheet

    private var timePickerSheet: some View {
        VStack(spacing: NotionTheme.space5) {
            HStack {
                Button("取消") { showTimePicker = false }
                    .foregroundStyle(Color.inkSecondary)
                Spacer()
                Text("选择时间")
                    .font(NotionFont.h3())
                Spacer()
                Button("完成") { showTimePicker = false }
                    .foregroundStyle(Color.accentBlue)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.top, NotionTheme.space5)

            DatePicker(
                "",
                selection: $vm.occurredAt,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "zh_CN"))

            Spacer(minLength: 0)
        }
        .themedSheetSurface()
    }

    // MARK: - Full image overlay

    private var fullImageOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let img = sourceImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            }
            VStack {
                HStack {
                    Spacer()
                    Button { showFullImage = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.black.opacity(0.4)))
                    }
                    .padding(NotionTheme.space5)
                }
                Spacer()
            }
        }
    }

    // MARK: - M7-Fix21 视觉 LLM 直识图流水线

    /// 金额合理性校验 —— 过滤 LLM 把订单号、卡号、流水号误填为金额的情况。
    private func isReasonableAmount(_ amount: Decimal?) -> Bool {
        guard let a = amount else { return false }
        return a > 0 && a <= 100_000_000
    }

    /// 主流程：图片 → 视觉 LLM → bills JSON → 写入 vm 或切换失败态
    /// M7-Fix21：废弃 Vision OCR 中转，直接把图片喂给视觉 LLM；
    /// 单一 processing 状态，去除 OCR/LLM 阶段切换闪动。
    @MainActor
    private func runRecognitionPipeline() async {
        guard let image = sourceImage else {
            mode = .llmFailed
            return
        }

        // 视觉 LLM 必须配置
        guard AppConfig.shared.isLLMVisionConfigured else {
            NSLog("[Vision LLM] 未配置 → llmFailed")
            mode = .llmFailed
            return
        }

        mode = .processing(phase: .llm)

        // 准备分类白名单
        let expense = (try? SQLiteCategoryRepository.shared.list(kind: .expense, includeDeleted: false)) ?? []
        let income  = (try? SQLiteCategoryRepository.shared.list(kind: .income,  includeDeleted: false)) ?? []
        var allowed = Set<String>()
        for c in expense { allowed.insert(c.name) }
        for c in income  { allowed.insert(c.name) }

        // 调用视觉 LLM
        let rawJSON: String
        do {
            let client = BillsVisionLLMClient()
            rawJSON = try await client.recognizeBills(
                image: image,
                allowedCategories: Array(allowed)
            )
        } catch {
            // M7-Fix25：Swift Task 被取消（视图销毁/重建）时 URLSession 抛 cancelled，
            // 此时视图已经不在了，改 mode 无意义且会触发 @State 警告。静默退出。
            if Task.isCancelled {
                NSLog("[Vision LLM] task 被取消（视图销毁），静默退出")
                return
            }
            NSLog("[Vision LLM] 调用失败：\(error.localizedDescription) → llmFailed")
            mode = .llmFailed
            return
        }

        // 解析 JSON（复用 BillsLLMParser 的解析路径）
        let bills: [ParsedBill]
        do {
            bills = try BillsLLMParser().decodeBillsJSON(
                raw: rawJSON,
                allowedCategories: Array(allowed),
                requiredFields: ["amount", "occurred_at", "direction", "category"]
            )
        } catch {
            NSLog("[Vision LLM] JSON 解析失败：\(error.localizedDescription) → llmFailed")
            mode = .llmFailed
            return
        }

        // 校验输出
        guard let first = bills.first else {
            NSLog("[Vision LLM] 返回空账单 → llmFailed")
            mode = .llmFailed
            return
        }
        guard let amt = first.amount, isReasonableAmount(amt) else {
            NSLog("[Vision LLM] 金额不合理（amount=\(String(describing: first.amount))）→ llmFailed")
            mode = .llmFailed
            return
        }

        // 写入 vm（走 Gate 统一校验：超 1 亿/小数 > 2 等异常会被拒，保持 amountText 空）
        vm.applyAmountInput(AmountFormatter.display(amt))
        if let occ = first.occurredAt {
            vm.occurredAt = occ
        }
        if let dir = first.direction {
            let kind: CategoryKind = dir == .expense ? .expense : .income
            if vm.direction != kind {
                vm.setDirection(kind)
            }
        }
        if let catName = first.categoryName {
            if let matched = vm.availableCategories.first(where: { $0.name == catName }) {
                vm.selectedCategory = matched
            }
        }
        if let n = first.note, !n.isEmpty, vm.note.isEmpty {
            vm.note = n
        }

        // M7-Fix26：初始化用户确认态
        //   LLM 给了值 → confirmed = true（用户可直接保存）
        //   LLM 未给值 → confirmed = false（黄色『待确认』，需用户交互后确认）
        merchantType = first.merchantType
        amountConfirmed   = isReasonableAmount(amt)
        merchantConfirmed = (first.merchantType != nil)
        categoryConfirmed = (vm.selectedCategory != nil)

        // M7-Fix23：merchant 优先用 LLM 新字段 merchant_type（微信/支付宝/抖音/银行/其他）；
        // 无值时降级为 LLM 的 note（原 OCR 商户名逻辑）
        let merchantDisplay = first.merchantType ?? first.note
        let receipt = ParsedReceipt(
            amount: amt,
            merchant: merchantDisplay,
            occurredAt: first.occurredAt,
            confidence: 1.0,
            rawText: rawJSON
        )
        mode = .success(receipt: receipt)
    }
}

#if DEBUG
#Preview("Processing") {
    // 预览用占位图；真实流程由用户选图触发
    let img = UIImage(systemName: "photo")!
    return CaptureConfirmView(sourceImage: img)
        .preferredColorScheme(.dark)
}
#endif
