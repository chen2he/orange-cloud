//
//  DomainSearchView.swift
//  Orange Cloud
//
//  搜索新域名（Sheet，自带 NavigationStack）：关键词搜候选域名，点按某个域名向注册局实时确认；
//  可注册时给「在 Cloudflare 控制台注册」外跳。App 内不做任何购买。
//  入口：「域名注册」页（与之同门槛：免费、registrar-domains.read）。
//

import SwiftUI

struct DomainSearchView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: DomainSearchViewModel
    @FocusState private var fieldFocused: Bool

    /// dash 的账号占位深链：由控制台按当前账号展开
    private static let registerURL = URL(string: "https://dash.cloudflare.com/?to=/:account/registrar/register")!

    init(session: SessionStore) {
        _viewModel = State(initialValue: DomainSearchViewModel(
            service: session.registrarService,
            accountId: session.selectedAccount?.id ?? ""
        ))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(text: $viewModel.query) { Text(verbatim: "example.com") }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .submitLabel(.search)
                            .focused($fieldFocused)
                            .onSubmit { Task { await viewModel.search() } }
                        if viewModel.isSearching {
                            ProgressView()
                        }
                    }
                } footer: {
                    Text("搜索结果可能有延迟，点开后会实时确认")
                }
                .glassRow()

                if !viewModel.results.isEmpty {
                    Section {
                        ForEach(viewModel.results) { domain in
                            row(domain)
                        }
                    }
                    .glassRow()
                } else if viewModel.searched && !viewModel.isSearching {
                    Section {
                        Text("没有找到可用的域名")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .glassRow()
                }

                if let error = viewModel.error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                        APIErrorDocLink(message: error)
                    }
                    .glassRow()
                }
            }
            .daybreakList()
            .navigationTitle("搜索新域名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { fieldFocused = true }
        }
    }

    private func row(_ domain: DomainAvailability) -> some View {
        let checked = viewModel.checkedNames.contains(domain.name)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await viewModel.check(domain) }
            } label: {
                HStack(spacing: 8) {
                    Text(domain.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if domain.isPremium {
                        Text("溢价")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.12), in: Capsule())
                    }
                    Spacer(minLength: 4)
                    if viewModel.checkingName == domain.name {
                        ProgressView()
                    } else if checked {
                        // 已向注册局实时确认
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.checkingName != nil)

            HStack(spacing: 6) {
                Text(domain.isRegistrable ? String(localized: "可注册") : String(localized: "不可注册"))
                    .foregroundStyle(domain.isRegistrable ? Color.green : Color.secondary)
                if !domain.isRegistrable, let reason = domain.reasonText {
                    Text(verbatim: "·")
                    Text(reason)
                }
            }
            .font(.caption.weight(.medium))

            if let pricing = domain.pricing, let first = pricing.registrationCost {
                Text("首年 \(first) \(pricing.currency ?? "") · 续费 \(pricing.renewalCost ?? "—")/年")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // 只有实时确认过且可注册才引导去控制台（搜索结果可能过期）
            if checked && domain.isRegistrable {
                Link(destination: Self.registerURL) {
                    Label("在 Cloudflare 控制台注册", systemImage: "arrow.up.right.square")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Color.ocOrange)
            }
        }
        .padding(.vertical, 2)
    }
}
