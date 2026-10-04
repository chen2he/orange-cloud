//
//  LoadBalancerListView.swift
//  Orange Cloud
//
//  负载均衡中枢（从域名详情进入）：本域名的负载均衡器（zone 级，可增删改启停）+
//  账号级「源站池」「健康监测」入口。改路由 / 删除均走确认弹窗（影响线上流量）。
//

import SwiftUI

struct LoadBalancerListView: View {

    let zoneName: String
    let session: SessionStore

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: LoadBalancerListViewModel
    @State private var editorTarget: LBEditorTarget?
    @State private var lbToDelete: LoadBalancer?

    init(zoneId: String, zoneName: String, session: SessionStore) {
        self.zoneName = zoneName
        self.session = session
        _viewModel = State(initialValue: LoadBalancerListViewModel(
            service: session.loadBalancerService,
            zoneId: zoneId,
            accountId: session.selectedAccount?.id ?? ""
        ))
    }

    private var canWrite: Bool { auth.hasScope("load-balancers.write") }

    var body: some View {
        List {
            lbSection
            accountResourcesSection
        }
        .daybreakList()
        .navigationTitle("负载均衡")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("添加", systemImage: "plus") {
                    if canWrite { editorTarget = LBEditorTarget(lb: nil) }
                }
                .disabled(!canWrite)
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sensoryFeedback(.success, trigger: viewModel.didMutate)
        .sheet(item: $editorTarget) { target in
            LoadBalancerEditorView(existing: target.lb, viewModel: viewModel)
        }
        .confirmationDialog(
            "删除负载均衡器",
            isPresented: .init(get: { lbToDelete != nil }, set: { if !$0 { lbToDelete = nil } }),
            titleVisibility: .visible,
            presenting: lbToDelete
        ) { lb in
            Button("删除「\(lb.name ?? "")」", role: .destructive) {
                Task { _ = await viewModel.delete(lb) }
            }
        } message: { _ in
            Text("删除后该主机名将不再经负载均衡分发，立即影响线上流量。不可撤销。")
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

    private var lbSection: some View {
        Section {
            if viewModel.isLoading && !viewModel.loaded {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
            } else if viewModel.loadBalancers.isEmpty {
                Text(canWrite
                     ? String(localized: "暂无负载均衡器。点右上角 + 创建（需先有源站池）。")
                     : String(localized: "此域名暂无负载均衡器。"))
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.loadBalancers) { lb in
                    lbRow(lb)
                        .swipeActions(edge: .leading) {
                            if canWrite {
                                Button {
                                    Task { await viewModel.toggle(lb, enabled: !(lb.enabled ?? true)) }
                                } label: {
                                    Label(lb.enabled == false ? String(localized: "启用") : String(localized: "停用"),
                                          systemImage: lb.enabled == false ? "play" : "pause")
                                }
                                .tint(.orange)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            if canWrite {
                                Button(role: .destructive) { lbToDelete = lb } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                }
            }
        } header: {
            Text("负载均衡器（\(zoneName)）")
        } footer: {
            Text(canWrite
                 ? String(localized: "点按编辑，左滑启停，右滑删除。改动会立即影响线上流量分发。")
                 : String(localized: "当前授权仅限读取（load-balancers.read）。"))
        }
        .glassRow()
    }

    private func lbRow(_ lb: LoadBalancer) -> some View {
        Button {
            if canWrite { editorTarget = LBEditorTarget(lb: lb) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(lb.name ?? lb.id)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(lb.enabled == false ? String(localized: "已停用") : String(localized: "已启用"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(lb.enabled == false ? Color.secondary : Color.green)
                    if canWrite {
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                Text(String(localized: "策略：\(lb.steeringLabel) · \(lb.defaultPools?.count ?? 0) 个默认池"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .opacity(lb.enabled == false ? 0.55 : 1)
    }

    private var accountResourcesSection: some View {
        Section {
            NavigationLink {
                PoolListView(session: session)
            } label: {
                HStack(spacing: 12) {
                    TintIcon(systemImage: "server.rack", color: .indigo)
                    Text("源站池")
                }
            }
            NavigationLink {
                MonitorListView(session: session)
            } label: {
                HStack(spacing: 12) {
                    TintIcon(systemImage: "waveform.path.ecg", color: .green)
                    Text("健康监测")
                }
            }
        } header: {
            Text("账号级资源")
        } footer: {
            Text("源站池与健康监测在整个账号内共享，可被多个负载均衡器引用。")
        }
        .glassRow()
    }
}

struct LBEditorTarget: Identifiable {
    let lb: LoadBalancer?
    var id: String { lb?.id ?? "new" }
}

// MARK: - 负载均衡器编辑器

private struct LoadBalancerEditorView: View {

    let existing: LoadBalancer?
    let viewModel: LoadBalancerListViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var enabled: Bool
    @State private var proxied: Bool
    @State private var ttl: String
    @State private var steering: LBSteeringPolicy
    @State private var sessionAffinity: LBSessionAffinity
    @State private var selectedPools: Set<String>
    @State private var fallbackPool: String

    init(existing: LoadBalancer?, viewModel: LoadBalancerListViewModel) {
        self.existing = existing
        self.viewModel = viewModel
        _name = State(initialValue: existing?.name ?? "")
        _enabled = State(initialValue: existing?.enabled ?? true)
        _proxied = State(initialValue: existing?.proxied ?? true)
        _ttl = State(initialValue: existing?.ttl.map(String.init) ?? "30")
        _steering = State(initialValue: LBSteeringPolicy(rawValue: existing?.steeringPolicy ?? "") ?? .off)
        _sessionAffinity = State(initialValue: LBSessionAffinity(rawValue: existing?.sessionAffinity ?? "") ?? .none)
        _selectedPools = State(initialValue: Set(existing?.defaultPools ?? []))
        _fallbackPool = State(initialValue: existing?.fallbackPool ?? "")
    }

    private var isEditing: Bool { existing != nil }

    private var orderedSelectedPools: [String] {
        viewModel.pools.map(\.id).filter { selectedPools.contains($0) }
    }

    private var canSave: Bool {
        guard !viewModel.isMutating else { return false }
        if !isEditing && name.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        if selectedPools.isEmpty || fallbackPool.isEmpty { return false }
        if !proxied && (Int(ttl) ?? 0) <= 0 { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isEditing {
                        LabeledContent("主机名", value: name)
                    } else {
                        TextField("主机名，如 lb.example.com", text: $name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Toggle("启用", isOn: $enabled)
                    Toggle("通过 Cloudflare 代理", isOn: $proxied)
                    if !proxied {
                        HStack {
                            Text("TTL")
                            Spacer()
                            TextField("30", text: $ttl).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
                            Text("秒").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("基本")
                } footer: {
                    Text(proxied ? String(localized: "代理模式下 DNS TTL 由 Cloudflare 管理。") : String(localized: "非代理（DNS-only）时生效的记录 TTL。"))
                }

                Section("流量策略") {
                    Picker("转向策略", selection: $steering) {
                        ForEach(LBSteeringPolicy.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("会话保持", selection: $sessionAffinity) {
                        ForEach(LBSessionAffinity.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section {
                    if viewModel.pools.isEmpty {
                        Text("账号下暂无源站池，请先在「源站池」创建后再配置。")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.pools) { pool in
                            Toggle(isOn: Binding(
                                get: { selectedPools.contains(pool.id) },
                                set: { on in if on { selectedPools.insert(pool.id) } else { selectedPools.remove(pool.id) } }
                            )) {
                                Text(pool.name ?? pool.id)
                            }
                        }
                    }
                } header: {
                    Text("默认池")
                } footer: {
                    Text("按上方顺序作为主用池，前面的不可用时依次故障转移。")
                }

                if !viewModel.pools.isEmpty {
                    Section("回退池") {
                        Picker("回退池", selection: $fallbackPool) {
                            Text("未选择").tag("")
                            ForEach(viewModel.pools) { Text($0.name ?? $0.id).tag($0.id) }
                        }
                    }
                }

                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle(isEditing ? Text("编辑负载均衡器") : Text("新建负载均衡器"))
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
        var body = LoadBalancerUpdate()
        if !isEditing { body.name = name.trimmingCharacters(in: .whitespaces) }
        body.enabled = enabled
        body.proxied = proxied
        body.ttl = proxied ? nil : Int(ttl)
        body.steeringPolicy = steering.rawValue
        body.sessionAffinity = sessionAffinity.rawValue
        body.defaultPools = orderedSelectedPools
        body.fallbackPool = fallbackPool.isEmpty ? nil : fallbackPool
        if await viewModel.save(lbId: existing?.id, body: body) {
            dismiss()
        }
    }
}
