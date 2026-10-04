//
//  TurnstileDetailView.swift
//  Orange Cloud
//
//  Turnstile 组件详情：sitekey / secret（遮蔽 + 复制）、模式与域名、
//  编辑（sheet）、密钥轮换（立即 / 2 小时宽限）、删除。
//  由宿主栈根 navigationDestination(for: TurnstileWidget.self) 解析（值式导航）。
//

import SwiftUI

struct TurnstileDetailView: View {

    @Environment(SessionStore.self) private var session
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: TurnstileViewModel
    @State private var widget: TurnstileWidget
    @State private var showEditor = false
    @State private var showRotate = false
    @State private var showDelete = false
    @State private var showDenied = false
    @State private var secretRevealed = false
    @State private var copied = false

    init(widget: TurnstileWidget, session: SessionStore) {
        _widget = State(initialValue: widget)
        _viewModel = State(initialValue: TurnstileViewModel(
            service: session.turnstileService,
            accountId: session.selectedAccount?.id ?? ""
        ))
    }

    private var canWrite: Bool { auth.hasScope("challenge-widgets.write") }

    var body: some View {
        List {
            keysSection
            configSection
            if canWrite { dangerSection }
        }
        .scrollContentBackground(.hidden)
        .background { SkyBackground() }
        .navigationTitle(widget.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canWrite {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("编辑") { showEditor = true }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            TurnstileEditorSheet(viewModel: viewModel, existing: widget) { updated in
                widget = updated
            }
        }
        .task {
            // 列表响应通常已含 secret，单查兜底一次拿完整对象
            if widget.secret == nil, let fresh = await viewModel.detail(sitekey: widget.sitekey) {
                widget = fresh
            }
        }
        .sensoryFeedback(.success, trigger: copied)
        .confirmationDialog("轮换密钥", isPresented: $showRotate, titleVisibility: .visible) {
            Button("轮换（旧密钥保留 2 小时）") {
                Task {
                    if let updated = await viewModel.rotateSecret(sitekey: widget.sitekey, immediately: false) {
                        widget = updated
                        secretRevealed = true
                    }
                }
            }
            Button("立即作废旧密钥", role: .destructive) {
                Task {
                    if let updated = await viewModel.rotateSecret(sitekey: widget.sitekey, immediately: true) {
                        widget = updated
                        secretRevealed = true
                    }
                }
            }
        } message: {
            Text("轮换后服务端需改用新密钥调用 siteverify。选择宽限可让旧密钥再工作 2 小时，平滑过渡。")
        }
        .confirmationDialog(
            String(localized: "删除组件「\(widget.name)」？"),
            isPresented: $showDelete,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                Task {
                    if await viewModel.delete(widget) { dismiss() }
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
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            apiErrorDocButton(for: viewModel.error)
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: - 密钥

    private var keysSection: some View {
        Section {
            Button {
                UIPasteboard.general.string = widget.sitekey
                copied.toggle()
            } label: {
                HStack(spacing: 12) {
                    TintIcon(systemImage: "key.horizontal", color: .ocOrange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Sitekey")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(widget.sitekey)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if let secret = widget.secret {
                Button {
                    if secretRevealed {
                        UIPasteboard.general.string = secret
                        copied.toggle()
                    } else {
                        secretRevealed = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        TintIcon(systemImage: "key.fill", color: .ocOrange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "Secret")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(secretRevealed ? secret : String(repeating: "•", count: 24))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: secretRevealed ? "doc.on.doc" : "eye")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if canWrite {
                Button {
                    showRotate = true
                } label: {
                    Label("轮换密钥", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        } header: {
            Text("集成密钥")
        } footer: {
            Text("sitekey 嵌进网页组件，secret 用于服务端 siteverify 校验——secret 请勿泄露。点按可复制。")
        }
        .glassRow()
    }

    // MARK: - 配置

    private var configSection: some View {
        Section {
            LabeledContent("模式", value: TurnstileMode(apiValue: widget.mode).label)
            if widget.domains.isEmpty {
                LabeledContent("域名", value: String(localized: "任意主机名"))
            } else {
                ForEach(widget.domains, id: \.self) { domain in
                    LabeledContent("域名") {
                        Text(domain).font(.callout.monospaced())
                    }
                }
            }
            if let region = widget.region {
                LabeledContent("区域", value: region == "china" ? String(localized: "中国") : String(localized: "全球"))
            }
            if widget.botFightMode == true {
                LabeledContent("Bot Fight Mode", value: String(localized: "已开启"))
            }
        } header: {
            Text("配置")
        } footer: {
            Text("组件在所列域名及其子域生效；域名留空表示任意主机名均可使用。")
        }
        .glassRow()
    }

    // MARK: - 危险操作

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showDelete = true
            } label: {
                Label("删除组件", systemImage: "trash")
            }
        }
        .glassRow()
    }
}
