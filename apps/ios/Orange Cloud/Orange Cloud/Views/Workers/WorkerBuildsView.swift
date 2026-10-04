//
//  WorkerBuildsView.swift
//  Orange Cloud
//
//  Worker 的 CI 构建记录：状态、分支/commit、日志、取消。
//

import SwiftUI

struct WorkerBuildsView: View {

    let scriptName: String

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: WorkerBuildViewModel
    @State private var logTarget: WorkerBuild?
    @State private var watching = false

    init(scriptName: String, session: SessionStore) {
        self.scriptName = scriptName
        _viewModel = State(initialValue: WorkerBuildViewModel(
            service: session.workerBuildService,
            accountId: session.selectedAccount?.id ?? "",
            scriptId: scriptName
        ))
    }

    private var canWrite: Bool { auth.hasScope("workers-ci.write") }

    var body: some View {
        List {
            Section {
                Toggle("构建失败时通知我", isOn: Binding(
                    get: { watching },
                    set: { on in
                        watching = on
                        AppNotifications.setWatchingBuilds(scriptName, on)
                    }
                ))
            } footer: {
                // 说清是尽力而为，别让用户以为是实时推送
                Text("Cloudflare 没有为 Workers 构建提供告警，这里靠 App 在后台刷新时自行比对。时机由系统调度，可能延迟。")
            }
            .glassRow()

            Section {
                if viewModel.isLoading && !viewModel.loaded {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
                } else if viewModel.builds.isEmpty {
                    Text("这个 Worker 还没有构建记录。接上 Git 仓库后，每次推送都会在这里出现。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.builds) { build in
                        buildRow(build)
                            .swipeActions(edge: .trailing) {
                                // 只有进行中的构建才谈得上取消
                                if canWrite && build.displayState.isRunning {
                                    Button(role: .destructive) {
                                        Task { await viewModel.cancel(build) }
                                    } label: {
                                        Label("取消", systemImage: "stop.circle")
                                    }
                                }
                            }
                    }
                }
            } header: {
                Text("构建记录（\(scriptName)）")
            } footer: {
                Text("点按查看构建日志。进行中的构建可左滑取消。")
            }
            .glassRow()
        }
        .daybreakList()
        .navigationTitle("构建")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            watching = AppNotifications.isWatchingBuilds(scriptName)
            await viewModel.load()
        }
        .refreshable { await viewModel.load() }
        .sensoryFeedback(.success, trigger: viewModel.didMutate)
        .sheet(item: $logTarget) { build in
            NavigationStack {
                BuildLogsView(build: build, viewModel: viewModel)
            }
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

    private func buildRow(_ build: WorkerBuild) -> some View {
        Button {
            logTarget = build
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(stateColor(build.displayState))
                        .frame(width: 8, height: 8)
                    Text(build.displayState.label)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if let created = WorkerScript.parseDate(build.createdOn) {
                        Text(created, format: .relative(presentation: .named))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let meta = build.buildTriggerMetadata {
                    HStack(spacing: 6) {
                        if let branch = meta.branch {
                            Label(branch, systemImage: "arrow.triangle.branch")
                                .font(.caption2)
                        }
                        if let commit = meta.shortCommit {
                            Text(commit)
                                .font(.caption2.monospaced())
                        }
                    }
                    .foregroundStyle(.secondary)
                    if let author = meta.author {
                        Text(author)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func stateColor(_ state: BuildDisplayState) -> Color {
        switch state {
        case .success:            .green
        case .failed:             .red
        case .queued, .running:   .orange
        case .cancelled, .skipped, .unknown: .gray
        }
    }
}

// MARK: - 日志

private struct BuildLogsView: View {

    let build: WorkerBuild
    let viewModel: WorkerBuildViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                if viewModel.isLoadingLogs {
                    ProgressView().frame(maxWidth: .infinity)
                } else if viewModel.logs.isEmpty {
                    Text("没有日志输出。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(viewModel.logs.enumerated()), id: \.offset) { _, line in
                        Text(line.line ?? "")
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text(build.displayState.label)
            }
            .glassRow()
        }
        .daybreakList()
        .navigationTitle("构建日志")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadLogs(for: build) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
    }
}
