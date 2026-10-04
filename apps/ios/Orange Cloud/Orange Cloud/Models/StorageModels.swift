//
//  StorageModels.swift
//  Orange Cloud
//
//  P2 存储模块：R2 / D1 / KV 的数据模型。
//

import Foundation

// MARK: - R2

/// GET /accounts/{id}/r2/buckets 的 result 是 { buckets: [...] }（注意不是数组）
nonisolated struct R2BucketList: Codable, Sendable {
    let buckets: [R2Bucket]
}

/// POST /accounts/{id}/r2/buckets 请求体。R2 端点字段为 camelCase（与多数 CF API 不同）。
/// locationHint 为空时编码器省略，由 Cloudflare 就近放置；storageClass 省略时默认 Standard。
/// 司法辖区（EU 等）走 cf-r2-jurisdiction 头，App 内新建不涉及（只建默认辖区桶）。
nonisolated struct R2CreateRequest: Codable, Sendable {
    let name:         String
    let locationHint: String?
    let storageClass: String?
}

/// 存储桶。区域限制桶（EU / US / FedRAMP）的名字只在辖区内唯一，且**每个**桶级 REST 调用
/// （桶本身、/objects、/cors、/domains/*、/lifecycle、/lock、/sippy）都必须带
/// `cf-r2-jurisdiction: <辖区>` 头，否则 404。jurisdiction 随桶一路传到每个桶级调用。
nonisolated struct R2Bucket: Codable, Identifiable, Hashable, Sendable {
    let name:         String
    let creationDate: String?
    let location:     String?
    let storageClass: String?
    /// default | eu | us | fedramp | fedramp-high（老响应 / 新建响应可能没有 → 默认辖区）
    let jurisdiction: String?

    /// 默认辖区沿用桶名（置顶等持久化标识不变）；区域限制桶加辖区前缀，避免与同名默认桶撞 id
    var id: String {
        jurisdictionHeader.map { "\($0)/\(name)" } ?? name
    }

    /// 需要随请求发送的 cf-r2-jurisdiction 头取值；默认辖区为 nil（不发头）
    var jurisdictionHeader: String? { Self.headerValue(for: jurisdiction) }

    /// 非默认辖区的徽章文案：欧盟 / 美国 / FedRAMP；未知辖区原样大写
    var jurisdictionBadge: String? {
        guard let value = jurisdictionHeader else { return nil }
        switch value {
        case "eu":                      return String(localized: "欧盟")
        case "us":                      return String(localized: "美国")
        case "fedramp", "fedramp-high": return "FedRAMP"
        default:                        return value.uppercased()
        }
    }

    /// 辖区归一：空 / default → nil，其余小写原样
    static func headerValue(for jurisdiction: String?) -> String? {
        guard let value = jurisdiction?.trimmingCharacters(in: .whitespaces).lowercased(),
              !value.isEmpty, value != "default" else { return nil }
        return value
    }

    /// 桶级请求附加头（默认辖区为空字典）
    static func headers(jurisdiction: String?) -> [String: String] {
        headerValue(for: jurisdiction).map { ["cf-r2-jurisdiction": $0] } ?? [:]
    }

    /// 按某辖区列出来的桶若响应没带 jurisdiction 字段，补上请求所用的辖区
    func assumingJurisdiction(_ fallback: String) -> R2Bucket {
        guard jurisdiction == nil else { return self }
        return R2Bucket(name: name, creationDate: creationDate, location: location,
                        storageClass: storageClass, jurisdiction: fallback)
    }

    enum CodingKeys: String, CodingKey {
        case name, location, jurisdiction
        case creationDate = "creation_date"
        case storageClass = "storage_class"
    }
}

/// 单桶用量聚合：本月操作（Class A/B）+ 当前存储/对象数快照。来自 GraphQL，缺失时全 0。
nonisolated struct R2BucketUsage: Sendable, Hashable {
    var classARequests = 0
    var classBRequests = 0
    var storageBytes   = 0
    var objectCount    = 0

    var totalRequests: Int { classARequests + classBRequests }
}

// MARK: - R2 公开访问 / CORS（桶设置，字段为 camelCase；读用可选字段宽容缺省）

/// 托管公开访问 URL（r2.dev）。GET/PUT .../domains/managed
nonisolated struct R2ManagedDomain: Codable, Sendable {
    let bucketId: String?
    let domain:   String?
    let enabled:  Bool?
}

