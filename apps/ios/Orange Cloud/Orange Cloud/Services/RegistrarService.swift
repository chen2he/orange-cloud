//
//  RegistrarService.swift
//  Orange Cloud
//
//  Cloudflare Registrar（registrar-domains.read / .admin）。
//  用新版 /registrar/registrations —— 旧的 /registrar/domains 于 2026-09-27 停用。
//

import Foundation

struct RegistrarService {

    private let client: CFAPIClient

    init(client: CFAPIClient) {
        self.client = client
    }

    /// 账号下已注册域名。该端点是**游标分页**（不是页码），cursor 为空串即到底。
    func registrations(accountId: String) async throws -> [DomainRegistration] {
        var all: [DomainRegistration] = []
        var cursor: String?
        // 兜底上限，防止服务端游标异常导致死循环
        for _ in 0..<20 {
            var items = [URLQueryItem(name: "per_page", value: "50")]
            if let cursor, !cursor.isEmpty {
                items.append(URLQueryItem(name: "cursor", value: cursor))
            }
            let response: CFAPIResponseArray<DomainRegistration> = try await client.get(
                "accounts/\(accountId)/registrar/registrations",
                queryItems: items
            )
            guard response.success else {
                throw response.toAPIError()
            }
            all.append(contentsOf: response.result ?? [])
            cursor = response.resultInfo?.cursor
            guard let cursor, !cursor.isEmpty else { break }
        }
        return all
    }

    /// 设置自动续费。返回的是异步 workflow 状态，调用方成功后应回读列表。
    func setAutoRenew(accountId: String, domainName: String, enabled: Bool) async throws {
        let response: CFAPIResponse<RegistrarWorkflowStatus> = try await client.patch(
            "accounts/\(accountId)/registrar/registrations/\(domainName)",
            body: RegistrationUpdate(autoRenew: enabled)
        )
        guard response.success else {
            throw response.toAPIError()
        }
    }
}

// MARK: - 搜索新域名（只查不买：注册必须去 Cloudflare 控制台）

extension RegistrarService {

    /// 关键词搜索候选域名（结果可能有延迟，点开后再用 check 实时确认）
    func searchDomains(accountId: String, query: String, limit: Int = 20) async throws -> [DomainAvailability] {
        let response: CFAPIResponse<DomainSearchResponse> = try await client.get(
            "accounts/\(accountId)/registrar/domain-search",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
        guard response.success else {
            throw response.toAPIError()
        }
        return response.result?.domains ?? []
    }

    /// 向注册局实时确认（单次 ≤ 20 个）
    func checkDomains(accountId: String, names: [String]) async throws -> [DomainAvailability] {
        let response: CFAPIResponse<DomainSearchResponse> = try await client.post(
            "accounts/\(accountId)/registrar/domain-check",
            body: DomainCheckRequest(domains: Array(names.prefix(20)))
        )
        guard response.success else {
            throw response.toAPIError()
        }
        return response.result?.domains ?? []
    }
}

/// PATCH 的异步 workflow 结果，只取判定是否完成所需的字段
nonisolated struct RegistrarWorkflowStatus: Codable, Sendable {
    let completed: Bool?
    let state:     String?
}
