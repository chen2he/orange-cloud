//
//  KVKeyListView.swift
//  Orange Cloud
//
//  KV 键列表（游标分页 + 滑动删除）→ 值查看/编辑。
//  入口：StorageView 的 KV 段。
//

import SwiftUI

struct KVKeyListView: View {

    let namespace: KVNamespace

    @Environment(SessionStore.self) private var session
    @Environment(AuthManager.self) private var auth
    @State private var viewModel: KVKeyListViewModel
    @State private var searchText = ""
    @State private var keyToDelete: KVKey?
    @State private var showDenied = false

    init(namespace: KVNamespace, session: SessionStore) {
        self.namespace = namespace
        _viewModel = State(initialValue: KVKeyListViewModel(
            service: session.kvService,
            accountId: session.selectedAccount?.id ?? "",
            namespaceId: namespace.id
        ))
    }

    private var canWrite: Bool { auth.hasScope("workers-kv-storage.write") }

    private var filteredKeys: [KVKey] {
        guard !searchText.isEmpty else { return viewModel.keys }
        return viewModel.keys.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if viewModel.keys.isEmpty && viewModel.isLoading {
                SkeletonList(rows: 10, icon: .none)
            } else if viewModel.keys.isEmpty {
                ContentUnavailableView {
                    Label("空命名空间", systemImage: "square.grid.2x2")
                } description: {
                    Text("这个命名空间里还没有键")
                }
            } else if filteredKeys.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                keyList
            }
        }
        .background { SkyBackground() }
        .navigationTitle(namespace.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索键名")
        .task { await viewModel.load() }
        .confirmationDialog(
            "删除键",
            isPresented: .init(
                get: { keyToDelete != nil },
                set: { if !$0 { keyToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let key = keyToDelete {
                Button("删除 \(key.name)", role: .destructive) {
                    Task { _ = await viewModel.delete(key: key.name) }
                }
            }
        } message: {
            Text("此操作不可撤销。")
        }
        .alert("权限不足", isPresented: $showDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含 KV 编辑权限（workers-kv-storage.write）。\n请在设置中退出登录后重新授权以启用此功能。")
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            apiErrorDocButton(for: viewModel.error)
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    private var keyList: some View {
        List {
            ForEach(filteredKeys) { key in
                NavigationLink {
                    KVValueView(namespace: namespace, kvKey: key, session: session)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(key.name)
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let expiry = key.expirationDate {
                            Text("过期：\(expiry, format: .dateTime.year().month().day().hour().minute())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        if canWrite {
                            keyToDelete = key
                        } else {
                            showDenied = true
                        }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .glassRow()
            }
            if viewModel.hasMore && searchText.isEmpty {
                Button {
                    Task { await viewModel.loadMore() }
                } label: {
                    if viewModel.isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("加载更多").frame(maxWidth: .infinity)
                    }
                }
                .glassRow()
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable { await viewModel.load() }
    }
}

// MARK: - 值查看 / 编辑

struct KVValueView: View {

    let namespace: KVNamespace

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: KVValueViewModel

    init(namespace: KVNamespace, kvKey: KVKey, session: SessionStore) {
        self.namespace = namespace
        _viewModel = State(initialValue: KVValueViewModel(
            service: session.kvService,
            accountId: session.selectedAccount?.id ?? "",
            namespaceId: namespace.id,
            key: kvKey.name
        ))
    }

    private var canWrite: Bool { auth.hasScope("workers-kv-storage.write") }

    var body: some View {
        Group {
            if viewModel.isLoading {
                valueSkeleton
            } else if viewModel.isBinary {
                ContentUnavailableView {
                    Label("二进制数据", systemImage: "doc.zipper")
                } description: {
                    Text("该值不是 UTF-8 文本（\(Int64(viewModel.byteCount).ocBytes)），暂不支持预览")
                }
            } else {
                editor
            }
        }
        .navigationTitle(viewModel.key)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canWrite && !viewModel.isBinary && !viewModel.isLoading {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { _ = await viewModel.save() }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                        } else {
                            Text("保存").fontWeight(.semibold)
                        }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
        }
        .task { await viewModel.load() }
        .sensoryFeedback(.success, trigger: viewModel.didSave)
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            apiErrorDocButton(for: viewModel.error)
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    /// 值加载骨架：按编辑器形状铺几行文本占位
    private var valueSkeleton: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<7, id: \.self) { index in
                    SkeletonBlock(width: 140 + CGFloat((index * 67) % 160), height: 11)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(16)
            .glassIsland(cornerRadius: OCLayout.chipRadius)
            SkeletonBlock(width: 80, height: 10)
        }
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
        .background { SkyBackground() }
        .skeletonPulse()
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if canWrite {
                TextEditor(text: Binding(
                    get: { viewModel.valueText },
                    set: { viewModel.valueText = $0 }
                ))
                .font(.callout.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .scrollContentBackground(.hidden)
                .padding(8)
                .glassIsland(cornerRadius: OCLayout.chipRadius)
            } else {
                ScrollView {
                    Text(viewModel.valueText)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .glassIsland(cornerRadius: OCLayout.chipRadius)
            }

            Label {
                Text("\(Int64(viewModel.byteCount).ocBytes)\(canWrite ? "" : String(localized: " · 只读授权"))")
            } icon: {
                Image(systemName: canWrite ? "pencil" : "lock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background { SkyBackground() }
    }
}
