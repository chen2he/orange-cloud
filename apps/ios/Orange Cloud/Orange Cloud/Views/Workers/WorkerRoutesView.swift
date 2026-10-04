//
//  WorkerRoutesView.swift
//  Orange Cloud
//
//  Worker 域名/路由：workers.dev 子域开关 + 自定义域（挂/卸）+ Zone 路由（加/删）。
//  子域 / 自定义域是 account 级，按 workers-scripts.write 门控；
//  Zone 路由是 zone 级独立权限组，按 workers-routes.write 门控。
//

import SwiftUI

struct WorkerRoutesView: View {

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: WorkerRoutesViewModel
    @State private var sheet: RouteSheet?

    init(accountId: String, scriptName: String, session: SessionStore) {
        _viewModel = State(initialValue: WorkerRoutesViewModel(
            service: session.workerService, zoneService: session.zoneService,
            accountId: accountId, scriptName: scriptName
        ))
    }

    // 子域 / 自定义域（account 级）
    private var canWriteScript: Bool { auth.hasScope("workers-scripts.write") }
    // Zone 路由（zone 级，独立权限组）
    private var canWriteRoute:  Bool { auth.hasScope("workers-routes.write") }

    var body: some View {
        Group {
            if !viewModel.loaded && viewModel.isLoading {
                SkeletonList(rows: 5, icon: .none, trailing: true)
            } else {
                List {
                    subdomainSection
                    customDomainsSection
                    routesSection
                }
                .scrollContentBackground(.hidden)
                .refreshable { await viewModel.load() }
            }
        }
        .background { SkyBackground() }
        .navigationTitle("域名")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !viewModel.loaded { await viewModel.load() } }
        .sheet(item: $sheet) { kind in
            RouteEditorSheet(kind: kind, viewModel: viewModel)
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

    // MARK: - workers.dev 子域

    private var subdomainSection: some View {
        Section {
            if let subdomain = viewModel.subdomain {
                HStack(spacing: 12) {
                    TintIcon(systemImage: "globe.badge.chevron.backward", color: .ocOrange)
                    Text("workers.dev 子域")
                    Spacer()
                    if viewModel.togglingSubdomain {
                        ProgressView()
                    } else {
                        Toggle("", isOn: .init(
                            get: { subdomain.enabled },
                            set: { newValue in Task { await viewModel.toggleSubdomain(newValue) } }
                        ))
                        .labelsHidden()
                        .disabled(!canWriteScript)
                    }
                }
                if let url = viewModel.workersDevURL {
                    Link(destination: url) {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "arrow.up.right.square", color: .ocOrange)
                            Text(url.host ?? url.absoluteString)
                                .font(.callout.monospaced())
                                .foregroundStyle(Color.ocOrangeText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Image(systemName: "arrow.up.forward")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } else {
                Label("该账号未开通 workers.dev 子域", systemImage: "globe.badge.chevron.backward")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("workers.dev")
        } footer: {
            Text("开启后该 Worker 可经 <脚本名>.<子域>.workers.dev 访问。")
        }
        .glassRow()
    }

    // MARK: - 自定义域

    private var customDomainsSection: some View {
        Section {
            if viewModel.customDomains.isEmpty {
                Text("暂无自定义域").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.customDomains) { domain in
                    HStack(spacing: 12) {
                        TintIcon(systemImage: "link", color: .ocOrange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(domain.hostname).font(.callout.weight(.medium))
                            if let zone = domain.zoneName {
                                Text(zone).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .swipeActions(edge: .trailing) {
                        if canWriteScript {
                            Button("移除", role: .destructive) {
                                Task { await viewModel.detachDomain(domain) }
                            }
                        }
                    }
                }
            }
            if canWriteScript && !viewModel.zones.isEmpty {
                Button {
                    sheet = .domain
                } label: {
                    Label("挂载自定义域", systemImage: "plus")
                }
            }
        } header: {
            Text("自定义域")
        } footer: {
            Text("把某个域名/子域直接指向该 Worker，无需 DNS 与证书配置。")
        }
        .glassRow()
    }

    // MARK: - Zone 路由

    private var routesSection: some View {
        Section {
            if viewModel.routes.isEmpty {
                Text("暂无路由").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.routes) { scoped in
                    HStack(spacing: 12) {
                        TintIcon(systemImage: "arrow.triangle.branch", color: .ocOrange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(scoped.route.pattern).font(.callout.weight(.medium).monospaced())
                            Text(scoped.zoneName).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .swipeActions(edge: .trailing) {
                        if canWriteRoute {
                            Button("删除", role: .destructive) {
                                Task { await viewModel.deleteRoute(scoped) }
                            }
                        }
                    }
                }
            }
            if canWriteRoute && !viewModel.zones.isEmpty {
                Button {
                    sheet = .route
                } label: {
                    Label("添加路由", systemImage: "plus")
                }
            }
        } header: {
            Text("路由")
        } footer: {
            Text("用 URL 模式（如 example.com/api/*）把匹配请求交给该 Worker。")
        }
        .glassRow()
    }
}

// MARK: - 挂载域 / 添加路由弹窗

private enum RouteSheet: String, Identifiable {
    case domain, route
    var id: String { rawValue }
}

private struct RouteEditorSheet: View {

    let kind: RouteSheet
    let viewModel: WorkerRoutesViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var zoneId = ""

    private var isDomain: Bool { kind == .domain }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty && !zoneId.isEmpty && !viewModel.isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("域名") {
                    Picker("域名", selection: $zoneId) {
                        Text("请选择").tag("")
                        ForEach(viewModel.zones) { zone in
                            Text(zone.name).tag(zone.id)
                        }
                    }
                }

                Section {
                    TextField(isDomain ? "api.example.com" : "example.com/api/*", text: $text)
                        .font(.callout.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text(isDomain ? String(localized: "主机名") : String(localized: "路由模式"))
                } footer: {
                    Text(isDomain
                         ? String(localized: "完整主机名，须属于所选域名。")
                         : String(localized: "URL 模式，可用 * 通配，如 example.com/*。"))
                }

                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle(isDomain ? String(localized: "挂载自定义域") : String(localized: "添加路由"))
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
        }
    }

    private func save() async {
        viewModel.error = nil
        let value = text.trimmingCharacters(in: .whitespaces)
        let ok: Bool
        if isDomain {
            ok = await viewModel.attachDomain(hostname: value, zoneId: zoneId)
        } else {
            ok = await viewModel.addRoute(zoneId: zoneId, pattern: value)
        }
        if ok { dismiss() }
    }
}
