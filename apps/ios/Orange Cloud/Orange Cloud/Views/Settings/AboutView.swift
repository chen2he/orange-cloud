//
//  AboutView.swift
//  Orange Cloud
//
//  「关于」二级页：版本、评分、社区（GitHub / Telegram 频道）、法律（隐私 / 条款）。
//  设置根页只保留单个「关于」入口，避免根页堆积过多外链。
//

import SwiftUI
import StoreKit

struct AboutView: View {

    @Environment(\.requestReview) private var requestReview

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            // ── App 头部 ──
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.ocOrange)
                        .accessibilityHidden(true)
                    Text(verbatim: "Orange Cloud")
                        .font(.title2.bold())
                    Text(appVersion)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("第三方 Cloudflare 客户端")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            // ── 评价 ──
            Section {
                // 系统应用内评分弹窗（无需 App Store ID）；iOS 限频，可能不弹
                Button {
                    requestReview()
                } label: {
                    HStack(spacing: 12) {
                        TintIcon(systemImage: "star.fill", color: .yellow)
                        Text("为 App 评分")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .glassRow()

            // ── 社区 ──
            Section {
                aboutLink("GitHub", icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com/chen2he/orange-cloud")
                aboutLink(String(localized: "Telegram 频道"), icon: "paperplane", url: "https://t.me/orange_cloud_channel")
            } header: {
                Text("社区")
            } footer: {
                Text("Telegram 频道发布版本更新与项目动态。")
            }
            .glassRow()

            // ── 法律 ──
            Section {
                aboutLink(String(localized: "隐私政策"), icon: "doc.text", url: "https://o-c.do/privacy")
                aboutLink(String(localized: "使用条款"), icon: "doc.plaintext", url: "https://o-c.do/terms")
            } header: {
                Text("法律")
            } footer: {
                VStack(spacing: 4) {
                    Text("Orange Cloud · 第三方 Cloudflare 客户端")
                    Text("© 2026 柘家科技有限公司")
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
            }
            .glassRow()
        }
        .daybreakList()
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aboutLink(_ title: String, icon: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                TintIcon(systemImage: icon, color: .gray)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
