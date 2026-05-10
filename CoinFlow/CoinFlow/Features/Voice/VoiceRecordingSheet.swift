//  VoiceRecordingSheet.swift
//  CoinFlow · M5 · §5.5.12 录音态 · M7-Fix14 Siri 风点击切换交互
//
//  ⚠️ 交互模型（重大变更）：
//    用户反馈"按住说话"在 SwiftUI sheet/fullScreenCover 体系下存在系统级手势冲突，
//    多轮尝试（DragGesture / onLongPressGesture / UIKit touchesXxx）都无法 100% 可靠。
//    改为 Siri / 讯飞输入法的"点击切换"模型：
//      - idle 态 → 点一次按钮 = 开始录音
//      - recording 态 → 点一次按钮 = 停止录音并进入 ASR
//      - 顶部 xmark / 下方"取消"按钮 = 放弃本次录音
//
//  视觉：
//    - idle：灰色麦克风按钮，文案"点击开始"
//    - recording：红色渐变按钮 + 波形 + 文案"点击结束"
//    - 档位徽标（本地/云端）保留
//
//  所有倒计时、左滑取消、长按相关已全部移除。

import SwiftUI

struct VoiceRecordingSheet: View {

    @ObservedObject var recorder: AudioRecorder
    var engineLabel: String = "本地"
    /// idle 态：true = 尚未录音；false = 正在录音
    var isIdle: Bool = false
    /// idle 态点击回调 → 父层调 startRecording
    let onPressDown: () -> Void
    /// recording 态点击回调 → 父层调 stopRecordingAndProcess
    let onStop: () -> Void
    /// 取消回调 → 父层调 cancelRecording + dismiss
    let onCancel: () -> Void

    /// 从 engineLabel 派生 pill 颜色：本地档=绿，云端档=蓝
    private var tierDotColor: Color {
        engineLabel.contains("云端") ? Color.accentBlue : Color.statusSuccess
    }
    private var tierShortText: String {
        engineLabel.contains("云端") ? "云端" : "本地"
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: NotionTheme.space4)
            header
                .padding(.top, NotionTheme.space5)
                .padding(.horizontal, NotionTheme.space5)
            waveform
                .frame(height: 48)
                .padding(.top, NotionTheme.space6)
                .padding(.horizontal, NotionTheme.space7)
                .opacity(isIdle ? 0.25 : 1)
            Text(isIdle ? "点击下方按钮开始说话" : "正在聆听…")
                .font(NotionFont.small())
                .foregroundStyle(Color.inkTertiary)
                .padding(.top, NotionTheme.space5)
            recordButton
                .padding(.top, NotionTheme.space6)
            bottomHint
                .padding(.top, NotionTheme.space6)
                .padding(.bottom, NotionTheme.space7)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .top)
        // M7-Fix16：录音态不铺不透明底色，让容器的 .presentationBackground(.ultraThinMaterial)
        //          透出底层主界面虚化效果（对齐 CoinFlowPreview 设计）
        .background(Color.clear)
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text("语音记账")
                .font(.custom("PingFangSC-Semibold", size: 17))
                .foregroundStyle(Color.inkPrimary)

            HStack {
                tierPill
                Spacer()
                Button { onCancel() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }
        }
    }

    private var tierPill: some View {
        HStack(spacing: 4) {
            Circle().fill(tierDotColor).frame(width: 6, height: 6)
            Text(tierShortText)
                .font(NotionFont.micro())
                .foregroundStyle(Color.inkPrimary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Color.hoverBg))
    }

    // MARK: - Waveform

    private var waveform: some View {
        let count = 30
        return HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                let phase = CGFloat(i) / CGFloat(count) * .pi * 2
                let base = (sin(phase) * 0.5 + 0.6)
                let h = max(6, base * CGFloat(recorder.level) * 64)
                Capsule()
                    .fill(Color.inkPrimary.opacity(0.78))
                    .frame(width: 4, height: h)
            }
        }
        .animation(.linear(duration: 0.05), value: recorder.level)
    }

    // MARK: - Record button（Siri 风：点击 toggle）

    private var recordButton: some View {
        // recording 态 = 红色；idle 态 = 灰色；点击切换
        let activated = !isIdle
        let fillColors: [Color] = activated
            ? [Color(red: 1.00, green: 0.353, blue: 0.322),
               Color(red: 0.831, green: 0.251, blue: 0.208)]
            : [Color.inkTertiary.opacity(0.55),
               Color.inkTertiary.opacity(0.35)]
        let ringColor: Color = activated ? Color.dangerRed : Color.inkTertiary
        let shadowColor: Color = activated
            ? Color.dangerRed.opacity(0.45)
            : Color.black.opacity(0.15)

        return Button {
            if isIdle {
                onPressDown()
            } else {
                onStop()
            }
        } label: {
            ZStack {
                // 外环
                Circle()
                    .stroke(ringColor.opacity(activated ? 0.30 : 0.18), lineWidth: 1)
                    .frame(width: 132, height: 132)
                Circle()
                    .stroke(ringColor.opacity(activated ? 0.50 : 0.35), lineWidth: 1.5)
                    .frame(width: 112, height: 112)
                // 内球
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: fillColors),
                            center: .center,
                            startRadius: 4, endRadius: 50
                        )
                    )
                    .frame(width: 92, height: 92)
                    .shadow(color: shadowColor, radius: activated ? 18 : 10, y: 5)
                // 图标：idle = mic，recording = stop
                Image(systemName: activated ? "stop.fill" : "mic.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: activated)
        .accessibilityLabel(isIdle ? "开始录音" : "停止录音")
        .accessibilityHint(isIdle ? "点击开始语音记账" : "点击结束并识别账单内容")
    }

    // MARK: - Bottom hint

    private var bottomHint: some View {
        VStack(spacing: 4) {
            Text(isIdle ? "点击开始" : "点击结束")
                .font(NotionFont.bodyBold())
                .foregroundStyle(Color.inkPrimary)
                .animation(.easeOut(duration: 0.15), value: isIdle)
        }
    }
}
