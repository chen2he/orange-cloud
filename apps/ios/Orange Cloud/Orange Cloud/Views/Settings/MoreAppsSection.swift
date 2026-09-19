//
//  MoreAppsSection.swift
//  Orange Cloud
//
//  设置页「来自柘家科技」：给同一开发者的其他 App 一点曝光，数据源为 zhe.ltd/products。
//  只挑与 Orange Cloud 用户（开发者 / 站长）相关的几款，静态清单、图标内置，不联网取数。
//  文案走独立的 MoreApps.xcstrings（table: "MoreApps"），与 Localizable.xcstrings 解耦。
//

import SwiftUI

struct MoreAppsSection: View {

    @Environment(\.openURL) private var openURL

    private struct ProductApp: Identifiable {
        let id: String            // App Store ID
        let name: String          // 品牌名，不翻译
        let tagline: String
        let icon: String          // Assets 里的 imageset
        let macOnly: Bool
        let minimumOS: OperatingSystemVersion
        let chineseOnly: Bool     // 只对中文界面有意义的产品

        var storeURL: URL { URL(string: "https://apps.apple.com/app/id\(id)")! }
    }

    private static let apps: [ProductApp] = [
        ProductApp(
            id: "6796458283",
            name: "Apolu",
            tagline: String(localized: "App Store 排名追踪，覆盖 175 个国家和地区", table: "MoreApps"),
            icon: "MoreAppApolu",
            macOnly: false,
            minimumOS: OperatingSystemVersion(majorVersion: 18, minorVersion: 0, patchVersion: 0),
            chineseOnly: false
        ),
        ProductApp(
            id: "6782443539",
            name: "PrivyMark",
            tagline: String(localized: "分享前，先把隐私盖住", table: "MoreApps"),
            icon: "MoreAppPrivyMark",
            macOnly: false,
            minimumOS: OperatingSystemVersion(majorVersion: 17, minorVersion: 6, patchVersion: 0),
            chineseOnly: false
        ),
        // 软著登记是中国大陆特有流程，非中文界面不展示
        ProductApp(
            id: "6804225303",
            name: "著手",
            tagline: String(localized: "软著源程序鉴别材料，一次整理到位", table: "MoreApps"),
            icon: "MoreAppZhushou",
            macOnly: true,
            minimumOS: OperatingSystemVersion(majorVersion: 17, minorVersion: 0, patchVersion: 0),
            chineseOnly: true
        ),
    ]

    private var uiLanguage: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    private var visibleApps: [ProductApp] {
        let isChinese = uiLanguage.hasPrefix("zh")
        return Self.apps.filter { app in
            (!app.chineseOnly || isChinese)
                && ProcessInfo.processInfo.isOperatingSystemAtLeast(app.minimumOS)
        }
    }

    /// zhe.ltd 只有简中（默认）/ 繁中 / 英文三套
    private var productsURL: URL {
        let path: String
        switch uiLanguage {
        case "zh-Hans": path = "/products"
        case "zh-Hant", "zh-HK": path = "/zh-Hant/products"
        default: path = "/en/products"
        }
        return URL(string: "https://zhe.ltd\(path)")!
    }

    var body: some View {
        Section {
            ForEach(visibleApps) { app in
                // 用 Button + openURL 而非 Link：Link 会把整行文字染成强调色
                Button {
                    openURL(app.storeURL)
                } label: {
                    appRow(app)
                }
                .accessibilityHint(Text("在 App Store 中打开", tableName: "MoreApps"))
            }

            Button {
                openURL(productsURL)
            } label: {
                HStack(spacing: 12) {
                    TintIcon(systemImage: "square.grid.2x2", color: .gray)
                    Text("更多产品", tableName: "MoreApps")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(verbatim: "zhe.ltd")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text("来自柘家科技", tableName: "MoreApps")
        } footer: {
            Text("Orange Cloud 出自柘家科技，以上是我们开发的其他 App。", tableName: "MoreApps")
        }
        .glassRow()
    }

    private func appRow(_ app: ProductApp) -> some View {
        HStack(spacing: 12) {
            Image(app.icon)
                .resizable()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 38 * 0.225, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 38 * 0.225, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: app.name)
                        .foregroundStyle(.primary)
                    if app.macOnly {
                        Text(verbatim: "Mac")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.secondary.opacity(0.14), in: Capsule())
                    }
                }
                Text(app.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
