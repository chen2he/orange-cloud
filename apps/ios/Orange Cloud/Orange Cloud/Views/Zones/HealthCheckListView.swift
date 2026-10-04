//
//  HealthCheckListView.swift
//  Orange Cloud
//
//  独立健康检查：源站是否在线。与负载均衡的监控器不同源，别混用。
//

import SwiftUI

struct HealthCheckListView: View {

    let zoneName: String

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: HealthCheckViewModel
    @State private var checkToDelete: HealthCheck?
    @State private var detailTarget: HealthCheck?
    @State private var alertViewModel: HealthCheckAlertViewModel

    init(zoneId: String, zoneName: String, session: SessionStore) {
        self.zoneName = zoneName
        _viewModel = State(initialValue: HealthCheckViewModel(
            service: session.healthCheckService,
            zoneId: zoneId
        ))
        _alertViewModel = State(initialValue: HealthCheckAlertViewModel(
            service: session.alertingService,
            accountId: session.selectedAccount?.id ?? ""
        ))
    }

    private var canWrite: Bool { auth.hasScope("healthcheck.write") }

    var body: some View {
        List {
            alertSection
            checksSection
        }
        .daybreakList()
        .navigationTitle("健康检查")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .task { if auth.hasScope("notifications.read") { await alertViewModel.load() } }
        .refreshable { await viewModel.load() }
        .sensoryFeedback(.success, trigger: viewModel.didMutate)
        .sheet(item: $detailTarget) { check in
            NavigationStack {
                HealthCheckDetailView(check: check)
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "删除健康检查",
            isPresented: .init(get: { checkToDelete != nil }, set: { if !$0 { checkToDelete = nil } }),
            titleVisibility: .visible,
            presenting: checkToDelete
        ) { check in
            Button("删除「\(check.name)」", role: .destructive) {
                Task { await viewModel.delete(check) }
            }
        } message: { _ in
            Text("删除后将不再监控该源站，也不会再收到相关通知。不可撤销。")
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

    /// 源站异常时推送。走 CF 原生告警（health_check_status_notification），
    /// 服务端投递 webhook —— App 关着也能收到，比客户端轮询可靠。
    @ViewBuilder
    private var alertSection: some View {
        if alertViewModel.pushEndpoint != nil && alertViewModel.isAvailable {
            Section {
                Toggle("源站异常时通知我", isOn: Binding(
                    get: { alertViewModel.isEnabled },
                    set: { on in Task { await alertViewModel.setEnabled(on) } }
                ))
                .disabled(!auth.hasScope("notifications.write") || alertViewModel.isMutating)
            } footer: {
                Text("由 Cloudflare 在源站状态变化时直接推送，App 不需要开着。")
            }
            .glassRow()
        }
    }

    private var checksSection: some View {
        Section {
            if viewModel.isLoading && !viewModel.loaded {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
            } else if viewModel.checks.isEmpty {
                // 免费套餐不支持健康检查，此处同样是空列表——不臆测原因，只说事实
                Text("此域名暂无健康检查。可在 Cloudflare 控制台创建后回到这里查看与暂停。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.checks) { check in
                    checkRow(check)
                        .swipeActions(edge: .leading) {
                            if canWrite {
                                Button {
                                    Task {
                                        await viewModel.setSuspended(check, suspended: !(check.suspended ?? false))
                                    }
                                } label: {
                                    Label(check.suspended == true
                                          ? String(localized: "恢复") : String(localized: "暂停"),
                                          systemImage: check.suspended == true ? "play" : "pause")
                                }
                                .tint(.orange)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            if canWrite {
                                Button(role: .destructive) { checkToDelete = check } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                }
            }
        } header: {
            Text("源站监控（\(zoneName)）")
        } footer: {
            Text(canWrite
                 ? String(localized: "点按查看详情，左滑暂停或恢复，右滑删除。暂停后不再向源站发送检查。")
                 : String(localized: "当前授权仅限读取（healthcheck.read）。"))
        }
        .glassRow()
    }

    private func checkRow(_ check: HealthCheck) -> some View {
        Button {
            detailTarget = check
        } label: {
            HStack(spacing: 12) {
                TintIcon(systemImage: "waveform.path.ecg", color: statusColor(check))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(check.name)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text(check.displayStatus.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(statusColor(check))
                    }
                    if let address = check.address {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    // 只在真的异常时显示原因，避免正常态也占一行
                    if check.displayStatus == .unhealthy,
                       let reason = check.failureReason, !reason.isEmpty {
                        Text(reason)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private func statusColor(_ check: HealthCheck) -> Color {
        switch check.displayStatus {
        case .healthy:   .green
        case .unhealthy: .red
        case .suspended: .gray
        case .unknown:   .orange
        }
    }
}

// MARK: - 详情

private struct HealthCheckDetailView: View {

    let check: HealthCheck
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("状态") {
                LabeledContent("当前状态", value: check.displayStatus.label)
                if check.displayStatus == .unhealthy,
                   let reason = check.failureReason, !reason.isEmpty {
                    LabeledContent("失败原因", value: reason)
                }
                if let fails = check.consecutiveFails {
                    LabeledContent("连续失败", value: "\(fails)")
                }
                if let successes = check.consecutiveSuccesses {
                    LabeledContent("连续成功", value: "\(successes)")
                }
            }
            .glassRow()

            Section("配置") {
                if let address = check.address {
                    LabeledContent("源站") {
                        Text(address)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                if let type = check.type {
                    LabeledContent("协议", value: type)
                }
                if let interval = check.interval {
                    LabeledContent("检查间隔", value: String(localized: "\(interval) 秒"))
                }
                if let timeout = check.timeout {
                    LabeledContent("超时", value: String(localized: "\(timeout) 秒"))
                }
                if let retries = check.retries {
                    LabeledContent("重试次数", value: "\(retries)")
                }
                if let regions = check.checkRegions, !regions.isEmpty {
                    LabeledContent("检查区域", value: regions.joined(separator: "、"))
                } else {
                    LabeledContent("检查区域", value: String(localized: "由 Cloudflare 自选"))
                }
                if let description = check.description, !description.isEmpty {
                    LabeledContent("备注", value: description)
                }
            }
            .glassRow()
        }
        .daybreakList()
        .navigationTitle(check.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
    }
}
