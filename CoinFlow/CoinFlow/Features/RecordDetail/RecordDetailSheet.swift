//  RecordDetailSheet.swift
//  CoinFlow · M3.3 · §5.5.9
//
//  Bottom Sheet（presentationDetents medium/large）。
//  - 金额、分类、备注 显式保存（顶部「保存」按钮）
//  - 关闭时若有未保存修改 → 二次确认
//  - 删除按钮在底部，破坏性操作

import SwiftUI

struct RecordDetailSheet: View {

    /// 键盘焦点统一枚举（官方最佳实践：单一 FocusState + 外层单一 toolbar）
    private enum Field: Hashable { case amount, note }

    @StateObject private var vm: RecordDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCategoryPicker = false
    /// 删除确认弹窗显隐（ActionSheet / confirmationDialog）
    @State private var showDeleteConfirm = false
    /// 「未保存就关闭」二次确认弹窗
    @State private var showDiscardConfirm = false
    /// 统一管理金额/备注的键盘焦点
    @FocusState private var focusedField: Field?

    /// 金额拦截彩蛋 toast（与 NewRecordModal 行为完全一致）
    @State private var clampedToastText: String? = nil
    @State private var clampedToastTask: DispatchWorkItem? = nil

    /// 备注输入框底色：liquidGlass 主题下避免黑色实色（v6 修正）
    /// - notion / darkLiquid：维持原 `Color.canvasBG`（白/纯黑）
    /// - liquidGlass：用半透 hoverBg，保留输入框轮廓但不挡玻璃折射
    private var noteFieldFill: Color {
        LGAThemeStore.shared.kind == .liquidGlass
            ? Color.hoverBg
            : Color.canvasBG
    }

