//
//  EmailRoutingService.swift
//  Orange Cloud
//
//  Email Routing：域名级设置/规则（email-routing-rule.*）+ 账号级目的地址（email-routing-address.*）。
//

import Foundation

struct EmailRoutingService {

    private let client: CFAPIClient

    init(client: CFAPIClient) {
        self.client = client
    }

    // MARK: - 设置（域名级）

    /// 读 Email Routing 总设置（开关 + 状态）
    func settings(zoneId: String) async throws -> EmailRoutingSettings {
        let response: CFAPIResponse<EmailRoutingSettings> = try await client.get(
            "zones/\(zoneId)/email/routing"
        )
        guard response.success, let result = response.result else {
            throw response.toAPIError()
        }
        return result
    }

    /// 开启 / 关闭 Email Routing（空 body POST 到 enable/disable）
    func setEnabled(zoneId: String, enabled: Bool) async throws {
        let action = enabled ? "enable" : "disable"
        let response: CFAPIResponse<EmailRoutingSettings> = try await client.post(
            "zones/\(zoneId)/email/routing/\(action)",
            body: [String: String]()
        )
        guard response.success else {
            throw response.toAPIError()
        }
    }

    // MARK: - 规则（域名级）

    /// 列出路由规则（不含 catch-all）。端点默认 per_page=20（上限 50），不翻页第 21 条起就看不见。
    func rules(zoneId: String) async throws -> [EmailRoutingRule] {
        try await allPages { page in
            try await client.get(
                "zones/\(zoneId)/email/routing/rules",
                queryItems: [
                    URLQueryItem(name: "page",     value: String(page)),
                    URLQueryItem(name: "per_page", value: "50"),
                ]
            )
        }
    }

    /// 页码分页取全量（上限 20 页兜底，防服务端 total_pages 异常死循环）
    private func allPages<T: Codable & Sendable>(
        _ fetch: (Int) async throws -> CFAPIResponseArray<T>
    ) async throws -> [T] {
        var all: [T] = []
        var page = 1
        while page <= 20 {
            let response = try await fetch(page)
            guard response.success else { throw response.toAPIError() }
            all.append(contentsOf: response.result ?? [])
            let totalPages = response.resultInfo?.totalPages ?? 1
            guard page < totalPages else { break }
            page += 1
        }
        return all
    }

    /// 新建规则
    func createRule(zoneId: String, input: EmailRoutingRuleInput) async throws -> EmailRoutingRule {
        let response: CFAPIResponse<EmailRoutingRule> = try await client.post(
            "zones/\(zoneId)/email/routing/rules",
            body: input
        )
        guard response.success, let result = response.result else {
            throw response.toAPIError()
        }
        return result
    }

    /// 全量更新规则（PUT 需带完整 matchers/actions）
    func updateRule(zoneId: String, ruleId: String, input: EmailRoutingRuleInput) async throws -> EmailRoutingRule {
        let response: CFAPIResponse<EmailRoutingRule> = try await client.put(
            "zones/\(zoneId)/email/routing/rules/\(ruleId)",
            body: input
        )
        guard response.success, let result = response.result else {
            throw response.toAPIError()
        }
        return result
    }

    /// 删除规则
    func deleteRule(zoneId: String, ruleId: String) async throws {
        try await client.delete("zones/\(zoneId)/email/routing/rules/\(ruleId)")
    }

    // MARK: - 目的地址（账号级）

    /// 列出账号下全部目的地址（含未验证）。
    /// OpenAPI 规范里 `verified` 查询参数默认 true（只回已验证），而 UI 有专门的「待验证」态，
    /// 刚添加的地址必须能出现——所以已验证 / 未验证各拉一遍再合并；分页同 rules（默认 20 条）。
    func addresses(accountId: String) async throws -> [EmailDestinationAddress] {
        var merged: [EmailDestinationAddress] = []
        var seen = Set<String>()
        for verified in ["true", "false"] {
            let items: [EmailDestinationAddress] = try await allPages { page in
                try await client.get(
                    "accounts/\(accountId)/email/routing/addresses",
                    queryItems: [
                        URLQueryItem(name: "page",     value: String(page)),
                        URLQueryItem(name: "per_page", value: "50"),
                        URLQueryItem(name: "verified", value: verified),
                    ]
                )
            }
            for item in items where seen.insert(item.id).inserted {
                merged.append(item)
            }
        }
        return merged
    }

    /// 新增目的地址（提交后 Cloudflare 向该邮箱发验证信）
    func createAddress(accountId: String, email: String) async throws -> EmailDestinationAddress {
        let response: CFAPIResponse<EmailDestinationAddress> = try await client.post(
            "accounts/\(accountId)/email/routing/addresses",
            body: EmailDestinationCreate(email: email)
        )
        guard response.success, let result = response.result else {
            throw response.toAPIError()
        }
        return result
    }

    /// 删除目的地址
    func deleteAddress(accountId: String, addressId: String) async throws {
        try await client.delete("accounts/\(accountId)/email/routing/addresses/\(addressId)")
    }

    // MARK: - 抑制列表（email-routing-suppression.read / .write）

    /// 被抑制的收件地址。⚠️ 该端点 2xx 时**不走 CF 标准信封**：顶层是 { page, per_page, total, result }
    /// 没有 success/errors（OpenAPI 规范如此，Sentry APPLE-IOS-AB 坐实），只能按专用页结构解。
    func suppressions(zoneId: String) async throws -> [EmailSuppression] {
        let page: EmailSuppressionPage = try await client.get(
            "zones/\(zoneId)/email/routing/suppression",
            queryItems: [URLQueryItem(name: "per_page", value: "100")]
        )
        return page.result ?? []
    }

    /// 手动抑制一个地址（此后不再向它转发）
    func addSuppression(zoneId: String, email: String) async throws {
        let response: CFAPIResponse<EmailSuppression> = try await client.post(
            "zones/\(zoneId)/email/routing/suppression",
            body: EmailSuppressionCreate(email: email)
        )
        guard response.success else {
            throw response.toAPIError()
        }
    }

    /// 解除抑制
    func deleteSuppression(zoneId: String, id: String) async throws {
        try await client.delete("zones/\(zoneId)/email/routing/suppression/\(id)")
    }

}
