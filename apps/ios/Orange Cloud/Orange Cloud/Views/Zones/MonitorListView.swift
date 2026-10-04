//
//  MonitorListView.swift
//  Orange Cloud
//
//  健康监测（account 级）：查看 / 新建 / 编辑 / 删除。
//  写按 load-balancing-monitors-and-pools.write 门控。
//

import SwiftUI

struct MonitorListView: View {

    let session: SessionStore

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: MonitorListViewModel
    @State private var editorTarget: MonitorEditorTarget?
    @State private var monitorToDelete: Monitor?

    init(session: SessionStore) {
        self.session = session
        _viewModel = State(initialValue: MonitorListViewModel(
            service: session.loadBalancerService,
            accountId: session.selectedAccount?.id ?? ""
        ))
    }

    private var canWrite: Bool { auth.hasScope("load-balancing-monitors-and-pools.write") }

    var body: some View {
        Group {
            if viewModel.isLoading && !viewModel.loaded {
                SkeletonList(rows: 4, icon: .none, trailing: true)
            } else if viewModel.monitors.isEmpty {
                ContentUnavailableView {
                    Label("没有健康监测", systemImage: "waveform.path.ecg")
                } description: {
                    Text(canWrite
                         ? String(localized: "健康监测定期探测源站，决定其是否健康可用。点右上角 + 创建。")
                         : String(localized: "此账号暂无健康监测。"))
                } actions: {
                    if canWrite {
                        Button("新建监测") { editorTarget = MonitorEditorTarget(monitor: nil) }
                            .buttonStyle(.borderedProminent).tint(Color.ocOrangePressed).fontWeight(.bold)
                    }
                }
            } else {
                List {
                    Section {
                        ForEach(viewModel.monitors) { monitor in
                            monitorRow(monitor)
                                .swipeActions(edge: .trailing) {
                                    if canWrite {
                                        Button(role: .destructive) { monitorToDelete = monitor } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    } footer: {
                        Text(canWrite
                             ? String(localized: "点按编辑，右滑删除。被源站池引用的监测无法删除。")
                             : String(localized: "当前授权仅限读取。"))
                    }
                    .glassRow()
                }
                .scrollContentBackground(.hidden)
                .refreshable { await viewModel.load() }
            }
        }
        .background { SkyBackground() }
        .navigationTitle("健康监测")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("添加", systemImage: "plus") {
                    if canWrite { editorTarget = MonitorEditorTarget(monitor: nil) }
                }
                .disabled(!canWrite)
            }
        }
        .task { await viewModel.load() }
        .sensoryFeedback(.success, trigger: viewModel.didMutate)
        .sheet(item: $editorTarget) { target in
            MonitorEditorView(existing: target.monitor, viewModel: viewModel)
        }
        .confirmationDialog(
            "删除健康监测",
            isPresented: .init(get: { monitorToDelete != nil }, set: { if !$0 { monitorToDelete = nil } }),
            titleVisibility: .visible,
            presenting: monitorToDelete
        ) { monitor in
            Button("删除", role: .destructive) {
                Task { _ = await viewModel.delete(monitor) }
            }
        } message: { _ in
            Text("此操作不可撤销。若仍被源站池引用，删除会失败。")
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil }, set: { if !$0 { viewModel.error = nil } }
        )) {
            apiErrorDocButton(for: viewModel.error)
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    private func monitorRow(_ monitor: Monitor) -> some View {
        Button {
            if canWrite { editorTarget = MonitorEditorTarget(monitor: monitor) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(monitor.typeLabel)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.ocOrange.opacity(0.14), in: Capsule())
                        .foregroundStyle(Color.ocOrangeText)
                    Text(monitor.summary)
                        .font(.callout).foregroundStyle(.primary).lineLimit(1)
                    Spacer()
                    if canWrite {
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                if let interval = monitor.interval {
                    Text(String(localized: "每 \(interval) 秒探测一次"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct MonitorEditorTarget: Identifiable {
    let monitor: Monitor?
    var id: String { monitor?.id ?? "new" }
}

// MARK: - 健康监测编辑器

private struct MonitorEditorView: View {

    let existing: Monitor?
    let viewModel: MonitorListViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var type: MonitorType
    @State private var method: MonitorMethod
    @State private var path: String
    @State private var expectedCodes: String
    @State private var expectedBody: String
    @State private var interval: String
    @State private var timeout: String
    @State private var retries: String
    @State private var port: String
    @State private var followRedirects: Bool
    @State private var allowInsecure: Bool
    @State private var description: String

    init(existing: Monitor?, viewModel: MonitorListViewModel) {
        self.existing = existing
        self.viewModel = viewModel
        _type = State(initialValue: MonitorType(rawValue: existing?.type ?? "") ?? .http)
        _method = State(initialValue: MonitorMethod(rawValue: existing?.method ?? "") ?? .get)
        _path = State(initialValue: existing?.path ?? "/")
        _expectedCodes = State(initialValue: existing?.expectedCodes ?? "200")
        _expectedBody = State(initialValue: existing?.expectedBody ?? "")
        _interval = State(initialValue: existing?.interval.map(String.init) ?? "60")
        _timeout = State(initialValue: existing?.timeout.map(String.init) ?? "5")
        _retries = State(initialValue: existing?.retries.map(String.init) ?? "2")
        _port = State(initialValue: existing?.port.map(String.init) ?? "")
        _followRedirects = State(initialValue: existing?.followRedirects ?? false)
        _allowInsecure = State(initialValue: existing?.allowInsecure ?? false)
        _description = State(initialValue: existing?.description ?? "")
    }

    private var isEditing: Bool { existing != nil }

    private var canSave: Bool {
        guard !viewModel.isMutating else { return false }
        if (Int(interval) ?? 0) <= 0 || (Int(timeout) ?? 0) <= 0 { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("类型") {
                    Picker("类型", selection: $type) {
                        ForEach(MonitorType.allCases) { Text($0.label).tag($0) }
                    }
                    TextField("描述（可选）", text: $description)
                }

                if type.isHTTP {
                    Section("HTTP 探测") {
                        Picker("方法", selection: $method) {
                            ForEach(MonitorMethod.allCases) { Text($0.label).tag($0) }
                        }
                        TextField("路径，如 /health", text: $path)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("期望状态码，如 200 或 2xx", text: $expectedCodes)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("期望响应体包含（可选）", text: $expectedBody)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Toggle("跟随重定向", isOn: $followRedirects)
                        Toggle("允许不安全证书", isOn: $allowInsecure)
                    }
                }

                Section {
                    numberField("探测间隔", text: $interval, unit: String(localized: "秒"))
                    numberField("超时", text: $timeout, unit: String(localized: "秒"))
                    numberField("重试次数", text: $retries, unit: "")
                    numberField("端口（可选）", text: $port, unit: "")
                } header: {
                    Text("探测参数")
                } footer: {
                    Text("间隔需大于超时；连续多次失败才判定源站不健康。")
                }

                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle(isEditing ? Text("编辑监测") : Text("新建监测"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if viewModel.isMutating { ProgressView() } else { Text("保存").fontWeight(.semibold) }
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(viewModel.isMutating)
            .onDisappear { viewModel.error = nil }
        }
    }

    private func numberField(_ title: LocalizedStringKey, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", text: text).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
            if !unit.isEmpty { Text(unit).foregroundStyle(.secondary) }
        }
    }

    private func save() async {
        viewModel.error = nil
        var body = MonitorUpdate()
        body.type = type.rawValue
        if type.isHTTP {
            body.method = method.rawValue
            body.path = path.trimmingCharacters(in: .whitespaces).nilIfEmptyLB ?? "/"
            body.expectedCodes = expectedCodes.trimmingCharacters(in: .whitespaces).nilIfEmptyLB
            body.expectedBody = expectedBody.trimmingCharacters(in: .whitespaces).nilIfEmptyLB
            body.followRedirects = followRedirects
            body.allowInsecure = allowInsecure
        }
        body.interval = Int(interval)
        body.timeout = Int(timeout)
        body.retries = Int(retries)
        body.port = Int(port)
        body.description = description.trimmingCharacters(in: .whitespaces).nilIfEmptyLB
        if await viewModel.save(monitorId: existing?.id, body: body) {
            dismiss()
        }
    }
}
