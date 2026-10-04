//
//  R2FileProviderClient.swift
//  Orange Cloud File
//
//  Extension 自包含的 R2 网络客户端：从共享 Keychain 读 OAuth token（按 sessionId）、
//  必要时自刷新（与主 App AuthManager 同口径，写回同一 Keychain 条目），再调 client/v4
//  的 R2 对象端点（列举 / 下载 / 上传 / 删除）。
//
//  刻意不依赖主 App 的 TokenStore/OAuthConfig/CFAPIClient——extension 是独立进程，
//  保持零跨 target 文件依赖，靠 folder-sync 单独编译。Keychain 的 service/account/access-group
//  与 StoredToken 的 JSON 形态必须与主 App TokenStore 完全一致，否则读不到 token。
//

import Foundation
import Security
import UniformTypeIdentifiers

actor R2FileProviderClient {

    // MARK: - 配置常量（须与主 App 对齐）

    /// client/v4 单次 PUT 上限（~300MB）。无 multipart、无服务端 copy，超限只能拒。
    static let maxUploadBytes = 300 * 1024 * 1024

    private static let keychainService = "app.orangecloud.oauth"
    private static let keychainAccessGroup = "6G78MMY657.jiamin.chen.orange-cloud.shared"
    private static let oauthClientID = "102240eb9095a1965ee11813ef4788cd"
    private static let oauthTokenURL = URL(string: "https://dash.cloudflare.com/oauth2/token")!
    private let apiBase = URL(string: "https://api.cloudflare.com/client/v4")!

    // MARK: - 凭证来源

    struct Credentials: Sendable {
        let sessionId: UUID
        let accountId: String
        let bucketName: String
        /// 区域限制桶的辖区（eu / us / fedramp…）；默认辖区为 nil。非空时每个桶级请求都带
        /// cf-r2-jurisdiction 头，否则 R2 按默认辖区找桶、一律 404。
        let jurisdiction: String?
    }

    let credentials: Credentials
    private let urlSession = URLSession(configuration: .default)
    private var refreshTask: Task<String, Error>?

    init(credentials: Credentials) {
        self.credentials = credentials
    }

    // MARK: - 对外模型

    struct R2Obj: Sendable {
        let key: String
        let size: Int?
        let etag: String?
        let lastModified: Date?
        let contentType: String?
    }

    struct ListResult: Sendable {
        let folders: [String]   // 折叠前缀（子文件夹）
        let files: [R2Obj]
        let nextCursor: String?
    }

    enum ClientError: Error {
        case notAuthenticated
        case tooLarge
        case http(Int)
        case badResponse
    }

    // MARK: - 列举（delimiter=/ 折叠子前缀）

    func list(prefix: String, cursor: String?) async throws -> ListResult {
        var items = [
            URLQueryItem(name: "per_page", value: "1000"),
            URLQueryItem(name: "delimiter", value: "/"),
        ]
        if !prefix.isEmpty { items.append(URLQueryItem(name: "prefix", value: prefix)) }
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }

        let data = try await send(method: "GET", path: objectsBase, query: items, body: nil, contentType: nil)
        let decoded = try JSONDecoder().decode(ListEnvelope.self, from: data)
        let folders = (decoded.result_info?.delimited ?? []).filter { $0 != prefix }
        let files = (decoded.result ?? [])
            .filter { !$0.key.hasSuffix("/") && $0.key != prefix }   // 跳过文件夹占位对象
            .map(Self.makeObj)
        let next = (decoded.result_info?.is_truncated == true) ? decoded.result_info?.cursor : nil
        return ListResult(folders: folders, files: files, nextCursor: next)
    }

    /// 精确取单个 key 的元数据（client/v4 无 HEAD，用 prefix 列举核对）
    func head(key: String) async throws -> R2Obj? {
        let items = [
            URLQueryItem(name: "per_page", value: "1000"),
            URLQueryItem(name: "prefix", value: key),
        ]
        let data = try await send(method: "GET", path: objectsBase, query: items, body: nil, contentType: nil)
        let decoded = try JSONDecoder().decode(ListEnvelope.self, from: data)
        return (decoded.result ?? []).first { $0.key == key }.map(Self.makeObj)
    }

    // MARK: - 下载 / 上传 / 删除

    /// 流式下载到自管临时文件，返回 URL（调用方负责删除）
    func download(key: String) async throws -> URL {
        let request = try await buildRequest(method: "GET", path: objectPath(key), query: [], contentType: nil)
        let (tempURL, response) = try await urlSession.download(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.badResponse }
        if http.statusCode == 401 {
            try await forceRefresh()
            return try await download(key: key)
        }
        guard (200...299).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: tempURL)
            throw ClientError.http(http.statusCode)
        }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("oc-fp-\(UUID().uuidString)")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }

    /// 流式上传文件到 key。超过 300MB 抛 .tooLarge（API 无 multipart）。
    func put(key: String, fileURL: URL, contentType: String) async throws {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes?[.size] as? Int) ?? 0
        if size > Self.maxUploadBytes { throw ClientError.tooLarge }
        let request = try await buildRequest(method: "PUT", path: objectPath(key), query: [], contentType: contentType)
        let (_, response) = try await urlSession.upload(for: request, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse else { throw ClientError.badResponse }
        if http.statusCode == 401 {
            try await forceRefresh()
            return try await put(key: key, fileURL: fileURL, contentType: contentType)
        }
        guard (200...299).contains(http.statusCode) else { throw ClientError.http(http.statusCode) }
    }

    /// 写一个 0 字节的文件夹占位对象（key 以 / 结尾）
    func putFolderMarker(prefix: String) async throws {
        let request = try await buildRequest(method: "PUT", path: objectPath(prefix), query: [], contentType: "application/x-directory")
        let (_, response) = try await urlSession.upload(for: request, from: Data())
        guard let http = response as? HTTPURLResponse else { throw ClientError.badResponse }
        if http.statusCode == 401 { try await forceRefresh(); return try await putFolderMarker(prefix: prefix) }
        guard (200...299).contains(http.statusCode) else { throw ClientError.http(http.statusCode) }
    }

    func delete(key: String) async throws {
        let data = try await send(method: "DELETE", path: objectPath(key), query: [], body: Data(), contentType: nil)
        _ = data
    }

    /// 复制对象到新 key（过设备：下载到临时文件再上传；无服务端 copy）。超 300MB 由 put 拒。
    func copy(sourceKey: String, destinationKey: String) async throws {
        let tempURL = try await download(key: sourceKey)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let contentType = (try? await head(key: sourceKey))?.contentType
            ?? Self.mimeType(forKey: destinationKey)
        try await put(key: destinationKey, fileURL: tempURL, contentType: contentType)
    }

    /// 递归列出某前缀下全部对象（不折叠，含占位对象）。文件夹改名/移动需要遍历整子树。
    func listAll(prefix: String) async throws -> [(key: String, size: Int)] {
        var out: [(String, Int)] = []
        var cursor: String?
        repeat {
            var items = [URLQueryItem(name: "per_page", value: "1000")]
            if !prefix.isEmpty { items.append(URLQueryItem(name: "prefix", value: prefix)) }
            if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
            let data = try await send(method: "GET", path: objectsBase, query: items, body: nil, contentType: nil)
            let decoded = try JSONDecoder().decode(ListEnvelope.self, from: data)
            for obj in decoded.result ?? [] {
                out.append((obj.key, obj.size ?? 0))
            }
            cursor = (decoded.result_info?.is_truncated == true) ? decoded.result_info?.cursor : nil
        } while cursor != nil
        return out
    }

    private static func mimeType(forKey key: String) -> String {
        let ext = (key as NSString).pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    /// 递归删除某前缀下所有对象（含占位对象本身）
    func deletePrefix(_ prefix: String) async throws {
        var cursor: String?
        repeat {
            var items = [URLQueryItem(name: "per_page", value: "1000")]
            if !prefix.isEmpty { items.append(URLQueryItem(name: "prefix", value: prefix)) }
            if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
            let data = try await send(method: "GET", path: objectsBase, query: items, body: nil, contentType: nil)
            let decoded = try JSONDecoder().decode(ListEnvelope.self, from: data)
            for obj in decoded.result ?? [] {
                try? await delete(key: obj.key)
            }
            cursor = (decoded.result_info?.is_truncated == true) ? decoded.result_info?.cursor : nil
        } while cursor != nil
        try? await delete(key: prefix)   // 兜底删占位对象
    }

    // MARK: - 请求底座

    private var objectsBase: String {
        "accounts/\(credentials.accountId)/r2/buckets/\(credentials.bucketName)/objects"
    }

    private func objectPath(_ key: String) -> String {
        "\(objectsBase)/\(Self.encodeKey(key))"
    }

    /// R2 key 含 / 空格等任意字符，必须显式百分号编码（路径视为已编码）
    private static func encodeKey(_ key: String) -> String {
        key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
    }

    /// 通用 JSON/字节请求（GET/DELETE 等），自带 401 重试
    private func send(method: String, path: String, query: [URLQueryItem], body: Data?, contentType: String?) async throws -> Data {
        let request = try await buildRequest(method: method, path: path, query: query, contentType: contentType, body: body)
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.badResponse }
        if http.statusCode == 401 {
            try await forceRefresh()
            return try await send(method: method, path: path, query: query, body: body, contentType: contentType)
        }
        guard (200...299).contains(http.statusCode) else { throw ClientError.http(http.statusCode) }
        return data
    }

    private func buildRequest(method: String, path: String, query: [URLQueryItem], contentType: String?, body: Data? = nil) async throws -> URLRequest {
        // path 里 key 段已百分号编码，appendingPathComponent 会二次编码 %，故用 percentEncodedPath 直拼
        var comps = URLComponents()
        comps.scheme = apiBase.scheme
        comps.host = apiBase.host
        comps.percentEncodedPath = "/client/v4/" + path
        if !query.isEmpty { comps.queryItems = query }
        guard let finalURL = comps.url else { throw ClientError.badResponse }

        var request = URLRequest(url: finalURL)
        request.httpMethod = method
        let token = try await validAccessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let jurisdiction = credentials.jurisdiction {
            request.setValue(jurisdiction, forHTTPHeaderField: "cf-r2-jurisdiction")
        }
        if let body { request.httpBody = body }
        return request
    }

    // MARK: - Token（共享 Keychain 读 + 自刷新）

    private func validAccessToken() async throws -> String {
        guard let stored = loadToken() else { throw ClientError.notAuthenticated }
        if stored.expiresAt.timeIntervalSinceNow > 60 { return stored.accessToken }
        return try await refresh(stored: stored)
    }

    private func forceRefresh() async throws {
        guard let stored = loadToken() else { throw ClientError.notAuthenticated }
        _ = try await refresh(stored: stored)
    }

    private func refresh(stored: StoredToken) async throws -> String {
        if let task = refreshTask { return try await task.value }
        let sessionId = credentials.sessionId.uuidString
        let task = Task<String, Error> {
            // 跨进程独占锁：避免与主 App 并发刷新同一个轮转 refresh token——Cloudflare 单次有效令牌
            // 被两进程同时用会触发复用检测吊销整条令牌链，主 App 随后卡死登录态。best-effort，拿不到也照常刷。
            let lock = await RefreshGate.acquire(sessionId: sessionId)
            defer { RefreshGate.release(lock) }

            // 等锁期间主 App 可能已把令牌轮换掉：重读共享钥匙串，用最新一份去刷新
            // （而非调用时手里那份陈旧令牌），避免拿旧令牌刷新触发复用检测。
            let current = loadToken() ?? stored
            guard let refreshToken = current.refreshToken else { throw ClientError.notAuthenticated }

            var request = URLRequest(url: Self.oauthTokenURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formBody([
                "grant_type": "refresh_token",
                "client_id": Self.oauthClientID,
                "refresh_token": refreshToken,
            ])
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw ClientError.notAuthenticated
            }
            let tr = try JSONDecoder().decode(TokenResponse.self, from: data)
            let newToken = StoredToken(
                accessToken: tr.access_token,
                refreshToken: tr.refresh_token ?? refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(tr.expires_in)),
                scope: tr.scope ?? current.scope
            )
            saveToken(newToken)
            return newToken.accessToken
        }
        refreshTask = task
        do {
            let value = try await task.value
            refreshTask = nil
            return value
        } catch {
            refreshTask = nil
            throw error
        }
    }

    private static func formBody(_ params: [String: String]) -> Data {
        params.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&").data(using: .utf8) ?? Data()
    }

    // MARK: - Keychain（与主 App TokenStore 完全同口径）

    private struct StoredToken: Codable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date
        var scope: String
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
        let scope: String?
    }

    private func loadToken() -> StoredToken? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: credentials.sessionId.uuidString,
            kSecAttrAccessGroup as String: Self.keychainAccessGroup,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &item)
        if status != errSecSuccess {
            // 回退：无 access-group 限定再试一次（容错 entitlement 差异）
            query.removeValue(forKey: kSecAttrAccessGroup as String)
            status = SecItemCopyMatching(query as CFDictionary, &item)
        }
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(StoredToken.self, from: data)
    }

    private func saveToken(_ token: StoredToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: credentials.sessionId.uuidString,
        ]
        var deleteQuery = base
        deleteQuery[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(deleteQuery as CFDictionary)

        var addQuery = base
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        addQuery[kSecAttrSynchronizable as String] = false
        addQuery[kSecAttrAccessGroup as String] = Self.keychainAccessGroup
        if SecItemAdd(addQuery as CFDictionary, nil) != errSecSuccess {
            addQuery.removeValue(forKey: kSecAttrAccessGroup as String)
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    // MARK: - 解码辅助

    private struct ListEnvelope: Decodable {
        let result: [ObjectDTO]?
        let result_info: Info?
        struct Info: Decodable {
            let cursor: String?
            let is_truncated: Bool?
            let delimited: [String]?
        }
    }

    private struct ObjectDTO: Decodable {
        let key: String
        let size: Int?
        let etag: String?
        let last_modified: String?
        let http_metadata: HTTPMeta?
        struct HTTPMeta: Decodable { let contentType: String? }
    }

    private static func makeObj(_ dto: ObjectDTO) -> R2Obj {
        R2Obj(
            key: dto.key,
            size: dto.size,
            etag: dto.etag,
            lastModified: dto.last_modified.flatMap { isoFormatter.date(from: $0) },
            contentType: dto.http_metadata?.contentType
        )
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

private extension CharacterSet {
    /// x-www-form-urlencoded value 允许集（保守：仅字母数字与少量安全符号）
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
