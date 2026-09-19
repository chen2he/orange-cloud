//
//  HyperdriveView.swift
//  Orange Cloud
//
//  Cloudflare Hyperdrive 列表 + 新建 / 删除 + 详情管理。account 级，读 query-cache.read / 写 query-cache.write。
//  详情用 sheet：改缓存（开关 / max_age / stale_while_revalidate）、重命名、改源连接、删除。
//  密码为写专用，列表与详情都不回显；改连接时需重新输入。
//

import SwiftUI

struct HyperdriveView: View {

    let session: SessionStore

    @Environment(AuthManager.self) private var auth
    @State private var vm: HyperdriveViewModel?
    @State private var showCreate = false
    @State private var detailTarget: HyperdriveConfig?
    @State private var deleteTarget: HyperdriveConfig?
    @State private var writeDenied = false

    private var canWrite: Bool { auth.hasScope("query-cache.write") }

    var body: some View {
        Group {
            if let vm { content(vm) } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .background { SkyBackground() }
        .navigationTitle("Hyperdrive")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if vm != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("新建配置", systemImage: "plus") {
                        if canWrite { showCreate = true } else { writeDenied = true }
                    }
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            if let vm { HyperdriveCreateView(viewModel: vm) }
        }
        .sheet(item: $detailTarget) { config in
            if let vm { HyperdriveDetailSheet(viewModel: vm, configId: config.id) }
        }
        .alert("权限不足", isPresented: $writeDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含 Hyperdrive 写权限（query-cache.write）。\n请在设置中退出登录后重新授权以启用此功能。")
        }
        .confirmationDialog(
            deleteTarget.map { String(localized: "删除配置「\($0.displayName)」？") } ?? "",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let c = deleteTarget, let vm { Task { await vm.delete(c) } }
            }
        } message: {
            Text("删除后引用该配置的 Worker 将无法连接，不可撤销。")
        }
        .task {
            await session.ensureAccounts()
            guard vm == nil else { return }
            let model = HyperdriveViewModel(service: session.hyperdriveService, accountId: session.selectedAccount?.id)
            vm = model
            await model.load()
        }
    }

    @ViewBuilder
    private func content(_ vm: HyperdriveViewModel) -> some View {
        if vm.isLoading && !vm.loaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.configs.isEmpty {
            ContentUnavailableView {
                Label("没有 Hyperdrive 配置", systemImage: "bolt.horizontal.circle")
            } description: {
                Text(vm.error ?? String(localized: "该账号下还没有 Hyperdrive 配置。"))
            } actions: {
                if canWrite {
                    Button("新建配置") { showCreate = true }
                        .buttonStyle(.borderedProminent).tint(Color.ocOrangePressed).fontWeight(.bold)
                }
            }
        } else {
            List {
                Section {
                    ForEach(vm.configs) { config in
                        Button { detailTarget = config } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(config.displayName).font(.callout.weight(.semibold)).lineLimit(1)
                                        .foregroundStyle(.primary)
                                    if let origin = config.origin {
                                        Text(origin.summary).font(.caption.monospaced())
                                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            if canWrite {
                                Button(role: .destructive) { deleteTarget = config } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                } footer: {
                    Text("点按查看详情与管理 · Hyperdrive 为外部 Postgres / MySQL 提供连接池与查询缓存。")
                }
                .glassRow()
            }
            .daybreakList()
            .refreshable { await vm.load() }
            .sensoryFeedback(.success, trigger: vm.didChange)
        }
    }
}

// MARK: - 详情管理 sheet

private struct HyperdriveDetailSheet: View {
    let viewModel: HyperdriveViewModel
    let configId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth
    @State private var showRename = false
    @State private var showCaching = false
    @State private var showConnection = false
    @State private var showDelete = false

    private var canWrite: Bool { auth.hasScope("query-cache.write") }
    private var config: HyperdriveConfig? { viewModel.configs.first { $0.id == configId } }
    private var cachingEnabled: Bool { !(config?.caching?.disabled ?? false) }

    /// 配置的次级动作。iOS 27+ 并入系统溢出菜单，以下版本走自建 ellipsis 菜单。
    @ViewBuilder private var configActions: some View {
        Button("重命名", systemImage: "pencil") { showRename = true }
        Button("编辑缓存", systemImage: "bolt.horizontal") { showCaching = true }
        Button("编辑连接", systemImage: "server.rack") { showConnection = true }
        Divider()
        Button("删除配置", systemImage: "trash", role: .destructive) { showDelete = true }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let config { detail(config) } else { ProgressView() }
            }
            .background { SkyBackground() }
            .navigationTitle(config?.displayName ?? String(localized: "配置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
                // 这组动作在 iOS 27+ 并入系统溢出菜单（见下方 ocOverflowActions）——
                // HIG 要求 ellipsis 只留给系统溢出菜单，App 别再自建一个；
                // iOS 26 及以下没有系统菜单，仍挂自建 ellipsis，两条路共用同一份 configActions。
                if canWrite, !ProcessInfo.usesSystemToolbarOverflow {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            configActions
                        } label: {
                            Label("更多", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
            .ocOverflowActions {
                if canWrite { configActions }
            }
            .sheet(isPresented: $showRename) {
                if let config { HyperdriveRenameSheet(viewModel: viewModel, configId: configId, currentName: config.displayName) }
            }
            .sheet(isPresented: $showCaching) {
                if let config { HyperdriveCachingSheet(viewModel: viewModel, configId: configId, caching: config.caching) }
            }
            .sheet(isPresented: $showConnection) {
                if let config { HyperdriveConnectionSheet(viewModel: viewModel, configId: configId, origin: config.origin) }
            }
            .confirmationDialog(
                config.map { String(localized: "删除配置「\($0.displayName)」？") } ?? "",
                isPresented: $showDelete, titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let config { Task { await viewModel.delete(config); dismiss() } }
                }
            } message: {
                Text("删除后引用该配置的 Worker 将无法连接，不可撤销。")
            }
            .onChange(of: viewModel.configs.contains { $0.id == configId }) { _, stillThere in
                if !stillThere { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func detail(_ config: HyperdriveConfig) -> some View {
        List {
            Section("源数据库") {
                if let origin = config.origin {
                    if let scheme = origin.scheme { LabeledContent("类型", value: scheme.uppercased()) }
                    if let host = origin.host { LabeledContent("主机", value: host) }
                    if let port = origin.port { LabeledContent("端口", value: String(port)) }
                    if let db = origin.database { LabeledContent("数据库", value: db) }
                    if let user = origin.user { LabeledContent("用户名", value: user) }
                } else {
                    Text("无连接信息").foregroundStyle(.secondary).font(.callout)
                }
            }
            .glassRow()

            Section {
                LabeledContent("查询缓存") {
                    Text(cachingEnabled ? "已启用" : "已禁用")
                        .foregroundStyle(cachingEnabled ? .secondary : Color.ocOrangeText)
                }
                if cachingEnabled {
                    LabeledContent("最大缓存时长", value: "\(config.caching?.maxAge ?? 60) 秒")
                    LabeledContent("陈旧重验证", value: "\(config.caching?.staleWhileRevalidate ?? 15) 秒")
                }
                if let limit = config.originConnectionLimit {
                    LabeledContent("连接上限", value: String(limit))
                }
            } header: {
                Text("缓存")
            } footer: {
                Text("Hyperdrive 缓存数据库的只读查询结果以降低延迟。")
            }
            .glassRow()

            if let error = viewModel.error {
                Section { Text(error).font(.footnote).foregroundStyle(.red) }.glassRow()
            }
        }
        .daybreakList()
    }
}

// MARK: - 重命名

private struct HyperdriveRenameSheet: View {
    let viewModel: HyperdriveViewModel
    let configId: String
    let currentName: String

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(viewModel: HyperdriveViewModel, configId: String, currentName: String) {
        self.viewModel = viewModel
        self.configId = configId
        self.currentName = currentName
        _name = State(initialValue: currentName)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmed.isEmpty && trimmed != currentName && !viewModel.isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $name)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("重命名配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { if await viewModel.update(configId: configId, patch: HyperdrivePatch(name: trimmed)) { dismiss() } }
                    } label: {
                        if viewModel.isSaving { ProgressView() } else { Text("保存").fontWeight(.semibold) }
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .onAppear { viewModel.error = nil }
        }
    }
}

// MARK: - 编辑缓存

private struct HyperdriveCachingSheet: View {
    let viewModel: HyperdriveViewModel
    let configId: String

    @Environment(\.dismiss) private var dismiss
    @State private var enabled: Bool
    @State private var maxAgeText: String
    @State private var swrText: String

    init(viewModel: HyperdriveViewModel, configId: String, caching: HyperdriveCaching?) {
        self.viewModel = viewModel
        self.configId = configId
        _enabled = State(initialValue: !(caching?.disabled ?? false))
        _maxAgeText = State(initialValue: caching?.maxAge.map(String.init) ?? "60")
        _swrText = State(initialValue: caching?.staleWhileRevalidate.map(String.init) ?? "15")
    }

    private var maxAge: Int? { Int(maxAgeText) }
    private var swr: Int? { Int(swrText) }
    private var canSave: Bool {
        if viewModel.isSaving { return false }
        if !enabled { return true }
        return (maxAge ?? -1) >= 0 && (swr ?? -1) >= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("启用查询缓存", isOn: $enabled)
                } footer: {
                    Text("关闭后所有查询都直连源数据库，不缓存结果。")
                }
                if enabled {
                    Section {
                        TextField("最大缓存时长（秒）", text: $maxAgeText).keyboardType(.numberPad)
                    } footer: {
                        Text("缓存结果保留多久，默认 60 秒。")
                    }
                    Section {
                        TextField("陈旧重验证（秒）", text: $swrText).keyboardType(.numberPad)
                    } footer: {
                        Text("缓存过期后仍可返回旧结果的秒数，默认 15 秒。")
                    }
                }
                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("编辑缓存")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let patch: HyperdrivePatch = enabled
                            ? HyperdrivePatch(caching: HyperdriveCachingPatch(disabled: false, maxAge: maxAge, staleWhileRevalidate: swr))
                            : HyperdrivePatch(caching: HyperdriveCachingPatch(disabled: true))
                        Task { if await viewModel.update(configId: configId, patch: patch) { dismiss() } }
                    } label: {
                        if viewModel.isSaving { ProgressView() } else { Text("保存").fontWeight(.semibold) }
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .onAppear { viewModel.error = nil }
        }
    }
}

// MARK: - 编辑源连接（需重新输入密码）

private struct HyperdriveConnectionSheet: View {
    let viewModel: HyperdriveViewModel
    let configId: String

    @Environment(\.dismiss) private var dismiss
    @State private var scheme: HyperdriveScheme
    @State private var host: String
    @State private var portText: String
    @State private var database: String
    @State private var user: String
    @State private var password = ""

    init(viewModel: HyperdriveViewModel, configId: String, origin: HyperdriveOrigin?) {
        self.viewModel = viewModel
        self.configId = configId
        _scheme = State(initialValue: origin?.scheme == "mysql" ? .mysql : .postgres)
        _host = State(initialValue: origin?.host ?? "")
        _portText = State(initialValue: origin?.port.map(String.init) ?? "5432")
        _database = State(initialValue: origin?.database ?? "")
        _user = State(initialValue: origin?.user ?? "")
    }

    private var canSave: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
            && !database.trimmingCharacters(in: .whitespaces).isEmpty
            && !user.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && Int(portText) != nil
            && !viewModel.isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("源数据库连接") {
                    Picker("数据库类型", selection: $scheme) {
                        ForEach(HyperdriveScheme.allCases) { Text($0.label).tag($0) }
                    }
                    .onChange(of: scheme) { _, new in
                        if portText == "5432" || portText == "3306" { portText = String(new.defaultPort) }
                    }
                    TextField("主机", text: $host)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("端口", text: $portText).keyboardType(.numberPad)
                    TextField("数据库名", text: $database)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("用户名", text: $user)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("密码", text: $password)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section {} footer: {
                    Text("出于安全，Cloudflare 不回显原密码，更新连接需重新输入密码。")
                }
                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("编辑连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let origin = HyperdriveCreate.Origin(
                            scheme: scheme.rawValue,
                            host: host.trimmingCharacters(in: .whitespaces),
                            port: Int(portText) ?? scheme.defaultPort,
                            database: database.trimmingCharacters(in: .whitespaces),
                            user: user.trimmingCharacters(in: .whitespaces),
                            password: password
                        )
                        Task { if await viewModel.update(configId: configId, patch: HyperdrivePatch(origin: origin)) { dismiss() } }
                    } label: {
                        if viewModel.isSaving { ProgressView() } else { Text("保存").fontWeight(.semibold) }
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .onAppear { viewModel.error = nil }
        }
    }
}

// MARK: - 新建

private struct HyperdriveCreateView: View {
    let viewModel: HyperdriveViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var scheme: HyperdriveScheme = .postgres
    @State private var host = ""
    @State private var portText = "5432"
    @State private var database = ""
    @State private var user = ""
    @State private var password = ""

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        !trimmedName.isEmpty && !host.trimmingCharacters(in: .whitespaces).isEmpty
            && !database.trimmingCharacters(in: .whitespaces).isEmpty
            && !user.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && Int(portText) != nil
            && !viewModel.isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("配置") {
                    TextField("名称", text: $name)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("数据库类型", selection: $scheme) {
                        ForEach(HyperdriveScheme.allCases) { Text($0.label).tag($0) }
                    }
                    .onChange(of: scheme) { _, new in portText = String(new.defaultPort) }
                }
                Section("源数据库连接") {
                    TextField("主机", text: $host)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("端口", text: $portText).keyboardType(.numberPad)
                    TextField("数据库名", text: $database)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("用户名", text: $user)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("密码", text: $password)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section {} footer: {
                    Text("密码只用于建立连接，Cloudflare 不会再回显。请确保该数据库允许 Cloudflare 出口 IP 访问。")
                }
                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("新建 Hyperdrive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if viewModel.isSaving { ProgressView() } else { Text("创建").fontWeight(.semibold) }
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .onAppear { viewModel.error = nil }
        }
    }

    private func save() async {
        let body = HyperdriveCreate(
            name: trimmedName,
            origin: HyperdriveCreate.Origin(
                scheme: scheme.rawValue,
                host: host.trimmingCharacters(in: .whitespaces),
                port: Int(portText) ?? scheme.defaultPort,
                database: database.trimmingCharacters(in: .whitespaces),
                user: user.trimmingCharacters(in: .whitespaces),
                password: password
            )
        )
        if await viewModel.create(body) { dismiss() }
    }
}