    init(record: Record) {
        _vm = StateObject(wrappedValue: RecordDetailViewModel(record: record))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NotionTheme.space6) {
                    amountField
                    categoryField
                    noteField
                    AttachmentPreviewSection(record: vm.original)
                    AASettlementLinkSection(record: vm.original)
                    metaInfo
                    deleteButton
                }
                .padding(NotionTheme.space5)
            }
            .overlay(clampedToastView)
            .scrollContentBackground(.hidden)
            .navigationTitle("流水详情")
            .navigationBarTitleDisplayMode(.inline)
            // 金额拦截 → 弹彩蛋 toast（仅 overLimit 触发，与 NewRecordModal 一致）
            .onChange(of: vm.amountClampedAt) { _ in
                showClampedToast()
            }
            .toolbar {
                // 左上：关闭（同时作为「取消」；脏标记才弹二次确认）
                //
                // liquidGlass 主题（iOS 26+）下交给系统 toolbar 自己包玻璃胶囊，
                // 不再手绘 `Circle().fill(Color.hoverBg)`——否则会在系统玻璃胶囊上
                // 又叠一层深色实心圆，视觉上显示为黑色圆点。
                // 其他两个主题保持原有手绘圆形按钮（与 NewRecordModal 顶栏风格一致）。
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        attemptDismiss()
                    } label: {
                        if LGAThemeStore.shared.kind == .liquidGlass {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .medium))
                        } else {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.inkPrimary)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.hoverBg))
                        }
                    }
                }
                // 右上：保存（仅在有修改且输入合法时可点）
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        // 收起键盘后再 commit，避免焦点未同步到 vm 中间态的 race
                        focusedField = nil
                        if vm.commit() {
                            Haptics.success()
                            dismiss()
                        } else {
                            Haptics.error()
                        }
                    }
                    .font(NotionFont.bodyBold())
                    .foregroundStyle((vm.isDirty && vm.canSave) ? Color.inkPrimary : Color.inkTertiary)
                    .disabled(!vm.isDirty || !vm.canSave)
                }
            }
            // 键盘「完成」按钮：由 AmountTextFieldUIKit / NoteTextFieldUIKit 自身的
            // inputAccessoryView 提供（系统级，sheet/detents 下也稳定）
            .sheet(isPresented: $showCategoryPicker) {
                CategoryPickerSheet(
                    categories: vm.availableCategories,
                    selectedId: vm.selectedCategory?.id,
                    onSelect: { vm.selectCategory($0) }
                )
                .presentationDetents([.medium, .large])
            }
            // 删除确认：底部 ActionSheet 样式（confirmationDialog 在 iOS 15+ 底部弹出）
            .confirmationDialog(
                "删除这笔流水？",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("都删除（本地 + 云端）", role: .destructive) {
                    vm.delete(localOnly: false)
                    dismiss()
                }
                Button("仅删除本地") {
                    vm.delete(localOnly: true)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("「仅删除本地」不会影响飞书多维表格中的记录；下次从飞书拉取时该记录会被重新同步到本地。")
            }
            // 未保存就关闭：二次确认
            .confirmationDialog(
                "放弃未保存的修改？",
                isPresented: $showDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button("放弃修改", role: .destructive) {
                    dismiss()
                }
                Button("继续编辑", role: .cancel) {}
            }
        }
        .themedSheetSurface()
    }

    /// 关闭请求统一入口：有脏改 → 弹二次确认；否则直接关闭。
    private func attemptDismiss() {
        focusedField = nil
        if vm.isDirty {
            showDiscardConfirm = true
        } else {
            dismiss()
        }
    }

    // MARK: - Amount

    private var amountField: some View {
        VStack(alignment: .center, spacing: NotionTheme.space3) {
            // 字号自适应（数值档位 + 字符兜底）：base 36pt 按数值大小分档缩放
            // 用 UIKit 包装的 AmountTextFieldUIKit 在 delegate 层硬拦截输入，
            // 与新建流水/语音/OCR 行为完全一致。
            let dynSize = AmountFontScale.scaledSize(base: 36, forText: vm.amountText)
            let amountColor = UIColor(DirectionColor.amountForeground(kind: vm.direction))
            // ¥ + TextField 整组居中：内层 HStack fixedSize（按内容排版），
            // 外层 .frame(maxWidth: .infinity, alignment: .center) 把整组推到中央。
            // 对齐用 .firstTextBaseline：与「新建流水」页保持一致，
            // ¥ 底部与数字底部齐平（数字无下降部，基线≈视觉底）。
            // ¥ 与数字字重/字体/比例统一（全局规则 §AmountSymbolStyle）。
            HStack(alignment: .firstTextBaseline, spacing: NotionTheme.space2) {
                Text("¥")
                    .font(NotionFont.amountBold(size: dynSize * AmountSymbolStyle.symbolScale))
                    .foregroundStyle(DirectionColor.amountForeground(kind: vm.direction))
                AmountTextFieldUIKit(
                    text: $vm.amountText,
                    placeholder: "0",
                    font: NotionFont.amountBoldUIKit(size: dynSize),
                    textColor: amountColor,
                    placeholderColor: UIColor(Color.inkTertiary),
                    alignment: .left,
                    onClamp: { reason in vm.handleClamp(reason) },
                    onFocusChange: { isFocused in
                        focusedField = isFocused ? .amount : nil
                    }
                )
                .frame(height: dynSize * 1.2)
                .fixedSize(horizontal: true, vertical: false)
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .center)
            // 拦截原因红字（与 NewRecord 文案一致）
            if vm.amountClampedHintVisible, let reason = vm.amountClampReason {
                Text(AmountInputGate.hintText(for: reason))
                    .font(NotionFont.small())
                    .foregroundStyle(Color.dangerRed)
                    .transition(.opacity)
            }
            Text(vm.direction == .expense ? "支出" : "收入")
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkTertiary)
            if let err = vm.saveError {
                Text(err)
                    .font(NotionFont.small())
                    .foregroundStyle(Color(hex: "#DF5452"))
            }
        }
        .frame(maxWidth: .infinity)
        // 金额超限/非法字符时 amount 区域抖动
        .shake(trigger: vm.amountClampedAt)
        .animation(Motion.standard(0.18), value: vm.amountClampedAt)
    }

    // MARK: - Clamped Toast（金额超限彩蛋，与 NewRecordModal 行为一致）

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
        guard let reason = vm.amountClampReason,
              AmountInputGate.shouldShowDreamToast(for: reason) else { return }
        withAnimation(Motion.exit(0.18)) {
            clampedToastText = AmountInputGate.dreamToastText
        }
        clampedToastTask?.cancel()
        let task = DispatchWorkItem {
            withAnimation(Motion.standard(0.22)) {
                clampedToastText = nil
            }
        }
        clampedToastTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: task)
    }

    // MARK: - Category

    private var categoryField: some View {
        Button { showCategoryPicker = true } label: {
            fieldRow(
                icon: vm.selectedCategory?.icon ?? "questionmark",
                label: "分类",
                value: vm.selectedCategory?.name ?? "未分类",
                showChevron: true
            )
        }
        .buttonStyle(.pressableRow)
    }

    // MARK: - Note
    //
    // 用 UIKit NoteTextFieldUIKit（键盘上方带「完成」按钮）。
    // 失焦 → onFocusChange(false) → focusedField = nil，仍走现有 onChange 触发 commit() 的路径。
    private var noteField: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space3) {
            HStack(spacing: NotionTheme.space5) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 24)
                Text("备注")
                    .font(NotionFont.body())
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
            }
            NoteTextFieldUIKit(
                text: $vm.note,
                placeholder: "点击添加备注…",
                font: NotionFont.bodyUIKit(),
                textColor: UIColor(Color.inkPrimary),
                placeholderColor: UIColor(Color.inkTertiary),
                minLines: 2,
                maxLines: 5,
                onFocusChange: { isFocused in
                    focusedField = isFocused ? .note : nil
                }
            )
            .padding(NotionTheme.space4)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusMD, style: .continuous)
                    .fill(noteFieldFill)
            )
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                .fill(Color.hoverBg)
        )
    }

    // MARK: - Meta info（只读）

    private var metaInfo: some View {
        VStack(spacing: 0) {
            metaRow(label: "发生时间", value: vm.occurredAtDisplay)
            Divider().background(Color.divider).padding(.leading, NotionTheme.space5)
            metaRow(label: "来源",     value: vm.sourceDisplay)
            Divider().background(Color.divider).padding(.leading, NotionTheme.space5)
            metaRow(label: "同步状态", value: vm.syncDisplay)
        }
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                .fill(Color.hoverBg)
        )
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(NotionFont.small())
                .foregroundStyle(Color.inkTertiary)
            Spacer()
            Text(value)
                .font(NotionFont.small())
                .foregroundStyle(Color.inkPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, NotionTheme.space4)
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button {
            Haptics.warn()
            showDeleteConfirm = true
        } label: {
            HStack {
                Spacer()
                Text("删除")
                    .font(NotionFont.bodyBold())
                    .foregroundStyle(Color(hex: "#DF5452"))
                Spacer()
            }
            .padding(NotionTheme.space5)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                    .fill(Color(hex: "#DF5452").opacity(0.12))
            )
        }
        .buttonStyle(.pressable(haptic: false))
    }

    // MARK: - Generic field row

    private func fieldRow(icon: String, label: String, value: String, showChevron: Bool) -> some View {
        HStack(spacing: NotionTheme.space5) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 24)
            Text(label)
                .font(NotionFont.body())
                .foregroundStyle(Color.inkPrimary)
            Spacer()
            Text(value)
                .font(NotionFont.body())
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(1)
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.inkTertiary)
            }
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                .fill(Color.hoverBg)
        )
    }
}