nonisolated struct R2ManagedDomainUpdate: Codable, Sendable {
    let enabled: Bool
}

/// 自定义域列表。GET .../domains/custom
nonisolated struct R2CustomDomainList: Codable, Sendable {
    let domains: [R2CustomDomain]?
}

nonisolated struct R2CustomDomain: Codable, Sendable, Identifiable {
    let domain:  String
    let enabled: Bool?
    let status:  R2CustomDomainStatus?
    let minTLS:  String?

    var id: String { domain }
}

nonisolated struct R2CustomDomainStatus: Codable, Sendable {
    let ownership: String?
    let ssl:       String?
}

/// 桶 CORS 策略。GET/PUT/DELETE .../cors
nonisolated struct R2CorsPolicy: Codable, Sendable {
    let rules: [R2CorsRule]?
}

nonisolated struct R2CorsRule: Codable, Sendable {
    let id:            String?
    let allowed:       R2CorsAllowed?
    let exposeHeaders: [String]?
    let maxAgeSeconds: Int?
}

nonisolated struct R2CorsAllowed: Codable, Sendable {
    let methods: [String]?
    let origins: [String]?
    let headers: [String]?
}

nonisolated struct R2Object: Codable, Identifiable, Hashable, Sendable {
    let key:          String
    let etag:         String?
    let lastModified: String?
    let size:         Int?
    let httpMetadata: R2HTTPMetadata?
    let storageClass: String?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, etag, size
        case lastModified = "last_modified"
        case httpMetadata = "http_metadata"
        case storageClass = "storage_class"
    }
}

nonisolated struct R2HTTPMetadata: Codable, Hashable, Sendable {
    let contentType: String?

    enum CodingKeys: String, CodingKey {
        case contentType = "contentType"   // R2 对象元数据是 camelCase
    }
}

// MARK: - R2 文件夹浏览（list 用 delimiter=/ 让服务端折叠子前缀，免客户端逐对象分组）

nonisolated struct R2ObjectListOptions: Sendable {
    let accountId:    String
    let bucketName:   String
    /// 桶的辖区（区域限制桶必须带 cf-r2-jurisdiction 头）
    let jurisdiction: String?
    let prefix:       String
    let cursor:       String?

    init(accountId: String, bucketName: String, jurisdiction: String?, prefix: String = "", cursor: String? = nil) {
        self.accountId = accountId
        self.bucketName = bucketName
        self.jurisdiction = jurisdiction
        self.prefix = prefix
        self.cursor = cursor
    }
}

nonisolated struct R2ObjectPage: Sendable {
    let objects:        [R2Object]
    let folderPrefixes: [String]
    let nextCursor:     String?
}

/// 一个「文件夹」= 某个折叠前缀（prefix 形如 a/b/）。name 取相对当前层的末段。
nonisolated struct R2Folder: Identifiable, Hashable, Sendable {
    let prefix:       String
    let parentPrefix: String

    var id: String { prefix }
    var name: String { Self.displayName(prefix: prefix, parentPrefix: parentPrefix) }

    static func makeList(from prefixes: [String], parentPrefix: String) -> [R2Folder] {
        Array(Set(prefixes))
            .filter { $0 != parentPrefix }
            .sorted()
            .map { R2Folder(prefix: $0, parentPrefix: parentPrefix) }
    }

    /// 当前前缀的上一级（a/b/c/ → a/b/，a/ → 根 ""）
    static func parentPrefix(of prefix: String) -> String {
        let trimmed = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let lastSlash = trimmed.lastIndex(of: "/") else { return "" }
        return String(trimmed[..<trimmed.index(after: lastSlash)])
    }

    private static func displayName(prefix: String, parentPrefix: String) -> String {
        let relative = prefix.dropFirst(parentPrefix.count)
        let trimmed = String(relative).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.components(separatedBy: "/").last ?? trimmed
    }
}

// MARK: - R2 账号级指标（GET /accounts/{id}/r2/metrics，r2 read scope 即可）

