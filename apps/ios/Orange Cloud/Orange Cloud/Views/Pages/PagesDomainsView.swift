//
//  PagesDomainsView.swift
//  Orange Cloud
//
//  Pages 项目自定义域名：列表 / 添加 / 删除 / 重新验证，
//  并检查 DNS 解析状态，zone 在当前账号时可一键添加 CNAME → <project>.pages.dev。
//

import SwiftUI

struct PagesDomainsView: View {

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: PagesDomainsViewModel
    @State private var showAdd = false
    @State private var newDomain = ""
    @State private var detailTarget: PagesDomain?
    @State private var deleteTarget: PagesDomain?
    @State private var writeDenied = false

    init(project: PagesProject, session: SessionStore) {
        _viewModel = State(initialValue: PagesDomainsViewModel(
            service: session.pagesService,
            dnsService: session.dnsService,
            accountId: session.selectedAccount?.id ?? "",
            projectName: project.name,
            subdomain: project.subdomain
        ))
    }

    private var canWrite: Bool { auth.hasScope("page.write") }
    private var canReadDNS: Bool { auth.hasScope("dns.read") }
    private var canWriteDNS: Bool { auth.hasScope("dns.write") }

    var body: some View {
        Group {
            if viewModel.isLoading && !viewModel.loaded {
                SkeletonList(rows: 4, trailing: true)
            } else if viewModel.domains.isEmpty {
                emptyState
            } else {
                domainList
            }
        }
        .background { SkyBackground() }
        .navigationTitle("自定义域名")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("添加域名", systemImage: "plus") {
                    if canWrite { showAdd = true } else { writeDenied = true }
                }
            }
        }
        .task { await viewModel.load(canReadDNS: canReadDNS) }
        .sheet(item: $detailTarget) { domain in
            PagesDomainDetailSheet(
                domain: domain,
                viewModel: viewModel,
                canWrite: canWrite,
                canReadDNS: canReadDNS,
                canWriteDNS: canWriteDNS
            )
        }
        .alert("添加域名", isPresented: $showAdd) {
            addAlertActions
        } message: {
            Text("挂载后需将域名解析指向本项目才能生效。")
        }
        .confirmationDialog(
            Text("删除域名「\(deleteTarget?.name ?? "")」？"),
            isPresented: .init(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除域名", role: .destructive, action: deleteConfirmedDomain)
        } message: {
            Text("将从该 Pages 项目移除此域名，不影响已有 DNS 记录。")
        }
        .sensoryFeedback(.success, trigger: viewModel.didMutate)
        .alert("权限不足", isPresented: $writeDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含 Pages 写权限（page.write）。\n请在设置中退出登录后重新授权以启用此功能。")
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

    @ViewBuilder
    private var addAlertActions: some View {
        // String 重载：占位符不走本地化
        TextField("example.com" as String, text: $newDomain)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        Button("添加", action: addDomain)
        Button("取消", role: .cancel) { newDomain = "" }
    }

    private func addDomain() {
        let name = newDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        newDomain = ""
        guard name.contains("."), !name.contains(" ") else { return }
        Task {
            await viewModel.add(
                name: name,
                canReadDNS: canReadDNS,
                canWriteDNS: auth.hasScope("dns.write")
            )
        }
    }

    private func deleteConfirmedDomain() {
        if let target = deleteTarget {
            Task { await viewModel.delete(target) }
        }
        deleteTarget = nil
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("没有自定义域名", systemImage: "globe")
        } description: {
            Text("绑定你自己的域名，并在此完成解析与验证。")
        } actions: {
            if canWrite {
                Button("添加域名") { showAdd = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.ocOrangePressed)
                    .fontWeight(.bold)
            }
        }
    }

    private var domainList: some View {
        List {
            Section {
                ForEach(viewModel.domains) { domain in
                    Button {
                        detailTarget = domain
                    } label: {
                        domainRow(domain)
                    }
                    .foregroundStyle(.primary)
                    .swipeActions(edge: .trailing) {
                        if canWrite {
                            Button("删除域名", systemImage: "trash", role: .destructive) {
                                deleteTarget = domain
                            }
                        }
                    }
                }
            } footer: {
                Text("\(viewModel.domains.count) 个域名")
            }
            .glassRow()
        }
        .scrollContentBackground(.hidden)
        .refreshable { await viewModel.load(canReadDNS: canReadDNS) }
    }

    private func domainRow(_ domain: PagesDomain) -> some View {
        HStack(spacing: 12) {
            TintIcon(systemImage: "globe", color: .ocOrange)
            VStack(alignment: .leading, spacing: 2) {
                Text(domain.name)
                    .font(.callout.weight(.semibold).monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                if case .missing = viewModel.dnsStates[domain.name] {
                    Text("尚无解析记录")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            PagesDomainStatusBadge(status: domain.statusValue)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 域名详情（状态 / TXT 验证 / DNS 解析 / 操作）

private struct PagesDomainDetailSheet: View {

    let domain: PagesDomain
    let viewModel: PagesDomainsViewModel
    let canWrite: Bool
    let canReadDNS: Bool
    let canWriteDNS: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var dnsWriteDenied = false

    /// 操作后列表会刷新，展示始终取 viewModel 里的最新快照
    private var current: PagesDomain { viewModel.domains.first { $0.id == domain.id } ?? domain }
    private var dnsState: PagesDomainsViewModel.DNSState? { viewModel.dnsStates[current.name] }

    var body: some View {
        NavigationStack {
            List {
                statusSection
                txtSection
                dnsSection
                actionsSection
            }
            .navigationTitle(current.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .confirmationDialog("删除域名「\(current.name)」？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("删除域名", role: .destructive) {
                    Task {
                        if await viewModel.delete(current) { dismiss() }
                    }
                }
            } message: {
                Text("将从该 Pages 项目移除此域名，不影响已有 DNS 记录。")
            }
            .alert("权限不足", isPresented: $dnsWriteDenied) {
                Button("好", role: .cancel) {}
            } message: {
                Text("当前授权未包含 DNS 写权限（dns.write）。\n请在设置中退出登录后重新授权以启用此功能。")
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: 状态

    private var statusSection: some View {
        Section {
            HStack {
                Text("状态")
                Spacer()
                PagesDomainStatusBadge(status: current.statusValue)
            }
            if let target = viewModel.cnameTarget {
                HStack {
                    Text(verbatim: "CNAME")
                    Spacer()
                    Text(target)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .contextMenu {
                    Button("复制", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = target
                    }
                }
            }
        } footer: {
            if let message = current.verificationData?.errorMessage ?? current.validationData?.errorMessage,
               !message.isEmpty {
                Text(message)
            }
        }
    }

    // MARK: TXT 验证（zone 不在 CF 时的归属验证）

    @ViewBuilder
    private var txtSection: some View {
        if let validation = current.validationData,
           validation.method == "txt",
           validation.status != "active",
           let txtName = validation.txtName,
           let txtValue = validation.txtValue {
            Section {
                copyRow(title: Text("记录名"), value: txtName)
                copyRow(title: Text("记录值"), value: txtValue)
            } header: {
                Text("验证 TXT 记录")
            }
        }
    }

    private func copyRow(title: Text, value: String) -> some View {
        HStack {
            title
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contextMenu {
            Button("复制", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = value
            }
        }
    }

    // MARK: DNS 解析

    @ViewBuilder
    private var dnsSection: some View {
        switch dnsState {
        case .resolved(let content):
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("已指向本项目")
                    Spacer()
                    Text(content)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } header: {
                Text(verbatim: "DNS")
            }
        case .conflicting(let content):
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("未指向本项目")
                    Spacer()
                    Text(content)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } header: {
                Text(verbatim: "DNS")
            }
        case .missing:
            Section {
                Button {
                    if canWriteDNS {
                        Task { await viewModel.createCNAME(for: current) }
                    } else {
                        dnsWriteDenied = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        TintIcon(systemImage: "plus.circle", color: .ocOrange)
                        Text("添加 CNAME 记录")
                        if viewModel.isMutating {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.isMutating)
            } header: {
                Text(verbatim: "DNS")
            } footer: {
                if let target = viewModel.cnameTarget {
                    Text("将在该域名所在的区域添加一条已代理的 CNAME 记录，指向 \(target)。")
                }
            }
        case .external:
            Section {
                Text("该域名不在当前账号的 Cloudflare 区域内，请在域名服务商处添加指向 \(viewModel.cnameTarget ?? "") 的 CNAME 记录。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text(verbatim: "DNS")
            }
        case .unknown, nil:
            EmptyView()
        }
    }

    // MARK: 操作

    @ViewBuilder
    private var actionsSection: some View {
        if canWrite {
            Section {
                if current.statusValue != .active {
                    Button {
                        Task { await viewModel.retry(current, canReadDNS: canReadDNS) }
                    } label: {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "arrow.clockwise", color: .blue)
                            Text("重新验证")
                            if viewModel.isMutating {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(viewModel.isMutating)
                }
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    HStack(spacing: 12) {
                        TintIcon(systemImage: "trash", color: .red)
                        Text("删除域名")
                    }
                }
                .disabled(viewModel.isMutating)
            }
        }
    }
}

// MARK: - 状态徽章

struct PagesDomainStatusBadge: View {
    let status: PagesDomainStatus
    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
    private var color: Color {
        switch status {
        case .active:                .green
        case .pending, .initializing: .orange
        case .blocked, .error:       .red
        case .deactivated, .unknown: .gray
        }
    }
}
