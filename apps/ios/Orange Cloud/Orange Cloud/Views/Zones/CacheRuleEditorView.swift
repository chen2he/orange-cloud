//
//  CacheRuleEditorView.swift
//  Orange Cloud
//
//  Cache Rule 新建 / 编辑表单：匹配表达式 + 缓存资格（可缓存 / 绕过）+ 边缘·浏览器 TTL +
//  serve stale / 强 ETag / 源站错误页透传。含高级设置的规则只读（避免覆盖丢配置）。
//

import SwiftUI

struct CacheRuleEditorView: View {

    let existing: CacheRule?
    let viewModel: CacheRulesViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var ruleDescription: String
    @State private var expression: String
    @State private var enabled: Bool
    @State private var eligibility: CacheEligibility
    @State private var edgeMode: CacheTTLMode
    @State private var edgeSeconds: String
    @State private var browserMode: CacheTTLMode
    @State private var browserSeconds: String
    @State private var serveStaleWhileRevalidating: Bool
    @State private var respectStrongEtags: Bool
    @State private var originErrorPagePassthru: Bool

    /// existing 规则里我们不开放编辑的 status_code_ttl，保存时原样回写，避免丢失
    private let preservedStatusCodeTtl: [CacheStatusCodeTTL]?
    /// existing 含高级设置（自定义缓存键 / Cache Reserve 等）→ 整页只读
    private let isReadOnly: Bool

    init(existing: CacheRule?, viewModel: CacheRulesViewModel) {
        self.existing = existing
        self.viewModel = viewModel
        let p = existing?.actionParameters
        _ruleDescription = State(initialValue: existing?.description ?? "")
        _expression = State(initialValue: existing?.expression ?? "")
        _enabled = State(initialValue: existing?.enabled ?? true)
        _eligibility = State(initialValue: (p?.cache ?? true) ? .eligible : .bypass)
        _edgeMode = State(initialValue: CacheTTLMode(rawValue: p?.edgeTtl?.mode ?? "") ?? .respectOrigin)
        _edgeSeconds = State(initialValue: p?.edgeTtl?.defaultTtl.map(String.init) ?? "14400")
        _browserMode = State(initialValue: CacheTTLMode(rawValue: p?.browserTtl?.mode ?? "") ?? .respectOrigin)
        _browserSeconds = State(initialValue: p?.browserTtl?.defaultTtl.map(String.init) ?? "14400")
        _serveStaleWhileRevalidating = State(initialValue: !(p?.serveStale?.disableStaleWhileUpdating ?? false))
        _respectStrongEtags = State(initialValue: p?.respectStrongEtags ?? false)
        _originErrorPagePassthru = State(initialValue: p?.originErrorPagePassthru ?? false)
        preservedStatusCodeTtl = p?.edgeTtl?.statusCodeTtl
        isReadOnly = p?.hasAdvancedSettings ?? false
    }

    private var isEditing: Bool { existing != nil }

