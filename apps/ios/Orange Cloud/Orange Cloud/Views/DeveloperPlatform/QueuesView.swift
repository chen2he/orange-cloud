//
//  QueuesView.swift
//  Orange Cloud
//
//  Cloudflare Queues 列表 + 新建 / 删除 + 详情管理。account 级，读 queues.read / 写 queues.write。
//  详情用 sheet（自带 NavigationStack）：暂停/恢复投递、改保留期与投递延迟、重命名、清空消息、删除。
//

import SwiftUI

struct QueuesView: View {

    let session: SessionStore

    @Environment(AuthManager.self) private var auth
    @State private var vm: QueuesViewModel?
    @State private var showCreate = false
    @State private var detailTarget: CFQueue?
    @State private var deleteTarget: CFQueue?
    @State private var writeDenied = false

    private var canWrite: Bool { auth.hasScope("queues.write") }

    var body: some View {
        Group {
            if let vm { content(vm) } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .background { SkyBackground() }
        .navigationTitle("Queues")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if vm != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("新建队列", systemImage: "plus") {
                        if canWrite { showCreate = true } else { writeDenied = true }
                    }
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            if let vm { QueueCreateView(viewModel: vm) }
        }
        .sheet(item: $detailTarget) { queue in
            if let vm { QueueDetailSheet(viewModel: vm, queueId: queue.queueId) }
        }
        .alert("权限不足", isPresented: $writeDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含 Queues 写权限（queues.write）。\n请在设置中退出登录后重新授权以启用此功能。")
        }
        .confirmationDialog(
            deleteTarget.map { String(localized: "删除队列「\($0.name)」？") } ?? "",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let q = deleteTarget, let vm { Task { await vm.delete(q) } }
            }
        } message: {
            Text("删除后该队列及其未消费消息将被移除，不可撤销。")
        }
        .task {
            await session.ensureAccounts()
            guard vm == nil else { return }
            let model = QueuesViewModel(service: session.queueService, accountId: session.selectedAccount?.id)
            vm = model
            await model.load()
        }
    }

    @ViewBuilder
    private func content(_ vm: QueuesViewModel) -> some View {
        if vm.isLoading && !vm.loaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.queues.isEmpty {
            ContentUnavailableView {
                Label("没有队列", systemImage: "tray.2")
            } description: {
                Text(vm.error ?? String(localized: "该账号下还没有 Queue。"))
            } actions: {
                if canWrite {
                    Button("新建队列") { showCreate = true }
                        .buttonStyle(.borderedProminent).tint(Color.ocOrangePressed).fontWeight(.bold)
                }
            }
        } else {
            List {
                Section {
                    ForEach(vm.queues) { queue in
                        Button { detailTarget = queue } label: {
                            QueueRow(queue: queue)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            if canWrite {
                                Button(role: .destructive) { deleteTarget = queue } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                } footer: {
                    Text("点按查看详情与管理 · 生产者 / 消费者绑定在 Worker 中配置。")
                }
                .glassRow()
            }
            .daybreakList()
            .refreshable { await vm.load() }
            .sensoryFeedback(.success, trigger: vm.didChange)
        }
    }
}

private struct QueueRow: View {
    let queue: CFQueue

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(queue.name).font(.callout.weight(.semibold)).lineLimit(1).foregroundStyle(.primary)
                Text("\(queue.producers?.count ?? 0) 生产者 · \(queue.consumers?.count ?? 0) 消费者")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if queue.settings?.deliveryPaused == true {
                Text("已暂停").font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.ocOrangeText)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.ocOrange.opacity(0.14), in: Capsule())
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - 详情管理 sheet

private struct QueueDetailSheet: View {
    let viewModel: QueuesViewModel
    let queueId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth
    @State private var showRename = false
    @State private var showSettings = false
    @State private var showPurge = false
    @State private var showDelete = false

    private var canWrite: Bool { auth.hasScope("queues.write") }
    private var queue: CFQueue? { viewModel.queues.first { $0.queueId == queueId } }
    private var isPaused: Bool { queue?.settings?.deliveryPaused ?? false }

    /// 队列的次级动作。iOS 27+ 并入系统溢出菜单，以下版本走自建 ellipsis 菜单。
    @ViewBuilder private var queueActions: some View {
        Button("重命名", systemImage: "pencil") { showRename = true }
        Button("编辑设置", systemImage: "slider.horizontal.3") { showSettings = true }
        Button("清空消息", systemImage: "trash.slash", role: .destructive) { showPurge = true }
        Divider()
        Button("删除队列", systemImage: "trash", role: .destructive) { showDelete = true }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let queue { detail(queue) } else { ProgressView() }
            }
            .background { SkyBackground() }
            .navigationTitle(queue?.name ?? String(localized: "队列"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
                // 这组动作在 iOS 27+ 并入系统溢出菜单（见下方 ocOverflowActions）——
                // HIG 要求 ellipsis 只留给系统溢出菜单，App 别再自建一个；
                // iOS 26 及以下没有系统菜单，仍挂自建 ellipsis，两条路共用同一份 queueActions。
                if canWrite, !ProcessInfo.usesSystemToolbarOverflow {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            queueActions
                        } label: {
                            Label("更多", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
            .ocOverflowActions {
                if canWrite { queueActions }
            }
            .sheet(isPresented: $showRename) {
                if let queue { QueueRenameSheet(viewModel: viewModel, queueId: queueId, currentName: queue.name) }
            }
            .sheet(isPresented: $showSettings) {
                if let queue { QueueSettingsSheet(viewModel: viewModel, queueId: queueId, settings: queue.settings) }
            }
            .confirmationDialog(
                String(localized: "清空队列全部消息？"),
                isPresented: $showPurge, titleVisibility: .visible
            ) {
                Button("清空消息", role: .destructive) {
                    Task { await viewModel.purge(queueId: queueId) }
                }
            } message: {
                Text("将永久删除该队列中所有未消费的消息，不可撤销。队列本身保留。")
            }
            .confirmationDialog(
                queue.map { String(localized: "删除队列「\($0.name)」？") } ?? "",
                isPresented: $showDelete, titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let queue {
                        Task { await viewModel.delete(queue); dismiss() }
                    }
                }
            } message: {
                Text("删除后该队列及其未消费消息将被移除，不可撤销。")
            }
            // 队列被删（列表里没了）时自动收起
            .onChange(of: viewModel.queues.contains { $0.queueId == queueId }) { _, stillThere in
                if !stillThere { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func detail(_ queue: CFQueue) -> some View {
        List {
            Section {
                LabeledContent("状态") {
                    Text(isPaused ? "投递已暂停" : "投递中")
                        .foregroundStyle(isPaused ? Color.ocOrangeText : .secondary)
                }
                if canWrite {
                    Button {
                        Task { await viewModel.togglePause(queueId: queueId, paused: !isPaused) }
                    } label: {
                        Label(isPaused ? "恢复投递" : "暂停投递",
                              systemImage: isPaused ? "play.fill" : "pause.fill")
                    }
                    .disabled(viewModel.isSaving)
                }
            } header: {
                Text("投递")
            } footer: {
                Text("暂停后队列仍会接收消息，但暂停向消费者投递。")
            }
            .glassRow()

            Section("设置") {
                LabeledContent("消息保留期", value: Self.formatSeconds(queue.settings?.messageRetentionPeriod))
                LabeledContent("投递延迟", value: Self.formatSeconds(queue.settings?.deliveryDelay))
                if let created = queue.createdOn, let date = WorkerScript.parseDate(created) {
                    LabeledContent("创建于", value: date.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .glassRow()

            Section {
                if let producers = queue.producers, !producers.isEmpty {
                    ForEach(Array(producers.enumerated()), id: \.offset) { _, p in
                        Text(p.script ?? p.type ?? String(localized: "未知")).font(.callout.monospaced()).lineLimit(1)
                    }
                } else {
                    Text("无生产者").foregroundStyle(.secondary).font(.callout)
                }
            } header: {
                Text("生产者（\(queue.producersTotalCount ?? queue.producers?.count ?? 0)）")
            }
            .glassRow()

            Section {
                if let consumers = queue.consumers, !consumers.isEmpty {
                    ForEach(Array(consumers.enumerated()), id: \.offset) { _, c in
                        ConsumerRow(consumer: c)
                    }
                } else {
                    Text("无消费者").foregroundStyle(.secondary).font(.callout)
                }
            } header: {
                Text("消费者（\(queue.consumersTotalCount ?? queue.consumers?.count ?? 0)）")
            } footer: {
                Text("消费者绑定与批处理参数在 Worker 中配置。")
            }
            .glassRow()

            if let error = viewModel.error {
                Section { Text(error).font(.footnote).foregroundStyle(.red) }.glassRow()
            }
        }
        .daybreakList()
    }

    /// 秒 → 可读时长（如 345600 → 「4 天」）；nil → 「—」
    static func formatSeconds(_ seconds: Int?) -> String {
        guard let s = seconds else { return "—" }
        if s == 0 { return String(localized: "无") }
        if s % 86400 == 0 { return String(localized: "\(s / 86400) 天") }
        if s % 3600 == 0 { return String(localized: "\(s / 3600) 小时") }
        if s % 60 == 0 { return String(localized: "\(s / 60) 分钟") }
        return String(localized: "\(s) 秒")
    }
}

private struct ConsumerRow: View {
    let consumer: CFQueueEndpoint

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(consumer.script ?? consumer.type ?? String(localized: "未知"))
                .font(.callout.monospaced()).lineLimit(1)
            if let s = consumer.settings {
                let parts = [
                    s.batchSize.map { String(localized: "批 \($0)") },
                    s.maxRetries.map { String(localized: "重试 \($0)") },
                    s.maxConcurrency.map { String(localized: "并发 \($0)") }
                ].compactMap { $0 }
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let dlq = consumer.deadLetterQueue {
                Text("死信队列：\(dlq)").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 重命名

private struct QueueRenameSheet: View {
    let viewModel: QueuesViewModel
    let queueId: String
    let currentName: String

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(viewModel: QueuesViewModel, queueId: String, currentName: String) {
        self.viewModel = viewModel
        self.queueId = queueId
        self.currentName = currentName
        _name = State(initialValue: currentName)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmed.isEmpty && trimmed != currentName && !viewModel.isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("队列名称", text: $name)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.callout.monospaced())
                } footer: {
                    Text("小写字母 / 数字 / 连字符。")
                }
                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("重命名队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { if await viewModel.update(queueId: queueId, queueName: trimmed) { dismiss() } }
                    } label: {
                        if viewModel.isSaving { ProgressView() } else { Text("保存").fontWeight(.semibold) }
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .onAppear { viewModel.error = nil }
        }
    }
}

// MARK: - 编辑设置（保留期 / 投递延迟）

private struct QueueSettingsSheet: View {
    let viewModel: QueuesViewModel
    let queueId: String

    @Environment(\.dismiss) private var dismiss
    @State private var retentionText: String
    @State private var delayText: String

    init(viewModel: QueuesViewModel, queueId: String, settings: CFQueueSettings?) {
        self.viewModel = viewModel
        self.queueId = queueId
        _retentionText = State(initialValue: settings?.messageRetentionPeriod.map(String.init) ?? "345600")
        _delayText = State(initialValue: settings?.deliveryDelay.map(String.init) ?? "0")
    }

    private var retention: Int? { Int(retentionText) }
    private var delay: Int? { Int(delayText) }
    private var canSave: Bool {
        guard let r = retention, (60...1_209_600).contains(r),
              let d = delay, (0...43_200).contains(d) else { return false }
        return !viewModel.isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("消息保留期（秒）", text: $retentionText).keyboardType(.numberPad)
                } footer: {
                    Text("60 秒 – 14 天（1209600 秒）。当前约 \(QueueDetailSheet.formatSeconds(retention))。")
                }
                Section {
                    TextField("投递延迟（秒）", text: $delayText).keyboardType(.numberPad)
                } footer: {
                    Text("0 – 12 小时（43200 秒）。消息进入队列后延迟多久才投递。")
                }
                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("编辑设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let r = retention, let d = delay else { return }
                        Task {
                            let ok = await viewModel.update(
                                queueId: queueId,
                                settings: CFQueueSettingsPatch(deliveryDelay: d, messageRetentionPeriod: r)
                            )
                            if ok { dismiss() }
                        }
                    } label: {
                        if viewModel.isSaving { ProgressView() } else { Text("保存").fontWeight(.semibold) }
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .onAppear { viewModel.error = nil }
        }
    }
}

private struct QueueCreateView: View {
    let viewModel: QueuesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmed.isEmpty && !viewModel.isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("队列名称", text: $name)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.callout.monospaced())
                } footer: {
                    Text("小写字母 / 数字 / 连字符。")
                }
                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("新建队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { if await viewModel.create(name: trimmed) { dismiss() } }
                    } label: {
                        if viewModel.isSaving { ProgressView() } else { Text("创建").fontWeight(.semibold) }
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .onAppear { viewModel.error = nil }
        }
    }
}
