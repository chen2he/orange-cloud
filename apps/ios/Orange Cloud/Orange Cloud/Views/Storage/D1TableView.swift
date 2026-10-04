//
//  D1TableView.swift
//  Orange Cloud
//
//  D1 表浏览器：列结构 + rowid 分页行浏览，点行进编辑器（仅更新变更列）。
//  写操作按 d1.write 门控。
//

import SwiftUI

struct D1TableView: View {

    let database: D1Database
    let tableName: String

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: D1TableViewModel
    @State private var indexVM: D1IndexListViewModel
    @State private var editingRow: [String: JSONValue]?
    @State private var showDenied = false

    init(database: D1Database, tableName: String, session: SessionStore) {
        self.database = database
        self.tableName = tableName
        _viewModel = State(initialValue: D1TableViewModel(
            service: session.d1Service,
            accountId: session.selectedAccount?.id ?? "",
            databaseId: database.uuid,
            tableName: tableName
        ))
        _indexVM = State(initialValue: D1IndexListViewModel(
            service: session.d1Service,
            accountId: session.selectedAccount?.id ?? "",
            databaseId: database.uuid,
            tableName: tableName
        ))
    }

    private var canWrite: Bool { auth.hasScope("d1.write") }

    var body: some View {
        Group {
            if viewModel.rows.isEmpty && viewModel.isLoading {
                ScrollView {
                    gridSkeleton.padding()
                }
            } else if viewModel.rows.isEmpty {
                ScrollView {
                    ContentUnavailableView {
                        Label("空表", systemImage: "tablecells")
                    } description: {
                        Text("这张表里还没有数据")
                    }
                    .padding(.top, 40)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    dataTable

                    Text(canWrite ? String(localized: "点按一行进行编辑。") : String(localized: "当前授权仅限读取（d1.read）。"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)

                    indexCard
                }
                .padding()
            }
        }
        .background { SkyBackground() }
        .navigationTitle(tableName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .task { await indexVM.load() }
        .refreshable { await viewModel.load() }
        .sheet(item: .init(
            get: { editingRow.map { EditingRowBox(row: $0) } },
            set: { if $0 == nil { editingRow = nil } }
        )) { box in
            D1RowEditorView(viewModel: viewModel, row: box.row, canWrite: canWrite)
        }
        .alert("权限不足", isPresented: $showDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含 D1 写权限（d1.write）。\n请在设置中退出登录后重新授权以启用此功能。")
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil && editingRow == nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            apiErrorDocButton(for: viewModel.error)
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
        .sensoryFeedback(.success, trigger: viewModel.didSave)
    }

    // MARK: - 索引卡（PRAGMA index_list，只读补充信息）

    @ViewBuilder
    private var indexCard: some View {
        if indexVM.loaded && !indexVM.indexes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("索引", systemImage: "list.bullet.indent")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                VStack(spacing: 6) {
                    ForEach(indexVM.indexes) { index in
                        indexRow(index)
                        if index.id != indexVM.indexes.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(OCLayout.islandPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassIsland(cornerRadius: OCLayout.chipRadius)
            }
        }
    }

    private func indexRow(_ index: D1IndexInfo) -> some View {
        HStack(spacing: 8) {
            Text(index.name)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if index.isUnique {
                Text(verbatim: "UNIQUE")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.ocOrangeText)
            }
            Text(index.originLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 网格骨架（表头 + 数据行的占位条）

    private var gridSkeleton: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
            GridRow {
                ForEach(0..<4, id: \.self) { column in
                    VStack(alignment: .leading, spacing: 4) {
                        SkeletonBlock(width: 44 + CGFloat((column * 23) % 30), height: 10)
                        SkeletonBlock(width: 30, height: 7)
                    }
                }
            }
            .padding(.vertical, 6)

            Divider()

            ForEach(0..<8, id: \.self) { row in
                GridRow {
                    ForEach(0..<4, id: \.self) { column in
                        SkeletonBlock(width: 36 + CGFloat(((row + column) * 31) % 40), height: 10)
                    }
                }
                .padding(.vertical, 9)
                if row < 7 {
                    Divider()
                }
            }
        }
        .padding(OCLayout.islandPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassIsland(cornerRadius: OCLayout.chipRadius)
        .skeletonPulse()
    }

    // MARK: - 数据表格（双轴滚动 + LazyVStack：行滚出屏即回收，大表不撑爆布局与内存）

    private var dataTable: some View {
        ScrollView([.vertical, .horizontal], showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
                headerRow
                    .padding(.vertical, 6)

                Divider()

                ForEach(Array(viewModel.rows.enumerated()), id: \.offset) { index, row in
                    rowView(row)
                    if index < viewModel.rows.count - 1 {
                        Divider()
                    }
                }

                tableFooter
            }
            .padding(OCLayout.islandPadding)
        }
        .glassIsland(cornerRadius: OCLayout.chipRadius)
        // 数据表格保持 LTR 列序（单元格内的阿拉伯语文本仍由 bidi 正确渲染）
        .environment(\.layoutDirection, .leftToRight)
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(viewModel.columns) { column in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text(column.name)
                            .font(.caption.bold())
                        if column.isPrimaryKey {
                            Image(systemName: "key.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.ocOrangeText)
                        }
                    }
                    Text(column.type.isEmpty ? "—" : column.type)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(width: columnWidth(column), alignment: .leading)
            }
        }
    }

    /// 懒加载行用定宽列（首页采样算定），保证行间对齐、免全局布局
    private func rowView(_ row: [String: JSONValue]) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(viewModel.columns) { column in
                Text(D1TableViewModel.displayText(for: row[column.name]))
                    .font(.caption.monospaced())
                    .foregroundStyle(isNull(row[column.name]) ? .tertiary : .primary)
                    .lineLimit(1)
                    .frame(width: columnWidth(column), alignment: .leading)
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { tapRow(row) }
    }

    /// 行尾 sentinel：滚到底自动翻页；到行数上限后停下并给出筛选指引
    @ViewBuilder
    private var tableFooter: some View {
        if viewModel.reachedCap {
            Text("已加载 \(D1TableViewModel.maxLoadedRows) 行，请在查询控制台用 WHERE 条件继续筛选")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 10)
        } else if viewModel.hasMore {
            HStack(spacing: 8) {
                ProgressView()
                Text("加载更多")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.vertical, 10)
            .onAppear {
                Task { await viewModel.loadMore() }
            }
        }
    }

    private func columnWidth(_ column: D1Column) -> CGFloat {
        viewModel.columnWidths[column.name] ?? 120
    }

    /// 点行编辑：列表里大字段是截断的，先按 rowid 取整行完整值再开编辑器
    private func tapRow(_ row: [String: JSONValue]) {
        guard canWrite else {
            showDenied = true
            return
        }
        Task {
            if let full = await viewModel.fullRow(from: row) {
                editingRow = full
            }
        }
    }

    private func isNull(_ value: JSONValue?) -> Bool {
        if case .null = value { return true }
        return value == nil
    }
}

/// sheet(item:) 需要 Identifiable 的包装
private struct EditingRowBox: Identifiable {
    let row: [String: JSONValue]
    var id: String { row[D1TableViewModel.rowidKey]?.displayText ?? UUID().uuidString }
}

// MARK: - 行编辑器

private struct D1RowEditorView: View {

    let viewModel: D1TableViewModel
    let row: [String: JSONValue]
    let canWrite: Bool

    /// 超过此长度的文本字段转只读预览（TextField 排大文本会卡主线程），改值走查询控制台
    private static let largeFieldLimit = 8_000

    @Environment(\.dismiss) private var dismiss
    @State private var fields: [String: String] = [:]
    @State private var showDeleteConfirm = false

    private var rowid: String {
        row[D1TableViewModel.rowidKey]?.displayText ?? ""
    }

    private var editableColumns: [D1Column] {
        viewModel.columns.filter { $0.name != D1TableViewModel.rowidKey }
    }

    /// 仅变更的列（原值为 NULL 且输入仍为空 → 视为未变更）
    private var changes: [String: String] {
        var result: [String: String] = [:]
        for column in editableColumns {
            let original = row[column.name]
            let originalText: String? = {
                guard let original, !isNull(original) else { return nil }
                return original.displayText
            }()
            let current = fields[column.name] ?? ""
            if originalText == nil {
                if !current.isEmpty { result[column.name] = current }
            } else if current != originalText {
                result[column.name] = current
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(editableColumns) { column in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(column.name)
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                if column.isPrimaryKey {
                                    Image(systemName: "key.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(Color.ocOrangeText)
                                }
                                if !column.type.isEmpty {
                                    Text(column.type)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            inputField(for: column)
                        }
                    }
                } header: {
                    Text("rowid \(rowid)")
                } footer: {
                    Text("只会提交修改过的列。原值为 NULL 的列留空则保持 NULL。")
                }

                if canWrite {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("删除此行", systemImage: "trash")
                        }
                    }
                }

                if let error = viewModel.error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("编辑行")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if await viewModel.updateRow(rowid: rowid, changes: changes) {
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                        } else {
                            Text("保存").fontWeight(.semibold)
                        }
                    }
                    .disabled(!canWrite || changes.isEmpty || viewModel.isSaving)
                }
            }
            .onAppear {
                guard fields.isEmpty else { return }
                for column in editableColumns {
                    if let value = row[column.name], !isNull(value) {
                        fields[column.name] = value.displayText
                    }
                }
            }
            .confirmationDialog("删除此行？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    Task {
                        if await viewModel.deleteRow(rowid: rowid) {
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("此操作不可撤销。")
            }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
    }