nonisolated struct R2AccountMetrics: Codable, Sendable {
    let standard:         R2ClassMetrics?
    let infrequentAccess: R2ClassMetrics?

    /// 免费额度只计 Standard 存储
    var standardBytes: Int {
        (standard?.published?.totalBytes ?? 0) + (standard?.unpublished?.totalBytes ?? 0)
    }

    var standardObjects: Int {
        (standard?.published?.objects ?? 0) + (standard?.unpublished?.objects ?? 0)
    }
}

nonisolated struct R2ClassMetrics: Codable, Sendable {
    let published:   R2MetricsSnapshot?
    let unpublished: R2MetricsSnapshot?
}

nonisolated struct R2MetricsSnapshot: Codable, Sendable {
    let objects:      Int?
    let payloadSize:  Int?
    let metadataSize: Int?

    var totalBytes: Int { (payloadSize ?? 0) + (metadataSize ?? 0) }
}

// MARK: - D1

nonisolated struct D1Database: Codable, Identifiable, Hashable, Sendable {
    let uuid:      String
    let name:      String
    let version:   String?
    let createdAt: String?
    let fileSize:  Int?
    let numTables: Int?

    var id: String { uuid }

    enum CodingKeys: String, CodingKey {
        case uuid, name, version
        case createdAt = "created_at"
        case fileSize  = "file_size"
        case numTables = "num_tables"
    }
}

/// 2026-09-01 起免费套餐的 D1 每日读取 / 写入行数上限开始强制执行（含 SQL 控制台用的
/// REST POST /d1/database/{id}/query）。CF 的报错是英文原文，这里识别后在前面补一句中文说明，
/// 原文保留在后面（便于排查 / 搜索）。
nonisolated enum D1FreeTierLimit {

    /// 「daily」+「limit」或「free tier」（不区分大小写）
    static func matches(_ message: String) -> Bool {
        let lower = message.lowercased()
        return (lower.contains("daily") && lower.contains("limit")) || lower.contains("free tier")
    }

    /// D1 报错的展示文案：命中免费额度上限时加说明，否则原样
    static func message(for error: Error) -> String {
        annotate(error.localizedDescription)
    }

    static func annotate(_ raw: String) -> String {
        guard matches(raw) else { return raw }
        return String(localized: "已超过 D1 免费套餐的每日读取/写入行数上限，额度在 UTC 0 点重置；升级到 Workers 付费计划可提高上限。")
            + "\n\n" + raw
    }
}

nonisolated struct D1QueryRequest: Codable, Sendable {
    let sql:    String
    let params: [String]?    // 参数化查询（行编辑用，避免拼接注入）
}

/// POST /accounts/{id}/d1/database 的请求体。primaryLocationHint 为空时
/// 编码器自动省略该字段（Optional 走 encodeIfPresent），由 Cloudflare 就近放置。
nonisolated struct D1CreateRequest: Codable, Sendable {
    let name:                String
    let primaryLocationHint: String?

    enum CodingKeys: String, CodingKey {
        case name
        case primaryLocationHint = "primary_location_hint"
    }
}

/// PRAGMA table_info 解析后的列结构
nonisolated struct D1Column: Identifiable, Sendable {
    let name:         String
    let type:         String
    let isPrimaryKey: Bool

    var id: String { name }
}

/// POST /query 的 result 是 [D1QueryResult]（每条语句一个结果）
nonisolated struct D1QueryResult: Codable, Sendable {
    let results: [[String: JSONValue]]?
    let success: Bool
    let meta:    D1QueryMeta?
}

nonisolated struct D1QueryMeta: Codable, Sendable {
    let duration:    Double?
    let changes:     Int?
    let lastRowId:   Int?
    let rowsRead:    Int?
    let rowsWritten: Int?

    enum CodingKeys: String, CodingKey {
        case duration, changes
        case lastRowId   = "last_row_id"
        case rowsRead    = "rows_read"
        case rowsWritten = "rows_written"
    }
}

// MARK: - KV

nonisolated struct KVNamespace: Codable, Identifiable, Hashable, Sendable {
    let id:    String
    let title: String
}

/// POST /accounts/{id}/storage/kv/namespaces 请求体（仅 title）
nonisolated struct KVCreateRequest: Codable, Sendable {
    let title: String
}

nonisolated struct KVKey: Codable, Identifiable, Hashable, Sendable {
    let name:       String
    let expiration: Int?     // Unix 秒

    var id: String { name }

    var expirationDate: Date? {
        expiration.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}
