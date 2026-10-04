//
//  ZoneDNSSettingsView.swift
//  Orange Cloud
//
//  域名的 DNS 设置：DNSSEC、CNAME 展平、多提供商 DNS、NS 类型、域名模式。
//  与 DNS 记录列表分开——那里是逐条记录，这里是 zone 级策略。
//

import SwiftUI

struct ZoneDNSSettingsView: View {

    let zoneName: String

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: DNSSettingsViewModel

    init(zoneId: String, zoneName: String, session: SessionStore) {
        self.zoneName = zoneName
        _viewModel = State(initialValue: DNSSettingsViewModel(
            service: session.dnsSettingsService, zoneId: zoneId
        ))
    }

    private var canEditSettings: Bool { auth.hasScope("zone-dns-settings.write") }
    private var canEditDNS: Bool { auth.hasScope("dns.write") }

    var body: some View {
        List {
            if viewModel.dnssecLoaded { dnssecSection }
            if viewModel.settingsLoaded { settingsSection }
            if !viewModel.isLoading && !viewModel.dnssecLoaded && !viewModel.settingsLoaded {
                Section {
                    Text("读不到该域名的 DNS 设置。可能是权限不足，或此域名不支持这些选项。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .glassRow()
            }
        }
        .daybreakList()
        .navigationTitle("DNS 设置")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sensoryFeedback(.success, trigger: viewModel.didMutate)
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil }, set: { if !$0 { viewModel.error = nil } }
        )) {
            apiErrorDocButton(for: viewModel.error)
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: DNSSEC

    @ViewBuilder
    private var dnssecSection: some View {
        if let dnssec = viewModel.dnssec {
            Section {
                Toggle(isOn: Binding(
                    get: { dnssec.isEnabled },
                    set: { on in Task { await viewModel.setDNSSEC(on) } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DNSSEC")
                        Text(dnssec.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!canEditDNS || viewModel.isMutating)

                // DS 记录必须由用户粘到域名注册商处，DNSSEC 才真正生效——
                // 这是最容易被忽略的一步，所以单独列出并可复制
                if let ds = dnssec.ds, !ds.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DS 记录")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(ds)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = ds
                        } label: {
                            Label("复制 DS 记录", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("DNSSEC")
            } footer: {
                Text(dnssec.status == "pending"
                     ? String(localized: "还需把上面的 DS 记录添加到你的域名注册商处，DNSSEC 才会真正生效。")
                     : String(localized: "为 DNS 应答加签，防止解析结果被篡改。"))
            }
            .glassRow()
        }
    }

    // MARK: DNS 设置

    @ViewBuilder
    private var settingsSection: some View {
        if let settings = viewModel.settings {
            Section {
                Toggle("展平所有 CNAME", isOn: Binding(
                    get: { settings.flattenAllCnames ?? false },
                    set: { on in Task { await viewModel.setFlattenAllCnames(on) } }
                ))
                .disabled(!canEditSettings || viewModel.isMutating)

                Toggle("多提供商 DNS", isOn: Binding(
                    get: { settings.multiProvider ?? false },
                    set: { on in Task { await viewModel.setMultiProvider(on) } }
                ))
                .disabled(!canEditSettings || viewModel.isMutating)

                Toggle("高级名称服务器", isOn: Binding(
                    get: { settings.nameservers?.type == "cloudflare.advanced" },
                    set: { on in Task { await viewModel.setAdvancedNameservers(on) } }
                ))
                .disabled(!canEditSettings || viewModel.isMutating)

                Picker("域名模式", selection: Binding(
                    get: { ZoneMode(apiValue: settings.zoneMode) },
                    set: { mode in Task { await viewModel.setZoneMode(mode) } }
                )) {
                    ForEach(ZoneMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .disabled(!canEditSettings || viewModel.isMutating)

                if let ttl = settings.nsTtl {
                    LabeledContent("NS 记录 TTL", value: String(localized: "\(Int(ttl)) 秒"))
                }
            } header: {
                Text("解析（\(zoneName)）")
            } footer: {
                Text(canEditSettings
                     ? String(localized: "展平 CNAME 会把 CNAME 解析成最终 IP 返回。多提供商 DNS 允许与其他 DNS 服务商共存。")
                     : String(localized: "当前授权仅限读取（zone-dns-settings.read）。"))
            }
            .glassRow()
        }
    }
}
