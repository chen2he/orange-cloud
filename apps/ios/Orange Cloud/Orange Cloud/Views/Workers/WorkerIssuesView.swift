//
//  WorkerIssuesView.swift
//  Orange Cloud
//
//  Workers Issues（公开测试）：Cloudflare 自动归类的 Worker 未捕获异常 / 5xx / 错误日志。
//  入口两处：Workers 列表顶部「问题」（全账户）与 Worker 详情「调试」区（只看该 Worker）。
//  Pro 门槛与实时日志 / 历史日志相同（ProFeature.workerTail），读需 workers-observability.read。
//
//  本页是叶子：问题详情走 sheet（自带 NavigationStack），不在宿主栈里继续 push——
//  两处入口分属不同宿主栈，值式路由要在每个栈根各挂一份 navdest，sheet 免去这层耦合。
//

import SwiftUI

struct WorkerIssuesView: View {

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: WorkerIssuesViewModel
    @State private var selected: WorkerIssue?

    private let session: SessionStore
    private let accountId: String

    /// scriptName 为 nil = 全账户；否则只看该 Worker
    init(accountId: String, scriptName: String?, session: SessionStore) {
        self.session = session
        self.accountId = accountId
        _viewModel = State(initialValue: WorkerIssuesViewModel(
            service: session.workerIssuesService,
            accountId: accountId,
            scriptName: scriptName
        ))
    }

    var body: some View {
        List {
            Section {
                // 从 Worker 详情进来时只看该 Worker：标出名字，行内不再重复
                if let service = viewModel.service {
                    Text(service)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                }

                Picker("状态", selection: $viewModel.status) {
                    ForEach(WorkerIssueStatus.allCases) { status in
                        Text(status.label).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if let summary = viewModel.summary {
                    Text("活跃问题 \(summary.activeIssues ?? 0) · 共发生 \(summary.activeOccurrences ?? 0) 次")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 0, trailing: 4))
                }
            }

            content
        }
        .daybreakList()
        .background { SkyBackground() }
        .navigationTitle("问题")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RefreshButton(
                    isLoading: viewModel.isLoading,
                    failed: viewModel.error != nil && !viewModel.issues.isEmpty
                ) {
                    Task { await viewModel.load() }
                }
            }
        }
        .task(id: viewModel.status) { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(item: $selected) { issue in
            WorkerIssueDetailSheet(
                issue: issue,
                accountId: accountId,
                session: session,
                onUpdate: { updated in Task { await viewModel.apply(updated: updated) } }
            )
        }
        // 列表加载失败有整页失败态；这里只弹续页失败
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil && !viewModel.issues.isEmpty },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            apiErrorDocButton(for: viewModel.error)
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.issues.isEmpty {
            Section {
                ForEach(0..<6, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBlock(width: 160 + CGFloat((index * 41) % 90), height: 12)
                        SkeletonBlock(width: 110, height: 10)
                    }
                    .padding(.vertical, 4)
                }
                .skeletonPulse()
            }
            .glassRow()
        } else if let error = viewModel.error, viewModel.issues.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { Task { await viewModel.load() } }
                        .buttonStyle(.bordered)
                        .tint(Color.ocOrange)
                    APIErrorDocLink(message: error)
                }
                .listRowBackground(Color.clear)
            }
        } else if viewModel.loaded && viewModel.issues.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("没有检测到问题", systemImage: "checkmark.circle")
                } description: {
                    Text("Cloudflare 会自动把 Worker 的未捕获异常、5xx 响应和错误日志归类成问题（公开测试中）")
                }
                .listRowBackground(Color.clear)
            }
        } else {
            Section {
                ForEach(viewModel.issues) { issue in
                    Button {
                        selected = issue
                    } label: {
                        WorkerIssueRow(issue: issue, showsService: viewModel.service == nil)
                    }
                    .buttonStyle(.plain)
                }
                if viewModel.canLoadMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .task { await viewModel.loadMore() }
                }
            } footer: {
                Text("Cloudflare 会自动把 Worker 的未捕获异常、5xx 响应和错误日志归类成问题（公开测试中）")
                    .font(.caption)
            }
            .glassRow()
        }
    }
}

// MARK: - 问题行

