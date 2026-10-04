//
//  APIErrorDocButton.swift
//  Orange Cloud
//
//  错误展示处的「查看所需权限」：错误文案能对上 CF 回的 documentation_url 时才出现，
//  点开该端点所需角色 / 权限的官方文档（见 APIErrorDocLinks）。
//
//  做成返回 `some View` 的函数而非自定义 View 结构体：alert 的 actions 只认 Button
//  （及 Optional / 条件等系统容器），包一层自定义 View 在部分系统版本上会被忽略。
//

import SwiftUI
import UIKit

/// 放进 `.alert { … }` 的 actions：无文档地址时什么都不渲染
@ViewBuilder
func apiErrorDocButton(for message: String?) -> some View {
    if let url = APIErrorDocLinks.url(for: message) {
        Button(String(localized: "查看所需权限")) {
            UIApplication.shared.open(url)
        }
    }
}

/// 页内错误态（ContentUnavailableView 的 actions、内联错误文字下方）用的链接样式版本
struct APIErrorDocLink: View {
    let message: String?

    var body: some View {
        if let url = APIErrorDocLinks.url(for: message) {
            Link(destination: url) {
                Label(String(localized: "查看所需权限"), systemImage: "doc.text.magnifyingglass")
            }
            .font(.footnote)
        }
    }
}
