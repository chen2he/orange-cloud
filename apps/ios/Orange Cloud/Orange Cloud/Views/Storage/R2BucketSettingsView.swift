//
//  R2BucketSettingsView.swift
//  Orange Cloud
//
//  R2 桶设置：公开访问（r2.dev 托管域）、自定义域、CORS 规则。
//  入口：R2 对象列表右上角齿轮。写操作按 workers-r2.write 门控。
//

import SwiftUI

struct R2BucketSettingsView: View {

    let canWrite: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth
    @Environment(EntitlementStore.self) private var entitlements
    @State private var viewModel: R2BucketSettingsViewModel
    @State private var catalogViewModel: R2CatalogViewModel
    @State private var showCatalogEnableConfirm = false
    @State private var showAddCors = false
    @State private var showDenied = false
    @State private var showSQLConsole = false

    // 文件 App 挂载（Pro）
    private let bucketName: String
    /// 区域限制桶的辖区：挂载时编进 domain，extension 的每个请求都要带 cf-r2-jurisdiction 头
    private let jurisdiction: String?
    /// GraphQL 分析口径的桶名（区域限制桶带 eu_ / us_ 前缀），按桶查带宽用
    private let analyticsBucketName: String
    /// 本桶近 30 天带宽（best-effort，账户级 GraphQL 不可用时为 nil，整段隐藏）
    @State private var bandwidth: R2Bandwidth?
    private let accountId: String
    private let session: SessionStore
    @State private var isMounted = false
    @State private var isMountBusy = false
    @State private var mountPaywall = false