private struct WorkerIssueRow: View {
    let issue: WorkerIssue
    let showsService: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TintIcon(systemImage: "exclamationmark.bubble", color: tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.displayTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if showsService, let service = issue.service {
                        Text(service)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                    }
                    if let count = issue.count {
                        Label {
                            Text(count.formatted())
                                .monospacedDigit()
                        } icon: {
                            Image(systemName: "number")
                        }
                        .font(.caption)
                    }
                    Spacer(minLength: 0)
                    if let last = issue.lastObserved {
                        Text(last, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var tint: Color {
        switch issue.knownStatus {
        case .active:   .red
        case .resolved: .green
        case .ignored:  .gray
        }
    }
}

// MARK: - 问题详情

struct WorkerIssueDetailSheet: View {

    let onUpdate: (WorkerIssue) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth
    @State private var viewModel: WorkerIssueDetailViewModel

    init(issue: WorkerIssue, accountId: String, session: SessionStore, onUpdate: @escaping (WorkerIssue) -> Void) {
        self.onUpdate = onUpdate
        _viewModel = State(initialValue: WorkerIssueDetailViewModel(
            issue: issue, service: session.workerIssuesService, accountId: accountId
        ))
    }

    private var canWrite: Bool { auth.hasScope("workers-observability.write") }
    private var issue: WorkerIssue { viewModel.issue }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(issue.displayTitle)
                        .font(.body.weight(.semibold))
                        .textSelection(.enabled)
                    if let service = issue.service {
                        LabeledContent {
                            Text(service).font(.callout.monospaced())
                        } label: {
                            Text(verbatim: "Worker")
                        }
                    }
                    LabeledContent("状态", value: issue.knownStatus.label)
                    if let count = issue.count {
                        LabeledContent("发生次数") {
                            Text(count.formatted()).monospacedDigit()
                        }
                    }
                    if let first = issue.firstObserved {
                        LabeledContent("首次发生") {
                            Text(first, format: .dateTime.year().month().day().hour().minute())
                        }
                    }
                    if let last = issue.lastObserved {
                        LabeledContent("最后发生") {
                            Text(last, format: .relative(presentation: .named))
                        }
                    }
                    if let type = issue.type, !type.isEmpty {
                        LabeledContent("类型", value: type)
                    }
                }
                .glassRow()

                actionsSection
                    .glassRow()

                Section("最近发生") {
                    if !viewModel.occurrencesLoaded && viewModel.isLoadingOccurrences {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if viewModel.occurrences.isEmpty {
                        if let error = viewModel.error {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            APIErrorDocLink(message: error)
                        } else {
                            Text(verbatim: "—")
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        ForEach(viewModel.occurrences) { occurrence in
                            OccurrenceRow(occurrence: occurrence)
                        }
                        if viewModel.nextCursor != nil {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .task { await viewModel.loadMoreOccurrences() }
                        }
                    }
                }
                .glassRow()
            }
            .daybreakList()
            .background { SkyBackground() }
            .navigationTitle("问题")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sensoryFeedback(.success, trigger: viewModel.didUpdate)
            // 发生记录加载失败已内联展示；这里只弹改状态失败
            .alert("出错了", isPresented: .init(
                get: { viewModel.actionError != nil },
                set: { if !$0 { viewModel.actionError = nil } }
            )) {
                apiErrorDocButton(for: viewModel.actionError)
                Button("好", role: .cancel) {}
            } message: {
                Text(viewModel.actionError ?? "")
            }
        }
    }

    // MARK: - 改状态

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            switch issue.knownStatus {
            case .active:
                statusButton(String(localized: "标记为已解决"), systemImage: "checkmark.circle", to: .resolved)
                statusButton(String(localized: "忽略"), systemImage: "eye.slash", to: .ignored)
            case .resolved, .ignored:
                statusButton(String(localized: "重新打开"), systemImage: "arrow.uturn.backward.circle", to: .active)
            }
        } footer: {
            // 无写权限：按钮置灰 + 就地补授权（老用户的 token 不含新 scope）
            if !canWrite {
                VStack(alignment: .leading, spacing: 8) {
                    Text("需要额外授权才能修改")
                    if let sessionId = auth.currentSessionId {
                        ReauthorizeButton(sessionId: sessionId, scopes: ["workers-observability.write"])
                            .font(.footnote.weight(.semibold))
                    }
                }
            }
        }
    }

    private func statusButton(_ title: String, systemImage: String, to status: WorkerIssueStatus) -> some View {
        Button {
            Task {
                if let updated = await viewModel.setStatus(status) {
                    onUpdate(updated)
                }
            }
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if viewModel.isUpdating { ProgressView() }
            }
        }
        .disabled(!canWrite || viewModel.isUpdating)
    }
}

// MARK: - 单次发生

private struct OccurrenceRow: View {
    let occurrence: WorkerIssueOccurrence

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(occurrence.headline)
                .font(.caption.monospaced())
                .foregroundStyle(.red)
                .lineLimit(4)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                if let summary = occurrence.invocation?.summary {
                    Text(summary)
                        .font(.caption2.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let status = occurrence.invocation?.statusCode {
                    Text(String(status))
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(status >= 500 ? Color.red : (status >= 400 ? Color.orange : Color.secondary))
                }
                Spacer(minLength: 0)
                if let time = occurrence.timestamp {
                    Text(time, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.secondary)

            if let stack = occurrence.error?.stack, !stack.isEmpty {
                DisclosureGroup {
                    Text(stack)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("堆栈")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tint(.secondary)
            }
        }
        .padding(.vertical, 2)
        // 错误正文恒定 LTR，避免 RTL 语言下路径 / 堆栈被镜像
        .environment(\.layoutDirection, .leftToRight)
    }
}
