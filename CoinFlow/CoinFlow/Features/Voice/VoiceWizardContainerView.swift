//  VoiceWizardContainerView.swift
//  CoinFlow · M5
//
//  语音多笔记账的顶层容器（从流水页/首页通过 .sheet 弹出）。
//  按 VM.phase 切换子视图：
//    idle/recording → VoiceRecordingSheet（半屏 .medium detent）
//    asr/parsing    → VoiceParsingView（全屏 .large detent）
//    wizard         → VoiceWizardStepView（全屏）
//    summary        → VoiceSummaryView（全屏）
//    manual         → NewRecordModal（全屏；手动兜底）
//    failed         → 错误提示（全屏）
//
//  M7-Fix15：录音交互已改为"点击切换"（Siri 风），不再有长按手势与 sheet 下拉冲突，
//            因此恢复半屏 .sheet 呈现；用 dynamic detent 在录音态保持 medium，其他阶段升到 large。
//  dragIndicator 仅录音态显示（对齐参考图）；其余阶段隐藏避免误触中断流程。

import SwiftUI

struct VoiceWizardContainerView: View {

    @StateObject private var vm = VoiceWizardViewModel()
    @Environment(\.dismiss) private var dismiss

    /// 当前 detent 选择（录音态 medium，其他 large）
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        Group {
            switch vm.phase {
            case .idle:
                // M7 修复：不自动开始录音；idle 态点击 onPressDown 才 start
                VoiceRecordingSheet(
                    recorder: vm.recorder,
                    engineLabel: engineLabel,
                    isIdle: true,
                    onPressDown: {
                        Task { await vm.startRecording() }
                    },
                    onStop: {
                        Task { await vm.stopRecordingAndProcess() }
                    },
                    onCancel: {
                        vm.cancelRecording()
                        dismiss()
                    }
                )

            case .recording:
                VoiceRecordingSheet(
                    recorder: vm.recorder,
                    engineLabel: engineLabel,
                    isIdle: false,
                    onPressDown: {},
                    onStop: {
                        Task { await vm.stopRecordingAndProcess() }
                    },
                    onCancel: {
                        vm.cancelRecording()
                        dismiss()
                    }
                )

            case .asr:
                VoiceParsingView(stage: .asr, engineLabel: engineLabel)

            case .parsing:
                VoiceParsingView(stage: .parsing, engineLabel: engineLabel)

            case .wizard:
                VoiceWizardStepView(vm: vm, onExit: { dismiss() })

            case .summary:
                VoiceSummaryView(
                    confirmed: vm.confirmedBillsRO,
                    skipped: vm.skippedBillsRO,
                    totalParsed: vm.bills.count,
                    onDone: {
                        // M7 修复问题 4：summary 阶段才统一入库
                        _ = vm.finalizeAllToDatabase()
                        dismiss()
                    }
                )

            case .manual:
                manualFallback

            case .failed(let msg):
                failureView(msg)
            }
        }
        // M7-Fix15：动态 detent —— 录音/idle 半屏，其他阶段全屏；仅录音态显示下拉指示
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(isRecordingPhase ? .visible : .hidden)
        // M7-Fix16：sheet 背景改为 .ultraThinMaterial，透出底层主界面产生虚化效果
        //          （对齐 CoinFlowPreview VoiceWizardView 的背景虚化设计）
        //          需 iOS 16.4+；16.0~16.3 沿用默认不透明背景
        .modifier(BlurredSheetBackground())
        .onChange(of: vm.phase) { newPhase in
            withAnimation(.easeInOut(duration: 0.25)) {
                detent = Self.isRecording(newPhase) ? .medium : .large
            }
        }
    }

    private var isRecordingPhase: Bool {
        Self.isRecording(vm.phase)
    }

    private static func isRecording(_ phase: VoiceWizardViewModel.Phase) -> Bool {
        switch phase {
        case .idle, .recording: return true
        default: return false
        }
    }

    private var engineLabel: String {
        switch vm.usedEngine {
        case .speechLocal:      return "ASR · 本地"
        case .whisper, .aliyun: return "ASR · 云端"
        }
    }

    // MARK: - Manual fallback（手动兜底，双 nav 避免）

    @ViewBuilder
    private var manualFallback: some View {
        VStack(spacing: 0) {
            // 顶部统一 bar：标题 + 关闭；NewRecordModal 内部不再显示自己的 nav（它有自己的，
            // 视觉会略重复；接受这个权衡而非重构 NewRecordModal — 兜底路径用户进入概率低）
            HStack {
                Text("手动记录")
                    .font(NotionFont.h3())
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.inkPrimary)
                        .frame(width: 36, height: 36)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, NotionTheme.space5)
            .frame(height: NotionTheme.topbarHeight)
            .background(Color.appSheetCanvas)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.divider).frame(height: NotionTheme.borderWidth)
            }
            Text("语音识别未能解析出有效账单，请手动补填")
                .font(NotionFont.small())
                .foregroundStyle(Color.inkSecondary)
                .padding(.top, NotionTheme.space5)
            NewRecordModal(onSaved: { _ in dismiss() })
        }
        .themedSheetSurface()
    }

    private func failureView(_ msg: String) -> some View {
        // M7-Fix12：针对"未识别到账单信息"给出重试 + 关闭双按钮，其他错误保持单按钮
        let isRetryable = msg.contains("未识别到")
        return VStack(spacing: NotionTheme.space5) {
            Image(systemName: isRetryable ? "mic.slash" : "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.inkTertiary)
            Text(isRetryable ? "未识别到账单信息" : "无法继续")
                .font(NotionFont.h3())
                .foregroundStyle(Color.inkPrimary)
            Text(isRetryable
                 ? "请再试一次，清晰地说一句含金额的记账内容，例如：午饭花了 30 块"
                 : msg)
                .font(NotionFont.small())
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, NotionTheme.space7)

            if isRetryable {
                HStack(spacing: NotionTheme.space4) {
                    Button {
                        dismiss()
                    } label: {
                        Text("关闭")
                            .font(NotionFont.bodyBold())
                            .foregroundStyle(Color.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                                    .fill(Color.hoverBg)
                            )
                    }.buttonStyle(.plain)

                    Button {
                        // 重置到 idle 等待用户再次按住录音
                        vm.resetToIdle()
                    } label: {
                        Text("重试")
                            .font(NotionFont.bodyBold())
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                                    .fill(Color.accentBlue)
                            )
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, NotionTheme.space6)
            } else {
                Button {
                    dismiss()
                } label: {
                    Text("我知道了")
                        .font(NotionFont.bodyBold())
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                                .fill(Color.accentBlue)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, NotionTheme.space6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedSheetSurface()
    }
}

// MARK: - M7-Fix16 背景虚化 Modifier
//
// SwiftUI 的 .presentationBackground(.ultraThinMaterial) 让 sheet 半透明，
// 底层主界面透过 material 自然产生"磨砂玻璃"虚化效果，对齐 CoinFlowPreview
// VoiceWizardView 的 backgroundBlur 设计（RecordsListView + .blur(6) + 黑色蒙层）。
//
// API 可用性：.presentationBackground 需 iOS 16.4+；项目 deployment target 16.0，
// 对 16.0~16.3 设备降级为默认 sheet 背景（不虚化，但不影响功能）。
//
// 主题感知：
//   - liquidGlass 主题下，由 .themedSheetSurface() 内部叠加 LiquidGlassBackground
//     并通过 .presentationBackground(.clear) 透明化 sheet 容器，让真玻璃效果
//     从 sheet 内层渗透出来；这里跳过 .ultraThinMaterial，避免双重模糊冲淡折射
//   - notion / darkLiquid 主题保持原 ultraThinMaterial 行为
private struct BlurredSheetBackground: ViewModifier {
    @ObservedObject private var store = LGAThemeStore.shared

    func body(content: Content) -> some View {
        if store.kind == .liquidGlass {
            // 玻璃主题：让 .themedSheetSurface 内部的 .presentationBackground(.clear)
            // 主导，避免与 .ultraThinMaterial 叠加成重雾
            content
        } else if #available(iOS 16.4, *) {
            content.presentationBackground(.ultraThinMaterial)
        } else {
            content
        }
    }
}

// MARK: - VM read-only helpers

extension VoiceWizardViewModel {
    var confirmedBillsRO: [ParsedBill] { confirmedBillsDerived }
    var skippedBillsRO: [ParsedBill] { skippedBillsDerived }
}
