//
//  APIErrorDocLinks.swift
//  Orange Cloud
//
//  错误文案 → CF「所需权限」文档地址的进程内映射。
//
//  2026-08-21 起 CF 在 403 错误体里带 `errors[].documentation_url`，APIError 已解码。
//  但全 App 的 ViewModel 统一把错误存成 `error.localizedDescription` 字符串交给视图，
//  URL 在这一步就丢了。为了不改几十个 ViewModel 的 error 类型，这里在 APIError 生成
//  展示文案（errorDescription）时顺手记下「文案 → 文档地址」，视图拿着同一段文案反查，
//  查到就在错误弹窗里加一个「查看所需权限」按钮（见 apiErrorDocButton）。
//
//  只收 https 且主机在 cloudflare.com 之下的地址：链接来自 API 响应，不放行任意 scheme。
//

import Foundation

nonisolated enum APIErrorDocLinks {

    private static let lock = NSLock()
    /// 文案 → 文档地址。条目极少（只有带 documentation_url 的错误才进来），封顶防无限增长。
    nonisolated(unsafe) private static var links: [String: URL] = [:]
    private static let capacity = 64

    /// APIError 生成展示文案时调用
    static func record(message: String, documentationURL raw: String?) {
        guard let raw, let url = URL(string: raw), isTrusted(url), !message.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if links.count >= capacity { links.removeAll() }
        links[message] = url
    }

    /// 视图展示的错误文案对应的文档地址。文案可能被调用方加了前后缀（如 D1 额度提示），
    /// 精确匹配不到时再按「包含原始文案」兜底。
    static func url(for displayed: String?) -> URL? {
        guard let displayed, !displayed.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let exact = links[displayed] { return exact }
        return links.first { displayed.contains($0.key) }?.value
    }

    private static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "cloudflare.com" || host.hasSuffix(".cloudflare.com")
    }
}
