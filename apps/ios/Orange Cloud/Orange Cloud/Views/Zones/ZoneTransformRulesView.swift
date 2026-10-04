//
//  ZoneTransformRulesView.swift
//  Orange Cloud
//
//  Transform Rules：按 phase 分组查看 / 新建 / 编辑 / 删除 / 启停。
//  写操作按 zone-transform-rules.write 门控。
//

import SwiftUI

struct ZoneTransformRulesView: View {

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: ZoneTransformRulesViewModel
    @State private var showDenied = false
    @State private var editorTarget: EditorTarget?
    @State private var pendingDelete: PendingDelete?

    init(zoneId: String, session: SessionStore) {
        _viewModel = State(initialValue: ZoneTransformRulesViewModel(
            service: session.transformRuleService, zoneId: zoneId
        ))
    }

    private var canWrite: Bool { auth.hasScope("zone-transform-rules.write") }

    var body: some View {
        Group {
            if viewModel.isLoading && !viewModel.loaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
            } else if viewModel.loaded && !viewModel.hasAnyRule && !canWrite {
                ContentUnavailableView {
                    Label("暂无 Transform Rules", systemImage: "arrow.triangle.branch")
                } description: {
                    Text("此域名暂时没有 URL 重写或请求/响应头规则。")
                }
            } else {
                List {
                    ForEach(TransformPhase.allCases) { section($0) }
                }
                .scrollContentBackground(.hidden)
                .refreshable { await viewModel.load() }
            }
        }
        .background { SkyBackground() }
        .navigationTitle(Text(verbatim: "Transform Rules"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .sheet(item: $editorTarget) { target in
            TransformRuleEditorView(phase: target.phase, existing: target.rule, viewModel: viewModel)
        }
        .confirmationDialog(
            "删除规则",
            isPresented: .init(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            if let pd = pendingDelete {
                Button("删除「\(pd.rule.description ?? String(localized: "未命名规则"))」", role: .destructive) {
                    Task { await viewModel.delete(phase: pd.phase, rule: pd.rule) }
                }
            }
        } message: {
            Text("此操作不可撤销，规则将立即停止生效。")
        }
        .alert("权限不足", isPresented: $showDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含 Transform Rules 编辑权限（zone-transform-rules.write）。\n请在设置中退出登录后重新授权以启用此功能。")
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil && editorTarget == nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            apiErrorDocButton(for: viewModel.error)
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    @ViewBuilder
    private func section(_ phase: TransformPhase) -> some View {
        let rules = viewModel.rules(for: phase)
        Section {
            if rules.isEmpty {
                Text("暂无规则")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rules) { rule in
                    row(phase: phase, rule: rule)
                        .swipeActions(edge: .leading) {
                            if canWrite {
                                Button {
                                    Task { await viewModel.toggle(phase: phase, rule: rule, enabled: !(rule.enabled ?? true)) }
                                } label: {
                                    Label(rule.enabled == false ? String(localized: "启用") : String(localized: "停用"),
                                          systemImage: rule.enabled == false ? "play" : "pause")
                                }
                                .tint(.orange)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                if canWrite { pendingDelete = PendingDelete(phase: phase, rule: rule) }
                                else { showDenied = true }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                }
            }
        } header: {
            HStack {
                Text(phase.title)
                Spacer()
                Button("添加规则", systemImage: "plus") {
                    if canWrite { editorTarget = EditorTarget(phase: phase, rule: nil) }
                    else { showDenied = true }
                }
                .labelStyle(.iconOnly)
                .font(.body)
            }
        }
        .glassRow()
    }

    private func row(phase: TransformPhase, rule: TransformRule) -> some View {
        Button {
            if canWrite { editorTarget = EditorTarget(phase: phase, rule: rule) }
            else { showDenied = true }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(rule.description ?? String(localized: "未命名规则"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
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
                if let summary = rule.summary(for: phase) {
                    Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
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
    let phase: TransformPhase
    let rule: TransformRule?
    var id: String { "\(phase.rawValue)-\(rule?.id ?? "new")" }
}

private struct PendingDelete {
    let phase: TransformPhase
    let rule: TransformRule
}
