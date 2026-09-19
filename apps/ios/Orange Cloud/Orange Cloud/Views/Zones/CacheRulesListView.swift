//
//  CacheRulesListView.swift
//  Orange Cloud
//
//  Cache Rules：查看 / 新建 / 编辑 / 删除 / 启停。写按 cache-settings.write 门控。
//  含高级设置（自定义缓存键等）的规则在编辑器内只读，避免覆盖丢配置。
//

import SwiftUI

struct CacheRulesListView: View {

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: CacheRulesViewModel
    @State private var showDenied = false
    @State private var editorTarget: EditorTarget?
    @State private var ruleToDelete: CacheRule?
    @State private var searchText = ""

    init(zoneId: String, session: SessionStore) {
        _viewModel = State(initialValue: CacheRulesViewModel(
            service: session.cacheRuleService, zoneId: zoneId
        ))
    }

    private var canWrite: Bool { auth.hasScope("cache-settings.write") }

    private var filteredRules: [CacheRule] {
        guard !searchText.isEmpty else { return viewModel.rules }
        return viewModel.rules.filter { rule in
            (rule.description ?? "").localizedCaseInsensitiveContains(searchText)
                || (rule.expression ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if viewModel.isLoading && !viewModel.loaded {
                SkeletonList(rows: 5, icon: .none, trailing: true)
            } else if viewModel.rules.isEmpty {
                ContentUnavailableView {
                    Label("没有缓存规则", systemImage: "bolt.horizontal")
                } description: {
                    Text(canWrite
                         ? String(localized: "缓存规则可按 URL 覆盖边缘 / 浏览器缓存时长，或对匹配请求绕过缓存。点右上角 + 创建第一条。")
                         : String(localized: "此域名暂时没有缓存规则。当前授权仅限读取（cache-settings.read）。"))
                } actions: {
                    if canWrite {
                        Button("添加规则") { editorTarget = EditorTarget(rule: nil) }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.ocOrangePressed)
                            .fontWeight(.bold)
                    }
                }
            } else if filteredRules.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    Section {
                        ForEach(filteredRules) { rule in
                            row(rule)
                                .swipeActions(edge: .leading) {
                                    if canWrite {
                                        Button {
                                            Task { await viewModel.toggle(rule: rule, enabled: !(rule.enabled ?? true)) }
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
                             : String(localized: "当前授权仅限读取（cache-settings.read），无法修改规则。"))
                    }
                    .glassRow()
                }
                .scrollContentBackground(.hidden)
                .refreshable { await detachedRefresh { await viewModel.load() } }
            }
        }
        .background { SkyBackground() }
        .navigationTitle("缓存规则")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索规则")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("添加", systemImage: "plus") {
                    if canWrite { editorTarget = EditorTarget(rule: nil) } else { showDenied = true }
                }
            }
        }
        .task { await viewModel.load() }
        .sheet(item: $editorTarget) { target in
            CacheRuleEditorView(existing: target.rule, viewModel: viewModel)
        }
        .confirmationDialog(
            "删除规则",
            isPresented: .init(get: { ruleToDelete != nil }, set: { if !$0 { ruleToDelete = nil } }),
            titleVisibility: .visible
        ) {
            if let rule = ruleToDelete {
                Button("删除「\(rule.description ?? String(localized: "未命名规则"))」", role: .destructive) {
                    Task { await viewModel.delete(rule: rule) }
                }
            }
        } message: {
            Text("此操作不可撤销，规则将立即停止生效。")
        }
        .alert("权限不足", isPresented: $showDenied) {
            if let sessionId = auth.currentSessionId {
                Button("一键重授权") {
                    Task { await auth.reauthorize(sessionId: sessionId, additionalScopes: ["cache-settings.write"]) }
                }
            }
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含缓存规则编辑权限（cache-settings.write）。点「一键重授权」补齐，无需退出登录。")
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil && editorTarget == nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    private func row(_ rule: CacheRule) -> some View {
        Button {
            if canWrite { editorTarget = EditorTarget(rule: rule) } else { showDenied = true }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(rule.description ?? String(localized: "未命名规则"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if rule.actionParameters?.hasAdvancedSettings == true {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("含高级设置")
                    }
                    Spacer()
                    if rule.enabled == false {
                        Text("已停用").font(.caption2).foregroundStyle(.secondary)
                    }
                    if canWrite {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
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

private struct EditorTarget: Identifiable {
    let rule: CacheRule?
    var id: String { rule?.id ?? "new" }
}
