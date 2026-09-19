//
//  ZoneAccessRulesView.swift
//  Orange Cloud
//
//  IP 访问规则：查看 / 新建 / 编辑（动作+备注）/ 删除。写按 firewall-services.write 门控。
//

import SwiftUI

struct ZoneAccessRulesView: View {

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: ZoneAccessRulesViewModel
    @State private var showDenied = false
    @State private var editorTarget: EditorTarget?
    @State private var pendingDelete: FirewallAccessRule?
    @State private var searchText = ""

    init(zoneId: String, session: SessionStore) {
        _viewModel = State(initialValue: ZoneAccessRulesViewModel(
            service: session.firewallAccessRuleService, zoneId: zoneId
        ))
    }

    private var canWrite: Bool { auth.hasScope("firewall-services.write") }

    private var filteredRules: [FirewallAccessRule] {
        guard !searchText.isEmpty else { return viewModel.rules }
        return viewModel.rules.filter { rule in
            (rule.configuration?.value ?? "").localizedCaseInsensitiveContains(searchText)
                || (rule.notes ?? "").localizedCaseInsensitiveContains(searchText)
                || (rule.mode ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if viewModel.isLoading && !viewModel.loaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
            } else if viewModel.loaded && viewModel.rules.isEmpty && !canWrite {
                ContentUnavailableView("暂无访问规则", systemImage: "hand.raised",
                    description: Text("此域名暂时没有 IP 访问规则。"))
            } else {
                List {
                    Section {
                        if filteredRules.isEmpty {
                            Text(searchText.isEmpty
                                 ? String(localized: "暂无规则")
                                 : String(localized: "无匹配规则"))
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            ForEach(filteredRules) { rule in
                                row(rule)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            if canWrite { pendingDelete = rule } else { showDenied = true }
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    } footer: {
                        Text(canWrite
                             ? String(localized: "左滑删除，点按可改动作与备注；匹配对象不可改。")
                             : String(localized: "当前授权仅限读取（firewall-services.read）。"))
                    }
                    .glassRow()
                }
                .scrollContentBackground(.hidden)
                .refreshable { await detachedRefresh { await viewModel.load() } }
            }
        }
        .background { SkyBackground() }
        .navigationTitle("IP 访问规则")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索 IP / 备注")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("添加", systemImage: "plus") {
                    if canWrite { editorTarget = EditorTarget(rule: nil) } else { showDenied = true }
                }
            }
        }
        .task { await viewModel.load() }
        .sheet(item: $editorTarget) { target in
            AccessRuleEditorView(existing: target.rule, viewModel: viewModel)
        }
        .confirmationDialog(
            "删除规则",
            isPresented: .init(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            if let rule = pendingDelete {
                Button("删除", role: .destructive) {
                    Task { await viewModel.delete(rule) }
                }
            }
        } message: {
            Text("此操作不可撤销。")
        }
        .alert("权限不足", isPresented: $showDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含 IP 访问规则编辑权限（firewall-services.write）。\n请在设置中退出登录后重新授权以启用此功能。")
        }
        .alert("加载失败", isPresented: .init(
            get: { viewModel.error != nil && editorTarget == nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    private func row(_ rule: FirewallAccessRule) -> some View {
        Button {
            if canWrite { editorTarget = EditorTarget(rule: rule) } else { showDenied = true }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(rule.modeLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(modeColor(rule.mode).opacity(0.16), in: Capsule())
                        .foregroundStyle(modeColor(rule.mode))
                    if let cfg = rule.configuration {
                        Text(cfg.targetLabel).font(.caption).foregroundStyle(.secondary)
                        Text(cfg.value ?? "—").font(.callout.monospaced()).foregroundStyle(.primary)
                    }
                    Spacer()
                    if canWrite {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                if let notes = rule.notes, !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func modeColor(_ mode: String?) -> Color {
        switch mode {
        case "block":     .red
        case "whitelist": .green
        default:          .orange
        }
    }
}

private struct EditorTarget: Identifiable {
    let rule: FirewallAccessRule?
    var id: String { rule?.id ?? "new" }
}
