//  DataImportExportView.swift
//  CoinFlow · M7 · [09-2]
//
//  设计基线：design/screens/09-settings/edit-*.png（该页命名反向，edit=导入/导出子页）+
//           CoinFlowPreview MiscScreensView.SettingsView `.importExport` 模式
//
//  M7 范围：UI 全对齐 + 占位动作（真实 CSV/JSON 导入导出链路 → V2）
//  M7 只完成：
//    - 导出：CSV / JSON 纯内存打包 → UIActivityViewController
//    - 导入：点击后展示"V2 开放"占位 alert（避免误操作破坏本地 DB）

import SwiftUI
import UniformTypeIdentifiers

struct DataImportExportView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var recordCount: Int = 0
    @State private var isExporting: Bool = false
    @State private var exportError: String?
    @State private var exportShareItem: ShareItem?
    @State private var placeholderAlert: PlaceholderAlert?

    private struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }
    private struct PlaceholderAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        ZStack {
            ThemedBackgroundLayer(kind: .settings)
            VStack(spacing: 0) {
                navBar
                ScrollView {
                    VStack(spacing: NotionTheme.space6) {
                        exportSection
                        importSection
                        tipBanner
                        if let err = exportError {
                            Text(err)
                                .font(NotionFont.small())
                                .foregroundStyle(Color.dangerRed)
                                .padding(.horizontal, NotionTheme.space5)
                        }
                        Color.clear.frame(height: NotionTheme.space9)
                    }
                    .padding(.horizontal, NotionTheme.space5)
                    .padding(.top, NotionTheme.space6)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear { loadCount() }
        .sheet(item: $exportShareItem) { item in
            ShareSheet(items: [item.url])
        }
        .alert(item: $placeholderAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("知道了"))
            )
        }
    }

    // MARK: - Nav

    private var navBar: some View {
        ZStack {
            Text("数据导入 / 导出")
                .font(.custom("PingFangSC-Semibold", size: 17))
                .foregroundStyle(Color.inkPrimary)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.inkPrimary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")
                Spacer()
            }
            .padding(.horizontal, NotionTheme.space4)
        }
        .frame(height: NotionTheme.topbarHeight)
        .background(Color.appCanvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.divider).frame(height: NotionTheme.borderWidth)
        }
    }

    // MARK: - Export

    private var exportSection: some View {
        SettingsSection(title: "导出") {
            VStack(spacing: 0) {
                exportRow(
                    icon: "doc.text",
                    title: "导出 CSV（全部流水）",
                    rightText: "\(recordCount) 笔"
                ) {
                    exportCSV()
                }
                innerDivider
                exportRow(
                    icon: "doc.richtext",
                    title: "导出 JSON 备份",
                    rightText: nil
                ) {
                    exportJSON()
                }
                innerDivider
                exportRow(
                    icon: "doc.zipper",
                    title: "完整备份（含截图）",
                    rightText: "V2 开放"
                ) {
                    placeholderAlert = .init(
                        title: "即将上线",
                        message: "完整备份（含截图附件）会在后续版本开放。当前版本可用 CSV / JSON 备份流水数据。"
                    )
                }
            }
        }
    }

    private var importSection: some View {
        SettingsSection(title: "导入") {
            VStack(spacing: 0) {
                exportRow(
                    icon: "doc.badge.plus",
                    title: "从 CSV 导入",
                    rightText: "V2 开放"
                ) {
                    placeholderAlert = .init(
                        title: "即将上线",
                        message: "CSV 导入会校验列名 / 时间格式 / 分类映射，避免破坏本地数据。此链路留到 V2。"
                    )
                }
                innerDivider
                exportRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "从其他记账 App 迁移",
                    rightText: "V2 开放"
                ) {
                    placeholderAlert = .init(
                        title: "即将上线",
                        message: "支持微信记账 / 随手记 / MoneyWiz 格式迁移，V2 启用。"
                    )
                }
            }
        }
    }

    private var tipBanner: some View {
        HStack(alignment: .top, spacing: NotionTheme.space4) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.accentBlue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("数据完整保留")
                    .font(.custom("PingFangSC-Semibold", size: 13))
                    .foregroundStyle(Color.inkPrimary)
                Text("导出不会修改本地数据，可放心操作。CSV 兼容 Notion / Excel / 飞书文档。")
                    .font(NotionFont.small())
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(NotionTheme.space5)
        .background(
            RoundedRectangle(cornerRadius: NotionTheme.radiusLG)
                .fill(Color.accentBlueBG)
        )
    }

    @ViewBuilder
    private func exportRow(icon: String, title: String, rightText: String?,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: NotionTheme.space5) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 24)
                Text(title)
                    .font(NotionFont.body())
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
                if let r = rightText {
                    Text(r)
                        .font(NotionFont.small())
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.inkTertiary)
            }
            .padding(.horizontal, NotionTheme.space5)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isExporting)
        .accessibilityLabel(title)
    }

    private var innerDivider: some View {
        Rectangle().fill(Color.divider).frame(height: 0.5)
            .padding(.leading, NotionTheme.space5 + 24 + NotionTheme.space5)
    }

    // MARK: - Export actions

    private func loadCount() {
        recordCount = (try? SQLiteRecordRepository.shared.list(.init(
            ledgerId: DefaultSeeder.defaultLedgerId,
            includesDeleted: false,
            limit: nil
        )).count) ?? 0
    }

    private func exportCSV() {
        isExporting = true
        defer { isExporting = false }
        do {
            let records = try SQLiteRecordRepository.shared.list(.init(
                ledgerId: DefaultSeeder.defaultLedgerId,
                includesDeleted: false,
                limit: nil
            ))
            let cats = try SQLiteCategoryRepository.shared.list(kind: nil, includeDeleted: true)
            let catById = Dictionary(uniqueKeysWithValues: cats.map { ($0.id, $0) })
            var csv = "occurred_at,category,direction,amount,note\n"
            let fmt = ISO8601DateFormatter()
            for r in records {
                let cat = catById[r.categoryId]
                let dir = cat?.kind == .income ? "income" : "expense"
                let note = (r.note ?? "").replacingOccurrences(of: "\"", with: "\"\"")
                csv += "\(fmt.string(from: r.occurredAt)),"
                csv += "\"\(cat?.name ?? "")\","
                csv += "\(dir),"
                csv += "\(r.amount),"
                csv += "\"\(note)\"\n"
            }
            let url = try writeTempFile(name: "coinflow-export.csv", text: csv)
            exportShareItem = .init(url: url)
            exportError = nil
        } catch {
            exportError = "导出失败：\(error.localizedDescription)"
        }
    }

    private func exportJSON() {
        isExporting = true
        defer { isExporting = false }
        do {
            let records = try SQLiteRecordRepository.shared.list(.init(
                ledgerId: DefaultSeeder.defaultLedgerId,
                includesDeleted: false,
                limit: nil
            ))
            // 只导出稳定字段（避免 E2EE 密文泄漏）
            struct ExportItem: Encodable {
                let id: String
                let occurredAt: Date
                let amount: Decimal
                let categoryId: String
                let note: String?
                let source: String
            }
            let items = records.map { r in
                ExportItem(
                    id: r.id,
                    occurredAt: r.occurredAt,
                    amount: r.amount,
                    categoryId: r.categoryId,
                    note: r.note,
                    source: r.source.rawValue
                )
            }
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(items)
            let url = try writeTempData(name: "coinflow-backup.json", data: data)
            exportShareItem = .init(url: url)
            exportError = nil
        } catch {
            exportError = "导出失败：\(error.localizedDescription)"
        }
    }

    private func writeTempFile(name: String, text: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(name)
        try text.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }
    private func writeTempData(name: String, data: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - ShareSheet（UIKit bridge）

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#if DEBUG
#Preview {
    NavigationStack { DataImportExportView() }
        .preferredColorScheme(.dark)
}
#endif
