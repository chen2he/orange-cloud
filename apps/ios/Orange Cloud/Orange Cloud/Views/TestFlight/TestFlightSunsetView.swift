//
//  TestFlightSunsetView.swift
//  Orange Cloud
//
//  TestFlight 测试轨停用公告（晨昏风），及 .testFlightSunsetNotice() 触发修饰器。
//  只在 TestFlight 包上出现（判据见 TestFlightSunset），领码走系统邮件——
//  **App 不收集、不上传、不存储邮箱**：用户从自己的邮件客户端发出，地址天然在发件人里。
//

import SwiftUI
import MessageUI
import UIKit

struct TestFlightSunsetView: View {

    let accountCount: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var mailData: MailData?
    @State private var shareItems: [Any]?

    /// 点过「领码」或「去 App Store」即视为已处理，之后不再打扰
    let onAct: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 内容短时居中、长时（德语/阿拉伯语等）正常滚动
            GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 10) {
                        Image(systemName: "airplane.departure")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.ocOrange)
                            .accessibilityHidden(true)
                        Text("TestFlight 测试版即将停用")
                            .font(.title.weight(.bold))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 18) {
                        paragraph(
                            "clock.badge.exclamationmark",
                            Text("这个测试版不再更新，\(Self.dateText(TestFlightSunset.buildExpiry)) 之后会过期、无法再打开。App Store 版本一直在更新，功能与修复都在那边。")
                        )
                        paragraph(
                            "ticket",
                            Text("感谢你一路陪着测试。在 \(Self.dateText(TestFlightSunset.codeDeadline)) 前来信，我们会回你一张 Pro 优惠码。")
                        )
                        paragraph(
                            "creditcard.trianglebadge.exclamationmark",
                            Text("提醒：TestFlight 版本内的购买走 Apple 沙盒环境——订阅几分钟就会过期，也读不到你在 App Store 的真实购买。购买或恢复 Pro 请使用 App Store 版本。")
                        )
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                .padding(.horizontal, 28)
            }
            }

            VStack(spacing: 10) {
                Button(action: requestCode) {
                    Text("发邮件领取优惠码")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.ocOrangePressed)

                Button {
                    openURL(TestFlightSunset.appStoreURL)
                    onAct()
                    dismiss()
                } label: {
                    Text("前往 App Store")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)

                Button("稍后再说") { dismiss() }
                    .font(.subheadline)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background { SkyBackground().ignoresSafeArea() }
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

    @ViewBuilder
    private func paragraph(_ symbol: String, _ text: Text) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.ocOrange)
                .frame(width: 28, alignment: .center)
                .accessibilityHidden(true)
            text
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// 领码：拉起系统邮件，收件人 / 标题 / 正文全预填，用户点发送即可。
    /// 没有邮件账号时回退系统分享，正文照样带齐。
    private func requestCode() {
        onAct()
        let body = String(localized: "我想领取 TestFlight 用户的 Pro 优惠码。")
            + "\n\n" + DiagnosticsInfo.summary(accountCount: accountCount)
        let subject = String(localized: "TestFlight 优惠码申请")
        if MFMailComposeViewController.canSendMail() {
            mailData = MailData(
                recipients: [DiagnosticsInfo.supportEmail],
                subject: subject,
                body: body,
                attachmentURL: nil
            )
        } else {
            shareItems = ["\(DiagnosticsInfo.supportEmail)\n\(subject)\n\n\(body)"]
        }
    }

    private var shareBinding: Binding<Bool> {
        Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })
    }

    /// 按用户语言/地区格式化日期（阿拉伯语等会自动用当地写法）
    private static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.wide).day())
    }
}

// MARK: - 触发修饰器

private struct TestFlightSunsetModifier: ViewModifier {

    /// 呈现与内容绑定到同一个值（.sheet(item:)）——iOS 17 上 isPresented + 旁路 state
    /// 会捕获到赋值生效前一拍的空内容，见 WhatsNewModifier 的注释。
    private struct Payload: Identifiable { let id = UUID() }

    @AppStorage("tfSunsetNoticeActed") private var acted = false
    @AppStorage("tfSunsetNoticeShownCount") private var shownCount = 0

    @Environment(AuthManager.self) private var auth
    @State private var payload: Payload?

    func body(content: Content) -> some View {
        content
            .task {
                guard TestFlightSunset.shouldPresent(acted: acted, shownCount: shownCount) else { return }
                // 与 What's New / 体验者计划询问错峰：同一次启动只出一个弹窗
                try? await Task.sleep(for: .seconds(2))
                guard !WhatsNewGate.presentedThisLaunch,
                      TestFlightSunset.shouldPresent(acted: acted, shownCount: shownCount) else { return }
                WhatsNewGate.presentedThisLaunch = true
                shownCount += 1
                payload = Payload()
            }
            .sheet(item: $payload) { _ in
                TestFlightSunsetView(accountCount: auth.sessions.count) { acted = true }
            }
    }
}

extension View {
    /// TestFlight 测试轨停用公告（挂在登录后的会话根视图，What's New / 体验者询问之后）
    func testFlightSunsetNotice() -> some View {
        modifier(TestFlightSunsetModifier())
    }
}
