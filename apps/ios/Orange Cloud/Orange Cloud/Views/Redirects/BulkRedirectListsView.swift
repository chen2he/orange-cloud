//
//  BulkRedirectListsView.swift
//  Orange Cloud
//
//  Bulk Redirects 重定向列表（account 级）。入口在 Dashboard 网络区。
//

import SwiftUI

struct BulkRedirectListsView: View {

    let session: SessionStore

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: RedirectListsViewModel
    @State private var searchText = ""
    @State private var showCreate = false
    @State private var listToDelete: RedirectList?

    init(session: SessionStore) {
        self.session = session
        _viewModel = State(initialValue: RedirectListsViewModel(
            service: session.bulkRedirectService,
            accountId: session.selectedAccount?.id ?? ""
        ))
    }

    private var canWrite: Bool { auth.hasScope("account-rule-lists.write") }

    private var filtered: [RedirectList] {
        guard !searchText.isEmpty else { return viewModel.lists }
        return viewModel.lists.filter {
            ($0.name ?? "").localizedCaseInsensitiveContains(searchText)
                || ($0.description ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if viewModel.isLoading && !viewModel.loaded {
                SkeletonList(rows: 5, trailing: true)
            } else if viewModel.lists.isEmpty {
                ContentUnavailableView {
                    Label("没有重定向列表", systemImage: "arrowshape.turn.up.right")
                } description: {
                    Text(canWrite
                         ? String(localized: "批量重定向把大量「源 URL → 目标 URL」放进一个列表统一管理。点右上角 + 创建。")
                         : String(localized: "此账号暂无 Bulk Redirects 列表。"))
                } actions: {
                    if canWrite {
                        Button("新建列表") { showCreate = true }
                            .buttonStyle(.borderedProminent).tint(Color.ocOrangePressed).fontWeight(.bold)
                    }
                }
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    Section {
                        ForEach(filtered) { list in
                            NavigationLink {
                                RedirectListDetailView(list: list, session: session)
                            } label: {
                                listRow(list)
                            }
                            .swipeActions(edge: .trailing) {
                                if canWrite {
                                    Button(role: .destructive) { listToDelete = list } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    } footer: {
                        Text("\(viewModel.lists.count) 个重定向列表")
                    }
                    .glassRow()
                }
                .scrollContentBackground(.hidden)
                .refreshable { await detachedRefresh { await viewModel.load() } }
            }
        }
        .background { SkyBackground() }
        .navigationTitle(Text(verbatim: "Bulk Redirects"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索列表")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("添加", systemImage: "plus") {
                    if canWrite { showCreate = true }
                }
                .disabled(!canWrite)
            }
        }
        .task { await viewModel.load() }
        .sensoryFeedback(.success, trigger: viewModel.didMutate)
        .sheet(isPresented: $showCreate) {
            CreateRedirectListSheet(viewModel: viewModel)
        }
        .confirmationDialog(
            "删除重定向列表",
            isPresented: .init(get: { listToDelete != nil }, set: { if !$0 { listToDelete = nil } }),
            titleVisibility: .visible,
            presenting: listToDelete
        ) { list in
            Button("删除「\(list.name ?? "")」", role: .destructive) {
                Task { _ = await viewModel.delete(list) }
            }
        } message: { _ in
            Text("将删除该列表及其所有重定向条目，不可撤销。若仍被启用规则引用，删除可能失败。")
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil }, set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    private func listRow(_ list: RedirectList) -> some View {
        HStack(spacing: 12) {
            TintIcon(systemImage: "arrowshape.turn.up.right", color: .ocOrange)
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name ?? list.id)
                    .font(.callout.weight(.semibold)).lineLimit(1)
                Text(list.description?.isEmpty == false
                     ? list.description!
                     : String(localized: "\(list.numItems ?? 0) 条重定向"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 新建列表

private struct CreateRedirectListSheet: View {

    let viewModel: RedirectListsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !viewModel.isMutating
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("列表名称", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("仅限字母、数字、下划线（如 my_redirects），用于规则表达式引用。")
                }
                Section {
                    TextField("描述（可选）", text: $description)
                }
                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("新建重定向列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if await viewModel.create(
                                name: name.trimmingCharacters(in: .whitespaces),
                                description: description.trimmingCharacters(in: .whitespaces).nilIfEmptyLB
                            ) { dismiss() }
                        }
                    } label: {
                        if viewModel.isMutating { ProgressView() } else { Text("创建").fontWeight(.semibold) }
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(viewModel.isMutating)
            .onDisappear { viewModel.error = nil }
        }
    }
}
