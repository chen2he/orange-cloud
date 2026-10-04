//
//  SecurityInsightsView.swift
//  Orange Cloud
//
//  安全洞察（Security Center Insights）：按严重度分组列出 zone 的安全配置问题，
//  可「去处理」（外跳 Dashboard 对应页）、逐条「忽略」，工具栏「立即扫描」。
//  入口：域名详情「管理」卡（与 WAF / IP 访问规则同处安全区）。全套餐免费。
//  读需 zone-settings.read（入口已门控），扫描 / 忽略需 zone-settings.write。
//

import SwiftUI

struct SecurityInsightsView: View {

    let zoneName: String

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: SecurityInsightsViewModel
    @State private var showScanStarted = false
    @State private var showDenied = false

    init(zoneId: String, zoneName: String, session: SessionStore) {
        self.zoneName = zoneName
        _viewModel = State(initialValue: SecurityInsightsViewModel(
            service: session.securityInsightService, zoneId: zoneId
        ))
    }

    private var canWrite: Bool { auth.hasScope("zone-settings.write") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !viewModel.loaded && viewModel.isLoading {
                    SkeletonIslandRows(rows: 4, icon: .circle(28), showsSubtitle: true)
                } else if !viewModel.loaded, let error = viewModel.error {
                    loadFailed(error)
                } else if viewModel.loaded && viewModel.issues.isEmpty {
                    ContentUnavailableView {
                        Label("未发现安全问题", systemImage: "checkmark.shield")
                    } description: {
                        Text("每个账户每 24 小时最多扫描 5 次")
                    }
                    .padding(.top, 40)
                } else {
                    ForEach(viewModel.groups) { group in
                        severitySection(group)
                    }
                    Text("每个账户每 24 小时最多扫描 5 次")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding()
        }
        .background { SkyBackground() }
        .navigationTitle("安全洞察")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isScanning {
                    ProgressView()
                } else {
                    Button("立即扫描", systemImage: "arrow.triangle.2.circlepath.circle") {
                        if canWrite {
                            Task { await viewModel.startScan() }
                        } else {
                            showDenied = true
                        }
                    }
                }
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sensoryFeedback(.success, trigger: viewModel.didStartScan)
        .sensoryFeedback(.success, trigger: viewModel.didDismiss)
        .onChange(of: viewModel.didStartScan) { showScanStarted = true }
        .alert("已发起扫描，结果稍后更新", isPresented: $showScanStarted) {
            Button("好", role: .cancel) {}
        } message: {
            Text("每个账户每 24 小时最多扫描 5 次")
        }
        .alert("权限不足", isPresented: $showDenied) {
            if let sessionId = auth.currentSessionId {
                Button("一键重授权") {
                    Task { await auth.reauthorize(sessionId: sessionId, additionalScopes: ["zone-settings.write"]) }
                }
            }
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含此操作所需权限（\("zone-settings.write")）。点「一键重授权」补齐，无需退出登录。")
        }
        // 加载失败已有整页失败态；这里只弹操作（扫描 / 忽略）与刷新时的错误
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil && viewModel.loaded },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            apiErrorDocButton(for: viewModel.error)
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: - 分组

    private func severitySection(_ group: SecurityInsightsViewModel.SeverityGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color(for: group.severity))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(group.severity.label)
                Text(verbatim: "\(group.issues.count)")
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(group.issues) { issue in
                    issueRow(issue, severity: group.severity)
                    if issue.id != group.issues.last?.id {
                        Divider().padding(.leading, 54)
                    }
                }
            }
            .glassIsland(cornerRadius: OCLayout.chipRadius)
        }
    }

    private func issueRow(_ issue: SecurityInsight, severity: SecurityInsightSeverity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                TintIcon(systemImage: icon(for: severity), color: color(for: severity))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(issue.typeLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if issue.isResolved {
                            Text("已解决")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                    if let subject = issue.subject, !subject.isEmpty {
                        Text(subject)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                    if let since = issue.sinceDate {
                        Text(since, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                if let url = issue.resolveURL {
                    Link(destination: url) {
                        Label(resolveTitle(issue), systemImage: "arrow.up.right.square")
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.ocOrange)
                }
                Spacer(minLength: 0)
                if viewModel.dismissingId == issue.id {
                    ProgressView()
                } else {
                    Button("忽略") {
                        if canWrite {
                            Task { await viewModel.dismiss(issue) }
                        } else {
                            showDenied = true
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .disabled(viewModel.dismissingId != nil)
                }
            }
            .font(.footnote)
            .padding(.leading, 42)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func resolveTitle(_ issue: SecurityInsight) -> String {
        if let text = issue.resolveText?.trimmingCharacters(in: .whitespaces), !text.isEmpty {
            return text
        }
        return String(localized: "去处理")
    }

    private func loadFailed(_ message: String) -> some View {
        ContentUnavailableView {
            Label("加载失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重试") { Task { await viewModel.load() } }
                .buttonStyle(.borderedProminent)
                .tint(Color.ocOrangePressed)
            APIErrorDocLink(message: message)
        }
        .padding(.top, 40)
    }

    // MARK: - 严重度样式

    private func color(for severity: SecurityInsightSeverity) -> Color {
        switch severity {
        case .critical: .red
        case .moderate: .orange
        case .low:      .yellow
        case .other:    .gray
        }
    }

    private func icon(for severity: SecurityInsightSeverity) -> String {
        switch severity {
        case .critical: "exclamationmark.octagon"
        case .moderate: "exclamationmark.triangle"
        case .low:      "info.circle"
        case .other:    "questionmark.circle"
        }
    }
}
