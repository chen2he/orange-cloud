//
//  ZoneRuleEditorView.swift
//  Orange Cloud
//
//  五个 Rulesets phase 的新建 / 编辑表单（schema 均已按 OpenAPI 核实）：
//  - 单条重定向（redirect）：from_value{target_url{value|expression}, status_code, preserve_query_string}，
//    action_parameters 恰含一项；from_list（批量列表）规则只读。
//  - 源站规则（route）：host_header / origin{host,port} / sni{value}，至少一项；未建模字段合并保留。
//  - 配置规则（set_config）：稀疏设置字典（至少一项）；disable_* 仅允许 true；未建模字段合并保留。
//  - 压缩规则（compress_response）：algorithms 有序去重列表（none/auto/default/gzip/brotli/zstd）。
//  - 自定义错误（serve_error）：content_type 必填 + content 与 asset_name 二选一（资产型保留 asset_name）。
//

import SwiftUI

// MARK: - TunnelJSONValue 取值小工具（编辑器解析用）

private extension TunnelJSONValue {
    var objectValue: [String: TunnelJSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }
    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
    var arrayValue: [TunnelJSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
}

// MARK: - 编辑器

struct ZoneRuleEditorView: View {

    let phase: ZoneRulePhase
    let existing: ZoneRule?
    let viewModel: ZonePhaseRulesViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var ruleDescription: String
    @State private var expression: String
    @State private var enabled: Bool

    // —— 单条重定向 ——
    @State private var redirectIsExpression: Bool
    @State private var redirectTarget: String
    @State private var redirectStatus: Int
    @State private var redirectPreserveQuery: Bool

    // —— 源站规则 ——
    @State private var originHostHeader: String
    @State private var originHost: String
    @State private var originPort: String
    @State private var originSNI: String

    // —— 配置规则（稀疏字典，未建模键随 raw 底座保留） ——
    @State private var configParams: [String: TunnelJSONValue]

    // —— 压缩规则 ——
    @State private var algorithms: [String]

    // —— 自定义错误 ——
    @State private var errorContent: String
    @State private var errorContentType: String
    @State private var errorStatusCode: String
    private let preservedAssetName: String?

    /// 单条重定向的 from_list（批量列表）形态不在 App 内编辑
    private let isReadOnly: Bool
    /// 既有 raw 参数（可合并 phase 的保留底座）
    private let rawParams: [String: TunnelJSONValue]

    init(phase: ZoneRulePhase, existing: ZoneRule?, viewModel: ZonePhaseRulesViewModel) {
        self.phase = phase
        self.existing = existing
        self.viewModel = viewModel
        let raw = existing?.actionParameters?.objectValue ?? [:]
        rawParams = raw
        _ruleDescription = State(initialValue: existing?.description ?? "")
        _expression = State(initialValue: existing?.expression ?? "")
        _enabled = State(initialValue: existing?.enabled ?? true)

        // 单条重定向
        let fromValue = raw["from_value"]?.objectValue
        let targetURL = fromValue?["target_url"]?.objectValue
        _redirectIsExpression = State(initialValue: targetURL?["expression"] != nil)
        _redirectTarget = State(initialValue: targetURL?["expression"]?.stringValue ?? targetURL?["value"]?.stringValue ?? "")
        _redirectStatus = State(initialValue: fromValue?["status_code"]?.intValue ?? 301)
        _redirectPreserveQuery = State(initialValue: fromValue?["preserve_query_string"]?.boolValue ?? false)
        isReadOnly = (phase == .singleRedirect && raw["from_list"] != nil)

        // 源站规则
        _originHostHeader = State(initialValue: raw["host_header"]?.stringValue ?? "")
        let origin = raw["origin"]?.objectValue
        _originHost = State(initialValue: origin?["host"]?.stringValue ?? "")
        _originPort = State(initialValue: origin?["port"]?.intValue.map(String.init) ?? "")
        _originSNI = State(initialValue: raw["sni"]?.objectValue?["value"]?.stringValue ?? "")

        // 配置规则
        _configParams = State(initialValue: raw)

        // 压缩规则
        let names = raw["algorithms"]?.arrayValue?.compactMap { $0.objectValue?["name"]?.stringValue } ?? []
        _algorithms = State(initialValue: names)

        // 自定义错误
        _errorContent = State(initialValue: raw["content"]?.stringValue ?? "")
        _errorContentType = State(initialValue: raw["content_type"]?.stringValue ?? "text/html")
        _errorStatusCode = State(initialValue: raw["status_code"]?.intValue.map(String.init) ?? "")
        preservedAssetName = raw["asset_name"]?.stringValue
    }

