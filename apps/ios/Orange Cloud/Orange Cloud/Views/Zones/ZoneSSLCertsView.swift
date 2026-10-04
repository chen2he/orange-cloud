//
//  ZoneSSLCertsView.swift
//  Orange Cloud
//
//  SSL 证书：展示 + Universal SSL 开关 + 删除证书包（仅非 Universal）。
//  写按 ssl-and-certificates.write 门控。
//

import SwiftUI

struct ZoneSSLCertsView: View {

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: ZoneSSLCertsViewModel
    @State private var showDenied = false
    @State private var pendingDelete: SSLCertificatePack?
    @State private var pendingUniversalOff = false

    init(zoneId: String, session: SessionStore) {
        _viewModel = State(initialValue: ZoneSSLCertsViewModel(
            service: session.sslCertificateService, zoneId: zoneId
        ))
    }

    private var canWrite: Bool { auth.hasScope("ssl-and-certificates.write") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.universalLoaded {
                    universalCard
                }

                if !viewModel.loaded && viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if viewModel.loaded && viewModel.packs.isEmpty {
                    ContentUnavailableView("暂无证书", systemImage: "checkmark.seal",
                        description: Text("此域名暂时没有边缘证书。"))
                        .padding(.top, 30)
                } else {
                    ForEach(viewModel.packs) { card($0) }
                }
            }
            .padding()
        }
        .background { SkyBackground() }
        .navigationTitle("SSL 证书")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .confirmationDialog("关闭 Universal SSL？", isPresented: $pendingUniversalOff, titleVisibility: .visible) {
            Button("关闭", role: .destructive) {
                Task { await viewModel.setUniversal(false) }
            }
        } message: {
            Text("关闭后该域名将不再自动签发边缘证书，HTTPS 可能失效。")
        }
        .confirmationDialog(
            "删除证书包",
            isPresented: .init(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            if let pack = pendingDelete {
                Button("删除", role: .destructive) {
                    Task { await viewModel.deletePack(pack) }
                }
            }
        } message: {
            Text("此操作不可撤销，该证书将被移除。")
        }
        .alert("权限不足", isPresented: $showDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含 SSL 编辑权限（ssl-and-certificates.write）。\n请在设置中退出登录后重新授权以启用此功能。")
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

    private var universalCard: some View {
        HStack(spacing: 12) {
            TintIcon(systemImage: "lock.shield", color: .green)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "Universal SSL")
                Text("Cloudflare 自动签发与续期的免费证书")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.isTogglingUniversal {
                ProgressView()
            } else if canWrite {
                Toggle("", isOn: Binding(
                    get: { viewModel.universalEnabled },
                    set: { on in
                        if on { Task { await viewModel.setUniversal(true) } }
                        else { pendingUniversalOff = true }
                    }
                ))
                .labelsHidden()
                .accessibilityLabel(Text(verbatim: "Universal SSL"))
            } else {
                Text(viewModel.universalEnabled ? String(localized: "开") : String(localized: "关"))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .glassIsland(cornerRadius: OCLayout.chipRadius)
    }

    private func card(_ pack: SSLCertificatePack) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TintIcon(systemImage: "checkmark.seal", color: .green)
                Text(pack.typeLabel).font(.headline)
                Spacer()
                Text(pack.statusLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
            if let hosts = pack.hosts, !hosts.isEmpty {
                Text(hosts.joined(separator: ", "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack(spacing: 14) {
                if let issuer = pack.issuer {
                    Label(issuer, systemImage: "building.columns")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let exp = pack.expiresOnDay {
                    Label(exp, systemImage: "calendar")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassIsland(cornerRadius: OCLayout.chipRadius)
        .contextMenu {
            if canWrite && !pack.isUniversal {
                Button("删除证书", systemImage: "trash", role: .destructive) {
                    pendingDelete = pack
                }
            }
        }
    }
}
