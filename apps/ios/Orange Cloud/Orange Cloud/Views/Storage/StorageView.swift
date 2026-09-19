//
//  StorageView.swift
//  Orange Cloud
//
//  存储 Tab（设计稿 storage.jsx）：SegmentedControl 在 R2 / D1 / KV 间切换，
//  各资源一组玻璃列表行，按 scope 分别门控。
//

import SwiftUI

enum StorageKind: String, CaseIterable, Identifiable {
    case r2, d1, kv

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }

    var requiredScope: String {
        switch self {
        case .r2: "workers-r2.read"
        case .d1: "d1.read"
        case .kv: "workers-kv-storage.read"
        }
    }

    /// 创建 / 删除所需的写权限
    var writeScope: String {
        switch self {
        case .r2: "workers-r2.write"
        case .d1: "d1.write"
        case .kv: "workers-kv-storage.write"
        }
    }

    var featureName: String {
        switch self {
        case .r2: String(localized: "R2 对象存储")
        case .d1: String(localized: "D1 数据库")
        case .kv: String(localized: "KV 存储")
        }
    }

    /// 「+」按钮标题
    var createLabel: LocalizedStringKey {
        switch self {
        case .r2: "创建存储桶"
        case .d1: "创建数据库"
        case .kv: "创建命名空间"
        }
    }
}

/// 存储 Tab 外壳：NavigationStack 常驻，账号切换只重建栈内内容。
/// **不要把 `.id(账号)` 挪回栈外或 MainTabView**：selectedAccount 可能在本 Tab 可见时
/// 才翻转（ensureAccounts 延迟完成/重试），重建可见 NavigationStack 在 iOS 17.0.x
/// 导航栏硬断言必崩（1.8.2(24) 复发根因，详见 DashboardView 注释）。
struct StorageView: View {

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
    }

    var body: some View {
        NavigationStack {
            StorageContent(session: session)
                .id(session.selectedAccount?.id)
        }
    }
}

/// 存储页内容（原 StorageView 本体）：ViewModel 持有的列表随外壳 `.id` 在账号切换时重置。
private struct StorageContent: View {

    @Environment(SessionStore.self) private var session
    @Environment(AuthManager.self) private var auth
    @Environment(EntitlementStore.self) private var entitlements

    @State private var kind: StorageKind = .r2
    @State private var r2ViewModel: R2BucketListViewModel
    @State private var d1ViewModel: D1DatabaseListViewModel
    @State private var kvViewModel: KVNamespaceListViewModel
    @State private var showR2Create = false
    @State private var showD1Create = false
    @State private var showKVCreate = false
    @State private var bucketToDelete: R2Bucket?
    @State private var databaseToDelete: D1Database?
    @State private var namespaceToDelete: KVNamespace?
    @State private var writeDenied = false

    /// 当前段的创建 / 删除是否有写权限（读权限已是进入该段的前置条件）
    private var canWriteCurrent: Bool { auth.hasScope(kind.writeScope) }
    private var canWriteR2: Bool { auth.hasScope(StorageKind.r2.writeScope) }
    private var canWriteD1: Bool { auth.hasScope(StorageKind.d1.writeScope) }
    private var canWriteKV: Bool { auth.hasScope(StorageKind.kv.writeScope) }

    init(session: SessionStore) {
        _r2ViewModel = State(initialValue: R2BucketListViewModel(service: session.r2Service, analyticsService: session.analyticsService))
        _d1ViewModel = State(initialValue: D1DatabaseListViewModel(service: session.d1Service))
        _kvViewModel = State(initialValue: KVNamespaceListViewModel(service: session.kvService))
    }

