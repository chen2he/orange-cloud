//
//  RegistrarView.swift
//  Orange Cloud
//
//  在 Cloudflare 注册的域名：到期日、自动续费、转移锁；以及「搜索新域名」（只查不买）。
//

import SwiftUI

struct RegistrarView: View {

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: RegistrarViewModel
    @State private var showSearch = false
    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
        _viewModel = State(initialValue: RegistrarViewModel(
            service: session.registrarService,
            accountId: session.selectedAccount?.id ?? ""
        ))
    }

    private var canAdmin: Bool { auth.hasScope("registrar-domains.admin") }

    var body: some View {
        List {
            // 搜索新域名：sheet 内自带导航栈（本页被 push 在概览栈里，不再往下 push）
            Section {
                Button {
                    showSearch = true
                } label: {
                    HStack(spacing: 12) {
                        TintIcon(systemImage: "magnifyingglass", color: .ocOrange)
                        Text("搜索新域名").foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .glassRow()

            Section {
                if viewModel.isLoading && !viewModel.loaded {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
                } else if viewModel.registrations.isEmpty {
                    Text("此账号下没有在 Cloudflare 注册的域名。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.registrations) { registration in
                        registrationRow(registration)
                    }
                }
            } header: {
                Text("已注册域名")
            } footer: {
                Text(canAdmin
                     ? String(localized: "开启自动续费即授权 Cloudflare 在到期前 30 天内扣默认支付方式。域名注册与转移锁请在 Cloudflare 控制台操作。")
                     : String(localized: "当前授权仅限读取（registrar-domains.read）。"))
            }
            .glassRow()
        }
        .daybreakList()
        .navigationTitle("域名注册")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sensoryFeedback(.success, trigger: viewModel.didMutate)
        .sheet(isPresented: $showSearch) {
            DomainSearchView(session: session)
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

    private func registrationRow(_ registration: DomainRegistration) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(registration.domainName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(registration.statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(registration.status == "active" ? Color.secondary : Color.orange)
            }

            if let expiry = registration.expiryDate {
                HStack(spacing: 6) {
                    Text("到期")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(expiry, format: .dateTime.year().month().day())
                        .font(.caption)
                        .foregroundStyle(registration.needsAttention ? Color.orange : Color.secondary)
                    if let days = registration.daysUntilExpiry, days <= 30 {
                        Text(days >= 0
                             ? String(localized: "还剩 \(days) 天")
                             : String(localized: "已过期"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }

            Toggle("自动续费", isOn: Binding(
                get: { registration.autoRenew ?? false },
                set: { on in Task { await viewModel.setAutoRenew(registration, enabled: on) } }
            ))
            .font(.caption)
            .disabled(!canAdmin || viewModel.isMutating)

            // 转移锁在新版 API 里只读，做成开关会误导用户以为能改
            if let locked = registration.locked {
                Text(locked ? String(localized: "转移锁：已开启") : String(localized: "转移锁：未开启"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
