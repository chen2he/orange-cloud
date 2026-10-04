//
//  SnippetDetailView.swift
//  Orange Cloud
//
//  单个 Snippet：只读代码 + 触发规则（启停/增删改）+ 删除 Snippet。
//  写操作按 snippets.write 门控；规则改动经 ViewModel 整组回写。
//

import SwiftUI

struct SnippetDetailView: View {

    let snippet: Snippet
    let zoneName: String
    let viewModel: SnippetsViewModel

    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var code: String?
    @State private var loadingCode = true
    @State private var showEditor = false
    @State private var showAddRule = false
    @State private var showDenied = false
    @State private var ruleToDelete: SnippetRule?
    @State private var ruleToEdit: SnippetRule?
    @State private var showDeleteSnippet = false

    private var canWrite: Bool { auth.hasScope("snippets.write") }
    private var myRules: [SnippetRule] { viewModel.rules(for: snippet.snippetName) }

    var body: some View {
        List {
            // 代码
            Section {
                if loadingCode {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding(.vertical, 8)
                } else if let code, !code.isEmpty {
                    ScrollView {
                        Text(code)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 320)
                    // JS 源码始终 LTR
                    .environment(\.layoutDirection, .leftToRight)
                } else {
                    Text("（空）").foregroundStyle(.secondary)
                }
            } header: {
                Text("代码")
            }
            .glassRow()

            // 触发规则
            Section {
                if myRules.isEmpty {
                    Text("未配置触发规则，此 Snippet 不会执行。")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else {
                    ForEach(myRules) { rule in
                        SnippetRuleRow(
                            rule: rule,
                            canWrite: canWrite,
                            isToggling: viewModel.togglingRuleId == rule.id,
                            onToggle: { enabled in
                                Task { await viewModel.setRule(rule, enabled: enabled) }
                            },
                            onEdit: {
                                if canWrite { ruleToEdit = rule } else { showDenied = true }
                            },
                            onDenied: { showDenied = true }
                        )
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                if canWrite { ruleToDelete = rule } else { showDenied = true }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                if canWrite { ruleToEdit = rule } else { showDenied = true }
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("触发规则")
                    Spacer()
                    if canWrite {
                        Button("添加", systemImage: "plus") { showAddRule = true }
                            .font(.caption)
                    }
                }
            } footer: {
                Text("规则用 Cloudflare Rules 表达式匹配请求，满足时运行此 Snippet。点按规则可编辑。")
            }
            .glassRow()

            // 危险操作
            if canWrite {
                Section {
                    Button(role: .destructive) {
                        showDeleteSnippet = true
                    } label: {
                        Label("删除 Snippet", systemImage: "trash")
                    }
                }
                .glassRow()
            }
        }
        .scrollContentBackground(.hidden)
        .background { SkyBackground() }
        .navigationTitle(snippet.snippetName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("编辑代码", systemImage: "pencil") {
                    if canWrite { showEditor = true } else { showDenied = true }
                }
            }
        }
        .task { await loadCode() }
        .sheet(isPresented: $showEditor, onDismiss: { Task { await loadCode() } }) {
            SnippetEditorView(viewModel: viewModel, existing: snippet)
        }
        .sheet(isPresented: $showAddRule) {
            SnippetRuleFormView(viewModel: viewModel, snippetName: snippet.snippetName)
        }
        .sheet(item: $ruleToEdit) { rule in
            SnippetRuleFormView(viewModel: viewModel, snippetName: snippet.snippetName, existing: rule)
        }
        .confirmationDialog(
            "删除规则",
            isPresented: .init(
                get: { ruleToDelete != nil },
                set: { if !$0 { ruleToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let rule = ruleToDelete {
                Button("删除「\(rule.description ?? String(localized: "未命名规则"))」", role: .destructive) {
                    Task { await viewModel.deleteRule(rule) }
                }
            }
        } message: {
            Text("此操作不可撤销，规则将立即停止生效。")
        }
        .confirmationDialog(
            "删除 Snippet「\(snippet.snippetName)」？",
            isPresented: $showDeleteSnippet,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                Task {
                    await viewModel.deleteSnippet(snippet)
                    if viewModel.error == nil { dismiss() }
                }
            }
        } message: {
            Text("将同时移除指向它的触发规则，此操作不可撤销。")
        }
        .alert("权限不足", isPresented: $showDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含 Snippets 编辑权限（snippets.write）。")
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil && !showEditor && !showAddRule && ruleToEdit == nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            apiErrorDocButton(for: viewModel.error)
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    private func loadCode() async {
        loadingCode = true
        code = await viewModel.code(for: snippet.snippetName)
        loadingCode = false
    }
}

// MARK: - 规则行

private struct SnippetRuleRow: View {

    let rule: SnippetRule
    let canWrite: Bool
    let isToggling: Bool
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDenied: () -> Void

    private var isEnabled: Bool { rule.enabled ?? true }

    private var title: String {
        rule.description.map { $0.isEmpty ? String(localized: "未命名规则") : $0 }
            ?? String(localized: "未命名规则")
    }

    var body: some View {
        // 文本区与开关是两个独立点击目标：点文本进编辑，开关只管启停
        HStack(alignment: .top, spacing: 12) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(rule.expression)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        // Cloudflare Rules 表达式始终 LTR
                        .environment(\.layoutDirection, .leftToRight)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(canWrite
                               ? String(localized: "轻点两下编辑规则")
                               : String(localized: "需要写入权限才能修改"))

            if isToggling {
                ProgressView().controlSize(.small)
            } else if canWrite {
                Toggle("", isOn: Binding(get: { isEnabled }, set: { onToggle($0) }))
                    .labelsHidden()
                    .accessibilityLabel("启用规则")
            } else {
                Button {
                    onDenied()
                } label: {
                    Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isEnabled ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isEnabled
                                    ? String(localized: "已启用")
                                    : String(localized: "已停用"))
                .accessibilityHint("需要写入权限才能修改")
            }
        }
        .padding(.vertical, 4)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

// MARK: - 规则表单（新增 / 编辑共用）

private struct SnippetRuleFormView: View {

    let viewModel: SnippetsViewModel
    let snippetName: String
    /// nil = 新增；非 nil = 编辑这条已存在的规则
    let existing: SnippetRule?

    @Environment(\.dismiss) private var dismiss

    @State private var description: String
    @State private var expression: String
    @State private var enabled: Bool

    init(viewModel: SnippetsViewModel, snippetName: String, existing: SnippetRule? = nil) {
        self.viewModel = viewModel
        self.snippetName = snippetName
        self.existing = existing
        _description = State(initialValue: existing?.description ?? "")
        _expression  = State(initialValue: existing?.expression ?? "")
        _enabled     = State(initialValue: existing?.enabled ?? true)
    }

    private var canSave: Bool {
        !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("规则") {
                    TextField("描述（可选）", text: $description)
                    Toggle("启用", isOn: $enabled)
                }

                Section {
                    TextEditor(text: $expression)
                        .font(.callout.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 100)
                        // Cloudflare Rules 表达式始终 LTR
                        .environment(\.layoutDirection, .leftToRight)
                } header: {
                    Text("表达式")
                } footer: {
                    Text("Cloudflare Rules 语言，例如：\n(http.request.uri.path contains \"/api\")")
                }

                if let error = viewModel.error {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existing == nil
                             ? String(localized: "添加触发规则")
                             : String(localized: "编辑触发规则"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                        } else {
                            Text("保存").fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
    }

    private func save() async {
        viewModel.error = nil
        let trimmedDesc = description.trimmingCharacters(in: .whitespaces)
        let desc = trimmedDesc.isEmpty ? nil : trimmedDesc
        let expr = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok: Bool
        if let existing {
            ok = await viewModel.updateRule(
                existing, expression: expr, description: desc, enabled: enabled
            )
        } else {
            ok = await viewModel.addRule(
                snippetName: snippetName, expression: expr, description: desc, enabled: enabled
            )
        }
        if ok { dismiss() }
    }
}
