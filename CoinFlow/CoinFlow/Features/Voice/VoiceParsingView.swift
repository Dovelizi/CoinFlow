//  VoiceParsingView.swift
//  CoinFlow · M5 · §5.5.12 解析中
//
//  端到端过渡页：ASR 完成 → LLM 拆分 → 向导。
//  视觉基线：CoinFlowPreview VoiceParsingView（三段阶段指示）。

import SwiftUI

struct VoiceParsingView: View {

    /// 当前正在做 "asr"（转写中）还是 "parse"（拆分中）
    let stage: Stage
    let engineLabel: String       // "ASR · 本地" / "ASR · 云端"

    enum Stage { case asr, parsing }

    var body: some View {
        VStack(spacing: NotionTheme.space7) {
            tierBadge
            ProgressView()
                .controlSize(.large)
                .scaleEffect(1.4)
                .tint(Color.inkSecondary)
                .padding(.top, NotionTheme.space7)
            VStack(spacing: NotionTheme.space3) {
                Text(primaryTitle)
                    .font(NotionFont.h3())
                    .foregroundStyle(Color.inkPrimary)
                Text(subtitleText)
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
            }
            stageList
                .padding(.top, NotionTheme.space7)
                .padding(.horizontal, NotionTheme.space6)
            Spacer()
        }
        .padding(.top, NotionTheme.space8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedSheetSurface()
    }

    private var primaryTitle: String {
        switch stage {
        case .asr:     return "正在转写…"
        case .parsing: return "正在拆分账单…"
        }
    }

    private var subtitleText: String {
        switch stage {
        case .asr:     return "将您的口述转为文字"
        case .parsing: return "分析多笔账结构并做字段缺失检测"
        }
    }

    private var tierBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: engineLabel.contains("云端") ? "cloud" : "iphone.gen3")
                .font(.system(size: 11, weight: .semibold))
            Text(engineLabel)
                .font(NotionFont.micro())
        }
        .foregroundStyle(Color.accentBlue)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(Color.accentBlueBG))
    }

    private var stageList: some View {
        VStack(alignment: .leading, spacing: NotionTheme.space5) {
            // Stage 1：音频转文字
            stageRow(icon: "waveform", label: "音频转文字",
                     done: stage != .asr, active: stage == .asr)
            // Stage 2：拆分多笔账单
            // asr 阶段 = pending（灰）；parsing 阶段 = active（蓝 ProgressView）
            stageRow(icon: "scissors", label: "拆分多笔账单",
                     done: false, active: stage == .parsing)
            // Stage 3：字段缺失检测
            // asr 阶段 = pending；parsing 阶段 = 视觉上与 stage 2 同步 active（M5 里两步串行）
            stageRow(icon: "checkmark.circle", label: "字段缺失检测",
                     done: false, active: stage == .parsing)
        }
    }

    @ViewBuilder
    private func stageRow(icon: String, label: String, done: Bool, active: Bool) -> some View {
        HStack(spacing: NotionTheme.space5) {
            ZStack {
                Circle()
                    .fill(done
                          ? Color(hex: "#448361").opacity(0.18)
                          : (active ? Color.accentBlueBG : Color.hoverBg))
                    .frame(width: 32, height: 32)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: "#448361"))
                } else if active {
                    ProgressView().scaleEffect(0.7).tint(Color.accentBlue)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.inkTertiary)
                }
            }
            Text(label)
                .font(NotionFont.body())
                .foregroundStyle(active || done ? Color.inkPrimary : Color.inkTertiary)
            Spacer()
            if done {
                Text("完成")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color(hex: "#448361"))
            } else if active {
                Text("进行中…")
                    .font(NotionFont.micro())
                    .foregroundStyle(Color.accentBlue)
            }
        }
    }
}
