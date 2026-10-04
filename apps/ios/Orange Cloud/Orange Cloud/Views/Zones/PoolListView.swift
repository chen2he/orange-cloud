//
//  PoolListView.swift
//  Orange Cloud
//
//  源站池（account 级）：查看（含健康）/ 新建 / 编辑（源站列表）/ 删除 / 启停。
//  写按 load-balancing-monitors-and-pools.write 门控。
//

import SwiftUI

struct PoolListView: View {

    let session: SessionStore

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: PoolListViewModel
    @State private var editorTarget: PoolEditorTarget?
    @State private var poolToDelete: Pool?

    init(session: SessionStore) {
        self.session = session
        _viewModel = State(initialValue: PoolListViewModel(
            service: session.loadBalancerService,
            accountId: session.selectedAccount?.id ?? ""
        ))
    }

    private var canWrite: Bool { auth.hasScope("load-balancing-monitors-and-pools.write") }

    var body: some View {
        Group {
            if viewModel.isLoading && !viewModel.loaded {
                SkeletonList(rows: 5, icon: .none, trailing: true)
            } else if viewModel.pools.isEmpty {
                ContentUnavailableView {
                    Label("没有源站池", systemImage: "server.rack")
                } description: {
                    Text(canWrite
                         ? String(localized: "源站池是一组后端服务器，供负载均衡器分发流量。点右上角 + 创建。")
                         : String(localized: "此账号暂无源站池。"))
                } actions: {
                    if canWrite {
                        Button("新建源站池") { editorTarget = PoolEditorTarget(pool: nil) }
                            .buttonStyle(.borderedProminent).tint(Color.ocOrangePressed).fontWeight(.bold)
                    }
                }
            } else {
                List {
                    Section {
                        ForEach(viewModel.pools) { pool in
                            poolRow(pool)
                                .swipeActions(edge: .leading) {
                                    if canWrite {
                                        Button {
                                            Task { await viewModel.toggle(pool, enabled: !(pool.enabled ?? true)) }
                                        } label: {
                                            Label(pool.enabled == false ? String(localized: "启用") : String(localized: "停用"),
                                                  systemImage: pool.enabled == false ? "play" : "pause")
                                        }
                                        .tint(.orange)
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    if canWrite {
                                        Button(role: .destructive) { poolToDelete = pool } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    } footer: {
                        Text(canWrite
                             ? String(localized: "点按编辑源站，左滑启停，右滑删除。被负载均衡器引用的池无法删除。")
                             : String(localized: "当前授权仅限读取。"))
                    }
                    .glassRow()
                }
                .scrollContentBackground(.hidden)
                .refreshable { await viewModel.load() }
            }
        }
        .background { SkyBackground() }
        .navigationTitle("源站池")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("添加", systemImage: "plus") {
                    if canWrite { editorTarget = PoolEditorTarget(pool: nil) }
                }
                .disabled(!canWrite)
            }
        }
        .task { await viewModel.load() }
        .sensoryFeedback(.success, trigger: viewModel.didMutate)
        .sheet(item: $editorTarget) { target in
            PoolEditorView(existing: target.pool, viewModel: viewModel)
        }
        .confirmationDialog(
            "删除源站池",
            isPresented: .init(get: { poolToDelete != nil }, set: { if !$0 { poolToDelete = nil } }),
            titleVisibility: .visible,
            presenting: poolToDelete
        ) { pool in
            Button("删除「\(pool.name ?? "")」", role: .destructive) {
                Task { _ = await viewModel.delete(pool) }
            }
        } message: { _ in
            Text("此操作不可撤销。若仍被负载均衡器引用，删除会失败。")
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil }, set: { if !$0 { viewModel.error = nil } }
        )) {
            apiErrorDocButton(for: viewModel.error)
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    private func poolRow(_ pool: Pool) -> some View {
        Button {
            if canWrite { editorTarget = PoolEditorTarget(pool: pool) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(pool.name ?? pool.id)
                        .font(.callout.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    Spacer()
                    if pool.enabled == false {
                        Text("已停用").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    if canWrite {
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                HStack(spacing: 6) {
                    Text(String(localized: "\(pool.enabledOriginsCount)/\(pool.originsCount) 源站启用"))
                        .font(.caption).foregroundStyle(.secondary)
                    if let health = viewModel.healthText(for: pool) {
                        Text("·").foregroundStyle(.tertiary)
                        Text(health).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(pool.enabled == false ? 0.55 : 1)
    }
}

struct PoolEditorTarget: Identifiable {
    let pool: Pool?
    var id: String { pool?.id ?? "new" }
}

// MARK: - 源站池编辑器

private struct PoolEditorView: View {

    let existing: Pool?
    let viewModel: PoolListViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var enabled: Bool
    @State private var description: String
    @State private var monitor: String
    @State private var notificationEmail: String
    @State private var originRows: [OriginRow]

    init(existing: Pool?, viewModel: PoolListViewModel) {
        self.existing = existing
        self.viewModel = viewModel
        _name = State(initialValue: existing?.name ?? "")
        _enabled = State(initialValue: existing?.enabled ?? true)
        _description = State(initialValue: existing?.description ?? "")
        _monitor = State(initialValue: existing?.monitor ?? "")
        _notificationEmail = State(initialValue: existing?.notificationEmail ?? "")
        let rows = (existing?.origins ?? []).map { o in
            OriginRow(
                name: o.name ?? "",
                address: o.address ?? "",
                weight: o.weight.map { String($0) } ?? "1",
                enabled: o.enabled ?? true,
                preserved: o
            )
        }
        _originRows = State(initialValue: rows.isEmpty ? [OriginRow()] : rows)
    }

    private var isEditing: Bool { existing != nil }

    private var canSave: Bool {
        guard !viewModel.isMutating else { return false }
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return originRows.contains { !$0.address.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本") {
                    TextField("名称", text: $name)
                    Toggle("启用", isOn: $enabled)
                    TextField("描述（可选）", text: $description)
                }

                Section {
                    ForEach($originRows) { $row in
                        VStack(spacing: 8) {
                            HStack {
                                TextField("地址（IP 或主机名）", text: $row.address)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                Toggle("", isOn: $row.enabled).labelsHidden()
                            }
                            HStack(spacing: 10) {
                                TextField("名称（可选）", text: $row.name)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                Divider()
                                Text("权重").font(.caption).foregroundStyle(.secondary)
                                TextField("1", text: $row.weight)
                                    .keyboardType(.decimalPad).frame(width: 56).multilineTextAlignment(.trailing)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { originRows.remove(atOffsets: $0) }

                    Button("添加源站", systemImage: "plus") { originRows.append(OriginRow()) }
                } header: {
                    Text("源站")
                } footer: {
                    Text("权重 0–1，决定各源站分到的流量比例；关闭开关可临时摘除某源站。")
                }

                Section("健康监测") {
                    Picker("监测", selection: $monitor) {
                        Text("无").tag("")
                        ForEach(viewModel.monitors) { Text($0.summary).tag($0.id) }
                    }
                    TextField("通知邮箱（可选）", text: $notificationEmail)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                }

                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle(isEditing ? Text("编辑源站池") : Text("新建源站池"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if viewModel.isMutating { ProgressView() } else { Text("保存").fontWeight(.semibold) }
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(viewModel.isMutating)
            .onDisappear { viewModel.error = nil }
        }
    }

    private func save() async {
        viewModel.error = nil
        let origins: [OriginInput] = originRows.compactMap { row in
            let addr = row.address.trimmingCharacters(in: .whitespaces)
            guard !addr.isEmpty else { return nil }
            var origin = row.preserved ?? Origin()
            origin.name = row.name.trimmingCharacters(in: .whitespaces).nilIfEmptyLB
            origin.address = addr
            origin.enabled = row.enabled
            origin.weight = Double(row.weight)
            return OriginInput(from: origin)
        }
        var body = PoolUpdate()
        body.name = name.trimmingCharacters(in: .whitespaces)
        body.enabled = enabled
        body.description = description.trimmingCharacters(in: .whitespaces).nilIfEmptyLB
        body.monitor = monitor.isEmpty ? nil : monitor
        body.notificationEmail = notificationEmail.trimmingCharacters(in: .whitespaces).nilIfEmptyLB
        body.origins = origins
        if await viewModel.save(poolId: existing?.id, body: body) {
            dismiss()
        }
    }
}

private struct OriginRow: Identifiable {
    let id = UUID()
    var name: String = ""
    var address: String = ""
    var weight: String = "1"
    var enabled: Bool = true
    var preserved: Origin? = nil
}

extension String {
    /// 负载均衡编辑器用：去空白后空串转 nil
    var nilIfEmptyLB: String? { isEmpty ? nil : self }
}