    private var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            Form {
                if isReadOnly {
                    Section {
                        Label("该规则基于批量列表（from_list），请在 Cloudflare Dashboard 编辑。", systemImage: "exclamationmark.triangle")
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
                } header: {
                    Text("匹配表达式")
                } footer: {
                    Text("Cloudflare Rules 语言，例如：\n(http.request.uri.path contains \"/static/\")")
                }

                switch phase {
                case .singleRedirect: redirectSections
                case .origin:         originSections
                case .config:         configSections
                case .compression:    compressionSections
                case .customErrors:   customErrorSections
                // 缓存响应规则只做查看 / 启停 / 删除，列表页不会打开编辑器
                case .cacheResponse:  EmptyView()
                }

                if let error = viewModel.error {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(.red)
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
                        Task {
                            if await viewModel.save(ruleId: existing?.id, payload: buildPayload()) {
                                dismiss()
                            }
                        }
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
            .onDisappear { viewModel.error = nil }
        }
    }

    // MARK: - 校验

    private var canSave: Bool {
        guard !isReadOnly, !viewModel.isSaving,
              !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch phase {
        case .singleRedirect:
            return !redirectTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .origin:
            return !(originHostHeader.isEmpty && originHost.isEmpty && originPort.isEmpty && originSNI.isEmpty)
                && (originPort.isEmpty || Int(originPort).map { (1...65535).contains($0) } == true)
        case .config:
            // schema minProperties 1
            return !configParams.isEmpty
        case .compression:
            return !algorithms.isEmpty
        case .customErrors:
            let statusOK = errorStatusCode.isEmpty || Int(errorStatusCode).map { (400...999).contains($0) } == true
            let bodyOK = preservedAssetName != nil || !errorContent.isEmpty
            return statusOK && bodyOK
        case .cacheResponse:
            return false
        }
    }

    // MARK: - 构建 payload

    private func buildPayload() -> ZoneRulePayload {
        ZoneRulePayload(
            action: phase.action,
            expression: expression.trimmingCharacters(in: .whitespacesAndNewlines),
            description: ruleDescription,
            enabled: enabled,
            actionParameters: buildParams()
        )
    }

    private func buildParams() -> TunnelJSONValue {
        switch phase {
        case .singleRedirect:
            // schema：action_parameters 恰含一项；target_url 恰含一项。整体重建（封闭 schema，无保留风险）
            var fromValue: [String: TunnelJSONValue] = [
                "target_url": .object([
                    redirectIsExpression ? "expression" : "value": .string(redirectTarget.trimmingCharacters(in: .whitespacesAndNewlines))
                ]),
                "status_code": .int(redirectStatus),
            ]
            if redirectPreserveQuery { fromValue["preserve_query_string"] = .bool(true) }
            return .object(["from_value": .object(fromValue)])

        case .origin:
            // 以既有 raw 为底合并，未建模字段保留
            var params = rawParams
            if originHostHeader.isEmpty { params["host_header"] = nil }
            else { params["host_header"] = .string(originHostHeader) }
            var origin: [String: TunnelJSONValue] = rawParams["origin"]?.objectValue ?? [:]
            if originHost.isEmpty { origin["host"] = nil } else { origin["host"] = .string(originHost) }
            if let port = Int(originPort), !originPort.isEmpty { origin["port"] = .int(port) } else { origin["port"] = nil }
            params["origin"] = origin.isEmpty ? nil : .object(origin)
            if originSNI.isEmpty { params["sni"] = nil } else { params["sni"] = .object(["value": .string(originSNI)]) }
            return .object(params)

        case .config:
            return .object(configParams)

        case .compression:
            return .object(["algorithms": .array(algorithms.map { .object(["name": .string($0)]) })])

        case .customErrors:
            var params = rawParams
            params["content_type"] = .string(errorContentType)
            if let code = Int(errorStatusCode), !errorStatusCode.isEmpty {
                params["status_code"] = .int(code)
            } else {
                params["status_code"] = nil
            }
            if preservedAssetName == nil {
                params["content"] = .string(errorContent)
            }
            return .object(params)

        case .cacheResponse:
            // 不提供编辑器（supportsEditor == false），原样回传以防万一
            return .object(rawParams)
        }
    }

    // MARK: - 单条重定向

    @ViewBuilder private var redirectSections: some View {
        Section {
            Picker("目标类型", selection: $redirectIsExpression) {
                Text("静态 URL").tag(false)
                Text("动态表达式").tag(true)
            }
            TextField(redirectIsExpression ? "concat(\"https://example.com\", http.request.uri.path)" : "https://example.com/new/",
                      text: $redirectTarget, axis: .vertical)
                .font(.callout.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Picker("状态码", selection: $redirectStatus) {
                ForEach([301, 302, 303, 307, 308], id: \.self) { Text(verbatim: "\($0)").tag($0) }
            }
            Toggle("保留查询字符串", isOn: $redirectPreserveQuery)
        } header: {
            Text("重定向")
        } footer: {
            Text(redirectIsExpression
                 ? String(localized: "目标为 Rules 表达式，求值结果作为跳转地址。")
                 : String(localized: "301/308 为永久跳转，302/303/307 为临时跳转；307/308 保留原 HTTP 方法。"))
        }
    }

    // MARK: - 源站规则

    @ViewBuilder private var originSections: some View {
        Section {
            TextField("Host 标头覆盖（可选）", text: $originHostHeader)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("源站主机（可选）", text: $originHost)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("源站端口（可选）", text: $originPort)
                .keyboardType(.numberPad)
            TextField("SNI 覆盖（可选，仅企业版）", text: $originSNI)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("源站覆盖")
        } footer: {
            Text("至少设置一项。匹配的请求将按此覆盖回源目标。")
        }
    }

    // MARK: - 配置规则

    /// 可编辑的设置清单（key / 展示名 / 控件类型；schema 已核实，deprecated 项不入菜单但保留原值）
    private static let configSpecs: [(key: String, label: String, kind: ConfigKind)] = [
        ("automatic_https_rewrites", String(localized: "自动 HTTPS 重写"), .toggle),
        ("bic", String(localized: "浏览器完整性检查"), .toggle),
        ("email_obfuscation", String(localized: "Email 混淆"), .toggle),
        ("fonts", "Cloudflare Fonts", .toggle),
        ("hotlink_protection", String(localized: "热链保护"), .toggle),
        ("opportunistic_encryption", String(localized: "机会性加密"), .toggle),
        ("rocket_loader", "Rocket Loader", .toggle),
        ("security_level", String(localized: "安全级别"), .choice(["off", "essentially_off", "low", "medium", "high", "under_attack"])),
        ("ssl", "SSL", .choice(["off", "flexible", "full", "strict", "origin_pull"])),
        ("polish", "Polish", .choice(["off", "lossless", "lossy", "webp"])),
        ("request_body_buffering", String(localized: "请求体缓冲"), .choice(["none", "standard", "full"])),
        ("response_body_buffering", String(localized: "响应体缓冲"), .choice(["none", "standard"])),
        ("autominify", String(localized: "自动压缩源码"), .autominify),
        ("disable_zaraz", String(localized: "停用 Zaraz"), .disableFlag),
        ("disable_rum", String(localized: "停用 RUM"), .disableFlag),
        ("disable_pay_per_crawl", String(localized: "停用 Pay Per Crawl"), .disableFlag),
    ]

    enum ConfigKind { case toggle, disableFlag, choice([String]), autominify }

    private var activeSpecs: [(key: String, label: String, kind: ConfigKind)] {
        Self.configSpecs.filter { configParams[$0.key] != nil }
    }

    private var addableSpecs: [(key: String, label: String, kind: ConfigKind)] {
        Self.configSpecs.filter { configParams[$0.key] == nil }
    }

    @ViewBuilder private var configSections: some View {
        Section {
            ForEach(activeSpecs, id: \.key) { spec in
                configRow(spec)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            configParams[spec.key] = nil
                        } label: {
                            Label("移除", systemImage: "minus.circle")
                        }
                    }
            }
            if !addableSpecs.isEmpty {
                Menu {
                    ForEach(addableSpecs, id: \.key) { spec in
                        Button(spec.label) {
                            configParams[spec.key] = defaultValue(for: spec.kind)
                        }
                    }
                } label: {
                    Label("添加设置", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("要覆盖的设置")
        } footer: {
            Text("至少一项。仅列出的设置会被此规则覆盖；左滑移除。")
        }
    }

    private func defaultValue(for kind: ConfigKind) -> TunnelJSONValue {
        switch kind {
        case .toggle:            .bool(true)
        case .disableFlag:       .bool(true)
        case .choice(let opts):  .string(opts.first ?? "")
        case .autominify:        .object(["html": .bool(true), "css": .bool(true), "js": .bool(true)])
        }
    }

    @ViewBuilder private func configRow(_ spec: (key: String, label: String, kind: ConfigKind)) -> some View {
        switch spec.kind {
        case .toggle:
            Toggle(spec.label, isOn: .init(
                get: { configParams[spec.key]?.boolValue ?? false },
                set: { configParams[spec.key] = .bool($0) }
            ))
        case .disableFlag:
            // schema 仅允许 true：出现即生效，移除即取消
            LabeledContent(spec.label) {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
            }
        case .choice(let options):
            Picker(spec.label, selection: .init(
                get: { configParams[spec.key]?.stringValue ?? options[0] },
                set: { configParams[spec.key] = .string($0) }
            )) {
                ForEach(options, id: \.self) { Text(verbatim: $0).tag($0) }
            }
        case .autominify:
            let minify = configParams[spec.key]?.objectValue ?? [:]
            DisclosureGroup(spec.label) {
                ForEach(["html", "css", "js"], id: \.self) { part in
                    Toggle(part.uppercased(), isOn: .init(
                        get: { minify[part]?.boolValue ?? false },
                        set: { newValue in
                            var m = configParams[spec.key]?.objectValue ?? [:]
                            m[part] = .bool(newValue)
                            configParams[spec.key] = .object(m)
                        }
                    ))
                }
            }
        }
    }

    // MARK: - 压缩规则

    private static let allAlgorithms = ["auto", "default", "gzip", "brotli", "zstd", "none"]

    @ViewBuilder private var compressionSections: some View {
        Section {
            ForEach(algorithms, id: \.self) { name in
                Text(verbatim: name).font(.callout.monospaced())
            }
            .onDelete { algorithms.remove(atOffsets: $0) }
            .onMove { algorithms.move(fromOffsets: $0, toOffset: $1) }
            let remaining = Self.allAlgorithms.filter { !algorithms.contains($0) }
            if !remaining.isEmpty {
                Menu {
                    ForEach(remaining, id: \.self) { name in
                        Button(name) { algorithms.append(name) }
                    }
                } label: {
                    Label("添加算法", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("压缩算法（按偏好排序）")
        } footer: {
            Text("Cloudflare 使用列表中访客浏览器支持的第一个算法；none 表示不压缩，auto/default 交给 Cloudflare 决定。长按拖动排序。")
        }
    }

    // MARK: - 自定义错误

    @ViewBuilder private var customErrorSections: some View {
        Section {
            Picker("内容类型", selection: $errorContentType) {
                ForEach(["text/html", "application/json", "text/plain", "text/xml"], id: \.self) {
                    Text(verbatim: $0).tag($0)
                }
            }
            TextField("状态码（可选，400–999）", text: $errorStatusCode)
                .keyboardType(.numberPad)
        } header: {
            Text("错误响应")
        } footer: {
            Text("不填状态码则沿用原响应状态。")
        }
        if let asset = preservedAssetName {
            Section {
                LabeledContent("自定义资产", value: asset)
            } footer: {
                Text("该规则的内容由自定义资产提供，App 内不改动资产本身。")
            }
        } else {
            Section {
                TextEditor(text: $errorContent)
                    .font(.callout.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(minHeight: 140)
            } header: {
                Text("响应内容")
            } footer: {
                Text("最大 10 KB。将按上方内容类型原样返回给访客。")
            }
        }
    }
}
