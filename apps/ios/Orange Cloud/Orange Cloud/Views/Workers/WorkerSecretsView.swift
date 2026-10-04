//
//  WorkerSecretsView.swift
//  Orange Cloud
//
//  Worker 密钥（secret_text）+ 环境变量（plain_text）管理 + 只读绑定清单。
//  写操作按 workers-scripts.write 门控；改任一变量都整组回写（其余 inherit），不丢既有绑定。
//

import SwiftUI

struct WorkerSecretsView: View {

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: WorkerBindingsViewModel
    @State private var sheet: EditorSheet?
    @State private var secretToDelete: WorkerSecret?
    @State private var variableToDelete: WorkerBinding?
    @State private var bindingToUnbind: WorkerBinding?

    init(accountId: String, scriptName: String, session: SessionStore) {
        _viewModel = State(initialValue: WorkerBindingsViewModel(
            service: session.workerService, d1Service: session.d1Service, kvService: session.kvService,
            r2Service: session.r2Service, accountId: accountId, scriptName: scriptName
        ))
    }

    private var canWrite:   Bool { auth.hasScope("workers-scripts.write") }
    private var canReadD1:  Bool { auth.hasScope("d1.read") }
    private var canReadKV:  Bool { auth.hasScope("workers-kv-storage.read") }
    private var canReadR2:  Bool { auth.hasScope("workers-r2.read") }
    /// 能读到至少一类资源才提供快速绑定入口
    private var canBind:    Bool { canWrite && (canReadD1 || canReadKV || canReadR2) }

