//
//  WAFRuleListView.swift
//  Orange Cloud
//
//  WAF 自定义规则：查看 / 新建 / 编辑 / 删除 / 启停，写操作按 zone-waf.write 门控。
//

import SwiftUI

struct WAFRuleListView: View {

    let zoneName: String

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: WAFRulesViewModel
    @State private var showDenied = false
    @State private var showForm = false
    @State private var editingRule: WAFRule?
    @State private var showUnsupportedEdit = false
    @State private var ruleToDelete: WAFRule?
    @State private var searchText = ""

    init(zoneId: String, zoneName: String, session: SessionStore) {
        self.zoneName = zoneName
        _viewModel = State(initialValue: WAFRulesViewModel(service: session.wafService, zoneId: zoneId))
    }

    private var canWrite: Bool { auth.hasScope("zone-waf.write") }

    private var filteredRules: [WAFRule] {
        guard !searchText.isEmpty else { return viewModel.rules }
        return viewModel.rules.filter { rule in
            (rule.description ?? "").localizedCaseInsensitiveContains(searchText)
                || (rule.expression ?? "").localizedCaseInsensitiveContains(searchText)
                || (rule.action ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if viewModel.isLoading && !viewModel.loaded {
                SkeletonList(rows: 6, icon: .none, trailing: true)
            } else if viewModel.rules.isEmpty {
                ContentUnavailableView {
                    Label("没有自定义规则", systemImage: "shield")
                } description: {
                    Text(canWrite
                         ? String(localized: "点击右上角 + 创建第一条防火墙规则")
                         : String(localized: "在 Cloudflare Dashboard → 安全性 → WAF 中创建自定义规则"))
                } actions: {
                    if canWrite {
                        Button("添加规则") { showForm = true }
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
                            WAFRuleRow(
                                rule: rule,
                                canWrite: canWrite,
                                isToggling: viewModel.togglingRuleId == rule.id,
                                onToggle: { enabled in
                                    Task { await viewModel.toggle(rule: rule, enabled: enabled) }
                                },
                                onDenied: { showDenied = true }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard canWrite else { return }
                                // skip 等带额外参数的动作不在表单支持范围，改动会丢参数
                                if WAFRuleAction(rawValue: rule.action ?? "") != nil {
                                    editingRule = rule
                                } else {
                                    showUnsupportedEdit = true
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    if canWrite {
                                        ruleToDelete = rule
                                    } else {
                                        showDenied = true
                                    }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text(canWrite
                             ? String(localized: "规则按从上到下的顺序执行，点按可编辑，左滑可删除。")
                             : String(localized: "当前授权仅限读取（zone-waf.read），无法修改规则。"))
                    }
                    .glassRow()
                }
                .scrollContentBackground(.hidden)
                .refreshable { await detachedRefresh { await viewModel.load() } }
            }
        }
        .background { SkyBackground() }
        .navigationTitle("WAF 防火墙")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索规则")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("添加", systemImage: "plus") {
                    if canWrite {
                        showForm = true
                    } else {
                        showDenied = true
                    }
                }
            }
        }
        .sheet(isPresented: $showForm) {
            WAFRuleFormView(viewModel: viewModel, rule: nil)
        }
        .sheet(item: $editingRule) { rule in
            WAFRuleFormView(viewModel: viewModel, rule: rule)
        }
        .task { await viewModel.load() }
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
                    Task { await viewModel.delete(rule: rule) }
                }
            }
        } message: {
            Text("此操作不可撤销，规则将立即停止生效。")
        }
        .alert("暂不支持编辑", isPresented: $showUnsupportedEdit) {
            Button("好", role: .cancel) {}
        } message: {
            Text("「跳过」等带额外参数的规则暂不支持在 App 内编辑，请在 Cloudflare Dashboard 中修改。")
        }
        .alert("权限不足", isPresented: $showDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含 WAF 编辑权限（zone-waf.write）。\n请在设置中退出登录后重新授权以启用此功能。")
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil && !showForm && editingRule == nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }
}

// MARK: - 新建 / 编辑规则表单

private struct WAFRuleFormView: View {

    let viewModel: WAFRulesViewModel
    /// 非 nil 为编辑模式：预填并以表达式编辑器打开（表达式反解回条件行不可靠）
    let rule: WAFRule?

    @Environment(\.dismiss) private var dismiss

    private enum EditorMode: String, CaseIterable, Identifiable {
        case builder, expression
        var id: String { rawValue }
        var label: LocalizedStringKey { self == .builder ? "书写规则" : "表达式编辑器" }
    }

    private struct ConditionRow: Identifiable {
        let id = UUID()
        var fieldKey: String
        var op: WAFOperator
        var value: String
    }

    @State private var name = ""
    @State private var action: WAFRuleAction = .block
    @State private var enabled = true

