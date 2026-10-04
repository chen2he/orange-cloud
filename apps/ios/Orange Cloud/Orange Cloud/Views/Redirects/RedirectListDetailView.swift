//
//  RedirectListDetailView.swift
//  Orange Cloud
//
//  重定向列表详情：启用开关（管理 http_request_redirect 规则）+ 条目（异步增删）。
//  条目的增删是 Cloudflare 异步批量操作，提交后轮询至完成再刷新。
//

import SwiftUI

struct RedirectListDetailView: View {

    @State private var viewModel: RedirectListDetailViewModel
    @State private var showItemEditor = false
    @State private var itemToDelete: RedirectListItem?
    @Environment(AuthManager.self) private var auth

    init(list: RedirectList, session: SessionStore) {
        _viewModel = State(initialValue: RedirectListDetailViewModel(
            list: list,
            accountId: session.selectedAccount?.id ?? "",
            service: session.bulkRedirectService
        ))
    }

    private var canWriteItems: Bool { auth.hasScope("account-rule-lists.write") }
    private var canEnable: Bool { auth.hasScope("mass-url-redirects.write") }

    var body: some View {
        List {
            enableSection
            itemsSection
        }
        .daybreakList()
        .navigationTitle(viewModel.list.name ?? String(localized: "重定向列表"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("添加", systemImage: "plus") {
                    if canWriteItems { showItemEditor = true }
                }
                .disabled(!canWriteItems || viewModel.isMutating)
            }
        }
        .task {
            await viewModel.loadItems()
            await viewModel.loadEnableStatus()
        }
        .sensoryFeedback(.success, trigger: viewModel.didMutate)
        .sheet(isPresented: $showItemEditor) {
            RedirectItemEditorView(viewModel: viewModel)
        }
        .confirmationDialog(
            "删除重定向",
            isPresented: .init(get: { itemToDelete != nil }, set: { if !$0 { itemToDelete = nil } }),
            titleVisibility: .visible,
            presenting: itemToDelete
        ) { item in
            Button("删除", role: .destructive) {
                Task { _ = await viewModel.deleteItem(item) }
            }
        } message: { item in
            Text("将删除「\(item.redirect?.sourceUrl ?? "")」这条重定向。")
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

    private var enableSection: some View {
        Section {
            if !viewModel.enableLoaded {
                HStack {
                    Text("启用此列表的重定向")
                    Spacer()
                    ProgressView()
                }
            } else if canEnable {
                Toggle(isOn: Binding(
                    get: { viewModel.isEnabled },
                    set: { on in Task { _ = await viewModel.setEnabled(on) } }
                )) {
                    Text("启用此列表的重定向")
                }
                .disabled(viewModel.isMutating)
            } else {
                HStack {
                    Text("启用此列表的重定向")
                    Spacer()
                    Text(viewModel.isEnabled ? String(localized: "已启用") : String(localized: "未启用"))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("启用")
        } footer: {
            Text("启用后，列表中的重定向才会经 http_request_redirect 规则实际生效。停用只关闭规则，不删除条目。")
        }
        .glassRow()
    }

    private var itemsSection: some View {
        Section {
            if viewModel.isLoadingItems && !viewModel.itemsLoaded {
                ProgressView().frame(maxWidth: .infinity)
            } else if viewModel.items.isEmpty {
                Text(canWriteItems
                     ? String(localized: "暂无重定向条目，点右上角 + 添加。")
                     : String(localized: "暂无重定向条目。"))
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.items) { item in
                    itemRow(item)
                        .swipeActions(edge: .trailing) {
                            if canWriteItems {
                                Button(role: .destructive) { itemToDelete = item } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                }
            }
        } header: {
            HStack {
                Text("重定向条目")
                Spacer()
                if let status = viewModel.statusText {
                    ProgressView().controlSize(.small)
                    Text(status).font(.caption).foregroundStyle(.secondary).textCase(nil)
                }
            }
        } footer: {
            Text("增删条目为 Cloudflare 异步操作，提交后稍候即生效。")
        }
        .glassRow()
    }

    private func itemRow(_ item: RedirectListItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(item.redirect?.sourceUrl ?? "")
                    .font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Spacer()
                if let code = item.redirect?.statusCode {
                    Text("\(code)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.ocOrange.opacity(0.14), in: Capsule())
                        .foregroundStyle(Color.ocOrangeText)
                }
            }
            HStack(spacing: 4) {
                Image(systemName: "arrow.turn.down.right").font(.caption2).foregroundStyle(.tertiary)
                Text(item.redirect?.targetUrl ?? "")
                    .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 条目编辑器（新增）

private struct RedirectItemEditorView: View {

    let viewModel: RedirectListDetailViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var sourceUrl = ""
    @State private var targetUrl = ""
    @State private var statusCode: RedirectStatusCode = .movedPermanently
    @State private var includeSubdomains = false
    @State private var subpathMatching = false
    @State private var preserveQueryString = false
    @State private var preservePathSuffix = true

    private var canSave: Bool {
        !sourceUrl.trimmingCharacters(in: .whitespaces).isEmpty
            && !targetUrl.trimmingCharacters(in: .whitespaces).isEmpty
            && !viewModel.isMutating
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("源 URL，如 example.com/old", text: $sourceUrl)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("目标 URL，如 https://example.com/new", text: $targetUrl)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Picker("状态码", selection: $statusCode) {
                        ForEach(RedirectStatusCode.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("重定向")
                }

                Section {
                    Toggle("包含子域名", isOn: $includeSubdomains)
                    Toggle("子路径匹配", isOn: $subpathMatching)
                    Toggle("保留查询字符串", isOn: $preserveQueryString)
                    if subpathMatching {
                        Toggle("保留剩余路径", isOn: $preservePathSuffix)
                    }
                } header: {
                    Text("选项")
                } footer: {
                    Text("子路径匹配开启后，「保留剩余路径」才生效。")
                }

                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("添加重定向")
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
        let redirect = RedirectRule(
            sourceUrl: sourceUrl.trimmingCharacters(in: .whitespaces),
            targetUrl: targetUrl.trimmingCharacters(in: .whitespaces),
            statusCode: statusCode.rawValue,
            includeSubdomains: includeSubdomains,
            subpathMatching: subpathMatching,
            preserveQueryString: preserveQueryString,
            preservePathSuffix: subpathMatching ? preservePathSuffix : nil
        )
        if await viewModel.addItem(redirect) {
            dismiss()
        }
    }
}
