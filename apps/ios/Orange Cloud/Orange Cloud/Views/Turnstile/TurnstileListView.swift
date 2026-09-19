//
//  TurnstileListView.swift
//  Orange Cloud
//
//  Turnstile 人机验证：widget 列表 / 新建 / 编辑 / 密钥轮换 / 删除。
//  读 challenge-widgets.read，写操作按 challenge-widgets.write 门控。
//
//  导航：入口在概览页「网络」岛（DashboardRoute.turnstile），列表行点击继续 push 详情，
//  详情由宿主栈根 .navigationDestination(for: TurnstileWidget.self) 解析——
//  本链路全值式，eager 形态在 iOS 17.0 会卡死（见 DashboardView 注释）。
//

import SwiftUI

struct TurnstileListView: View {

    @Environment(SessionStore.self) private var session
    @Environment(AuthManager.self) private var auth
    @State private var viewModel: TurnstileViewModel
    @State private var showCreate = false
    @State private var showDenied = false
    @State private var widgetToDelete: TurnstileWidget?

    init(session: SessionStore) {
        _viewModel = State(initialValue: TurnstileViewModel(
            service: session.turnstileService,
            accountId: session.selectedAccount?.id ?? ""
        ))
    }

    private var canWrite: Bool { auth.hasScope("challenge-widgets.write") }

    var body: some View {
        Group {
            if viewModel.widgets.isEmpty && viewModel.isLoading {
                SkeletonList(rows: 4)
            } else if viewModel.widgets.isEmpty {
                ContentUnavailableView {
                    Label("没有 Turnstile 组件", systemImage: "checkmark.shield")
                } description: {
                    Text("Turnstile 是 Cloudflare 的免费人机验证，替代传统验证码。新建组件后把 sitekey 嵌进你的网站即可。")
                } actions: {
                    if canWrite {
                        Button("新建组件") { showCreate = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.ocOrangePressed)
                            .fontWeight(.bold)
                    }
                }
            } else {
                List(viewModel.widgets) { widget in
                    NavigationLink(value: widget) {
                        TurnstileRow(widget: widget)
                    }
                    .glassRow()
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            if canWrite { widgetToDelete = widget } else { showDenied = true }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .refreshable { await viewModel.load() }
            }
        }
        .background { SkyBackground() }
        .navigationTitle("Turnstile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("新建", systemImage: "plus") {
                    if canWrite { showCreate = true } else { showDenied = true }
                }
            }
            .ocPriority(.primary)
            ToolbarItem(placement: .topBarTrailing) {
                RefreshButton(
                    isLoading: viewModel.isLoading,
                    failed: viewModel.error != nil,
                    action: { Task { await viewModel.load() } }
                )
            }
            .ocPriority(.secondary)
        }
        .sheet(isPresented: $showCreate) {
            TurnstileEditorSheet(viewModel: viewModel, existing: nil)
        }
        .task { if !viewModel.loaded { await viewModel.load() } }
        .confirmationDialog(
            widgetToDelete.map { String(localized: "删除组件「\($0.name)」？") } ?? "",
            isPresented: .init(
                get: { widgetToDelete != nil },
                set: { if !$0 { widgetToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let widget = widgetToDelete {
                    Task { await viewModel.delete(widget) }
                }
            }
        } message: {
            Text("嵌在网站上的该组件将立即失效，此操作不可撤销。")
        }
        .alert("权限不足", isPresented: $showDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含 Turnstile 编辑权限（challenge-widgets.write）。\n请在设置中重新授权以启用此功能。")
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil && !viewModel.isLoading },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }
}

// MARK: - 列表行

private struct TurnstileRow: View {

    let widget: TurnstileWidget

    var body: some View {
        HStack(spacing: 12) {
            TintIcon(systemImage: "checkmark.shield", color: .ocOrange)
            VStack(alignment: .leading, spacing: 3) {
                Text(widget.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(widget.sitekey)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(TurnstileMode(apiValue: widget.mode).label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.ocOrangeText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.ocOrange.opacity(0.14), in: Capsule())
                Text(widget.domains.isEmpty
                     ? String(localized: "任意主机名")
                     : String(localized: "\(widget.domains.count) 个域名"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
