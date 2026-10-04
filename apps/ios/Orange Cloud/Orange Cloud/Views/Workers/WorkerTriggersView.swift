//
//  WorkerTriggersView.swift
//  Orange Cloud
//
//  Worker Cron 定时触发器：查看 + 增删（整组回写）。Cron 走 UTC，5 字段标准表达式。
//

import SwiftUI

struct WorkerTriggersView: View {

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: WorkerTriggersViewModel
    @State private var showAdd = false

    init(accountId: String, scriptName: String, session: SessionStore) {
        _viewModel = State(initialValue: WorkerTriggersViewModel(
            service: session.workerService, accountId: accountId, scriptName: scriptName
        ))
    }

    private var canWrite: Bool { auth.hasScope("workers-scripts.write") }

    var body: some View {
        Group {
            if !viewModel.loaded && viewModel.isLoading {
                SkeletonList(rows: 4, icon: .none, trailing: true)
            } else if viewModel.schedules.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(viewModel.schedules) { schedule in
                            row(schedule)
                                .swipeActions(edge: .trailing) {
                                    if canWrite {
                                        Button("删除", role: .destructive) {
                                            Task { await viewModel.deleteCron(schedule) }
                                        }
                                    }
                                }
                        }
                    } footer: {
                        Text(canWrite
                             ? String(localized: "Cron 按 UTC 时区执行。向左滑动删除。")
                             : String(localized: "当前授权仅可查看（缺少 workers-scripts.write）。"))
                    }
                    .glassRow()
                }
                .scrollContentBackground(.hidden)
                .refreshable { await viewModel.load() }
            }
        }
        .background { SkyBackground() }
        .navigationTitle("触发器")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if canWrite {
                    Button("添加", systemImage: "plus") { showAdd = true }
                }
            }
        }
        .task { if !viewModel.loaded { await viewModel.load() } }
        .sheet(isPresented: $showAdd) {
            CronEditorSheet(viewModel: viewModel)
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil && !showAdd },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            apiErrorDocButton(for: viewModel.error)
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    private func row(_ schedule: WorkerSchedule) -> some View {
        HStack(spacing: 12) {
            TintIcon(systemImage: "clock.fill", color: .ocOrange)
            VStack(alignment: .leading, spacing: 2) {
                Text(schedule.cron).font(.callout.weight(.semibold).monospaced())
                Text(CronDescriber.describe(schedule.cron))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("没有定时触发器", systemImage: "clock.badge.xmark")
        } description: {
            Text(canWrite
                 ? String(localized: "添加 Cron 表达式，让这个 Worker 按计划自动运行。")
                 : String(localized: "该 Worker 未配置 Cron 触发器。"))
        } actions: {
            if canWrite {
                Button("添加触发器") { showAdd = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.ocOrangePressed)
                    .fontWeight(.bold)
            }
        }
    }
}

// MARK: - 添加弹窗

private struct CronEditorSheet: View {

    let viewModel: WorkerTriggersViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var cron = ""

    private var fieldCount: Int {
        cron.split(whereSeparator: \.isWhitespace).count
    }
    private var isValid: Bool { fieldCount == 5 }
    private var canSave: Bool { isValid && !viewModel.isSaving }

    private static let presets: [(String, String)] = [
        ("*/5 * * * *", String(localized: "每 5 分钟")),
        ("0 * * * *",   String(localized: "每小时整点")),
        ("0 0 * * *",   String(localized: "每天 0 点（UTC）")),
        ("0 0 * * 1",   String(localized: "每周一 0 点（UTC）")),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("*/5 * * * *", text: $cron)
                        .font(.callout.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Cron 表达式")
                } footer: {
                    Text(isValid
                         ? CronDescriber.describe(cron)
                         : String(localized: "标准 5 字段：分 时 日 月 周（UTC）。"))
                    .foregroundStyle(isValid ? Color.secondary : Color.orange)
                }

                Section("常用") {
                    ForEach(Self.presets, id: \.0) { expr, label in
                        Button {
                            cron = expr
                        } label: {
                            HStack {
                                Text(expr).font(.callout.monospaced()).foregroundStyle(.primary)
                                Spacer()
                                Text(label).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let error = viewModel.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("添加触发器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            viewModel.error = nil
                            if await viewModel.addCron(cron) { dismiss() }
                        }
                    } label: {
                        if viewModel.isSaving { ProgressView() } else { Text("保存").fontWeight(.semibold) }
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
    }
}

// MARK: - Cron 人类可读释义（覆盖常见样式，其余回退原表达式）

nonisolated enum CronDescriber {
    static func describe(_ cron: String) -> String {
        let f = cron.split(whereSeparator: \.isWhitespace).map(String.init)
        guard f.count == 5 else { return String(localized: "自定义 Cron（UTC）") }
        let (minute, hour, dom, month, dow) = (f[0], f[1], f[2], f[3], f[4])

        // 每 N 分钟
        if minute.hasPrefix("*/"), hour == "*", dom == "*", month == "*", dow == "*",
           let n = Int(minute.dropFirst(2)) {
            return String(localized: "每 \(n) 分钟")
        }
        // 每小时整点
        if minute == "0", hour == "*", dom == "*", month == "*", dow == "*" {
            return String(localized: "每小时整点")
        }
        // 每天 HH:MM（UTC）
        if let m = Int(minute), let h = Int(hour), dom == "*", month == "*", dow == "*" {
            return String(localized: "每天 \(String(format: "%02d:%02d", h, m))（UTC）")
        }
        return String(localized: "自定义 Cron（UTC）")
    }
}
