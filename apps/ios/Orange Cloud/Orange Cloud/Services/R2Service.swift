//
//  R2Service.swift
//  Orange Cloud
//

import Foundation

struct R2Service {

    private let client: CFAPIClient

    init(client: CFAPIClient) {
        self.client = client
    }

    /// Bucket 列表（result 是 { buckets: [...] } 包装）。端点是游标分页：以前只取一页 100 个，
    /// 桶多的账号后面的桶在 App / Files.app 里根本不可达。
    func listBuckets(accountId: String) async throws -> [R2Bucket] {
        var all: [R2Bucket] = []
        var cursor: String?
        for _ in 0..<20 {
            var items = [URLQueryItem(name: "per_page", value: "100")]
            if let cursor, !cursor.isEmpty {
                items.append(URLQueryItem(name: "cursor", value: cursor))
            }
            let response: CFAPIResponse<R2BucketList> = try await client.get(
                "accounts/\(accountId)/r2/buckets",
                queryItems: items
            )
            guard response.success, let list = response.result else {
                throw response.toAPIError()
            }
            all.append(contentsOf: list.buckets)
            cursor = response.resultInfo?.cursor
            guard let cursor, !cursor.isEmpty, !list.buckets.isEmpty else { break }
        }
        return all
    }

    /// 创建桶（workers-r2.write）。locationHint 为空走自动放置，storageClass 为空默认 Standard。
    func createBucket(
        accountId: String,
        name: String,
        locationHint: String? = nil,
        storageClass: String? = nil
    ) async throws -> R2Bucket {
        let response: CFAPIResponse<R2Bucket> = try await client.post(
            "accounts/\(accountId)/r2/buckets",
            body: R2CreateRequest(name: name, locationHint: locationHint, storageClass: storageClass)
        )
        guard response.success, let bucket = response.result else {
            throw response.toAPIError()
        }
        return bucket
    }

    /// 删除桶（workers-r2.write）。Cloudflare 要求桶必须为空，否则报错。
    func deleteBucket(accountId: String, name: String) async throws {
        try await client.delete("accounts/\(accountId)/r2/buckets/\(name)")
    }

    /// 下载对象内容（原始字节）。key 含特殊字符需预编码。
    func getObjectData(accountId: String, bucketName: String, key: String) async throws -> Data {
        try await client.getRaw(
            "accounts/\(accountId)/r2/buckets/\(bucketName)/objects/\(Self.encodeKey(key))"
        )
    }

    /// 上传对象（原始字节 + Content-Type）
    func putObject(
        accountId: String,
        bucketName: String,
        key: String,
        data: Data,
        contentType: String
    ) async throws {
        let response: CFAPIResponse<EmptyResponse> = try await client.putRaw(
            "accounts/\(accountId)/r2/buckets/\(bucketName)/objects/\(Self.encodeKey(key))",
            body: data,
            contentType: contentType
        )
        guard response.success else {
            throw response.toAPIError()
        }
    }

    /// 删除对象
    func deleteObject(accountId: String, bucketName: String, key: String) async throws {
        try await client.delete(
            "accounts/\(accountId)/r2/buckets/\(bucketName)/objects/\(Self.encodeKey(key))"
        )
    }

    /// R2 key 可含 / 空格等任意字符，必须显式百分号编码（路径视为已编码）
    private nonisolated static func encodeKey(_ key: String) -> String {
        key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
    }

    /// 账号级存储指标（与 Dashboard 同源的当前快照，比 GraphQL 采样更准）
    func accountMetrics(accountId: String) async throws -> R2AccountMetrics {
        let response: CFAPIResponse<R2AccountMetrics> = try await client.get(
            "accounts/\(accountId)/r2/metrics"
        )
        guard response.success, let metrics = response.result else {
            throw response.toAPIError()
        }
        return metrics
    }

    /// 对象列表（游标分页，一次一页）。传 delimiter=/ 让服务端把子前缀折叠成「文件夹」，
    /// prefix 为当前所在文件夹；result_info.delimited 即子文件夹前缀列表。
    func listObjects(_ options: R2ObjectListOptions) async throws -> R2ObjectPage {
        var queryItems = [
            URLQueryItem(name: "per_page", value: "100"),
            URLQueryItem(name: "delimiter", value: "/"),
        ]
        if !options.prefix.isEmpty {
            queryItems.append(URLQueryItem(name: "prefix", value: options.prefix))
        }
        if let cursor = options.cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let response: CFAPIResponseArray<R2Object> = try await client.get(
            "accounts/\(options.accountId)/r2/buckets/\(options.bucketName)/objects",
            queryItems: queryItems
        )
        guard response.success else {
            throw response.toAPIError()
        }
        let isTruncated = response.resultInfo?.isTruncated ?? false
        return R2ObjectPage(
            objects: response.result ?? [],
            folderPrefixes: response.resultInfo?.delimited ?? [],
            nextCursor: isTruncated ? response.resultInfo?.cursor : nil
        )
    }

    // MARK: - 复制 / 移动（流式过临时文件；client/v4 无服务端 copy / multipart，只能过设备）

