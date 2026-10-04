//
//  KVService.swift
//  Orange Cloud
//
//  Workers KV：namespace 列表、键列表（游标分页）、值读写删。
//  注意：值端点返回原始字节（非 JSON 信封），key 需手动百分号编码后拼路径。
//

import Foundation

struct KVService {

    private let client: CFAPIClient

    init(client: CFAPIClient) {
        self.client = client
    }

    /// Namespace 列表（页码分页）
    func listNamespaces(accountId: String) async throws -> [KVNamespace] {
        var namespaces: [KVNamespace] = []
        var page = 1
        while true {
            let response: CFAPIResponseArray<KVNamespace> = try await client.get(
                "accounts/\(accountId)/storage/kv/namespaces",
                queryItems: [
                    URLQueryItem(name: "page",     value: String(page)),
                    URLQueryItem(name: "per_page", value: "100"),
                ]
            )
            guard response.success else {
                throw response.toAPIError()
            }
            namespaces.append(contentsOf: response.result ?? [])
            let totalPages = response.resultInfo?.totalPages ?? 1
            guard page < totalPages else { break }
            page += 1
        }
        return namespaces
    }

    /// 键列表（游标分页，一次一页）
    func listKeys(
        accountId: String,
        namespaceId: String,
        cursor: String? = nil
    ) async throws -> (keys: [KVKey], nextCursor: String?) {
        var queryItems = [URLQueryItem(name: "limit", value: "100")]
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let response: CFAPIResponseArray<KVKey> = try await client.get(
            "accounts/\(accountId)/storage/kv/namespaces/\(namespaceId)/keys",
            queryItems: queryItems
        )
        guard response.success else {
            throw response.toAPIError()
        }
        // cursor 为空字符串表示已到末尾
        let next = response.resultInfo?.cursor.flatMap { $0.isEmpty ? nil : $0 }
        return (response.result ?? [], next)
    }

    /// 创建命名空间（workers-kv-storage.write）。POST 返回新建的 KVNamespace。
    func createNamespace(accountId: String, title: String, jurisdiction: String? = nil) async throws -> KVNamespace {
        // jurisdiction：数据驻留（eu / us），nil = 不限（字段省略）
        let response: CFAPIResponse<KVNamespace> = try await client.post(
            "accounts/\(accountId)/storage/kv/namespaces",
            body: KVCreateRequest(title: title, jurisdiction: jurisdiction)
        )
        guard response.success, let namespace = response.result else {
            throw response.toAPIError()
        }
        return namespace
    }

    /// 删除命名空间（workers-kv-storage.write）。连同全部键值，不可恢复。
    func deleteNamespace(accountId: String, namespaceId: String) async throws {
        try await client.delete("accounts/\(accountId)/storage/kv/namespaces/\(namespaceId)")
    }

    /// 读取值（原始字节，调用方决定如何展示）
    func getValue(accountId: String, namespaceId: String, key: String) async throws -> Data {
        try await client.getRaw(
            "accounts/\(accountId)/storage/kv/namespaces/\(namespaceId)/values/\(encodeKey(key))"
        )
    }

    /// 写入文本值（multipart：value + metadata 两个 part 均必填）
    func putValue(accountId: String, namespaceId: String, key: String, value: String) async throws {
        let response: CFAPIResponse<EmptyResponse> = try await client.putMultipart(
            "accounts/\(accountId)/storage/kv/namespaces/\(namespaceId)/values/\(encodeKey(key))",
            fields: ["value": value, "metadata": "{}"]
        )
        guard response.success else {
            throw response.toAPIError()
        }
    }

    /// 删除键
    func deleteKey(accountId: String, namespaceId: String, key: String) async throws {
        try await client.delete(
            "accounts/\(accountId)/storage/kv/namespaces/\(namespaceId)/values/\(encodeKey(key))"
        )
    }

    /// KV key 可包含任意字符（含 / 和空格），必须显式编码
    private func encodeKey(_ key: String) -> String {
        key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
    }
}
