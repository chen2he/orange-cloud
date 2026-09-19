//
//  ZoneRulesHubView.swift
//  Orange Cloud
//
//  「规则」聚合入口（对齐 developers.cloudflare.com/rules/）：把域名详情页原本平铺的
//  规则类条目（Transform / 缓存规则 / Snippets）与新增的五个 Rulesets phase
//  （单条重定向 / 源站 / 配置 / 压缩 / 自定义错误）、Page Rules（传统）、URL 规范化
//  收进一个二级页。Bulk Redirects 是账号级，这里挂同一入口方便发现。
//
//  新类型 v1 = 查看 / 启停 / 删除（参数原样展示，PATCH 只碰 enabled 不回写参数，
//  规则创建/编辑请在 Cloudflare Dashboard 完成）。
//

import SwiftUI

struct ZoneRulesHubView: View {

    let zoneId: String
    let zoneName: String
    let session: SessionStore

    var body: some View {
        // 本页 eager 门控行的保留判据：目的页是叶子（ZonePhaseRules / Transform / 缓存规则 /
        // Page Rules / URL 规范化内部只开 sheet、不再 push）。Bulk Redirects 与 Snippets
        // 的目的页还要继续 push，已改值式（ZoneRoute，navdest 在宿主栈根）。
        List {
            Section("重定向") {
                ProGatedNavigationLink(
                    label: String(localized: "单条重定向"),
                    systemImage: "arrow.uturn.right",
                    requiredScope: ZoneRulePhase.singleRedirect.readScope,
                    feature: .zoneRules,
                    tint: .orange
                ) {
                    ZonePhaseRulesListView(zoneId: zoneId, phase: .singleRedirect, session: session)
                }
                // 列表页内部还要 push 条目详情且带 .searchable，入口必须值式
                // （本页自身也是被 push 的，navdest 在宿主栈根，见 zoneRouteDestinations）
                ProGatedValueLink(
                    label: "Bulk Redirects",
                    systemImage: "arrow.triangle.swap",
                    requiredScope: "mass-url-redirects.read",
                    feature: .bulkRedirects,
                    tint: .orange,
                    value: ZoneRoute.bulkRedirects
                )
            }
            .glassRow()

            Section("流量与内容") {
                ProGatedNavigationLink(
                    label: String(localized: "源站规则"),
                    systemImage: "server.rack",
                    requiredScope: ZoneRulePhase.origin.readScope,
                    feature: .zoneRules,
                    tint: .blue
                ) {
                    ZonePhaseRulesListView(zoneId: zoneId, phase: .origin, session: session)
                }
                ProGatedNavigationLink(
                    label: String(localized: "配置规则"),
                    systemImage: "slider.horizontal.3",
                    requiredScope: ZoneRulePhase.config.readScope,
                    feature: .zoneRules,
                    tint: .gray
                ) {
                    ZonePhaseRulesListView(zoneId: zoneId, phase: .config, session: session)
                }
                ProGatedNavigationLink(
                    label: String(localized: "压缩规则"),
                    systemImage: "rectangle.compress.vertical",
                    requiredScope: ZoneRulePhase.compression.readScope,
                    feature: .zoneRules,
                    tint: .mint
                ) {
                    ZonePhaseRulesListView(zoneId: zoneId, phase: .compression, session: session)
                }
                ProGatedNavigationLink(
                    label: String(localized: "自定义错误"),
                    systemImage: "exclamationmark.bubble",
                    requiredScope: ZoneRulePhase.customErrors.readScope,
                    feature: .zoneRules,
                    tint: .red
                ) {
                    ZonePhaseRulesListView(zoneId: zoneId, phase: .customErrors, session: session)
                }
            }
            .glassRow()

            Section("改写与缓存") {
                PermissionGatedNavigationLink(
                    label: String(localized: "托管头"),
                    systemImage: "list.bullet.rectangle.portrait",
                    requiredScope: "managed-headers.read",
                    tint: .teal
                ) {
                    ManagedHeadersView(zoneId: zoneId, session: session)
                }
                PermissionGatedNavigationLink(
                    label: "Transform Rules",
                    systemImage: "arrow.triangle.branch",
                    requiredScope: "zone-transform-rules.read",
                    tint: .indigo
                ) {
                    ZoneTransformRulesView(zoneId: zoneId, session: session)
                }
                ProGatedNavigationLink(
                    label: String(localized: "缓存规则"),
                    systemImage: "bolt.horizontal",
                    requiredScope: "cache-settings.read",
                    feature: .cacheRules,
                    tint: .cyan
                ) {
                    CacheRulesListView(zoneId: zoneId, session: session)
                }
                // Snippets 列表内部还要 push 详情页（代码 + 规则），入口必须值式
                ProGatedValueLink(
                    label: "Snippets",
                    systemImage: "curlybraces",
                    requiredScope: "snippets.read",
                    feature: .snippets,
                    tint: .indigo,
                    value: ZoneRoute.snippets(zoneId: zoneId, zoneName: zoneName)
                )
            }
            .glassRow()

            Section {
                ProGatedNavigationLink(
                    label: "Page Rules",
                    systemImage: "doc.text.below.ecg",
                    requiredScope: "page-rules.read",
                    feature: .zoneRules,
                    tint: .brown
                ) {
                    PageRulesListView(zoneId: zoneId, session: session)
                }
                PermissionGatedNavigationLink(
                    label: String(localized: "URL 规范化"),
                    systemImage: "textformat.abc.dottedunderline",
                    requiredScope: "config-settings.read",
                    tint: .teal
                ) {
                    URLNormalizationView(zoneId: zoneId, session: session)
                }
            } header: {
                Text("传统与全局")
            } footer: {
                Text("Page Rules 为传统功能，仅支持查看、启停与删除；其余规则类型支持在 App 内创建与编辑。")
            }
            .glassRow()
        }
        .daybreakList()
        .background { SkyBackground() }
        .navigationTitle("规则")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Rulesets phase 泛化列表（查看 / 启停 / 删除）

struct ZonePhaseRulesListView: View {

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: ZonePhaseRulesViewModel
    @State private var showDenied = false
    @State private var ruleToDelete: ZoneRule?
    @State private var detailRule: ZoneRule?
    @State private var editorTarget: ZoneRuleEditorTarget?

    private let phase: ZoneRulePhase

    init(zoneId: String, phase: ZoneRulePhase, session: SessionStore) {
        self.phase = phase
        _viewModel = State(initialValue: ZonePhaseRulesViewModel(
            service: session.zoneRulesetService, zoneId: zoneId, phase: phase
        ))
    }

    private var canWrite: Bool { auth.hasScope(phase.writeScope) }

    var body: some View {
        Group {
            if viewModel.isLoading && !viewModel.loaded {
                SkeletonList(rows: 5, icon: .none, trailing: true)
            } else if viewModel.rules.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "没有\(phase.title)"), systemImage: phase.systemImage)
                } description: {
                    Text(canWrite
                         ? String(localized: "此域名还没有这类规则。点右上角 + 创建第一条。")
                         : String(localized: "此域名还没有这类规则。当前授权仅限读取（\(phase.readScope)），无法创建。"))
                } actions: {
                    if canWrite {
                        Button("添加规则") { editorTarget = ZoneRuleEditorTarget(rule: nil) }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.ocOrangePressed)
                            .fontWeight(.bold)
                    }
                }
            } else {
                List {
                    Section {
                        ForEach(viewModel.rules) { rule in
                            row(rule)
                                .swipeActions(edge: .leading) {
                                    if canWrite {
                                        Button {
                                            Task { await viewModel.setEnabled(rule, enabled: !(rule.enabled ?? true)) }
                                        } label: {
                                            Label(rule.enabled == false ? String(localized: "启用") : String(localized: "停用"),
                                                  systemImage: rule.enabled == false ? "play" : "pause")
                                        }
                                        .tint(.orange)
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        if canWrite { ruleToDelete = rule } else { showDenied = true }
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                    } footer: {
                        Text(canWrite
                             ? String(localized: "规则按从上到下顺序执行；点按编辑，左滑启停，右滑删除。")
                             : String(localized: "当前授权仅限读取（\(phase.readScope)），无法修改规则。"))
                    }
                    .glassRow()
                }
                .scrollContentBackground(.hidden)
                .refreshable { await detachedRefresh { await viewModel.load() } }
            }
        }
        .background { SkyBackground() }
        .navigationTitle(phase.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("添加", systemImage: "plus") {
                    if canWrite { editorTarget = ZoneRuleEditorTarget(rule: nil) } else { showDenied = true }
                }
            }
        }
        .task { await viewModel.load() }
        .sensoryFeedback(.success, trigger: viewModel.didMutate)
        .sheet(item: $detailRule) { rule in
            ZoneRuleDetailSheet(rule: rule, phase: phase)
        }
        .sheet(item: $editorTarget) { target in
            ZoneRuleEditorView(phase: phase, existing: target.rule, viewModel: viewModel)
        }
        .confirmationDialog(
            "删除规则",
            isPresented: .init(get: { ruleToDelete != nil }, set: { if !$0 { ruleToDelete = nil } }),
            titleVisibility: .visible
        ) {
            if let rule = ruleToDelete {
                Button("删除「\(rule.description ?? String(localized: "未命名规则"))」", role: .destructive) {
                    Task { await viewModel.delete(rule) }
                }
            }
        } message: {
            Text("此操作不可撤销，规则将立即停止生效。")
        }
        .alert("权限不足", isPresented: $showDenied) {
            if let sessionId = auth.currentSessionId {
                Button("一键重授权") {
                    Task { await auth.reauthorize(sessionId: sessionId, additionalScopes: [phase.writeScope]) }
                }
            }
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含此规则的编辑权限（\(phase.writeScope)）。点「一键重授权」补齐，无需退出登录。")
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    private func row(_ rule: ZoneRule) -> some View {
        Button {
            // 有写权限点行进编辑器；只读授权保持只读详情
            if canWrite { editorTarget = ZoneRuleEditorTarget(rule: rule) } else { detailRule = rule }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(rule.description ?? String(localized: "未命名规则"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    if rule.enabled == false {
                        Text("已停用").font(.caption2).foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(rule.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let expr = rule.expression, !expr.isEmpty {
                    Text(expr)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(rule.enabled == false ? 0.5 : 1)
    }
}

/// 编辑器 sheet 目标（nil rule = 新建）
struct ZoneRuleEditorTarget: Identifiable {
    let rule: ZoneRule?
    var id: String { rule?.id ?? "new" }
}

/// 规则详情（只读）：表达式 + 动作 + 参数原样 JSON
private struct ZoneRuleDetailSheet: View {

    let rule: ZoneRule
    let phase: ZoneRulePhase
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("规则") {
                    LabeledContent("名称", value: rule.description ?? String(localized: "未命名规则"))
                    LabeledContent("动作", value: rule.action ?? "—")
                    LabeledContent("状态", value: rule.enabled == false ? String(localized: "已停用") : String(localized: "已启用"))
                }
                .glassRow()
                if let expr = rule.expression, !expr.isEmpty {
                    Section("匹配表达式") {
                        Text(expr)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    .glassRow()
                }
                if let params = rule.actionParameters {
                    Section("动作参数") {
                        Text(Self.prettyJSON(params))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    .glassRow()
                }
            }
            .daybreakList()
            .background { SkyBackground() }
            .navigationTitle(phase.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private static func prettyJSON(_ value: TunnelJSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return "—" }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Page Rules（传统）

struct PageRulesListView: View {

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: PageRulesViewModel
    @State private var showDenied = false
    @State private var ruleToDelete: PageRule?

    init(zoneId: String, session: SessionStore) {
        _viewModel = State(initialValue: PageRulesViewModel(
            service: session.zoneRulesetService, zoneId: zoneId
        ))
    }

    private var canWrite: Bool { auth.hasScope("page-rules.write") }

    var body: some View {
        Group {
            if viewModel.isLoading && !viewModel.loaded {
                SkeletonList(rows: 5, icon: .none, trailing: true)
            } else if viewModel.rules.isEmpty {
                ContentUnavailableView {
                    Label("没有 Page Rules", systemImage: "doc.text.below.ecg")
                } description: {
                    Text("Page Rules 是传统功能，Cloudflare 建议迁移到新的规则产品；已有规则可在此查看、启停与删除。")
                }
            } else {
                List {
                    Section {
                        ForEach(viewModel.rules) { rule in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(rule.targetLabel)
                                        .font(.callout.weight(.semibold))
                                        .lineLimit(1)
                                    Spacer()
                                    if !rule.isActive {
                                        Text("已停用").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Text(rule.actionsLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .opacity(rule.isActive ? 1 : 0.5)
                            .swipeActions(edge: .leading) {
                                if canWrite {
                                    Button {
                                        Task { await viewModel.setActive(rule, active: !rule.isActive) }
                                    } label: {
                                        Label(rule.isActive ? String(localized: "停用") : String(localized: "启用"),
                                              systemImage: rule.isActive ? "pause" : "play")
                                    }
                                    .tint(.orange)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    if canWrite { ruleToDelete = rule } else { showDenied = true }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text(canWrite
                             ? String(localized: "左滑启停，右滑删除。")
                             : String(localized: "当前授权仅限读取（page-rules.read），无法修改规则。"))
                    }
                    .glassRow()
                }
                .scrollContentBackground(.hidden)
                .refreshable { await detachedRefresh { await viewModel.load() } }
            }
        }
        .background { SkyBackground() }
        .navigationTitle("Page Rules")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .sensoryFeedback(.success, trigger: viewModel.didMutate)
        .confirmationDialog(
            "删除规则",
            isPresented: .init(get: { ruleToDelete != nil }, set: { if !$0 { ruleToDelete = nil } }),
            titleVisibility: .visible
        ) {
            if let rule = ruleToDelete {
                Button("删除「\(rule.targetLabel)」", role: .destructive) {
                    Task { await viewModel.delete(rule) }
                }
            }
        } message: {
            Text("此操作不可撤销，规则将立即停止生效。")
        }
        .alert("权限不足", isPresented: $showDenied) {
            if let sessionId = auth.currentSessionId {
                Button("一键重授权") {
                    Task { await auth.reauthorize(sessionId: sessionId, additionalScopes: ["page-rules.write"]) }
                }
            }
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含 Page Rules 编辑权限（page-rules.write）。点「一键重授权」补齐，无需退出登录。")
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }
}

// MARK: - URL Normalization

struct URLNormalizationView: View {

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: URLNormalizationViewModel

    init(zoneId: String, session: SessionStore) {
        _viewModel = State(initialValue: URLNormalizationViewModel(
            service: session.zoneRulesetService, zoneId: zoneId
        ))
    }

    private var canWrite: Bool { auth.hasScope("config-settings.write") }

    var body: some View {
        List {
            if let value = viewModel.value {
                Section {
                    Picker("规范化类型", selection: .init(
                        get: { value.type },
                        set: { newValue in Task { await viewModel.update(type: newValue) } }
                    )) {
                        Text(verbatim: "Cloudflare").tag("cloudflare")
                        Text(verbatim: "RFC 3986").tag("rfc3986")
                    }
                    .disabled(!canWrite || viewModel.isMutating)

                    Picker("作用范围", selection: .init(
                        get: { value.scope },
                        set: { newValue in Task { await viewModel.update(scope: newValue) } }
                    )) {
                        Text("仅入站 URL").tag("incoming")
                        Text("入站与规则匹配").tag("both")
                        Text("不规范化").tag("none")
                    }
                    .disabled(!canWrite || viewModel.isMutating)
                } footer: {
                    Text(canWrite
                         ? String(localized: "URL 规范化影响所有规则的表达式匹配方式，修改立即生效。")
                         : String(localized: "当前授权仅限读取（config-settings.read），无法修改。"))
                }
                .glassRow()
            } else if viewModel.isLoading {
                Section { SkeletonList(rows: 2, icon: .none, trailing: true) }
                    .glassRow()
            }
        }
        .daybreakList()
        .background { SkyBackground() }
        .navigationTitle("URL 规范化")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .sensoryFeedback(.success, trigger: viewModel.didMutate)
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }
}