    /// client/v4 单次 PUT 上限（~300MB）。超过则无法在本 App 复制/上传——
    /// 该 REST API 不提供 multipart 上传，也没有服务端 copy（那些只在 S3 API，OAuth 拿不到 S3 凭证）。
    nonisolated static let maxUploadBytes = 300 * 1024 * 1024

    /// 流式复制对象到新 key（同桶）。onProgress 回报 0...1（下载腿 0→0.5，上传腿 0.5→1）。
    func copyObject(
        accountId: String,
        bucketName: String,
        sourceKey: String,
        destinationKey: String,
        contentType: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let base = "accounts/\(accountId)/r2/buckets/\(bucketName)/objects"
        let tempURL = try await client.downloadToFile("\(base)/\(Self.encodeKey(sourceKey))")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        onProgress(0.5)
        let response: CFAPIResponse<EmptyResponse> = try await client.putFile(
            "\(base)/\(Self.encodeKey(destinationKey))",
            fileURL: tempURL,
            contentType: contentType,
            onProgress: { onProgress(0.5 + $0 * 0.5) }
        )
        guard response.success else { throw response.toAPIError() }
    }

    /// 移动 = 复制 → 校验目标已写入 → 删源。校验不过绝不删源，避免半路失败丢数据。
    func moveObject(
        accountId: String,
        bucketName: String,
        sourceKey: String,
        destinationKey: String,
        contentType: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await copyObject(
            accountId: accountId, bucketName: bucketName,
            sourceKey: sourceKey, destinationKey: destinationKey,
            contentType: contentType, onProgress: onProgress
        )
        guard try await objectExists(accountId: accountId, bucketName: bucketName, key: destinationKey) else {
            throw APIError.cloudflareError(
                code: 0,
                message: String(localized: "复制后未在目标确认到对象，已保留原对象未删除")
            )
        }
        try await deleteObject(accountId: accountId, bucketName: bucketName, key: sourceKey)
    }

    /// 精确判断某 key 是否存在（client/v4 对象端点无 HEAD，用 prefix 列举核对）
    func objectExists(accountId: String, bucketName: String, key: String) async throws -> Bool {
        let page = try await listObjects(
            R2ObjectListOptions(accountId: accountId, bucketName: bucketName, prefix: key)
        )
        return page.objects.contains { $0.key == key }
    }

    // MARK: - 公开访问（r2.dev / 自定义域）与 CORS（桶设置）

    private func bucketPath(_ accountId: String, _ bucketName: String) -> String {
        "accounts/\(accountId)/r2/buckets/\(bucketName)"
    }

    /// 托管公开访问 URL（r2.dev）当前状态
    func managedDomain(accountId: String, bucketName: String) async throws -> R2ManagedDomain {
        let response: CFAPIResponse<R2ManagedDomain> = try await client.get(
            "\(bucketPath(accountId, bucketName))/domains/managed"
        )
        guard response.success, let domain = response.result else { throw response.toAPIError() }
        return domain
    }

    /// 启用 / 停用 r2.dev 公开访问
    func setManagedDomainEnabled(accountId: String, bucketName: String, enabled: Bool) async throws {
        let response: CFAPIResponse<EmptyResponse> = try await client.put(
            "\(bucketPath(accountId, bucketName))/domains/managed",
            body: R2ManagedDomainUpdate(enabled: enabled)
        )
        guard response.success else { throw response.toAPIError() }
    }

    /// 已连接的自定义域
    func customDomains(accountId: String, bucketName: String) async throws -> [R2CustomDomain] {
        let response: CFAPIResponse<R2CustomDomainList> = try await client.get(
            "\(bucketPath(accountId, bucketName))/domains/custom"
        )
        guard response.success, let list = response.result else { throw response.toAPIError() }
        return list.domains ?? []
    }

    /// 移除（断开）一个自定义域
    func removeCustomDomain(accountId: String, bucketName: String, domain: String) async throws {
        try await client.delete(
            "\(bucketPath(accountId, bucketName))/domains/custom/\(Self.encodeKey(domain))"
        )
    }

    /// 当前 CORS 策略（无策略时由调用方按空处理）
    func corsPolicy(accountId: String, bucketName: String) async throws -> R2CorsPolicy {
        let response: CFAPIResponse<R2CorsPolicy> = try await client.get(
            "\(bucketPath(accountId, bucketName))/cors"
        )
        guard response.success else { throw response.toAPIError() }
        return response.result ?? R2CorsPolicy(rules: nil)
    }

    /// 整体写入 CORS 策略（PUT 覆盖；R2 的 CORS 是整组替换）
    func putCorsPolicy(accountId: String, bucketName: String, policy: R2CorsPolicy) async throws {
        let response: CFAPIResponse<EmptyResponse> = try await client.put(
            "\(bucketPath(accountId, bucketName))/cors",
            body: policy
        )
        guard response.success else { throw response.toAPIError() }
    }

    /// 清除 CORS 策略
    func deleteCorsPolicy(accountId: String, bucketName: String) async throws {
        try await client.delete("\(bucketPath(accountId, bucketName))/cors")
    }
}
