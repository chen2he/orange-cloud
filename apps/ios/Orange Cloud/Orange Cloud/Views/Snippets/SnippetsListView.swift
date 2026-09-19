//
//  SnippetsListView.swift
//  Orange Cloud
//
//  Snippets 列表：查看 / 新建，写操作按 snippets.write 门控。
//  入口在域名详情，整体已由 ProGatedNavigationLink 先验 Pro + snippets.read。
//

import SwiftUI

struct SnippetsListView: View {

    let zoneName: String

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: SnippetsViewModel
    @State private var showDenied = false
    @State private var showEditor = false
    @State private var searchText = ""

    init(zoneId: String, zoneName: String, session: SessionStore) {
        self.zoneName = zoneName
        _viewModel = State(initialValue: SnippetsViewModel(service: session.snippetService, zoneId: zoneId))
    }

    private var canWrite: Bool { auth.hasScope("snippets.write") }

    private var filteredSnippets: [Snippet] {
        guard !searchText.isEmpty else { return viewModel.snippets }
        return viewModel.snippets.filter { $0.snippetName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if viewModel.isLoading && !viewModel.loaded {
                SkeletonList(rows: 5, icon: .none, trailing: true)
            } else if viewModel.snippets.isEmpty {
                ContentUnavailableView {
                    Label("还没有 Snippet", systemImage: "curlybraces")
                } description: {
                    Text(canWrite
                         ? String(localized: "Snippets 是 Cloudflare Pro 及以上套餐的边缘 JS 能力。点击右上角 + 创建第一个。")
                         : String(localized: "Snippets 需要 Cloudflare Pro 及以上套餐，且当前授权未包含编辑权限。"))
                } actions: {
                    if canWrite {
                        Button("新建 Snippet") { showEditor = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.ocOrangePressed)
                            .fontWeight(.bold)
                    }
                }
            } else if filteredSnippets.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    Section {
                        ForEach(filteredSnippets) { snippet in
                            NavigationLink {
                                SnippetDetailView(snippet: snippet, zoneName: zoneName, viewModel: viewModel)
                            } label: {
                                SnippetRow(
                                    snippet: snippet,
                                    ruleCount: viewModel.rules(for: snippet.snippetName).count
                                )
                            }
                        }
                    } footer: {
                        Text(canWrite
                             ? String(localized: "每个 Snippet 需配触发规则才会执行，进入详情可管理代码与规则。")
                             : String(localized: "当前授权仅限读取（snippets.read），无法新建或修改。"))
                    }
                    .glassRow()
                }
                .scrollContentBackground(.hidden)
                .refreshable { await detachedRefresh { await viewModel.load() } }
            }
        }
        .background { SkyBackground() }
        .navigationTitle("Snippets")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索 Snippet")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("新建", systemImage: "plus") {
                    if canWrite { showEditor = true } else { showDenied = true }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            SnippetEditorView(viewModel: viewModel, existing: nil)
        }
        .task { await viewModel.load() }
        .alert("权限不足", isPresented: $showDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含 Snippets 编辑权限（snippets.write）。\n请在设置中退出登录后重新授权以启用此功能。")
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil && !showEditor },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }
}

// MARK: - 列表行

private struct SnippetRow: View {

    let snippet: Snippet
    let ruleCount: Int

    var body: some View {
        HStack(spacing: 12) {
            TintIcon(systemImage: "curlybraces", color: .ocOrange)
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.snippetName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(ruleCount == 0
                     ? String(localized: "未配置触发规则")
                     : String(localized: "\(ruleCount) 条触发规则"))
                    .font(.caption)
                    .foregroundStyle(ruleCount == 0 ? Color.orange : Color.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
