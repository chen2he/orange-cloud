//
//  FeedbackView.swift
//  Orange Cloud
//
//  设置 → 帮助与反馈：写反馈 → 系统邮件发到 support@zhe.ltd（自动带诊断头，可选附诊断日志）。
//  无邮件账号时回退系统分享（正文 + 日志文件）。
//

import SwiftUI
import MessageUI
import UIKit

struct FeedbackView: View {

    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var includeLogs = true
    @State private var mailData: MailData?
    @State private var shareItems: [Any]?

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 150)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("描述你遇到的问题，或想反馈的建议……")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("反馈内容")
                }

                Section {
                    Toggle(isOn: $includeLogs) {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "doc.text.magnifyingglass", color: .ocOrange)
                            Text("附带诊断日志")
                        }
                    }
                } footer: {
                    Text("日志只含 App 运行记录（请求路径、状态码、错误、登录态变化等），不含你的 Cloudflare 令牌、密钥值或账号密码。")
                }
            }
            .navigationTitle("发送反馈")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送") { send() }
                        .disabled(!canSend)
                }
            }
            .sheet(item: $mailData) { data in
                MailComposeView(data: data) { mailData = nil; dismiss() }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: shareBinding) {
                if let shareItems {
                    ActivityView(items: shareItems)
                }
            }
        }
    }

    private func send() {
        let header = DiagnosticsInfo.summary(accountCount: auth.sessions.count)
        let body = "\(text)\n\n\(header)"
        let logURL = includeLogs ? LogFileStore.shared.exportedFileURL() : nil

        if MFMailComposeViewController.canSendMail() {
            mailData = MailData(
                recipients: [DiagnosticsInfo.supportEmail],
                subject: String(localized: "Orange Cloud 反馈"),
                body: body,
                attachmentURL: logURL
            )
        } else {
            // 无邮件账号：回退系统分享，正文 + 日志文件
            var items: [Any] = [body]
            if let logURL { items.append(logURL) }
            shareItems = items
        }
    }

    private var shareBinding: Binding<Bool> {
        Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })
    }
}

// MARK: - 邮件撰写器（MessageUI 包装）

struct MailData: Identifiable {
    let id = UUID()
    let recipients: [String]
    let subject: String
    let body: String
    let attachmentURL: URL?
}

struct MailComposeView: UIViewControllerRepresentable {
    let data: MailData
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(data.recipients)
        controller.setSubject(data.subject)
        controller.setMessageBody(data.body, isHTML: false)
        if let url = data.attachmentURL, let bytes = try? Data(contentsOf: url) {
            controller.addAttachmentData(bytes, mimeType: "text/plain", fileName: url.lastPathComponent)
        }
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: (any Error)?
        ) {
            onFinish()
        }
    }
}

// MARK: - 系统分享（无邮件账号回退 / 导出日志共用）

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
