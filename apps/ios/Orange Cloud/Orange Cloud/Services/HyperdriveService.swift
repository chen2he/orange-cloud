//
//  HyperdriveService.swift
//  Orange Cloud
//
//  Cloudflare Hyperdrive（account 级）。读 query-cache.read，写 query-cache.write。
//

import Foundation

struct HyperdriveService {

    private let client: CFAPIClient

    init(client: CFAPIClient) { self.client = client }

    /// 端点默认 per_page=20（上限 100）：不带参数第 21 个配置起就看不见
    func list(accountId: String) async throws -> [HyperdriveConfig] {
        var all: [HyperdriveConfig] = []
        var page = 1
        while page <= 20 {
            let response: CFAPIResponseArray<HyperdriveConfig> = try await client.get(
                "accounts/\(accountId)/hyperdrive/configs",
                queryItems: [
                    URLQueryItem(name: "page",     value: String(page)),
                    URLQueryItem(name: "per_page", value: "100"),
                ]
            )
            guard response.success else { throw response.toAPIError() }
            all.append(contentsOf: response.result ?? [])
            guard page < (response.resultInfo?.totalPages ?? 1) else { break }
            page += 1
        }
        return all
    }

    func create(accountId: String, body: HyperdriveCreate) async throws -> HyperdriveConfig {
        let response: CFAPIResponse<HyperdriveConfig> = try await client.post(
            "accounts/\(accountId)/hyperdrive/configs", body: body
        )
        guard response.success, let config = response.result else { throw response.toAPIError() }
        return config
    }

    /// 改名 / 改缓存设置 / 改源连接。PATCH 全字段可选，omit 即不改。
    func update(accountId: String, configId: String, body: HyperdrivePatch) async throws -> HyperdriveConfig {
        let response: CFAPIResponse<HyperdriveConfig> = try await client.patch(
            "accounts/\(accountId)/hyperdrive/configs/\(configId)", body: body
        )
        guard response.success, let config = response.result else { throw response.toAPIError() }
        return config
    }

    func delete(accountId: String, configId: String) async throws {
        try await client.delete("accounts/\(accountId)/hyperdrive/configs/\(configId)")
    }
}
