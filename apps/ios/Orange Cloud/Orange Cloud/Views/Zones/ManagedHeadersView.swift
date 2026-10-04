//
//  ManagedHeadersView.swift
//  Orange Cloud
//
//  托管请求/响应头：Cloudflare 维护的一组开关式头部改写，不用自己写 Transform 规则。
//

import SwiftUI

struct ManagedHeadersView: View {

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: ManagedHeadersViewModel

    init(zoneId: String, session: SessionStore) {
        _viewModel = State(initialValue: ManagedHeadersViewModel(
            service: session.managedHeaderService, zoneId: zoneId
        ))
    }

    private var canWrite: Bool { auth.hasScope("managed-headers.write") }

    var body: some View {
        List {
            section(
                title: String(localized: "请求头"),
                items: viewModel.requestHeaders,
                isRequest: true
            )
            section(
                title: String(localized: "响应头"),
                items: viewModel.responseHeaders,
                isRequest: false
            )
        }
        .daybreakList()
        .navigationTitle("托管头")
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

    @ViewBuilder
    private func section(title: String, items: [ManagedTransform], isRequest: Bool) -> some View {
        Section {
            if viewModel.isLoading && !viewModel.loaded {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
            } else if items.isEmpty {
                Text("此域名没有可用的托管头。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(item.displayName, isOn: Binding(
                            get: { item.enabled ?? false },
                            set: { on in
                                Task { await viewModel.setEnabled(item, enabled: on, isRequest: isRequest) }
                            }
                        ))
                        .disabled(!canWrite || viewModel.isMutating)
                        // 互斥关系由接口给出，开之前让用户知道会顶掉谁
                        if let conflicts = item.conflictsWith, !conflicts.isEmpty {
                            Text("与 \(conflicts.joined(separator: "、")) 互斥")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text(title)
        } footer: {
            if !isRequest {
                Text(canWrite
                     ? String(localized: "由 Cloudflare 维护的头部改写，开关即生效，无需自己写 Transform 规则。")
                     : String(localized: "当前授权仅限读取（managed-headers.read）。"))
            }
        }
        .glassRow()
    }
}
