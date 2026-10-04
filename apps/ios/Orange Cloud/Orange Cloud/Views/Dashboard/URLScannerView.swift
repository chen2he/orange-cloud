//
//  URLScannerView.swift
//  Orange Cloud
//
//  URL 安全扫描：提交一个链接，看它的归属、状态与风险判定。
//  注意不能放进工具箱——那里是免登录的，本功能需要账号。
//

import SwiftUI

struct URLScannerView: View {

    @State private var viewModel: URLScannerViewModel
    @FocusState private var urlFocused: Bool

    init(session: SessionStore) {
        _viewModel = State(initialValue: URLScannerViewModel(
            service: session.urlScannerService,
            accountId: session.selectedAccount?.id ?? ""
        ))
    }

    var body: some View {
        List {
            inputSection
            if let result = viewModel.result {
                verdictSection(result)
                pageSection(result)
            }
        }
        .daybreakList()
        .navigationTitle("URL 扫描")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: viewModel.didFinish)
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
            TextField("example.com", text: $viewModel.urlText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .focused($urlFocused)

            Button {
                urlFocused = false
                Task { await viewModel.scan() }
            } label: {
                HStack {
                    if viewModel.isScanning {
                        ProgressView().padding(.trailing, 4)
                    }
                    Text(viewModel.isScanning ? String(localized: "扫描中…") : String(localized: "开始扫描"))
                }
            }
            .disabled(!viewModel.canScan)
        } header: {
            Text("扫描链接")
        } footer: {
            // 扫描是异步的，且结果会进 Cloudflare 的公共扫描库，得说清楚
            Text("由 Cloudflare 打开该链接并生成安全报告，通常需要几十秒。扫描记录会保存在 Cloudflare 的扫描库中。")
        }
        .glassRow()
    }

    private func verdictSection(_ result: URLScanResult) -> some View {
        Section("判定") {
            let malicious = result.verdicts?.overall?.malicious == true
            HStack(spacing: 8) {
                Image(systemName: malicious ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                    .foregroundStyle(malicious ? Color.red : Color.green)
                Text(malicious ? String(localized: "判定为恶意") : String(localized: "未发现恶意特征"))
                    .font(.callout.weight(.semibold))
            }
            if let categories = result.verdicts?.overall?.categories, !categories.isEmpty {
                LabeledContent("分类", value: categories.compactMap(\.name).joined(separator: "、"))
            }
        }
        .glassRow()
    }

    private func pageSection(_ result: URLScanResult) -> some View {
        Section("页面") {
            if let url = result.page?.url ?? result.task?.effectiveUrl {
                LabeledContent("最终地址") {
                    Text(url)
                        .font(.caption.monospaced())
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            if let ip = result.page?.ip {
                LabeledContent("IP", value: ip)
            }
            if let asn = result.page?.asn {
                LabeledContent("ASN", value: [asn, result.page?.asnname].compactMap { $0 }.joined(separator: " "))
            }
            if let country = result.page?.country {
                LabeledContent("国家/地区", value: country)
            }
            if let server = result.page?.server {
                LabeledContent("服务器", value: server)
            }
            if let code = result.page?.statusCode {
                LabeledContent("状态码", value: "\(code)")
            }
        }
        .glassRow()
    }
}
