//
//  D1QueryView.swift
//  Orange Cloud
//
//  D1 SQL 查询控制台：表入口（→ D1TableView 浏览/编辑）+ 最近/收藏 SQL + SQL 编辑器 + 结果卡片。
//  入口：StorageView 的 D1 段。
//
//  最近执行与收藏按 databaseId 分键落盘（D1QueryHistoryStore），不同库互不串。
//

import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

/// 待删除表的 sheet 载荷（String 非 Identifiable，包一层用于 .sheet(item:)）
private struct DropTarget: Identifiable {
    let id = UUID()
    let name: String
}

// MARK: - SQL 查询控制台

struct D1QueryView: View {

    let database: D1Database
    let session: SessionStore

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: D1QueryViewModel
    private let store = D1QueryHistoryStore.shared
    @State private var showLimitReminder = false
    @State private var tableToDrop: DropTarget?
    @FocusState private var sqlFocused: Bool

    init(database: D1Database, session: SessionStore) {
        self.database = database
        self.session = session
        _viewModel = State(initialValue: D1QueryViewModel(
            service: session.d1Service,
            accountId: session.selectedAccount?.id ?? "",
            databaseId: database.uuid
        ))
    }

    private var canWrite: Bool { auth.hasScope("d1.write") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                tablesIsland

                favoriteChips

                historyChips

                sqlEditor

                if let error = viewModel.error {
                    // D1 免费额度超限时文案已由 ViewModel 补上中文说明（D1FreeTierLimit），原文在后
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .padding(.horizontal, 4)
                    APIErrorDocLink(message: error)
                        .padding(.horizontal, 4)
                }

                ForEach(Array(viewModel.results.enumerated()), id: \.offset) { index, result in
                    D1ResultCard(
                        result: result,
                        index: index,
                        total: viewModel.results.count,
                        originalRowCount: viewModel.originalRowCounts.indices.contains(index)
                            ? viewModel.originalRowCounts[index]
                            : (result.results?.count ?? 0),
                        runToken: viewModel.didRun
                    )
                }
            }
            .padding()
        }
        .background { SkyBackground() }
        .navigationTitle(database.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadTables() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sqlFocused = false
                    // 不带 LIMIT 的 SELECT 在大表上会整包返回：先提醒，确认后再执行
                    if viewModel.needsLimitReminder {
                        showLimitReminder = true
                    } else {
                        Task { await runSQL() }
                    }
                } label: {
                    if viewModel.isRunning {
                        ProgressView()
                    } else {
                        Label("执行", systemImage: "play.fill")
                    }
                }
                .disabled(viewModel.isRunning)
            }
        }
        .sensoryFeedback(.success, trigger: viewModel.didRun)
        .confirmationDialog("查询未带 LIMIT", isPresented: $showLimitReminder, titleVisibility: .visible) {
            Button("仍要执行") {
                Task { await runSQL() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("大表可能返回大量行，造成等待和内存占用。建议加 LIMIT 后执行。")
        }
        .sheet(item: $tableToDrop) { target in
            D1DropTableConfirmView(tableName: target.name, viewModel: viewModel)
        }
    }

    /// 表入口：玻璃岛列表，点按进入 D1TableView 浏览/编辑行
    @ViewBuilder
    private var tablesIsland: some View {
        if !viewModel.tablesLoaded || !viewModel.tables.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("表", systemImage: "tablecells")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                if !viewModel.tablesLoaded {
                    SkeletonIslandRows(rows: 3, icon: .rounded(width: 22, height: 18), showsSubtitle: false)
                } else {
                    VStack(spacing: 0) {
                        ForEach(viewModel.tables, id: \.self) { table in
                            NavigationLink {
                                D1TableView(database: database, tableName: table, session: session)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "tablecells")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 22)
                                    Text(table)
                                        .font(.callout.monospaced())
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, OCLayout.islandPadding)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if canWrite {
                                    Button(role: .destructive) {
                                        tableToDrop = DropTarget(name: table)
                                    } label: {
                                        Label("删除表", systemImage: "trash")
                                    }
                                }
                            }

                            if table != viewModel.tables.last {
                                Divider()
                                    .padding(.leading, 46)
                            }
                        }
                    }
                    .glassIsland(cornerRadius: OCLayout.chipRadius)
                }
            }
        }
    }

    // MARK: - 最近 / 收藏

    private var databaseId: String { database.uuid }

    /// 执行成功才入历史（失败语句不值得回填）
    private func runSQL() async {
        let statement = viewModel.sql
        await viewModel.run()
        if viewModel.error == nil {
            store.record(statement, in: databaseId)
        }
    }

    @ViewBuilder
    private var favoriteChips: some View {
        let items = store.favorites(for: databaseId)
        if !items.isEmpty {
            chipStrip(title: String(localized: "收藏"), icon: "star.fill", items: items)
        }
    }

    @ViewBuilder
    private var historyChips: some View {
        let items = store.history(for: databaseId)
        if !items.isEmpty {
            chipStrip(title: String(localized: "最近"), icon: "clock.arrow.circlepath", items: items)
        }
    }

    /// 一行横滑 chip：点按回填输入框
    private func chipStrip(title: String, icon: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.footnote.bold())
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        Button {
                            viewModel.sql = item
                        } label: {
                            Text(Self.chipLabel(item))
                                .font(.caption.monospaced())
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .glassIsland(cornerRadius: 10)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: Self.chipLabel(item)))
                    }
                }
                .padding(.vertical, 2)
            }
            // SQL 始终 LTR，避免在 RTL 语言下镜像
            .environment(\.layoutDirection, .leftToRight)
        }
    }

    /// chip 上的单行摘要：折掉换行与连续空白，超长截断
    private static func chipLabel(_ sql: String) -> String {
        let flattened = sql
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return flattened.count > 42 ? String(flattened.prefix(42)) + "…" : flattened
    }

    private var isCurrentFavorite: Bool {
        store.isFavorite(viewModel.sql, in: databaseId)
    }

    private var favoriteButton: some View {
        Button {
            store.toggleFavorite(viewModel.sql, in: databaseId)
        } label: {
            Image(systemName: isCurrentFavorite ? "star.fill" : "star")
                .font(.footnote)
                .foregroundStyle(isCurrentFavorite ? Color.ocOrange : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel(Text(
            isCurrentFavorite ? String(localized: "取消收藏此 SQL") : String(localized: "收藏此 SQL")
        ))
    }

    private var sqlEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("SQL", systemImage: "terminal")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                favoriteButton
            }
            TextEditor(text: Binding(
                get: { viewModel.sql },
                set: { viewModel.sql = $0 }
            ))
            .font(.callout.monospaced())
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($sqlFocused)
            .frame(minHeight: 100, maxHeight: 180)
            .scrollContentBackground(.hidden)
            .padding(8)
            .glassIsland(cornerRadius: OCLayout.chipRadius)
            // SQL 始终 LTR，避免在 RTL 语言下镜像
            .environment(\.layoutDirection, .leftToRight)

            if !canWrite {
                Label("当前授权为只读（d1.read），写入语句会被 Cloudflare 拒绝", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 结果卡片

private struct D1ResultCard: View {

    let result: D1QueryResult
    let index: Int
    let total: Int
    /// 截断前的原始行数（ViewModel 只保留前 maxStoredRows 行驻留内存）
    let originalRowCount: Int
    /// 每次成功执行翻转一次，作为 CSV 重新生成的信号（同一视图身份复用时区分新旧结果）
    let runToken: Bool

    private static let maxRows = 100
    /// 单元格展示截断：完整大字段进 Text 会把 CoreText 排版拖上主线程
    private static let cellLimit = 256

    @State private var csvDoc: D1CSVDocument?

    private var rows: [[String: JSONValue]] { result.results ?? [] }

    private var columns: [String] {
        guard let first = rows.first else { return [] }
        return first.keys.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if total > 1 || !rows.isEmpty {
                HStack(spacing: 8) {
                    if total > 1 {
                        Text("语句 \(index + 1)")
                            .font(.footnote.bold())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !rows.isEmpty { exportButton }
                }
            }

            if rows.isEmpty {
                Label(result.success ? String(localized: "执行成功，无返回行") : String(localized: "执行失败"), systemImage: result.success ? "checkmark.circle" : "xmark.circle")
                    .font(.callout)
                    .foregroundStyle(result.success ? .green : .red)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow {
                            ForEach(columns, id: \.self) { column in
                                Text(column)
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                        ForEach(Array(rows.prefix(Self.maxRows).enumerated()), id: \.offset) { _, row in
                            GridRow {
                                ForEach(columns, id: \.self) { column in
                                    Text(cellDisplay(row[column]))
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                // 查询结果表（列名/数据值）保持 LTR 列序
                .environment(\.layoutDirection, .leftToRight)
                if originalRowCount > Self.maxRows {
                    Text("仅显示前 \(Self.maxRows) 行（共 \(originalRowCount) 行）")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if originalRowCount > rows.count {
                    Text("导出为当前已加载的 \(rows.count) 行，需要更多请加 LIMIT / OFFSET 分批查询")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if let meta = result.meta {
                HStack(spacing: 12) {
                    if let duration = meta.duration {
                        Label(String(format: "%.1f ms", duration), systemImage: "clock")
                    }
                    if let read = meta.rowsRead {
                        Label("读 \(read)", systemImage: "eye")
                    }
                    if let written = meta.rowsWritten, written > 0 {
                        Label("写 \(written)", systemImage: "pencil")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassIsland()
        .task(id: resultSignature) {
            guard !rows.isEmpty else {
                csvDoc = nil
                return
            }
            csvDoc = D1CSVDocument(
                filename: "d1-result-\(index + 1).csv",
                text: D1CSV.text(columns: columns, rows: rows)
            )
        }
    }

    /// 导出当前结果集为 CSV（只导已驻留的行，不为导出再发一次无上限查询）。
    /// CSV 文本在 .task 里生成一次并缓存，避免每次 body 求值都重新拼几百行字符串。
    @ViewBuilder
    private var exportButton: some View {
        if let csvDoc {
            ShareLink(item: csvDoc, preview: SharePreview("查询结果 CSV")) {
                Label("导出 CSV", systemImage: "square.and.arrow.up")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ocOrangeText)
        }
    }

    /// 结果内容变化的近似签名：驱动 CSV 重新生成
    private var resultSignature: String {
        "\(index)|\(rows.count)|\(originalRowCount)|\(result.meta?.duration ?? -1)|\(runToken)"
    }

    private func cellDisplay(_ value: JSONValue?) -> String {
        guard let value else { return "NULL" }
        let text = value.displayText
        return text.count > Self.cellLimit ? String(text.prefix(Self.cellLimit)) + "…" : text
    }
}

// MARK: - CSV 导出

/// 结果集 → CSV 文本（RFC 4180）。含逗号 / 双引号 / 换行的字段用双引号包裹，
/// 内部双引号写成两个。NULL 导出为空字段。数值/字节等一律出原值，不做本地化格式化。
private nonisolated enum D1CSV {

    static func text(columns: [String], rows: [[String: JSONValue]]) -> String {
        var lines: [String] = [columns.map(field).joined(separator: ",")]
        lines.reserveCapacity(rows.count + 1)
        for row in rows {
            lines.append(columns.map { field(rawText(row[$0])) }.joined(separator: ","))
        }
        return lines.joined(separator: "\r\n")
    }

    static func rawText(_ value: JSONValue?) -> String {
        guard let value else { return "" }
        if case .null = value { return "" }
        return value.displayText
    }

    static func field(_ text: String) -> String {
        let needsQuoting = text.contains(",") || text.contains("\"")
            || text.contains("\n") || text.contains("\r")
        guard needsQuoting else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// ShareLink 载荷：导出为 .csv 文件
private nonisolated struct D1CSVDocument: Transferable {

    let filename: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { document in
            // BOM：Excel 打开非 BOM 的 UTF-8 CSV 会把中文识别成乱码
            Data([0xEF, 0xBB, 0xBF]) + Data(document.text.utf8)
        }
        .suggestedFileName { $0.filename }
    }
}