// MARK: - AttachmentPreviewSection（M11）
//
// 显示规则：
// - record.attachmentLocalPath 存在 + 磁盘命中 → 直接读本地（最快路径）
//   * 场景：刚记账还没同步 / 同步关闭中 / 同步失败仍在重试
// - 否则 record.attachmentRemoteToken 存在 → 从飞书拉（RemoteAttachmentLoader 双层缓存）
//   * 场景：同步成功后本地图被 SyncQueue 主动清掉
// - 都不满足 → 整块隐藏（手动记账无附件 / 历史数据 / 上传失败且本地丢失）
//
// 点击图片放大（用 SwiftUI presentation sheet + zoomable）；先做最小可用：sheet 全屏展示
private struct AttachmentPreviewSection: View {
    let record: Record

    @State private var image: UIImage?
    @State private var isLoading: Bool = false
    @State private var loadFailed: Bool = false
    @State private var showFullScreen: Bool = false

    private var hasAttachment: Bool {
        let hasLocal = (record.attachmentLocalPath?.isEmpty == false)
            && ScreenshotStore.exists(path: record.attachmentLocalPath ?? "")
        let hasRemote = (record.attachmentRemoteToken?.isEmpty == false)
        return hasLocal || hasRemote
    }

    @ViewBuilder
    var body: some View {
        if hasAttachment {
            VStack(alignment: .leading, spacing: NotionTheme.space3) {
                HStack(spacing: NotionTheme.space5) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: 24)
                    Text("OCR 截图")
                        .font(NotionFont.body())
                        .foregroundStyle(Color.inkPrimary)
                    Spacer()
                }
                imageCard
            }
            .padding(NotionTheme.space5)
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                    .fill(Color.hoverBg)
            )
            .task(id: taskKey) {
                await loadImage()
            }
            .sheet(isPresented: $showFullScreen) {
                AttachmentFullScreenView(image: image)
            }
        } else {
            EmptyView()
        }
    }

    /// task id：本地路径或远端 token 变化时触发重载
    private var taskKey: String {
        (record.attachmentLocalPath ?? "") + "|" + (record.attachmentRemoteToken ?? "")
    }

    /// 图片底板：liquidGlass 主题下用 `.ultraThinMaterial` 真玻璃 + 半透白描边，
    /// 避免 `Color.canvasBG`（深色实心）裸露在玻璃卡内形成"黑色矩形"突兀感；
    /// 其他主题保留原 canvasBG 行为。
    private var isLiquidGlass: Bool {
        LGAThemeStore.shared.kind == .liquidGlass
    }

    @ViewBuilder
    private var imageCard: some View {
        ZStack {
            // 已加载到图片时，不再绘制底板（图片自身覆盖整个区域，避免双层背景叠色）
            if image == nil {
                Group {
                    if isLiquidGlass {
                        RoundedRectangle(cornerRadius: NotionTheme.radiusMD, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: NotionTheme.radiusMD, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: NotionTheme.radiusMD, style: .continuous)
                            .fill(Color.canvasBG)
                    }
                }
                .frame(height: 160)
            }

            if let img = image {
                HStack {
                    Spacer(minLength: 0)
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: NotionTheme.radiusMD, style: .continuous))
                        // liquidGlass 下给图片一圈 hairline 描边，让它和玻璃卡有视觉分层但不至于硬切
                        .overlay(
                            RoundedRectangle(cornerRadius: NotionTheme.radiusMD, style: .continuous)
                                .stroke(Color.white.opacity(isLiquidGlass ? 0.12 : 0.0), lineWidth: 1)
                        )
                        .onTapGesture {
                            showFullScreen = true
                        }
                    Spacer(minLength: 0)
                }
            } else if isLoading {
                ProgressView()
                    .controlSize(.regular)
            } else if loadFailed {
                VStack(spacing: NotionTheme.space2) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.inkTertiary)
                    Text("图片加载失败")
                        .font(NotionFont.small())
                        .foregroundStyle(Color.inkTertiary)
                    Button("重试") {
                        Task { await loadImage(forceReload: true) }
                    }
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
                }
            }
        }
        // 让 ZStack 占满外层卡的内容宽度，图片才能真正水平居中
        // （外层 VStack 是 .leading，不加这个 ZStack 会缩到图片自身宽度并贴左）
        .frame(maxWidth: .infinity)
    }

    @MainActor
    private func loadImage(forceReload: Bool = false) async {
        if image != nil && !forceReload { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }

        // 优先本地
        if let localPath = record.attachmentLocalPath, !localPath.isEmpty,
           ScreenshotStore.exists(path: localPath),
           let data = ScreenshotStore.read(path: localPath),
           let img = UIImage(data: data) {
            image = img
            return
        }
        // 退到远端
        if let token = record.attachmentRemoteToken, !token.isEmpty {
            let img = await RemoteAttachmentLoader.shared.image(for: token)
            if let img {
                image = img
            } else {
                loadFailed = true
            }
            return
        }
        loadFailed = true
    }
}

