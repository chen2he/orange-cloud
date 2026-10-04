//
//  RequestTracerView.swift
//  Orange Cloud
//
//  「这个请求为什么被拦了」——模拟一个请求打过 Cloudflare，看它逐步走了哪些规则。
//

import SwiftUI

struct RequestTracerView: View {

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: RequestTracerViewModel
    @FocusState private var urlFocused: Bool

    init(session: SessionStore) {
        _viewModel = State(initialValue: RequestTracerViewModel(
            service: session.requestTracerService,
            accountId: session.selectedAccount?.id ?? ""
        ))
    }

    var body: some View {
        List {
            inputSection
            if let result = viewModel.result {
                resultSection(result)
            }
        }
        .daybreakList()
        .navigationTitle("请求追踪")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: viewModel.didTrace)
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil }, set: { if !$0 { viewModel.error = nil } }
        )) {
            apiErrorDocButton(for: viewModel.error)
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    private var inputSection: some View {
        Section {
            Picker("请求方法", selection: $viewModel.method) {
                ForEach(RequestTracerViewModel.methods, id: \.self) { Text($0).tag($0) }
            }

            TextField("https://example.com/path", text: $viewModel.urlText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .focused($urlFocused)

            Button {
                urlFocused = false
                Task { await viewModel.run() }
            } label: {
                HStack {
                    if viewModel.isTracing {
                        ProgressView().padding(.trailing, 4)
                    }
                    Text("开始追踪")
                }
            }
            .disabled(!viewModel.canTrace)
        } header: {
            Text("模拟请求")
        } footer: {
            // 说清楚这是模拟而非真实流量，否则用户会以为在看线上请求
            Text("模拟一条请求打过 Cloudflare，看它命中了哪些规则。不会真的发到源站，也不影响线上流量。需要管理员角色。")
        }
        .glassRow()
    }

    private func resultSection(_ result: TraceResult) -> some View {
        Section {
            if viewModel.flatSteps.isEmpty {
                Text("没有可展示的求值步骤。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.flatSteps) { flat in
                    stepRow(flat)
                }
            }
        } header: {
            HStack {
                Text("求值过程")
                Spacer()
                if let code = result.statusCode {
                    Text(verbatim: "HTTP \(code)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("命中的步骤以橙色标出，缩进表示规则集与其下规则的从属关系。")
        }
        .glassRow()
    }

    private func stepRow(_ flat: FlatTraceStep) -> some View {
        let step = flat.step
        let matched = step.matched == true
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                // 命中与否是这页的核心信息，用图标 + 颜色双重编码，不只靠颜色
                Image(systemName: matched ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(matched ? Color.ocOrange : Color.secondary)
                Text(step.title)
                    .font(.callout.weight(matched ? .semibold : .regular))
                    .lineLimit(2)
                Spacer()
                if let action = step.action, !action.isEmpty {
                    Text(action)
                        .font(.caption2.monospaced())
                        .foregroundStyle(matched ? Color.ocOrange : Color.secondary)
                }
            }
            if let expression = step.expression, !expression.isEmpty {
                Text(expression)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if let type = step.type, !type.isEmpty {
                Text(type)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, CGFloat(flat.depth) * 14)
        .padding(.vertical, 1)
    }
}