    var body: some View {
        Group {
            // 整模块 Pro 闸门：免费层不展示存储内容
            if entitlements.isPro {
                proContent
            } else {
                ProLockedView(feature: .storage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background { SkyBackground() }
        .navigationTitle("存储")
        .toolbar {
            // R2 / D1 / KV 三段均提供创建入口（按各自写权限门控）
            if entitlements.isPro, auth.hasScope(kind.requiredScope) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(kind.createLabel, systemImage: "plus") { startCreate() }
                }
            }
        }
        // 三个创建表单与列表共用同一个 VM 并渲染 viewModel.error：列表加载失败后直接点「创建」，
        // 表单会先顶着一条列表的旧错误——打开前清掉。
        .sheet(isPresented: $showR2Create) {
            R2CreateView(viewModel: r2ViewModel, accountId: session.selectedAccount?.id ?? "")
                .onAppear { r2ViewModel.error = nil }
        }
        .sheet(isPresented: $showD1Create) {
            D1CreateView(viewModel: d1ViewModel, accountId: session.selectedAccount?.id ?? "")
                .onAppear { d1ViewModel.error = nil }
        }
        .sheet(isPresented: $showKVCreate) {
            KVCreateView(viewModel: kvViewModel, accountId: session.selectedAccount?.id ?? "")
                .onAppear { kvViewModel.error = nil }
        }
        .sheet(item: $bucketToDelete) { bucket in
            R2BucketDeleteConfirmView(bucket: bucket, viewModel: r2ViewModel, accountId: session.selectedAccount?.id ?? "")
        }
        .sheet(item: $databaseToDelete) { database in
            D1DeleteConfirmView(database: database, viewModel: d1ViewModel, accountId: session.selectedAccount?.id ?? "")
        }
        .sheet(item: $namespaceToDelete) { namespace in
            KVNamespaceDeleteConfirmView(namespace: namespace, viewModel: kvViewModel, accountId: session.selectedAccount?.id ?? "")
        }
        .alert("权限不足", isPresented: $writeDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含此资源的写权限（\(kind.writeScope)）。\n请在设置中退出登录后重新授权以启用此功能。")
        }
        .sensoryFeedback(.success, trigger: r2ViewModel.didCreate)
        .sensoryFeedback(.success, trigger: r2ViewModel.didDelete)
        .sensoryFeedback(.success, trigger: d1ViewModel.didCreate)
        .sensoryFeedback(.success, trigger: d1ViewModel.didDelete)
        .sensoryFeedback(.success, trigger: kvViewModel.didCreate)
        .sensoryFeedback(.success, trigger: kvViewModel.didDelete)
    }

    private var proContent: some View {
        VStack(spacing: 0) {
            Picker("资源类型", selection: $kind) {
                ForEach(StorageKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            if auth.hasScope(kind.requiredScope) {
                content
            } else {
                PermissionDeniedView(featureName: kind.featureName, requiredScope: kind.requiredScope)
                    .frame(maxHeight: .infinity)
            }
        }
        // 宽画布下收进可读宽度并居中（分段控件与列表一起收）
        .ocReadableWidth()
        .task(id: kind) {
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .r2: r2List
        case .d1: d1List
        case .kv: kvList
        }
    }

    // MARK: - R2

    @ViewBuilder
    private var r2List: some View {
        if r2ViewModel.buckets.isEmpty && r2ViewModel.isLoading {
            loadingView
        } else if r2ViewModel.buckets.isEmpty, let error = r2ViewModel.error {
            loadErrorView(error)
        } else if r2ViewModel.buckets.isEmpty {
            ContentUnavailableView {
                Label("没有存储桶", systemImage: "archivebox")
            } description: {
                Text(canWriteR2 ? String(localized: "点击右上角 + 创建第一个存储桶") : String(localized: "当前授权仅限读取，无法创建存储桶"))
            } actions: {
                if canWriteR2 {
                    Button("创建存储桶") { showR2Create = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.ocOrangePressed)
                        .fontWeight(.bold)
                }
            }
            .frame(maxHeight: .infinity)
        } else {
            List(r2ViewModel.buckets) { bucket in
                NavigationLink {
                    R2ObjectListView(bucket: bucket, session: session)
                } label: {
                    StorageRow(
                        icon: "externaldrive", tint: .ocOrange, mono: false,
                        name: bucket.name,
                        sub: r2Subtitle(for: bucket)
                    )
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        if canWriteR2 { bucketToDelete = bucket } else { writeDenied = true }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .glassRow()
            }
            .scrollContentBackground(.hidden)
            .refreshable { await load() }
        }
    }

    /// 桶副标题：有用量数据时显示存储/对象/请求，否则回退到位置 · 创建日期
    private func r2Subtitle(for bucket: R2Bucket) -> String {
        if let usage = r2ViewModel.usageByBucket[bucket.name], usage.storageBytes > 0 || usage.objectCount > 0 {
            var parts = [Int64(usage.storageBytes).ocBytes]
            if usage.objectCount > 0 { parts.append(String(localized: "\(usage.objectCount) 个对象")) }
            if usage.totalRequests > 0 { parts.append(String(localized: "本月 \(usage.totalRequests.formatted()) 次操作")) }
            return parts.joined(separator: " · ")
        }
        return [bucket.location, WorkerScript.parseDate(bucket.creationDate).map { $0.formatted(.dateTime.year().month().day()) }]
            .compactMap(\.self).joined(separator: " · ")
    }

    // MARK: - D1

    @ViewBuilder
    private var d1List: some View {
        if d1ViewModel.databases.isEmpty && d1ViewModel.isLoading {
            loadingView
        } else if d1ViewModel.databases.isEmpty, let error = d1ViewModel.error {
            loadErrorView(error)
        } else if d1ViewModel.databases.isEmpty {
            ContentUnavailableView {
                Label("没有数据库", systemImage: "cylinder")
            } description: {
                Text(canWriteD1 ? String(localized: "点击右上角 + 创建第一个数据库") : String(localized: "当前授权仅限读取，无法创建数据库"))
            } actions: {
                if canWriteD1 {
                    Button("创建数据库") { showD1Create = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.ocOrangePressed)
                        .fontWeight(.bold)
                }
            }
            .frame(maxHeight: .infinity)
        } else {
            List(d1ViewModel.databases) { database in
                NavigationLink {
                    D1QueryView(database: database, session: session)
                } label: {
                    StorageRow(
                        icon: "cylinder", tint: .blue, mono: true,
                        name: database.name,
                        sub: [
                            database.fileSize.map { Int64($0).ocBytes },
                            database.numTables.map { String(localized: "\($0) 张表") },
                        ].compactMap(\.self).joined(separator: " · ")
                    )
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        if canWriteD1 { databaseToDelete = database } else { writeDenied = true }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .glassRow()
            }
            .scrollContentBackground(.hidden)
            .refreshable { await load() }
        }
    }

    // MARK: - KV

    @ViewBuilder
    private var kvList: some View {
        if kvViewModel.namespaces.isEmpty && kvViewModel.isLoading {
            loadingView
        } else if kvViewModel.namespaces.isEmpty, let error = kvViewModel.error {
            loadErrorView(error)
        } else if kvViewModel.namespaces.isEmpty {
            ContentUnavailableView {
                Label("没有命名空间", systemImage: "key")
            } description: {
                Text(canWriteKV ? String(localized: "点击右上角 + 创建第一个命名空间") : String(localized: "当前授权仅限读取，无法创建命名空间"))
            } actions: {
                if canWriteKV {
                    Button("创建命名空间") { showKVCreate = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.ocOrangePressed)
                        .fontWeight(.bold)
                }
            }
            .frame(maxHeight: .infinity)
        } else {
            List(kvViewModel.namespaces) { namespace in
                NavigationLink {
                    KVKeyListView(namespace: namespace, session: session)
                } label: {
                    StorageRow(
                        icon: "key", tint: .green, mono: true,
                        name: namespace.title,
                        sub: namespace.id
                    )
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        if canWriteKV { namespaceToDelete = namespace } else { writeDenied = true }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .glassRow()
            }
            .scrollContentBackground(.hidden)
            .refreshable { await load() }
        }
    }

    // MARK: - 公共状态

    private var loadingView: some View {
        SkeletonList(rows: 7)
    }

    /// 「+」按钮：有写权限则弹对应创建表单，否则提示权限不足
    private func startCreate() {
        guard canWriteCurrent else { writeDenied = true; return }
        switch kind {
        case .r2: showR2Create = true
        case .d1: showD1Create = true
        case .kv: showKVCreate = true
        }
    }

    /// 列表加载失败（403 / 断网）以前没有任何展示，看起来跟「账号里没有资源」一模一样，
    /// 创建表单反而会替它显示这条错误。这里给一个带重试的失败态。
    private func loadErrorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("加载失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重试") { Task { await load() } }
                .buttonStyle(.borderedProminent)
        }
    }

    private func load() async {
        guard auth.hasScope(kind.requiredScope) else { return }
        await session.ensureAccounts()
        guard let accountId = session.selectedAccount?.id else { return }
        switch kind {
        case .r2: await r2ViewModel.load(accountId: accountId)
        case .d1: await d1ViewModel.load(accountId: accountId)
        case .kv: await kvViewModel.load(accountId: accountId)
        }
    }
}

// MARK: - 存储行（设计稿 StorageRow）

private struct StorageRow: View {
    let icon: String
    let tint: Color
    let mono: Bool
    let name: String
    let sub: String

    var body: some View {
        HStack(spacing: 12) {
            TintIcon(systemImage: icon, color: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(mono ? .callout.weight(.semibold).monospaced() : .body.weight(.semibold))
                    .lineLimit(1)
                if !sub.isEmpty {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
