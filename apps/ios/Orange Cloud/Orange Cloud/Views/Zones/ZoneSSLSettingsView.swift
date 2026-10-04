//
//  ZoneSSLSettingsView.swift
//  Orange Cloud
//
//  「SSL/TLS」设置面板：加密模式 / 始终使用 HTTPS / 自动 HTTPS 重写 /
//  最低 TLS 版本 / TLS 1.3。读走 zone-settings.read，写走 zone-settings.write。
//

import SwiftUI

struct ZoneSSLSettingsView: View {

    let zoneName: String
    @State private var viewModel: ZoneSSLViewModel
    @Environment(AuthManager.self) private var auth

    init(zoneId: String, zoneName: String, session: SessionStore) {
        self.zoneName = zoneName
        _viewModel = State(initialValue: ZoneSSLViewModel(
            service: session.zoneSettingsService, zoneId: zoneId
        ))
    }

    private var canEdit: Bool { auth.hasScope("zone-settings.write") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !viewModel.loaded {
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else {
                        ContentUnavailableView {
                            Label(String(localized: "无法读取 SSL/TLS 设置"), systemImage: "lock")
                        } description: {
                            Text("当前授权未包含「缓存与防护」的读取权限。请退出登录后重新授权。")
                        }
                        .padding(.top, 40)
                    }
                } else {
                    encryptionCard
                    httpsCard
                    tlsCard
                    if !canEdit {
                        Text("当前为只读授权，如需修改请重新登录并勾选「缓存与防护」的编辑权限。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal)
                    }
                }
            }
            .padding()
        }
        .background { SkyBackground() }
        .navigationTitle(Text(verbatim: "SSL/TLS"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .alert("操作失败", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            apiErrorDocButton(for: viewModel.error)
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: - 加密模式

    private var encryptionCard: some View {
        card(String(localized: "加密")) {
            HStack(spacing: 12) {
                TintIcon(systemImage: "lock.shield", color: .green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SSL/TLS 加密模式")
                    Text(viewModel.sslMode.blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.updating.contains("ssl") {
                    ProgressView()
                } else {
                    Picker(String(localized: "加密模式"), selection: Binding(
                        get: { viewModel.sslMode },
                        set: { mode in Task { await viewModel.setSSLMode(mode) } }
                    )) {
                        ForEach(SSLMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .disabled(!canEdit)
                }
            }
        }
    }

    // MARK: - HTTPS

    private var httpsCard: some View {
        card(String(localized: "HTTPS")) {
            VStack(spacing: 16) {
                toggleRow(
                    title: String(localized: "始终使用 HTTPS"),
                    subtitle: String(localized: "把所有 HTTP 请求重定向到 HTTPS"),
                    icon: "arrow.uturn.up", tint: .blue,
                    setting: "always_use_https",
                    isOn: viewModel.alwaysUseHTTPS,
                    set: { on in Task { await viewModel.setAlwaysUseHTTPS(on) } }
                )
                toggleRow(
                    title: String(localized: "自动 HTTPS 重写"),
                    subtitle: String(localized: "把页面内的 HTTP 链接改写为 HTTPS"),
                    icon: "link", tint: .blue,
                    setting: "automatic_https_rewrites",
                    isOn: viewModel.autoHTTPSRewrites,
                    set: { on in Task { await viewModel.setAutoHTTPSRewrites(on) } }
                )
            }
        }
    }

    // MARK: - TLS 版本

    private var tlsCard: some View {
        card(String(localized: "TLS 版本")) {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    TintIcon(systemImage: "checkmark.shield", color: .green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("最低 TLS 版本")
                        Text("低于该版本的旧客户端将被拒绝")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if viewModel.updating.contains("min_tls_version") {
                        ProgressView()
                    } else {
                        Picker(String(localized: "最低 TLS 版本"), selection: Binding(
                            get: { viewModel.minTLS },
                            set: { v in Task { await viewModel.setMinTLS(v) } }
                        )) {
                            ForEach(MinTLSVersion.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .disabled(!canEdit)
                    }
                }
                toggleRow(
                    title: String(localized: "TLS 1.3"),
                    subtitle: String(localized: "启用最新的 TLS 1.3 协议"),
                    icon: "bolt.shield", tint: .green,
                    setting: "tls_1_3",
                    isOn: viewModel.tls13,
                    set: { on in Task { await viewModel.setTLS13(on) } }
                )
            }
        }
    }

    // MARK: - 复用组件

    private func toggleRow(
        title: String, subtitle: String, icon: String, tint: Color,
        setting: String, isOn: Bool, set: @escaping (Bool) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            TintIcon(systemImage: icon, color: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.updating.contains(setting) {
                ProgressView()
            } else {
                Toggle("", isOn: Binding(get: { isOn }, set: set))
                    .labelsHidden()
                    .accessibilityLabel(title)
                    .disabled(!canEdit)
            }
        }
    }

    private func card(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                content()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            .glassIsland(cornerRadius: OCLayout.chipRadius)
        }
    }
}