    private var canSave: Bool {
        guard !isReadOnly,
              !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !viewModel.isSaving else { return false }
        if eligibility == .eligible {
            if edgeMode == .overrideOrigin, (Int(edgeSeconds) ?? 0) <= 0 { return false }
            if browserMode == .overrideOrigin, (Int(browserSeconds) ?? 0) <= 0 { return false }
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                if isReadOnly {
                    Section {
                        Label("此规则包含高级缓存设置（如自定义缓存键、Cache Reserve），为避免覆盖丢失配置，请在 Cloudflare 控制台编辑。", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("规则") {
                    TextField("规则说明（可选）", text: $ruleDescription)
                    Toggle("启用", isOn: $enabled)
                }

                Section {
                    TextEditor(text: $expression)
                        .font(.callout.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 90)

                    // 表达式是自由文本，字段全靠记——给常用字段一个点按插入。
                    // 含 2026-07-16 起缓存规则新支持的 bot 分数与 ASN 匹配。
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(CacheRuleField.common) { field in
                                Button {
                                    insert(field.token)
                                } label: {
                                    Text(field.label)
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.ocOrange.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("匹配表达式")
                } footer: {
                    Text("Cloudflare Rules 语言，例如：\n(http.request.uri.path contains \"/static/\")")
                }

                Section {
                    Picker("缓存资格", selection: $eligibility) {
                        ForEach(CacheEligibility.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("缓存")
                } footer: {
                    Text(eligibility == .bypass
                         ? String(localized: "匹配的请求将不被缓存。")
                         : String(localized: "匹配的请求按下方设置进行缓存。"))
                }

                if eligibility == .eligible {
                    edgeTtlSection
                    browserTtlSection
                    optionsSection
                }

                if !isReadOnly {
                    RuleValidateSection(
                        isValidating: viewModel.isValidating,
                        passed: viewModel.validationPassed,
                        disabled: !canSave || viewModel.isValidating
                    ) {
                        Task { await validate() }
                    }
                }

                if let error = viewModel.error {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(.red)
                        APIErrorDocLink(message: error)
                    }
                }
            }
            .disabled(isReadOnly)
            .navigationTitle(isEditing ? Text("编辑规则") : Text("新建规则"))
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
            // 草稿一改，上次的「校验通过」就不再代表当前内容
            .onChange(of: draftSignature) { viewModel.validationPassed = false }
            .onDisappear {
                viewModel.error = nil
                viewModel.validationPassed = false
            }
        }
    }

    private var edgeTtlSection: some View {
        Section {
            Picker("边缘缓存 TTL", selection: $edgeMode) {
                ForEach(CacheTTLMode.allCases) { Text($0.label).tag($0) }
            }
            if edgeMode == .overrideOrigin {
                secondsField(text: $edgeSeconds)
            }
        } header: {
            Text("边缘缓存 TTL")
        } footer: {
            Text(edgeMode == .overrideOrigin
                 ? durationHint(edgeSeconds)
                 : String(localized: "Cloudflare 边缘节点缓存内容的时长。"))
        }
    }

    private var browserTtlSection: some View {
        Section {
            Picker("浏览器缓存 TTL", selection: $browserMode) {
                ForEach(CacheTTLMode.allCases) { Text($0.label).tag($0) }
            }
            if browserMode == .overrideOrigin {
                secondsField(text: $browserSeconds)
            }
        } header: {
            Text("浏览器缓存 TTL")
        } footer: {
            Text(browserMode == .overrideOrigin
                 ? durationHint(browserSeconds)
                 : String(localized: "访客浏览器缓存内容的时长。"))
        }
    }

    private var optionsSection: some View {
        Section {
            Toggle("重新验证时提供陈旧内容", isOn: $serveStaleWhileRevalidating)
            Toggle("尊重强 ETag", isOn: $respectStrongEtags)
            Toggle("透传源站错误页", isOn: $originErrorPagePassthru)
        } header: {
            Text("其它选项")
        } footer: {
            Text("提供陈旧内容：回源更新时先返回旧缓存，减少等待。")
        }
    }

    private func secondsField(text: Binding<String>) -> some View {
        HStack {
            TextField("秒数", text: text)
                .keyboardType(.numberPad)
            Text("秒").foregroundStyle(.secondary)
        }
    }

    /// 秒数 → 人类可读时长（编辑器底部提示）
    private func durationHint(_ secondsText: String) -> String {
        guard let seconds = Int(secondsText), seconds > 0 else {
            return String(localized: "请输入大于 0 的秒数。")
        }
        let formatted = Duration.seconds(seconds)
            .formatted(.units(allowed: [.days, .hours, .minutes, .seconds], width: .wide))
        return String(localized: "= \(formatted)")
    }

    /// 保存与校验共用的草稿（参数构造与保存完全一致）
    private func makeDraft() -> CacheRuleCreate {
        let trimmedExpr = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        var params = CacheActionParameters()

        if eligibility == .bypass {
            params.cache = false
        } else {
            params.cache = true
            params.edgeTtl = CacheEdgeTTL(
                mode: edgeMode.rawValue,
                defaultTtl: edgeMode == .overrideOrigin ? Int(edgeSeconds) : nil,
                statusCodeTtl: preservedStatusCodeTtl
            )
            params.browserTtl = CacheBrowserTTL(
                mode: browserMode.rawValue,
                defaultTtl: browserMode == .overrideOrigin ? Int(browserSeconds) : nil
            )
            params.serveStale = CacheServeStale(disableStaleWhileUpdating: !serveStaleWhileRevalidating)
            params.respectStrongEtags = respectStrongEtags
            params.originErrorPagePassthru = originErrorPagePassthru
        }

        let trimmedDesc = ruleDescription.trimmingCharacters(in: .whitespaces)
        return CacheRuleCreate(
            action: "set_cache_settings",
            expression: trimmedExpr,
            description: trimmedDesc.isEmpty ? nil : trimmedDesc,
            enabled: enabled,
            actionParameters: params
        )
    }

    /// 草稿指纹：任一字段变动即清掉上次的校验结果
    private var draftSignature: String {
        "\(ruleDescription)|\(enabled)|\(expression)|\(eligibility)|\(edgeMode)|\(edgeSeconds)|"
            + "\(browserMode)|\(browserSeconds)|\(serveStaleWhileRevalidating)|"
            + "\(respectStrongEtags)|\(originErrorPagePassthru)"
    }

    /// 「校验」：发保存同款请求带 ?dry_run=true，不落库、不关表单
    private func validate() async {
        viewModel.error = nil
        await viewModel.validate(ruleId: existing?.id, draft: makeDraft())
    }

    private func save() async {
        viewModel.error = nil
        if await viewModel.save(ruleId: existing?.id, draft: makeDraft()) {
            dismiss()
        }
    }

    /// 点按插入字段：光标概念在 TextEditor 里不好拿，直接追加到末尾并补一个空格
    private func insert(_ token: String) {
        if expression.isEmpty {
            expression = token
        } else if expression.hasSuffix(" ") {
            expression += token
        } else {
            expression += " " + token
        }
    }

}
