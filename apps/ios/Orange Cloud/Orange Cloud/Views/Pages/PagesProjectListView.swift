//
//  PagesProjectListView.swift
//  Orange Cloud
//
//  Cloudflare Pages 项目列表（account 级）。入口在 Workers Tab 顶部。
//

import SwiftUI

struct PagesProjectListView: View {

    let session: SessionStore

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: PagesProjectListViewModel
    @State private var searchText = ""
    @State private var showCreate = false
    @State private var writeDenied = false
    @AppStorage("pagesListSort") private var sort: ResourceSort = .name

    /// 创建项目需要写权限（page.read 已是进入本页的前置条件）
    private var canWrite: Bool { auth.hasScope("page.write") }

    init(session: SessionStore) {
        self.session = session
        _viewModel = State(initialValue: PagesProjectListViewModel(service: session.pagesService))
    }

    private var filtered: [PagesProject] {
        let projects = searchText.isEmpty
            ? viewModel.projects
            : viewModel.projects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        return sort.sorted(
            projects,
            created: \.createdOn,
            modified: { $0.latestDeployment?.modifiedOn ?? $0.latestDeployment?.createdOn ?? $0.createdOn }
        )
    }

    var body: some View {
        Group {
            if viewModel.isLoading && !viewModel.loaded {
                SkeletonList(rows: 6, trailing: true)
            } else if viewModel.projects.isEmpty {
                ContentUnavailableView {
                    Label("没有 Pages 项目", systemImage: "doc.richtext")
                } description: {
                    Text(canWrite ? String(localized: "点击右上角 + 创建项目，或在此查看部署、重试 / 回滚与构建配置。") : String(localized: "在 Cloudflare Dashboard 创建 Pages 项目后，在此查看部署、重试 / 回滚与构建配置。"))
                } actions: {
                    if canWrite {
                        Button("创建项目") { showCreate = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.ocOrangePressed)
                            .fontWeight(.bold)
                    }
                }
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    Section {
                        ForEach(filtered) { project in
                            // 项目详情自身还要 push（域名/部署/构建配置），行必须值式：
                            // 本页已被 value push 进 DevHub 栈，行内 eager 目的页再 push 会失灵
                            NavigationLink(value: PagesProjectRoute(project: project)) {
                                PagesProjectRow(project: project)
                            }
                        }
                    } footer: {
                        Text("\(viewModel.projects.count) 个项目")
                    }
                    .glassRow()
                }
                .scrollContentBackground(.hidden)
                .refreshable { await detachedRefresh { await load() } }
            }
        }
        .background { SkyBackground() }
        .navigationTitle(Text(verbatim: "Pages"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索项目")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ResourceSortMenu(sort: $sort)
            }
            .ocPriority(.secondary)
            ToolbarItem(placement: .topBarTrailing) {
                Button("创建项目", systemImage: "plus") {
                    if canWrite { showCreate = true } else { writeDenied = true }
                }
            }
            .ocPriority(.primary)
        }
        .sheet(isPresented: $showCreate) {
            PagesCreateView(viewModel: viewModel, accountId: session.selectedAccount?.id ?? "")
        }
        .sensoryFeedback(.success, trigger: viewModel.didCreate)
        .task { await load() }
        .alert("权限不足", isPresented: $writeDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含 Pages 写权限（page.write）。\n请在设置中退出登录后重新授权以启用此功能。")
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil }, set: { if !$0 { viewModel.error = nil } }
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

private struct PagesProjectRow: View {
    let project: PagesProject
    var body: some View {
        HStack(spacing: 12) {
            TintIcon(systemImage: "doc.richtext", color: .ocOrange)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                if let sub = project.subdomain {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if let status = project.latestDeployment?.status, status != .unknown {
                PagesStatusBadge(status: status)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 部署状态徽章（列表 / 详情 / 阶段共用）
struct PagesStatusBadge: View {
    let status: PagesDeployStatus
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
        case .success:            .green
        case .active, .idle:      .orange
        case .failure:            .red
        case .canceled, .unknown: .gray
        }
    }
}

/// Pages 项目行的值式路由（宿主 DevHub 栈根解析）。PagesProject 嵌套配置类型多、
/// 未整体 Hashable，按项目名做导航身份（同账号下项目名唯一）。
nonisolated struct PagesProjectRoute: Hashable {
    let project: PagesProject

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.project.name == rhs.project.name }
    func hash(into hasher: inout Hasher) { hasher.combine(project.name) }
}