// MARK: - 全屏查看（最小可用）

private struct AttachmentFullScreenView: View {
    let image: UIImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.black.opacity(0.45)))
            }
            .padding(.top, 12)
            .padding(.trailing, 16)
        }
    }
}

// MARK: - AA 分账反向链接（M11，需求 9.7 / 11.5）
//
// 仅当 record.aaSettlementId != nil 时显示一行入口卡片：
// - AA 账本仍存在：点击 push 到 AASplitDetailView
// - AA 账本已软删/不存在：展示灰态文案"该分账已删除"，不可点击
//
// 这是「分账完成后回写到 default-ledger 的流水」反查 AA 详情的唯一入口。
private struct AASettlementLinkSection: View {
    let record: Record

    /// 关联 AA 账本（同步从 LedgerRepository 读，不走 ViewModel；该字段一旦写入不会变）
    @State private var aaLedger: Ledger?
    /// 是否已查询过（决定 "ledger == nil" 究竟是"未加载"还是"已删除"）
    @State private var loaded: Bool = false
    @State private var navigate: Bool = false

    @ViewBuilder
    var body: some View {
        if let aaId = record.aaSettlementId, !aaId.isEmpty {
            VStack(spacing: 0) {
                if loaded, let ledger = aaLedger {
                    Button {
                        Haptics.tap()
                        navigate = true
                    } label: {
                        rowContent(
                            icon: "person.2.fill",
                            title: "AA 分账详情",
                            value: ledger.name,
                            valueColor: Color.inkPrimary,
                            chevron: true
                        )
                    }
                    .buttonStyle(.pressableRow)
                    .background(
                        NavigationLink(
                            destination: AASplitDetailView(ledgerId: ledger.id),
                            isActive: $navigate
                        ) { EmptyView() }
                        .opacity(0)
                    )
                } else {
                    rowContent(
                        icon: "person.2.slash",
                        title: "AA 分账详情",
                        value: loaded ? "该分账已删除" : "加载中…",
                        valueColor: Color.inkTertiary,
                        chevron: false
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: NotionTheme.radiusLG, style: .continuous)
                    .fill(Color.hoverBg)
            )
            .task(id: aaId) { await load(aaId: aaId) }
        }
    }

    private func rowContent(icon: String,
                            title: String,
                            value: String,
                            valueColor: Color,
                            chevron: Bool) -> some View {
        HStack(spacing: NotionTheme.space5) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 24)
            Text(title)
                .font(NotionFont.body())
                .foregroundStyle(Color.inkPrimary)
            Spacer()
            Text(value)
                .font(NotionFont.body())
                .foregroundStyle(valueColor)
                .lineLimit(1)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.inkTertiary)
            }
        }
        .padding(NotionTheme.space5)
    }

    @MainActor
    private func load(aaId: String) async {
        // LedgerRepository.find 已经过滤软删行；返回 nil 视为"已删除/不存在"
        let found = (try? SQLiteLedgerRepository.shared.find(id: aaId)) ?? nil
        await MainActor.run {
            self.aaLedger = found
            self.loaded = true
        }
    }
}