    // 编辑器：两种模式
    @State private var mode: EditorMode = .builder
    @State private var expression = ""                 // 原始表达式（表达式模式 / 生成回填）
    @State private var logic: WAFConditionLogic = .and
    @State private var conditions: [ConditionRow] = [
        ConditionRow(fieldKey: WAFExpressionCatalog.fields[0].field, op: .eq, value: "")
    ]

    // 设备端 AI 生成
    @State private var nlPrompt = ""
    @State private var readback: String?

    init(viewModel: WAFRulesViewModel, rule: WAFRule?) {
        self.viewModel = viewModel
        self.rule = rule
        if let rule {
            _name = State(initialValue: rule.description ?? "")
            _action = State(initialValue: WAFRuleAction(rawValue: rule.action ?? "") ?? .block)
            _enabled = State(initialValue: rule.enabled ?? true)
            _expression = State(initialValue: rule.expression ?? "")
            _mode = State(initialValue: .expression)
        }
    }

    /// 由条件行实时生成的表达式
    private var generatedExpression: String {
        WAFExpressionBuilder.expression(
            logic: logic,
            conditions: conditions.compactMap { row in
                guard let field = WAFExpressionCatalog.field(for: row.fieldKey) else { return nil }
                return WAFExpressionBuilder.condition(field: field, op: row.op, rawValue: row.value)
            }
        )
    }