    var body: some View {
        Group {
            if !viewModel.loaded && viewModel.isLoading {
                SkeletonList(rows: 5, icon: .none, trailing: true)
            } else {
                List {
                    secretsSection
                    variablesSection
                    if !viewModel.otherBindings.isEmpty || canBind {
                        otherSection
                    }
                }
                .scrollContentBackground(.hidden)
                .refreshable { await viewModel.load() }
            }
        }
        .background { SkyBackground() }
        .navigationTitle("变量与密钥")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canWrite {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("批量导入 JSON", systemImage: "arrow.down.doc") {
                        sheet = .bulkImport
                    }
                }
            }
        }
        .confirmationDialog(
            secretToDelete.map { String(localized: "删除密钥「\($0.name)」？") } ?? "",
            isPresented: Binding(get: { secretToDelete != nil }, set: { if !$0 { secretToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let s = secretToDelete { Task { await viewModel.deleteSecret(s) } }
            }
        } message: {
            Text("密钥值无法读回，删除后需重新设置，不可撤销。")
        }
        .confirmationDialog(
            variableToDelete.map { String(localized: "删除变量「\($0.name)」？") } ?? "",
            isPresented: Binding(get: { variableToDelete != nil }, set: { if !$0 { variableToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let v = variableToDelete { Task { await viewModel.deleteVariable(v) } }
            }
        }
        .confirmationDialog(
            bindingToUnbind.map { String(localized: "解除绑定「\($0.name)」？") } ?? "",
            isPresented: Binding(get: { bindingToUnbind != nil }, set: { if !$0 { bindingToUnbind = nil } }),
            titleVisibility: .visible
        ) {
            Button("解除绑定", role: .destructive) {
                if let b = bindingToUnbind { Task { await viewModel.unbindResource(b) } }
            }
        } message: {
            Text("仅解除该 Worker 与此资源的绑定，不会删除资源本身。")
        }
        .task { if !viewModel.loaded { await viewModel.load() } }
        .sheet(item: $sheet) { kind in
            switch kind {
            case .bulkImport:
                WorkerBulkImportSheet(viewModel: viewModel)
            case .bindResource:
                WorkerBindResourceSheet(viewModel: viewModel, canReadD1: canReadD1, canReadKV: canReadKV, canReadR2: canReadR2)
            default:
                WorkerValueEditorSheet(kind: kind, viewModel: viewModel)
            }
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil && sheet == nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            apiErrorDocButton(for: viewModel.error)
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: - 密钥

    private var secretsSection: some View {
        Section {
            if viewModel.secrets.isEmpty {
                Text("暂无密钥").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.secrets) { secret in
                    HStack(spacing: 12) {
                        TintIcon(systemImage: "key.fill", color: .ocOrange)
                        Text(secret.name).font(.callout.weight(.medium))
                        Spacer()
                    }
                    .swipeActions(edge: .trailing) {
                        if canWrite {
                            Button("删除", role: .destructive) {
                                secretToDelete = secret
                            }
                        }
                    }
                }
            }
            if canWrite {
                Button {
                    sheet = .secret
                } label: {
                    Label("添加密钥", systemImage: "plus")
                }
            }
        } header: {
            Text("密钥")
        } footer: {
            Text(canWrite
                 ? String(localized: "密钥值出于安全无法读取，列表只显示名称。同名添加即覆盖。")
                 : String(localized: "当前授权仅可查看（缺少 workers-scripts.write）。"))
        }
        .glassRow()
    }

    // MARK: - 环境变量

    private var variablesSection: some View {
        Section {
            if viewModel.variables.isEmpty {
                Text("暂无变量").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.variables) { binding in
                    Button {
                        if canWrite { sheet = .variable(binding) }
                    } label: {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "textformat", color: .ocOrange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(binding.name).font(.callout.weight(.medium)).foregroundStyle(.primary)
                                Text(binding.text ?? "")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if canWrite {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .disabled(!canWrite)
                    .swipeActions(edge: .trailing) {
                        if canWrite {
                            Button("删除", role: .destructive) {
                                variableToDelete = binding
                            }
                        }
                    }
                }
            }
            if canWrite {
                Button {
                    sheet = .variable(nil)
                } label: {
                    Label("添加变量", systemImage: "plus")
                }
            }
        } header: {
            Text("环境变量")
        } footer: {
            Text("明文变量（plain_text），可读可改。改任一项不影响其它绑定。")
        }
        .glassRow()
    }

    // MARK: - 资源绑定（D1 / KV 可增删，其余只读）

    private var otherSection: some View {
        Section {
            if viewModel.otherBindings.isEmpty {
                Text("暂无资源绑定").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.otherBindings) { binding in
                    HStack(spacing: 12) {
                        TintIcon(systemImage: binding.isQuickManaged ? "cube.fill" : "cube",
                                 color: binding.isQuickManaged ? .ocOrange : .gray)
                        Text(binding.name).font(.callout)
                        Spacer()
                        Text(binding.typeLabel).font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        if canWrite && binding.isQuickManaged {
                            Button("解除", role: .destructive) {
                                bindingToUnbind = binding
                            }
                        }
                    }
                }
            }
            if canBind {
                Button {
                    sheet = .bindResource
                } label: {
                    Label("绑定 D1 / KV / R2", systemImage: "plus")
                }
            }
        } header: {
            Text("资源绑定")
        } footer: {
            Text(canBind
                 ? String(localized: "可绑定既有 D1 数据库 / KV 命名空间 / R2 存储桶；队列、Durable Object 等其它资源仍为只读，请用 Wrangler 或 Dashboard。")
                 : String(localized: "KV / D1 / R2 等资源绑定在此查看，编辑请用 Wrangler 或 Dashboard。"))
        }
        .glassRow()
    }
}

// MARK: - 添加/编辑弹窗

/// 弹窗类型：新增密钥 / 新增或编辑变量（编辑时锁定名称）/ 批量导入 JSON
private enum EditorSheet: Identifiable {
    case secret
    case variable(WorkerBinding?)
    case bulkImport
    case bindResource

    var id: String {
        switch self {
        case .secret:            "secret"
        case .variable(let b):   "var-\(b?.name ?? "new")"
        case .bulkImport:        "bulk"
        case .bindResource:      "bind"
        }
    }
}

private struct WorkerValueEditorSheet: View {

    let kind: EditorSheet
    let viewModel: WorkerBindingsViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var value = ""

    private var isSecret: Bool { if case .secret = kind { return true }; return false }

    /// 编辑既有变量时锁定名称
    private var lockedName: String? {
        if case .variable(let binding) = kind, let binding { return binding.name }
        return nil
    }

    private var nameValid: Bool {
        let target = lockedName ?? name
        return target.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
    }

    private var canSave: Bool {
        nameValid && !value.isEmpty && !viewModel.isSaving
    }

    private var title: String {
        if isSecret { return String(localized: "添加密钥") }
        return lockedName == nil ? String(localized: "添加变量") : String(localized: "编辑变量")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let lockedName {
                        Text(lockedName).font(.callout.monospaced()).foregroundStyle(.secondary)
                    } else {
                        TextField("NAME", text: $name)
                            .font(.callout.monospaced())
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("名称")
                } footer: {
                    if lockedName == nil {
                        Text("字母、数字、下划线，且不以数字开头。")
                    }
                }

                Section {
                    if isSecret {
                        SecureField("值", text: $value)
                            .font(.callout.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        TextField("值", text: $value, axis: .vertical)
                            .font(.callout.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .lineLimit(1...6)
                    }
                } header: {
                    Text(isSecret ? String(localized: "值（保存后不可读取）") : String(localized: "值"))
                }

                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if viewModel.isSaving { ProgressView() } else { Text("保存").fontWeight(.semibold) }
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .onAppear {
                if case .variable(let binding) = kind, let binding {
                    value = binding.text ?? ""
                }
            }
        }
    }

    private func save() async {
        viewModel.error = nil
        let ok: Bool
        if isSecret {
            ok = await viewModel.addSecret(name: name, text: value)
        } else {
            ok = await viewModel.setVariable(name: lockedName ?? name, value: value)
        }
        if ok { dismiss() }
    }
}

// MARK: - 批量导入 JSON

/// 导入目标：粘贴的 JSON 键值对作为变量或密钥写入
private enum BulkImportTarget: String, CaseIterable, Identifiable {
    case variable, secret
    var id: String { rawValue }
    var label: LocalizedStringKey { self == .variable ? "变量" : "密钥" }
}

/// 解析失败原因（携带可读信息，供 Result 使用）
private struct BulkParseError: Error {
    let message: String
}

private struct WorkerBulkImportSheet: View {

    let viewModel: WorkerBindingsViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var target: BulkImportTarget = .variable
    @State private var jsonText = ""

    /// 解析结果：成功给出 (name, value) 列表，失败给出可读错误
    private var parsed: Result<[(name: String, value: String)], BulkParseError> {
        Self.parse(jsonText)
    }

    private var pairs: [(name: String, value: String)] {
        if case .success(let p) = parsed { return p }
        return []
    }

    private var parseError: String? {
        if case .failure(let e) = parsed { return e.message }
        return nil
    }

    private var hasInput: Bool {
        !jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canImport: Bool { !pairs.isEmpty && !viewModel.isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("导入为", selection: $target) {
                        ForEach(BulkImportTarget.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(target == .secret
                         ? String(localized: "作为密钥一次性写入；同名将被覆盖，保存后不可读取。")
                         : String(localized: "作为明文变量一次性写入；同名将被覆盖，不影响其它绑定。"))
                }

                Section {
                    TextEditor(text: $jsonText)
                        .font(.callout.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 180)
                } header: {
                    Text("JSON")
                } footer: {
                    Text("粘贴一个 JSON 对象，键为名称、值为字符串或数字，例如：\n{\n  \"API_KEY\": \"abc123\",\n  \"MAX_RETRY\": 3\n}")
                }

                if hasInput, let parseError {
                    Section { Text(parseError).font(.footnote).foregroundStyle(.red) }
                } else if !pairs.isEmpty {
                    Section { Text("将导入 \(pairs.count) 项").font(.callout).foregroundStyle(.secondary) }
                }

                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("批量导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await performImport() }
                    } label: {
                        if viewModel.isSaving { ProgressView() } else { Text("导入").fontWeight(.semibold) }
                    }
                    .disabled(!canImport)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
    }

    private func performImport() async {
        viewModel.error = nil
        let ok: Bool
        switch target {
        case .variable: ok = await viewModel.bulkImportVariables(pairs)
        case .secret:   ok = await viewModel.bulkImportSecrets(pairs)
        }
        if ok { dismiss() }
    }

    /// 解析一个扁平 JSON 对象为 (name, value) 列表。
    /// 键须符合环境变量命名（字母/数字/下划线，不以数字开头）；值接受字符串、数字、布尔（转字符串）。
    private static func parse(_ text: String) -> Result<[(name: String, value: String)], BulkParseError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .success([]) }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return .failure(BulkParseError(message: String(localized: "不是有效的 JSON")))
        }
        guard let dict = object as? [String: Any] else {
            return .failure(BulkParseError(message: String(localized: "需要一个 JSON 对象，形如 {\"KEY\": \"值\"}")))
        }
        let keyPattern = "^[A-Za-z_][A-Za-z0-9_]*$"
        var pairs: [(name: String, value: String)] = []
        var invalidKeys: [String] = []
        for (key, raw) in dict {
            guard key.range(of: keyPattern, options: .regularExpression) != nil else {
                invalidKeys.append(key)
                continue
            }
            let value: String
            if let s = raw as? String {
                value = s
            } else if let n = raw as? NSNumber {
                value = CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : n.stringValue
            } else {
                return .failure(BulkParseError(message: String(localized: "键「\(key)」的值必须是字符串或数字")))
            }
            pairs.append((name: key, value: value))
        }
        if !invalidKeys.isEmpty {
            let list = invalidKeys.sorted().joined(separator: ", ")
            return .failure(BulkParseError(message: String(localized: "以下名称非法（须字母 / 数字 / 下划线，且不以数字开头）：\(list)")))
        }
        return .success(pairs.sorted { $0.name < $1.name })
    }
}

// MARK: - 快速绑定 D1 / KV / R2

/// 绑定既有 D1 数据库 / KV 命名空间：选类型 → 选资源 → 填绑定变量名 → PATCH settings（其余绑定 inherit）
private struct WorkerBindResourceSheet: View {

    let viewModel: WorkerBindingsViewModel
    let canReadD1: Bool
    let canReadKV: Bool
    let canReadR2: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var kind: ResourceKind = .kv
    @State private var selectedId = ""
    @State private var name = ""
    @State private var nameEditedManually = false

    private enum ResourceKind: String, CaseIterable, Identifiable {
        case kv, d1, r2
        var id: String { rawValue }
        var label: String {
            switch self {
            case .kv: "KV"
            case .d1: "D1"
            case .r2: "R2"
            }
        }
    }

    /// 仅展示有读权限的类型
    private var availableKinds: [ResourceKind] {
        var kinds: [ResourceKind] = []
        if canReadKV { kinds.append(.kv) }
        if canReadD1 { kinds.append(.d1) }
        if canReadR2 { kinds.append(.r2) }
        return kinds
    }

    /// 当前类型下可选资源：(id, 显示名)。R2 按桶名引用，故 id 即桶名。
    private var options: [(id: String, title: String)] {
        switch kind {
        case .kv: viewModel.kvNamespaces.map { ($0.id, $0.title) }
        case .d1: viewModel.d1Databases.map { ($0.uuid, $0.name) }
        case .r2: viewModel.r2Buckets.map { ($0.name, $0.name) }
        }
    }

    /// 无可选资源时的空态文案
    private var emptyText: String {
        switch kind {
        case .kv: String(localized: "该账号暂无 KV 命名空间")
        case .d1: String(localized: "该账号暂无 D1 数据库")
        case .r2: String(localized: "该账号暂无 R2 存储桶")
        }
    }

    /// 资源选择器行标题
    private var pickerLabel: String {
        switch kind {
        case .kv: String(localized: "命名空间")
        case .d1: String(localized: "数据库")
        case .r2: String(localized: "存储桶")
        }
    }

    /// 资源选择区段头
    private var sectionHeader: String {
        switch kind {
        case .kv: String(localized: "KV 命名空间")
        case .d1: String(localized: "D1 数据库")
        case .r2: String(localized: "R2 存储桶")
        }
    }

    private var nameValid: Bool {
        name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
    }

    private var nameDuplicate: Bool { viewModel.boundNames.contains(name) }

    private var canSave: Bool {
        !selectedId.isEmpty && nameValid && !nameDuplicate && !viewModel.isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                if availableKinds.count > 1 {
                    Section {
                        Picker("类型", selection: $kind) {
                            ForEach(availableKinds) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: kind) { _, _ in
                            selectedId = ""
                            if !nameEditedManually { name = "" }
                        }
                    }
                }

                Section {
                    if viewModel.loadingResources && options.isEmpty {
                        HStack { ProgressView(); Text("加载中…").foregroundStyle(.secondary) }
                    } else if options.isEmpty {
                        Text(emptyText).font(.callout).foregroundStyle(.secondary)
                    } else {
                        Picker(pickerLabel, selection: $selectedId) {
                            Text("请选择").tag("")
                            ForEach(options, id: \.id) { option in
                                Text(option.title).tag(option.id)
                            }
                        }
                    }
                } header: {
                    Text(sectionHeader)
                }

                Section {
                    TextField("BINDING_NAME", text: $name)
                        .font(.callout.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: name) { _, _ in nameEditedManually = true }
                } header: {
                    Text("绑定变量名")
                } footer: {
                    if nameDuplicate {
                        Text("已存在同名绑定。").foregroundStyle(.red)
                    } else {
                        Text("代码中通过 env 访问。字母、数字、下划线，且不以数字开头。")
                    }
                }

                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("绑定 D1 / KV / R2")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if viewModel.isSaving { ProgressView() } else { Text("绑定").fontWeight(.semibold) }
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .task {
                kind = availableKinds.first ?? .kv
                await viewModel.loadResources(canReadD1: canReadD1, canReadKV: canReadKV, canReadR2: canReadR2)
            }
            .onChange(of: selectedId) { _, newValue in
                // 未手动改过名字时，用所选资源名推导一个合法默认绑定名
                guard !nameEditedManually, !newValue.isEmpty,
                      let picked = options.first(where: { $0.id == newValue }) else { return }
                name = Self.suggestName(from: picked.title)
                nameEditedManually = false
            }
        }
    }

    private func save() async {
        viewModel.error = nil
        let resource: WorkerBindingInput = switch kind {
        case .kv: .kv(name: name, namespaceId: selectedId)
        case .d1: .d1(name: name, databaseId: selectedId)
        case .r2: .r2(name: name, bucketName: selectedId)   // R2 按桶名引用
        }
        if await viewModel.bindResource(resource) { dismiss() }
    }

    /// 资源名 → 合法绑定变量名（大写、非法字符转下划线、数字开头补前缀）
    private static func suggestName(from title: String) -> String {
        var s = title.uppercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }
        if let first = s.first, first.isNumber { s.insert("_", at: s.startIndex) }
        let result = String(s)
        return result.isEmpty ? "BINDING" : result
    }
}
