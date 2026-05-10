//  EmptyRecordsView.swift
//  CoinFlow · M3.2
//
//  无流水时的占位。引导用户点右上 + 新建。

import SwiftUI

struct EmptyRecordsView: View {
    var body: some View {
        VStack(spacing: NotionTheme.space5) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.inkTertiary)
            Text("暂无流水")
                .font(NotionFont.h3())
                .foregroundStyle(Color.inkPrimary)
            Text("按住首页「按住说话」按钮，或敲背面截图记账")
                .font(NotionFont.small())
                .foregroundStyle(Color.inkTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, NotionTheme.space7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(NotionTheme.space8)
    }
}

#if DEBUG
#Preview {
    EmptyRecordsView()
        .background(Color.canvasBG)
        .preferredColorScheme(.dark)
}
#endif