    /// 最终用于保存的表达式
    private var effectiveExpression: String {
        mode == .builder ? generatedExpression : expression.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !effectiveExpression.isEmpty
            && !viewModel.isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                if WAFAssistant.isReady {
                    aiSection
                }

                Section("规则") {
                    TextField("规则名称", text: $name)
                    Picker("动作", selection: $action) {
                        ForEach(WAFRuleAction.allCases) { action in
                            Text(action.label).tag(action)
                        }
                    }
                    Toggle("启用", isOn: $enabled)
                }

                Section {
                    // 切到「表达式编辑器」时，用当前条件生成的表达式回填，便于继续手改
                    Picker("编辑方式", selection: Binding(
                        get: { mode },
                        set: { newMode in
                            if newMode == .expression && mode == .builder {
                                expression = generatedExpression
                            }
                            mode = newMode
                        }
                    )) {
                        ForEach(EditorMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if mode == .builder {
                    builderSections
                } else {
                    expressionSection
                }

                if let error = viewModel.error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(rule == nil ? String(localized: "新建规则") : String(localized: "编辑规则"))
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
            .onDisappear {
                viewModel.error = nil
                viewModel.generationError = nil
            }
        }
    }

    // MARK: - 书写规则（可视化构建器）

    @ViewBuilder
    private var builderSections: some View {
        Section {
            Picker("匹配条件", selection: $logic) {
                ForEach(WAFConditionLogic.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(conditions.count < 2)
        } header: {
            Text("条件")
        }

        Section {
            ForEach($conditions) { $row in
                VStack(alignment: .leading, spacing: 8) {
                    Picker("字段", selection: $row.fieldKey) {
                        ForEach(WAFExpressionCatalog.fields) { Text($0.label).tag($0.field) }
                    }
                    HStack(spacing: 8) {
                        Picker("运算符", selection: $row.op) {
                            ForEach(availableOps(for: row.fieldKey)) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        TextField(placeholder(for: row.fieldKey), text: $row.value)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.callout.monospaced())
                    }
                }
                .padding(.vertical, 2)
                .onChange(of: row.fieldKey) { _, newKey in
                    // 换字段后若当前运算符不适用，回落到首个可用运算符
                    let ops = availableOps(for: newKey)
                    if !ops.contains(row.op) { row.op = ops.first ?? .eq }
                }
            }
            .onDelete { conditions.remove(atOffsets: $0) }

            Button {
                conditions.append(ConditionRow(fieldKey: WAFExpressionCatalog.fields[0].field, op: .eq, value: ""))
            } label: {
                Label("添加条件", systemImage: "plus")
            }
        } footer: {
            Text("「属于」可填多个值，用空格或逗号分隔。")
        }

        Section {
            Text(generatedExpression.isEmpty ? String(localized: "（条件尚未填完）") : generatedExpression)
                .font(.caption.monospaced())
                .foregroundStyle(generatedExpression.isEmpty ? .tertiary : .secondary)
                .textSelection(.enabled)
        } header: {
            Text("生成的表达式")
        }
    }

    // MARK: - 表达式编辑器（原始）

    private var expressionSection: some View {
        Section {
            TextEditor(text: $expression)
                .font(.callout.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 120)
        } header: {
            Text("表达式")
        } footer: {
            Text("Cloudflare Rules 语言，例如：\n(http.request.uri.path contains \"/admin\") or (ip.src eq 198.51.100.4)\n切回「书写规则」会用条件重新生成，手动修改将被覆盖。")
        }
    }

    private func availableOps(for fieldKey: String) -> [WAFOperator] {
        let type = WAFExpressionCatalog.field(for: fieldKey)?.type ?? .string
        return WAFOperator.available(for: type)
    }

    private func placeholder(for fieldKey: String) -> String {
        let type = WAFExpressionCatalog.field(for: fieldKey)?.type ?? .string
        return WAFExpressionCatalog.placeholder(for: type)
    }

    // MARK: - 设备端 AI 生成

    @ViewBuilder
    private var aiSection: some View {
        Section {
            TextField(
                String(localized: "例如：拦截来自中国大陆、访问 /admin 的请求"),
                text: $nlPrompt,
                axis: .vertical
            )
            .lineLimit(2...5)

            Button {
                Task { await generate() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isGenerating {
                        ProgressView().controlSize(.small)
                        Text("生成中…")
                    } else {
                        Image(systemName: "sparkles")
                        Text("生成表达式")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(nlPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isGenerating)

            if let readback {
                Label {
                    Text(readback)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.ocOrangeText)
                }
            }

            if let genError = viewModel.generationError {
                Text(genError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Label("用自然语言描述", systemImage: "sparkles")
        } footer: {
            Text(readback == nil
                 ? String(localized: "在设备上离线生成，描述会填入下方表达式，提交前请核对。")
                 : String(localized: "已填入下方表达式，并暂时关闭了「启用」，确认无误后再开启保存。"))
        }
    }

    private func generate() async {
        guard let result = await viewModel.generate(from: nlPrompt) else {
            readback = nil
            return
        }
        withAnimation(.smooth) {
            expression = result.expression
            action = result.action
            enabled = false        // AI 生成默认不启用，人在回路确认后再开
            readback = result.summary
            mode = .expression      // AI 产出原始表达式，切到表达式编辑器展示
        }
    }

    private func save() async {
        viewModel.error = nil
        let trimmedExpression = effectiveExpression
        if let problem = WAFExpressionLint.problem(in: trimmedExpression) {
            viewModel.error = problem
            return
        }
        let draft = WAFRuleCreate(
            action: action.rawValue,
            expression: trimmedExpression,
            description: name.trimmingCharacters(in: .whitespaces),
            enabled: enabled
        )
        let saved: Bool
        if let rule {
            saved = await viewModel.updateRule(ruleId: rule.id, draft: draft)
        } else {
            saved = await viewModel.addRule(draft)
        }
        if saved {
            dismiss()
        }
    }
}

// MARK: - 规则行

private struct WAFRuleRow: View {

    let rule: WAFRule
    let canWrite: Bool
    let isToggling: Bool
    let onToggle: (Bool) -> Void
    let onDenied: () -> Void

    @State private var explanation: String?
    @State private var isExplaining = false
    @State private var explainError: String?

    private var actionColor: Color {
        switch rule.action {
        case "block":                                    .red
        case "challenge", "managed_challenge", "js_challenge": .orange
        case "log":                                      .blue
        case "allow", "skip":                            .green
        default:                                         .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(rule.description ?? String(localized: "未命名规则"))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(rule.actionText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(actionColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(actionColor.opacity(0.14), in: Capsule())
                if isToggling {
                    ProgressView()
                        .controlSize(.small)
                } else if canWrite {
                    Toggle("", isOn: Binding(
                        get: { rule.enabled ?? true },
                        set: { onToggle($0) }
                    ))
                    .labelsHidden()
                    .accessibilityLabel("启用规则")
                } else {
                    Button {
                        onDenied()
                    } label: {
                        Image(systemName: (rule.enabled ?? true) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle((rule.enabled ?? true) ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel((rule.enabled ?? true) ? "已启用" : "已停用")
                    .accessibilityHint("需要写入权限才能修改")
                }
            }
            if let expression = rule.expression {
                Text(expression)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)

                if WAFAssistant.isReady, !expression.isEmpty {
                    explanationView(for: expression)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity((rule.enabled ?? true) ? 1 : 0.5)
    }

    /// 反向能力：按需把表达式翻译成大白话（设备端、只读）。
    @ViewBuilder
    private func explanationView(for expression: String) -> some View {
        if let explanation {
            Label {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(Color.ocOrangeText)
            }
            .padding(.top, 2)
            .transition(.opacity)
        } else {
            Button {
                Task { await explain(expression) }
            } label: {
                HStack(spacing: 4) {
                    if isExplaining {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isExplaining ? String(localized: "解释中…") : String(localized: "用大白话解释"))
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.ocOrangeText)
            }
            .buttonStyle(.borderless)
            .disabled(isExplaining)
            .padding(.top, 1)

            if let explainError {
                Text(explainError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private func explain(_ expression: String) async {
        guard !isExplaining else { return }
        isExplaining = true
        explainError = nil
        defer { isExplaining = false }
        do {
            let result = try await WAFAssistant.explainRule(expression: expression, action: rule.action)
            withAnimation(.smooth) { explanation = result }
        } catch {
            explainError = error.localizedDescription
        }
    }
}
