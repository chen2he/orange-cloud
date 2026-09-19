//
//  TunnelListView.swift
//  Orange Cloud
//
//  Cloudflare Tunnel 列表与详情：查看状态/连接，新建/删除隧道、管理公共主机名。
//  写操作按 argotunnel.write 门控（缺权限弹"权限不足"，引导重新授权）。
//

import SwiftUI

struct TunnelListView: View {

    @Environment(SessionStore.self) private var session
    @Environment(AuthManager.self) private var auth
    @State private var viewModel: TunnelListViewModel
    @State private var showCreate = false
    @State private var showDenied = false
    @State private var tunnelToDelete: Tunnel?

    init(session: SessionStore) {
        _viewModel = State(initialValue: TunnelListViewModel(service: session.tunnelService))
    }

    private var canWrite: Bool { auth.hasScope("argotunnel.write") }
    private var canWriteDNS: Bool { auth.hasScope("dns.write") }
    private var accountId: String? { session.selectedAccount?.id }

    var body: some View {
        Group {
            if viewModel.tunnels.isEmpty && viewModel.isLoading {
                SkeletonList(rows: 5)
            } else if viewModel.tunnels.isEmpty {
                ContentUnavailableView {
                    Label("没有隧道", systemImage: "arrow.triangle.2.circlepath")
                } description: {
                    Text(canWrite
                         ? String(localized: "点右上角 + 新建隧道，或用 cloudflared 创建后在此查看")
                         : String(localized: "用 cloudflared 创建隧道后会显示在这里"))
                } actions: {
                    if canWrite {
                        Button("新建隧道") { showCreate = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.ocOrangePressed)
                            .fontWeight(.bold)
                    }
                }
            } else {
                List(viewModel.tunnels) { tunnel in
                    // 值式导航：详情页由宿主栈根的 .navigationDestination(for: Tunnel.self) 解析
                    //（DashboardView），eager 形态的目的页内部再 push 在 iOS 17.0 会卡死。
                    NavigationLink(value: tunnel) {
                        TunnelRow(tunnel: tunnel)
                    }
                    .glassRow()
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            if canWrite { tunnelToDelete = tunnel } else { showDenied = true }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .refreshable { await load() }
            }
        }
        .background { SkyBackground() }
        .navigationTitle("Cloudflare Tunnel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("新建", systemImage: "plus") {
                    if canWrite { showCreate = true } else { showDenied = true }
                }
            }
            .ocPriority(.primary)
            ToolbarItem(placement: .topBarTrailing) {
                RefreshButton(
                    isLoading: viewModel.isLoading,
                    failed: viewModel.error != nil,
                    action: { Task { await load() } }
                )
            }
            .ocPriority(.secondary)
        }
        .sheet(isPresented: $showCreate) {
            if let accountId {
                TunnelCreateView(viewModel: viewModel, accountId: accountId, session: session)
            }
        }
        .task { await load() }
        .confirmationDialog(
            "删除隧道",
            isPresented: .init(
                get: { tunnelToDelete != nil },
                set: { if !$0 { tunnelToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let tunnel = tunnelToDelete, let accountId {
                Button("删除「\(tunnel.name)」", role: .destructive) {
                    Task { await viewModel.deleteTunnel(tunnel, accountId: accountId) }
                }
            }
        } message: {
            Text("将删除该隧道并断开其连接，此操作不可撤销。删除前请先停止对应的 cloudflared。")
        }
        .alert("权限不足", isPresented: $showDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含隧道编辑权限（argotunnel.write）。\n请在设置中退出登录后重新授权以启用此功能。")
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil && !showCreate },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    private func load() async {
        await session.ensureAccounts()
        guard let accountId = session.selectedAccount?.id else { return }
        await viewModel.load(accountId: accountId)
    }
}

// MARK: - 行

private struct TunnelRow: View {
    let tunnel: Tunnel

    var body: some View {
        HStack(spacing: 12) {
            TintIcon(systemImage: "arrow.triangle.2.circlepath", color: statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(tunnel.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(tunnel.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // 连接数来自列表响应内嵌的 connections，CF 将于 2026-10-05 移除该字段。
                    // 届时此处自然隐藏，仅保留状态点——不为列表每行单发一次连接请求（N+1）。
                    if let count = tunnel.connections?.count, count > 0 {
                        Text("· \(count) 个连接")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        switch tunnel.status {
        case "healthy":  .green
        case "degraded": .orange
        case "down":     .red
        default:         .gray
        }
    }
}

// MARK: - 详情

struct TunnelDetailView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: TunnelDetailViewModel
    @State private var hostnameEdit: HostnameEdit?
    @State private var showDeleteConfirm = false
    @State private var showCleanupConfirm = false

    let session: SessionStore
    let accountId: String
    let canWrite: Bool

    /// 公共主机名编辑目标（sheet item）：.new 新增，.edit 改既有。
    private enum HostnameEdit: Identifiable {
        case new
        case edit(index: Int, rule: IngressRule)
        var id: String {
            switch self {
            case .new:                "new"
            case .edit(let index, _): "edit-\(index)"
            }
        }
    }

    init(
        tunnel: Tunnel,
        accountId: String,
        session: SessionStore,
        canWrite: Bool,
        canWriteDNS: Bool
    ) {
        self.session = session
        self.accountId = accountId
        self.canWrite = canWrite
        _viewModel = State(initialValue: TunnelDetailViewModel(
            tunnel: tunnel, accountId: accountId, session: session, canWriteDNS: canWriteDNS
        ))
    }

    private var tunnel: Tunnel { viewModel.tunnel }
    private var isRemote: Bool { tunnel.remoteConfig == true }

    var body: some View {
        List {
            infoSection
            if canWrite { connectSection }
            if isRemote { publicHostnamesSection } else { localConfigNote }
            connectionsSection
            if canWrite { dangerSection }
        }
        .daybreakList()
        .navigationTitle(tunnel.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if isRemote { await viewModel.loadConfiguration() }
            await viewModel.loadConnections()
        }
        .sheet(item: $hostnameEdit) { edit in
            switch edit {
            case .new:
                PublicHostnameFormView(viewModel: viewModel, editIndex: nil, initialRule: nil)
            case .edit(let index, let rule):
                PublicHostnameFormView(viewModel: viewModel, editIndex: index, initialRule: rule)
            }
        }
        .confirmationDialog("删除隧道", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除「\(tunnel.name)」", role: .destructive) {
                // 删除走详情自己的 VM；弹回列表后其 .task 重新拉取，列表自然消掉该项
                Task {
                    if await viewModel.deleteTunnel() { dismiss() }
                }
            }
        } message: {
            Text("将删除该隧道并断开其连接，此操作不可撤销。")
        }
        .confirmationDialog("清理连接", isPresented: $showCleanupConfirm, titleVisibility: .visible) {
            Button("清理失活连接", role: .destructive) {
                Task { await viewModel.cleanupConnections() }
            }
        } message: {
            Text("移除已断开的连接记录；活跃的 cloudflared 会自动重连。")
        }
        .alert("DNS 记录", isPresented: .init(
            get: { viewModel.dnsNotice != nil },
            set: { if !$0 { viewModel.dnsNotice = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.dnsNotice ?? "")
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil && hostnameEdit == nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: 信息

    private var infoSection: some View {
        Section("信息") {
            LabeledContent("状态", value: tunnel.statusText)
            if let type = tunnel.tunType {
                LabeledContent("类型", value: type)
            }
            if let remote = tunnel.remoteConfig {
                LabeledContent("配置方式", value: remote
                    ? String(localized: "远程（Dashboard）")
                    : String(localized: "本地（config.yml）"))
            }
            if let created = WorkerScript.parseDate(tunnel.createdAt) {
                LabeledContent("创建时间") {
                    Text(created, format: .dateTime.year().month().day())
                }
            }
            LabeledContent("Tunnel ID") {
                Text(tunnel.id)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .glassRow()
    }

    // MARK: 连接（令牌与命令）

    private var connectSection: some View {
        Section {
            // 值式：连接页由栈根的 DashboardRoute navdest 解析（本页已是被 push 的目的页，
            // eager 形态在 iOS 17.0 会失灵）
            NavigationLink(value: DashboardRoute.tunnelConnect(tunnel)) {
                Label("连接信息（令牌与命令）", systemImage: "link")
            }
        } footer: {
            Text("查看连接 cloudflared 所需的令牌与安装命令。")
        }
        .glassRow()
    }

    // MARK: 公共主机名（仅远程托管）

    private var publicHostnamesSection: some View {
        Section {
            if viewModel.isLoadingConfig && !viewModel.configLoaded {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("加载配置…").foregroundStyle(.secondary)
                }
            } else if viewModel.publicHostnames.isEmpty {
                Text(canWrite
                     ? String(localized: "还没有公共主机名，点下方添加。")
                     : String(localized: "还没有公共主机名。"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(viewModel.publicHostnames.enumerated()), id: \.offset) { index, rule in
                    Button {
                        if canWrite { hostnameEdit = .edit(index: index, rule: rule) }
                    } label: {
                        PublicHostnameRow(rule: rule)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        if canWrite {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteHostname(at: index) }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            if canWrite {
                Button {
                    hostnameEdit = .new
                } label: {
                    Label("添加公共主机名", systemImage: "plus")
                }
            }
        } header: {
            Text("公共主机名")
        } footer: {
            Text("把对外域名映射到本地服务。新增时会自动创建橙云代理的 CNAME。")
        }
        .glassRow()
    }

    private var localConfigNote: some View {
        Section("公共主机名") {
            Text("该隧道为本地托管（config.yml），公共主机名请在 cloudflared 配置文件中管理。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .glassRow()
    }

    // MARK: 活跃连接

    private var connectionsSection: some View {
        Section("活跃连接") {
            if !viewModel.connections.isEmpty {
                ForEach(Array(viewModel.connections.enumerated()), id: \.offset) { _, connection in
                    HStack(spacing: 12) {
                        TintIcon(systemImage: "antenna.radiowaves.left.and.right", color: .green, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(connection.coloName ?? String(localized: "未知节点"))
                                .font(.callout.weight(.medium))
                            HStack(spacing: 6) {
                                if let version = connection.clientVersion {
                                    Text("cloudflared \(version)")
                                }
                                if let opened = WorkerScript.parseDate(connection.openedAt) {
                                    Text(opened, format: .relative(presentation: .named))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if viewModel.isLoadingConnections {
                ProgressView()
            } else {
                Text("没有活跃连接")
                    .foregroundStyle(.secondary)
            }
        }
        .glassRow()
    }

    // MARK: 危险操作（写权限）

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showCleanupConfirm = true
            } label: {
                Label("清理失活连接", systemImage: "bolt.slash")
            }
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("删除隧道", systemImage: "trash")
            }
        } header: {
            Text("危险操作")
        }
        .glassRow()
    }
}

// MARK: - 公共主机名行

private struct PublicHostnameRow: View {
    let rule: IngressRule

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rule.hostname ?? "—")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            HStack(spacing: 5) {
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(rule.service)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let path = rule.path, !path.isEmpty {
                Text("路径：\(path)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
