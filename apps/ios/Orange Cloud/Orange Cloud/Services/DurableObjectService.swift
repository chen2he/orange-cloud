//
//  DurableObjectService.swift
//  Orange Cloud
//
//  Durable Objects（account 级，只读）。命名空间由 Worker 迁移定义，API 无创建/删除，
//  仅列出。沿用 workers-scripts.read（与 Workers 同权限组）。
//

import Foundation

struct DurableObjectService {

    private let client: CFAPIClient

    init(client: CFAPIClient) { self.client = client }

    /// 端点默认 per_page=20（上限 1000）：不带参数第 21 个命名空间起就看不见
    func listNamespaces(accountId: String) async throws -> [DurableObjectNamespace] {
        var all: [DurableObjectNamespace] = []
        var page = 1
        while page <= 20 {
            let response: CFAPIResponseArray<DurableObjectNamespace> = try await client.get(
                "accounts/\(accountId)/workers/durable_objects/namespaces",
                queryItems: [
                    URLQueryItem(name: "page",     value: String(page)),
                    URLQueryItem(name: "per_page", value: "1000"),
                ]
            )
            guard response.success else { throw response.toAPIError() }
            all.append(contentsOf: response.result ?? [])
            guard page < (response.resultInfo?.totalPages ?? 1) else { break }
            page += 1
        }
        return all
    }

    /// 命名空间内的对象实例（只读，游标分页）。返回 (本页对象, 下一页游标)；游标为空即无更多。
    func listObjects(
        accountId: String, namespaceId: String, cursor: String? = nil, limit: Int = 100
    ) async throws -> (items: [DurableObjectInstance], cursor: String?) {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor, !cursor.isEmpty { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let response: CFAPIResponseArray<DurableObjectInstance> = try await client.get(
            "accounts/\(accountId)/workers/durable_objects/namespaces/\(namespaceId)/objects",
            queryItems: query
        )
        guard response.success else { throw response.toAPIError() }
        let next = response.resultInfo?.cursor
        return (response.result ?? [], (next?.isEmpty == false) ? next : nil)
    }
    // MARK: - 内存用量（GraphQL）

    /// 某 namespace 过去 24h 的 isolate 内存分位数。
    ///
    /// 走账户级 GraphQL —— 免费账号常被 authz 挡（与账号用量同一条链路），
    /// 故调用方应把失败当成「不可用」静默处理，不要弹错。
    func memoryUsage(accountId: String, namespaceId: String) async throws -> DurableObjectMemory? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let now = Date()
        let data: DOMemoryData = try await client.graphQL(
            query: DOMemoryQuery.text,
            variables: DOMemoryVariables(
                accountTag: accountId,
                namespaceId: namespaceId,
                since: formatter.string(from: now.addingTimeInterval(-86400)),
                until: formatter.string(from: now)
            )
        )
        guard let q = data.viewer.accounts.first?.periodic?.first?.quantiles,
              let p50 = q.p50, let p90 = q.p90, let p99 = q.p99, let p999 = q.p999 else {
            return nil
        }
        return DurableObjectMemory(p50: p50, p90: p90, p99: p99, p999: p999)
    }

}