    init(bucket: R2Bucket, session: SessionStore, canWrite: Bool) {
        self.canWrite = canWrite
        self.bucketName = bucket.name
        self.jurisdiction = bucket.jurisdiction
        self.analyticsBucketName = bucket.analyticsBucketName
        self.accountId = session.selectedAccount?.id ?? ""
        self.session = session
        _viewModel = State(initialValue: R2BucketSettingsViewModel(
            service: session.r2Service,
            accountId: session.selectedAccount?.id ?? "",
            bucketName: bucket.name,
            jurisdiction: bucket.jurisdiction
        ))
        _catalogViewModel = State(initialValue: R2CatalogViewModel(
            service: session.r2CatalogService,
            accountId: session.selectedAccount?.id ?? "",
            bucketName: bucket.name
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                bandwidthSection
                filesSection
                managedSection
                customDomainsSection
                dataCatalogSection
                corsSection
            }
            .navigationTitle("桶设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task { await refreshMountState() }
            .task {
                guard !accountId.isEmpty else { return }
                bandwidth = try? await session.analyticsService.r2Bandwidth(
                    accountId: accountId, bucketName: analyticsBucketName
                )
            }
            .task { if auth.hasScope("r2-catalog.read") { await catalogViewModel.load() } }
            .confirmationDialog(
                "启用数据目录",
                isPresented: $showCatalogEnableConfirm,
                titleVisibility: .visible
            ) {
                Button("启用") { Task { await catalogViewModel.setEnabled(true) } }
            } message: {
                Text("启用后该桶将作为 Apache Iceberg 目录，目录操作按量计费（每月含 100 万次免费额度）。")
            }
            .sheet(isPresented: $mountPaywall) {
                PaywallView(feature: .filesApp)
            }
            .overlay {
                if viewModel.isLoading && viewModel.managedDomain == nil
                    && viewModel.customDomains.isEmpty && viewModel.corsRules.isEmpty {
                    ProgressView()
                }
            }
            .task { await viewModel.load() }
            .sheet(isPresented: $showAddCors) {
                R2CorsRuleEditor { origins, methods, maxAge in
                    Task { await viewModel.addCorsRule(origins: origins, methods: methods, maxAgeSeconds: maxAge) }
                }
            }
            .sheet(isPresented: $showSQLConsole) {
                R2SQLQueryView(session: session, accountId: accountId, bucketName: bucketName)
            }
            .alert("权限不足", isPresented: $showDenied) {
                Button("好", role: .cancel) {}
            } message: {
                Text("当前授权未包含 R2 写权限（workers-r2.write）。\n请在设置中退出登录后重新授权以启用此功能。")
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
            .sensoryFeedback(.success, trigger: viewModel.didChange)
        }
    }

    // MARK: - 带宽（近 30 天）

    @ViewBuilder
    private var bandwidthSection: some View {
        if let bandwidth {
            Section {
                R2BandwidthRow(bandwidth: bandwidth)
            } header: {
                Text("带宽（近 30 天）")
            } footer: {
                Text("不含小于 100 KiB 的传输")
            }
        }
    }

    // MARK: - 文件 App 挂载（Pro，旗舰功能）

    @ViewBuilder
    private var filesSection: some View {
        Section {
            if entitlements.isPro {
                Toggle(isOn: Binding(
                    get: { isMounted },
                    set: { want in Task { await setMounted(want) } }
                )) {
                    Label("在「文件」App 中显示", systemImage: "folder.badge.gearshape")
                }
                .disabled(isMountBusy || accountId.isEmpty || auth.currentSessionId == nil)
            } else {
                Button {
                    mountPaywall = true
                } label: {
                    HStack {
                        Label("在「文件」App 中显示", systemImage: "folder.badge.gearshape")
                            .foregroundStyle(.primary)
                        Spacer()
                        ProBadge()
                    }
                }
            }
        } header: {
            Text("文件 App")
        } footer: {
            Text("打开后，这个存储桶会像 iCloud 云盘一样出现在系统「文件」App 里，可浏览、读取、上传、删除，并用任意 App 打开。单个文件上传上限约 300 MB（Cloudflare API 限制）。")
        }
    }

    private func refreshMountState() async {
        guard entitlements.isPro, let sid = auth.currentSessionId, !accountId.isEmpty else { return }
        isMounted = await FileProviderMountManager.isMounted(
            sessionId: sid, accountId: accountId, bucketName: bucketName, jurisdiction: jurisdiction
        )
    }

    private func setMounted(_ want: Bool) async {
        guard let sid = auth.currentSessionId, !accountId.isEmpty else { return }
        isMountBusy = true
        defer { isMountBusy = false }
        do {
            if want {
                try await FileProviderMountManager.mount(
                    sessionId: sid, accountId: accountId, bucketName: bucketName, jurisdiction: jurisdiction
                )
            } else {
                try await FileProviderMountManager.unmount(
                    sessionId: sid, accountId: accountId, bucketName: bucketName, jurisdiction: jurisdiction
                )
            }
        } catch {
            viewModel.error = error.localizedDescription
        }
        // 以系统真实状态为准回填开关
        isMounted = await FileProviderMountManager.isMounted(
            sessionId: sid, accountId: accountId, bucketName: bucketName, jurisdiction: jurisdiction
        )
    }

    // MARK: - 公开访问（r2.dev）

    private var managedSection: some View {
        Section {
            Toggle("启用 r2.dev 公开访问", isOn: Binding(
                get: { viewModel.managedDomain?.enabled ?? false },
                set: { newValue in
                    guard canWrite else { showDenied = true; return }
                    Task { await viewModel.setManagedEnabled(newValue) }
                }
            ))
            .disabled(viewModel.isSaving)

            if let domain = viewModel.managedDomain?.domain, !domain.isEmpty {
                LabeledContent("地址") {
                    Text(domain)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text("公开开发 URL")
        } footer: {
            Text("通过 Cloudflare 托管的 r2.dev 子域公开访问，仅供开发测试，有速率限制；生产请用自定义域。")
        }
    }

    // MARK: - 自定义域

    private var customDomainsSection: some View {
        Section("自定义域") {
            if viewModel.customDomains.isEmpty {
                Text("未连接自定义域")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.customDomains) { domain in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(domain.domain)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: 6) {
                            Text((domain.enabled ?? false) ? "已启用" : "已停用")
                                .font(.caption)
                                .foregroundStyle((domain.enabled ?? false) ? Color.ocOrangeText : .secondary)
                            if let ssl = domain.status?.ssl { badge(ssl) }
                            if let ownership = domain.status?.ownership { badge(ownership) }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            if canWrite {
                                Task { await viewModel.removeCustomDomain(domain.domain) }
                            } else {
                                showDenied = true
                            }
                        } label: {
                            Label("移除", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - CORS

    /// R2 数据目录（Iceberg）。启用是计费动作，故走二次确认。
    @ViewBuilder
    private var dataCatalogSection: some View {
        if auth.hasScope("r2-catalog.read") {
            Section {
                if catalogViewModel.isLoading && !catalogViewModel.loaded {
                    ProgressView()
                } else {
                    Toggle("启用数据目录", isOn: Binding(
                        get: { catalogViewModel.isEnabled },
                        set: { on in
                            if on {
                                showCatalogEnableConfirm = true
                            } else {
                                Task { await catalogViewModel.setEnabled(false) }
                            }
                        }
                    ))
                    .disabled(!auth.hasScope("r2-catalog.write") || catalogViewModel.isMutating)

                    if let catalog = catalogViewModel.catalog, catalogViewModel.isEnabled {
                        if let name = catalog.name {
                            LabeledContent("目录名") {
                                Text(name)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                        if let compaction = catalog.maintenanceConfig?.compaction?.state {
                            LabeledContent("自动压实", value: compaction == "enabled"
                                           ? String(localized: "已开启") : String(localized: "已关闭"))
                        }
                        if catalogViewModel.namespaces.isEmpty {
                            Text("暂无命名空间")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(catalogViewModel.namespaces) { namespace in
                                Text(namespace.displayName)
                                    .font(.caption.monospaced())
                            }
                        }
                        // R2 SQL 控制台（2026-08 起计费：$0.0025/GB 扫描、10GB/月免费）
                        if auth.hasScope("r2-catalog-sql.read") {
                            Button {
                                showSQLConsole = true
                            } label: {
                                Label("R2 SQL 查询", systemImage: "terminal")
                            }
                        }
                    }
                }
            } header: {
                Text("数据目录")
            } footer: {
                Text("把这个桶变成可被 Spark、Snowflake 等引擎查询的 Iceberg 数据仓库。注意：目录已启用时手动删除对象会破坏目录。")
            }
        }
    }

    private var corsSection: some View {
        Section {
            if viewModel.corsRules.isEmpty {
                Text("未配置 CORS 规则")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(viewModel.corsRules.enumerated()), id: \.offset) { index, rule in
                    VStack(alignment: .leading, spacing: 4) {
                        if let origins = rule.allowed?.origins, !origins.isEmpty {
                            Text(origins.joined(separator: ", "))
                                .font(.callout)
                                .lineLimit(2)
                        }
                        HStack(spacing: 6) {
                            ForEach(rule.allowed?.methods ?? [], id: \.self) { method in
                                badge(method)
                            }
                            if let age = rule.maxAgeSeconds {
                                Text("\(age)s")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            if canWrite {
                                Task { await viewModel.deleteCorsRule(at: index) }
                            } else {
                                showDenied = true
                            }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }

            Button {
                if canWrite { showAddCors = true } else { showDenied = true }
            } label: {
                Label("添加 CORS 规则", systemImage: "plus")
            }

            if !viewModel.corsRules.isEmpty {
                Button(role: .destructive) {
                    if canWrite {
                        Task { await viewModel.clearCors() }
                    } else {
                        showDenied = true
                    }
                } label: {
                    Label("清除全部 CORS", systemImage: "trash")
                }
            }
        } header: {
            Text("CORS 规则")
        } footer: {
            Text("跨域资源共享：允许指定来源的网页脚本访问桶内对象。规则为整组写入。")
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.ocOrange.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.ocOrangeText)
    }
}

// MARK: - CORS 规则编辑

private struct R2CorsRuleEditor: View {

    let onAdd: (_ origins: [String], _ methods: [String], _ maxAge: Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var originsText = "*"
    @State private var methods: Set<String> = ["GET"]
    @State private var maxAgeText = "3600"

    private let allMethods = ["GET", "PUT", "POST", "DELETE", "HEAD"]

    private var origins: [String] {
        originsText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("每行一个来源，* 表示全部", text: $originsText, axis: .vertical)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.callout.monospaced())
                } header: {
                    Text("允许来源")
                }

                Section("允许方法") {
                    ForEach(allMethods, id: \.self) { method in
                        Toggle(method, isOn: Binding(
                            get: { methods.contains(method) },
                            set: { isOn in
                                if isOn { methods.insert(method) } else { methods.remove(method) }
                            }
                        ))
                    }
                }

                Section("Max-Age（秒）") {
                    TextField("3600", text: $maxAgeText)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("添加 CORS 规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        onAdd(origins, allMethods.filter { methods.contains($0) }, Int(maxAgeText))
                        dismiss()
                    }
                    .disabled(methods.isEmpty || origins.isEmpty)
                }
            }
        }
    }
}
