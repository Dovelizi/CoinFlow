//  SystemConfigView.swift
//  CoinFlow
//
//  系统配置页面（用户在 App 内编辑运行时参数）。
//  - 飞书：App ID + App Secret（必填，决定云同步可用性）
//  - 文本 LLM：Provider + BaseURL + Model + API Key（必填，决定语音/OCR 多笔解析）
//  - 视觉 LLM：Provider + BaseURL + Model + API Key（必填，决定 OCR 截图识别第 3 档）
//
//  保存策略：用户编辑时仅更新本地 @State；点击右上角「保存」时统一写入
//  SystemConfigStore（Keychain + UserDefaults）并发出变更通知。

import SwiftUI

struct SystemConfigView: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeStore = LGAThemeStore.shared

    private let store = SystemConfigStore.shared

    // MARK: - 飞书

    @State private var feishuAppID: String = ""
    @State private var feishuAppSecret: String = ""
    @State private var showFeishuSecret: Bool = false

    // 飞书 - 高级
    @State private var feishuOwnerOpenID: String = ""
    @State private var showFeishuAdvanced: Bool = false

    // 飞书 - 自动生成（首次 bootstrap 后写入；用户也可手动改写以接管已有的多维表格）
    @State private var generatedAppToken: String = ""
    @State private var generatedTableId: String = ""
    @State private var generatedBitableURL: String = ""
    @State private var copyToast: String? = nil

    // MARK: - 文本 LLM

    @State private var textProvider: SystemTextProvider = .stub
    @State private var textBaseURL: String = ""
    @State private var textModel: String = ""
    @State private var textAPIKey: String = ""
    @State private var showTextKey: Bool = false

    // MARK: - 视觉 LLM

    @State private var visionProvider: SystemVisionProvider = .stub
    @State private var visionBaseURL: String = ""
    @State private var visionModel: String = ""
    @State private var visionAPIKey: String = ""
    @State private var showVisionKey: Bool = false

    // MARK: - 保存反馈

    @State private var savedToast: Bool = false

    // MARK: - 焦点管理（用于「完成」按钮 / 点击空白收起键盘）

    private enum Field: Hashable {
        case feishuAppID, feishuAppSecret
        case feishuOwnerOpenID
        case feishuAppToken, feishuTableId, feishuBitableURL
        case textBaseURL, textModel, textAPIKey
        case visionBaseURL, visionModel, visionAPIKey
    }

    @FocusState private var focusedField: Field?

    // MARK: - Body

    var body: some View {
        ZStack {
            ThemedBackgroundLayer(kind: .settings)
            VStack(spacing: 0) {
                navBar
                ScrollView {
                    VStack(spacing: NotionTheme.space6) {
                        feishuSection
                        textLLMSection
                        visionLLMSection
                        descriptionFooter
                    }
                    .padding(NotionTheme.space5)
                }
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .onTapGesture { focusedField = nil }
            }
            if savedToast { savedToastOverlay }
        }
        .onAppear {
            loadFromStore()
        }
        .onReceive(NotificationCenter.default.publisher(for: FeishuConfig.bitableMetadataDidChange)) { _ in
            // App 在后台/其他页面触发了重建表 → 实时刷新只读展示字段
            generatedAppToken = FeishuConfig.bitableAppToken ?? ""
            generatedTableId  = FeishuConfig.billsTableId ?? ""
            generatedBitableURL = FeishuConfig.bitableURL ?? ""
        }
        .hideTabBar()
        .navigationBarHidden(true)
        .enableInteractivePop()
    }

    // MARK: - Nav Bar

    private var navBar: some View {
        ZStack {
            Text("系统配置")
                .font(.custom("PingFangSC-Semibold", size: 17))
                .foregroundStyle(themeStore.isEnabled ? Color.white : Color.inkPrimary)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(themeStore.isEnabled ? Color.white : Color.inkPrimary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.pressableSoft)
                .accessibilityLabel("返回")
                Spacer()
                Button { save() } label: {
                    Text("保存")
                        .font(.custom("PingFangSC-Semibold", size: 15))
                        .foregroundStyle(themeStore.isEnabled
                                         ? Color.white
                                         : Color.accentBlue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.pressableSoft)
                .accessibilityLabel("保存配置")
            }
            .padding(.horizontal, NotionTheme.space5)
        }
        .frame(height: NotionTheme.topbarHeight)
        .background(Color.appCanvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(themeStore.isEnabled ? Color.white.opacity(0.06) : Color.divider)
                .frame(height: NotionTheme.borderWidth)
        }
    }

    // MARK: - 飞书

    private var feishuSection: some View {
        SettingsSection(title: "飞书云同步", icon: "cloud") {
            VStack(spacing: 0) {
                fieldRow(label: "App ID",
                         placeholder: "cli_xxxxxxxxxxxx",
                         text: $feishuAppID,
                         field: .feishuAppID)
                rowDivider
                secureFieldRow(label: "App Secret",
                               placeholder: "应用密钥",
                               text: $feishuAppSecret,
                               isVisible: $showFeishuSecret,
                               field: .feishuAppSecret)
                rowDivider
                advancedToggleRow
                if showFeishuAdvanced {
                    rowDivider
                    fieldRow(label: "Owner Open ID",
                             placeholder: "ou_xxxxxxxxxxxx",
                             text: $feishuOwnerOpenID,
                             field: .feishuOwnerOpenID)
                    rowDivider
                    editableValueRow(label: "App Token",
                                     placeholder: "首次同步后自动生成，可手动接管",
                                     text: $generatedAppToken,
                                     field: .feishuAppToken)
                    rowDivider
                    editableValueRow(label: "Table ID",
                                     placeholder: "tblxxxxxxxxxxxx",
                                     text: $generatedTableId,
                                     field: .feishuTableId)
                    rowDivider
                    editableValueRow(label: "多维表格 URL",
                                     placeholder: "https://my.feishu.cn/base/...",
                                     text: $generatedBitableURL,
                                     field: .feishuBitableURL)
                }
            }
        }
    }

    private var advancedToggleRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showFeishuAdvanced.toggle() }
        } label: {
            HStack {
                Text("高级配置")
                    .font(NotionFont.body())
                    .foregroundStyle(themeStore.isEnabled ? Color.white : Color.inkPrimary)
                Spacer()
                Image(systemName: showFeishuAdvanced ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(themeStore.isEnabled ? LGATheme.textSecondary : Color.inkTertiary)
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 既可编辑又带「复制」按钮的行：用于 App Token / Table ID / 多维表格 URL。
    private func editableValueRow(label: String,
                                  placeholder: String,
                                  text: Binding<String>,
                                  field: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(NotionFont.small())
                    .foregroundStyle(themeStore.isEnabled ? LGATheme.textSecondary : Color.inkSecondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = text.wrappedValue
                    showCopyToast("已复制")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(themeStore.isEnabled ? LGATheme.textSecondary : Color.accentBlue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("复制 \(label)")
                .disabled(text.wrappedValue.isEmpty)
                .opacity(text.wrappedValue.isEmpty ? 0.3 : 1)
            }
            TextField(placeholder, text: text)
                .focused($focusedField, equals: field)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .font(NotionFont.body())
                .foregroundStyle(themeStore.isEnabled ? Color.white : Color.inkPrimary)
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 12)
    }

    private func showCopyToast(_ text: String) {
        copyToast = text
        withAnimation { savedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { savedToast = false }
            copyToast = nil
        }
    }

    // MARK: - 文本 LLM

    private var textLLMSection: some View {
        SettingsSection(title: "文本 LLM（语音/多笔解析）", icon: "text.bubble") {
            VStack(spacing: 0) {
                providerPickerRow(
                    label: "服务商",
                    selection: Binding(
                        get: { textProvider },
                        set: { newValue in
                            // 切换 provider 时若用户尚未填，自动用默认 baseURL/model
                            if textBaseURL.isEmpty || textBaseURL == textProvider.defaultBaseURL {
                                textBaseURL = newValue.defaultBaseURL
                            }
                            if textModel.isEmpty || textModel == textProvider.defaultModel {
                                textModel = newValue.defaultModel
                            }
                            textProvider = newValue
                        }),
                    options: SystemTextProvider.allCases.map { ($0, $0.displayName) }
                )
                rowDivider
                fieldRow(label: "BaseURL",
                         placeholder: textProvider.defaultBaseURL,
                         text: $textBaseURL,
                         keyboard: .URL,
                         field: .textBaseURL)
                rowDivider
                fieldRow(label: "模型名称",
                         placeholder: textProvider.defaultModel,
                         text: $textModel,
                         field: .textModel)
                rowDivider
                secureFieldRow(label: "API Key",
                               placeholder: "sk-xxxxxxxx",
                               text: $textAPIKey,
                               isVisible: $showTextKey,
                               field: .textAPIKey)
            }
        }
    }

    // MARK: - 视觉 LLM

    private var visionLLMSection: some View {
        SettingsSection(title: "视觉 LLM（截图记账识别）", icon: "eye") {
            VStack(spacing: 0) {
                providerPickerRow(
                    label: "服务商",
                    selection: Binding(
                        get: { visionProvider },
                        set: { newValue in
                            if visionBaseURL.isEmpty || visionBaseURL == visionProvider.defaultBaseURL {
                                visionBaseURL = newValue.defaultBaseURL
                            }
                            if visionModel.isEmpty || visionModel == visionProvider.defaultModel {
                                visionModel = newValue.defaultModel
                            }
                            visionProvider = newValue
                        }),
                    options: SystemVisionProvider.allCases.map { ($0, $0.displayName) }
                )
                rowDivider
                fieldRow(label: "BaseURL",
                         placeholder: visionProvider.defaultBaseURL,
                         text: $visionBaseURL,
                         keyboard: .URL,
                         field: .visionBaseURL)
                rowDivider
                fieldRow(label: "模型名称",
                         placeholder: visionProvider.defaultModel,
                         text: $visionModel,
                         field: .visionModel)
                rowDivider
                secureFieldRow(label: "API Key",
                               placeholder: "sk-xxxxxxxx",
                               text: $visionAPIKey,
                               isVisible: $showVisionKey,
                               field: .visionAPIKey)
            }
        }
    }

    // MARK: - 底部说明

    private var descriptionFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("说明")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(themeStore.isEnabled ? LGATheme.textSecondary : Color.inkSecondary)
            Text("• 未配置 LLM 时，语音多笔与截图识别功能不可用。")
            Text("• 未配置飞书时，所有数据仅本地存储，不会同步到云端。")
            Text("• API Key 仅保存在本设备的 Keychain，加密存储。")
        }
        .font(NotionFont.small())
        .foregroundStyle(themeStore.isEnabled ? LGATheme.textSecondary : Color.inkTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, NotionTheme.space3)
    }

    // MARK: - 通用行控件

    private func fieldRow(label: String,
                          placeholder: String,
                          text: Binding<String>,
                          keyboard: UIKeyboardType = .default,
                          field: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(NotionFont.small())
                .foregroundStyle(themeStore.isEnabled ? LGATheme.textSecondary : Color.inkSecondary)
            TextField(placeholder, text: text)
                .focused($focusedField, equals: field)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .font(NotionFont.body())
                .foregroundStyle(themeStore.isEnabled ? Color.white : Color.inkPrimary)
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 12)
    }

    private func secureFieldRow(label: String,
                                placeholder: String,
                                text: Binding<String>,
                                isVisible: Binding<Bool>,
                                field: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(NotionFont.small())
                    .foregroundStyle(themeStore.isEnabled ? LGATheme.textSecondary : Color.inkSecondary)
                Spacer()
                Button {
                    isVisible.wrappedValue.toggle()
                } label: {
                    Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(themeStore.isEnabled ? LGATheme.textSecondary : Color.inkTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isVisible.wrappedValue ? "隐藏密钥" : "显示密钥")
            }
            Group {
                if isVisible.wrappedValue {
                    TextField(placeholder, text: text)
                } else {
                    SecureField(placeholder, text: text)
                }
            }
            .focused($focusedField, equals: field)
            .submitLabel(.done)
            .onSubmit { focusedField = nil }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .font(NotionFont.body())
            .foregroundStyle(themeStore.isEnabled ? Color.white : Color.inkPrimary)
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 12)
    }

    private func providerPickerRow<Provider: Hashable>(
        label: String,
        selection: Binding<Provider>,
        options: [(Provider, String)]
    ) -> some View {
        HStack(spacing: NotionTheme.space5) {
            Text(label)
                .font(NotionFont.body())
                .foregroundStyle(themeStore.isEnabled ? Color.white : Color.inkPrimary)
            Spacer()
            Menu {
                ForEach(options, id: \.0) { item in
                    Button {
                        selection.wrappedValue = item.0
                    } label: {
                        HStack {
                            Text(item.1)
                            if selection.wrappedValue == item.0 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(displayName(for: selection.wrappedValue, in: options))
                        .font(NotionFont.body())
                        .foregroundStyle(themeStore.isEnabled ? Color.white : Color.accentBlue)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(themeStore.isEnabled ? LGATheme.textSecondary : Color.inkTertiary)
                }
            }
        }
        .padding(.horizontal, NotionTheme.space5)
        .padding(.vertical, 14)
    }

    private func displayName<Provider: Hashable>(
        for value: Provider,
        in options: [(Provider, String)]
    ) -> String {
        options.first { $0.0 == value }?.1 ?? "未启用"
    }

    @ViewBuilder
    private var rowDivider: some View {
        Rectangle()
            .fill(themeStore.isEnabled ? Color.white.opacity(0.06) : Color.divider)
            .frame(height: NotionTheme.borderWidth)
            .padding(.leading, NotionTheme.space5)
    }

    private var savedToastOverlay: some View {
        VStack {
            Spacer()
            Text(copyToast ?? "已保存")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.black.opacity(0.7), in: Capsule())
                .padding(.bottom, 60)
        }
        .transition(.opacity)
    }

    // MARK: - Persistence

    private func loadFromStore() {
        feishuAppID = store.feishuAppID
        feishuAppSecret = store.feishuAppSecret
        feishuOwnerOpenID = store.feishuOwnerOpenID

        // 自动生成的元数据（只读展示）
        generatedAppToken = FeishuConfig.bitableAppToken ?? ""
        generatedTableId  = FeishuConfig.billsTableId ?? ""
        generatedBitableURL = FeishuConfig.bitableURL ?? ""

        textProvider = store.textProvider
        textBaseURL = store.textBaseURL
        textModel = store.textModel
        textAPIKey = store.textAPIKey

        visionProvider = store.visionProvider
        visionBaseURL = store.visionBaseURL
        visionModel = store.visionModel
        visionAPIKey = store.visionAPIKey
    }

    private func save() {
        // 收起键盘，避免保存后输入框仍然占据焦点
        focusedField = nil

        let trimmed: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        store.feishuAppID = trimmed(feishuAppID)
        store.feishuAppSecret = trimmed(feishuAppSecret)
        store.feishuOwnerOpenID = trimmed(feishuOwnerOpenID)

        // 用户手动接管 / 修改了多维表格元数据时同步落地。
        // 写空字符串等价于清空（FeishuConfig 内部按需保存）。
        let appTokenTrim = trimmed(generatedAppToken)
        let tableIdTrim = trimmed(generatedTableId)
        let bitableURLTrim = trimmed(generatedBitableURL)
        FeishuConfig.bitableAppToken = appTokenTrim.isEmpty ? nil : appTokenTrim
        FeishuConfig.billsTableId = tableIdTrim.isEmpty ? nil : tableIdTrim
        FeishuConfig.bitableURL = bitableURLTrim.isEmpty ? nil : bitableURLTrim

        store.textProvider = textProvider
        store.textBaseURL = trimmed(textBaseURL)
        store.textModel = trimmed(textModel)
        store.textAPIKey = trimmed(textAPIKey)

        store.visionProvider = visionProvider
        store.visionBaseURL = trimmed(visionBaseURL)
        store.visionModel = trimmed(visionModel)
        store.visionAPIKey = trimmed(visionAPIKey)

        store.notifyDidChange()

        withAnimation { savedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation { savedToast = false }
        }
    }
}