    private func isNull(_ value: JSONValue?) -> Bool {
        if case .null = value { return true }
        return value == nil
    }

    // MARK: - 按列类型分发输入组件

    /// 列声明类型 → 对应输入组件；底层统一写回 fields 字符串，changes 判定逻辑不变
    @ViewBuilder
    private func inputField(for column: D1Column) -> some View {
        let binding = Binding(
            get: { fields[column.name] ?? "" },
            set: { fields[column.name] = $0 }
        )
        let originalIsNull = isNull(row[column.name])

        switch D1InputKind.detect(column.type) {
        case .integer, .real:
            TextField(originalIsNull ? "NULL" : "", text: binding)
                .font(.callout.monospaced())
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        case .boolean:
            booleanField(binding: binding, originalIsNull: originalIsNull, label: column.name)
        case .datetime:
            dateField(binding: binding, originalIsNull: originalIsNull, includesTime: true, label: column.name)
        case .date:
            dateField(binding: binding, originalIsNull: originalIsNull, includesTime: false, label: column.name)
        case .text:
            let current = binding.wrappedValue
            if current.count > Self.largeFieldLimit {
                VStack(alignment: .leading, spacing: 4) {
                    Text(current.prefix(300) + "…")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                    Text("字段过大（\(current.count) 字符），请在查询控制台修改")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                TextField(originalIsNull ? "NULL" : "", text: binding, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.callout.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

    /// 布尔列：Toggle 写 1 / 0；原值 NULL 时可恢复
    private func booleanField(binding: Binding<String>, originalIsNull: Bool, label: String) -> some View {
        HStack(spacing: 10) {
            Text(binding.wrappedValue.isEmpty ? "NULL" : binding.wrappedValue)
                .font(.callout.monospaced())
                .foregroundStyle(binding.wrappedValue.isEmpty ? .tertiary : .primary)
            Spacer()
            if originalIsNull && !binding.wrappedValue.isEmpty {
                restoreNullButton(binding: binding)
            }
            Toggle("", isOn: Binding(
                get: { isTruthy(binding.wrappedValue) },
                set: { binding.wrappedValue = $0 ? "1" : "0" }
            ))
            .labelsHidden()
            .accessibilityLabel(label)
        }
    }

    /// 时间列：可识别格式用 DatePicker（UTC 口径，写回保持原存储格式），
    /// NULL 一键填入当前时间，无法识别时回退文本编辑。
    @ViewBuilder
    private func dateField(binding: Binding<String>, originalIsNull: Bool, includesTime: Bool, label: String) -> some View {
        let current = binding.wrappedValue
        if current.isEmpty {
            Button {
                binding.wrappedValue = D1DateValue.format(
                    Date(), as: includesTime ? .sqlDateTime : .sqlDate
                )
            } label: {
                Label(
                    originalIsNull ? String(localized: "NULL · 点按填入当前时间") : String(localized: "填入当前时间"),
                    systemImage: "calendar.badge.plus"
                )
                .font(.callout)
                .foregroundStyle(Color.ocOrange)
            }
            .buttonStyle(.plain)
        } else if let parsed = D1DateValue.parse(current) {
            HStack(spacing: 8) {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { D1DateValue.parse(binding.wrappedValue)?.date ?? parsed.date },
                        set: { binding.wrappedValue = D1DateValue.format($0, as: parsed.format) }
                    ),
                    displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date]
                )
                .labelsHidden()
                .accessibilityLabel(label)
                .environment(\.timeZone, .gmt)   // 与 SQLite 存储口径一致
                Spacer()
                if originalIsNull {
                    restoreNullButton(binding: binding)
                }
            }
            Text(verbatim: "\(current) · UTC")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        } else {
            TextField("", text: binding)
                .font(.callout.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Text("未识别的时间格式，按文本编辑")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func restoreNullButton(binding: Binding<String>) -> some View {
        Button {
            binding.wrappedValue = ""
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("恢复 NULL"))
    }

    private func isTruthy(_ value: String) -> Bool {
        value == "1" || value.lowercased() == "true"
    }
}

// MARK: - 列类型亲和性

/// SQLite 声明类型 → 输入组件的分发依据
private nonisolated enum D1InputKind {
    case integer, real, boolean, datetime, date, text

    static func detect(_ declaredType: String) -> D1InputKind {
        let type = declaredType.uppercased()
        if type.contains("BOOL") { return .boolean }
        if type.contains("DATETIME") || type.contains("TIMESTAMP") { return .datetime }
        if type.contains("DATE") { return .date }
        if type.contains("INT") { return .integer }
        if type.contains("REAL") || type.contains("FLOA") || type.contains("DOUB")
            || type.contains("DEC") || type.contains("NUM") { return .real }
        return .text
    }
}

// MARK: - 时间值解析（识别存储格式，编辑后按原格式写回）

private enum D1DateFormat {
    case sqlDateTime        // 2026-06-12 08:30:00（SQLite CURRENT_TIMESTAMP）
    case sqlDate            // 2026-06-12
    case iso8601            // 2026-06-12T08:30:00Z
    case iso8601Fractional  // 2026-06-12T08:30:00.000Z
    case epochSeconds       // 10 位 Unix 秒
    case epochMillis        // 13 位 Unix 毫秒
}

private enum D1DateValue {

    private static let sqlDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        return formatter
    }()

    private static let sqlDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func parse(_ text: String) -> (date: Date, format: D1DateFormat)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let date = sqlDateTime.date(from: trimmed) { return (date, .sqlDateTime) }
        if let date = sqlDate.date(from: trimmed) { return (date, .sqlDate) }
        if let date = iso8601Fractional.date(from: trimmed) { return (date, .iso8601Fractional) }
        if let date = iso8601.date(from: trimmed) { return (date, .iso8601) }
        if trimmed.allSatisfy(\.isNumber) {
            if trimmed.count == 13, let millis = Double(trimmed) {
                return (Date(timeIntervalSince1970: millis / 1000), .epochMillis)
            }
            if trimmed.count == 10, let seconds = Double(trimmed) {
                return (Date(timeIntervalSince1970: seconds), .epochSeconds)
            }
        }
        return nil
    }

    static func format(_ date: Date, as format: D1DateFormat) -> String {
        switch format {
        case .sqlDateTime:       sqlDateTime.string(from: date)
        case .sqlDate:           sqlDate.string(from: date)
        case .iso8601:           Self.iso8601.string(from: date)
        case .iso8601Fractional: Self.iso8601Fractional.string(from: date)
        case .epochSeconds:      String(Int(date.timeIntervalSince1970))
        case .epochMillis:       String(Int(date.timeIntervalSince1970 * 1000))
        }
    }
}
