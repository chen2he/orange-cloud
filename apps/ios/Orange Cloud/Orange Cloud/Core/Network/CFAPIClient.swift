//
//  CFAPIClient.swift
//  Orange Cloud
//
//  所有 Cloudflare API 调用的统一入口：
//  自动注入 Bearer Token、过期前主动刷新、401 刷新后重试一次、统一错误解析。
//

import Foundation

actor CFAPIClient {

    private let baseURL = URL(string: "https://api.cloudflare.com/client/v4")!
    private let session = CFAPIClient.makeSession()
    private let authManager: AuthManager

    /// 平时就是 `URLSession.shared`。仅 DEBUG + ORANGE_MOCK=1 时换成带
    /// `protocolClasses` 的独立 session——`URLSession.shared` **不查**
    /// `URLProtocol.registerClass` 注册的拦截器，只有写进 configuration 的才生效，
    /// 否则 mock 只塞了假 token、请求照样打到真 api.cloudflare.com（返回 cf=6003）。
    private static func makeSession() -> URLSession {
        #if DEBUG
        if MockCloudflare.isRequested {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockCFURLProtocol.self]
            return URLSession(configuration: config)
        }
        #endif
        return URLSession.shared
    }

    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    // MARK: - 核心请求方法

    func get<T: Codable & Sendable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        try await request(method: "GET", path: path, queryItems: queryItems, body: nil)
    }

    func post<T: Codable & Sendable, B: Codable & Sendable>(_ path: String, body: B) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await request(method: "POST", path: path, queryItems: [], body: data)
    }

    func put<T: Codable & Sendable, B: Codable & Sendable>(_ path: String, body: B) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await request(method: "PUT", path: path, queryItems: [], body: data)
    }

    func patch<T: Codable & Sendable, B: Codable & Sendable>(_ path: String, body: B) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await request(method: "PATCH", path: path, queryItems: [], body: data)
    }

    func delete(_ path: String) async throws {
        let _: EmptyResponse = try await request(method: "DELETE", path: path, queryItems: [], body: nil)
    }

    /// 带 JSON 体的 DELETE（如 Rules List 批量删条目：{items:[{id}]}），返回解码结果
    func delete<T: Codable & Sendable, B: Codable & Sendable>(_ path: String, body: B) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await request(method: "DELETE", path: path, queryItems: [], body: data)
    }

    /// 返回原始响应体（KV value 等非 JSON 信封端点）
    func getRaw(_ path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        try await performRequest(method: "GET", path: path, queryItems: queryItems, body: nil, contentType: nil).0
    }

    /// 原始响应体 + HTTP 响应（需读 Content-Type 的 boundary，如 Worker 源码 multipart）
    func getRawResponse(_ path: String, queryItems: [URLQueryItem] = []) async throws -> (Data, HTTPURLResponse) {
        try await performRequest(method: "GET", path: path, queryItems: queryItems, body: nil, contentType: nil)
    }

    /// JSON 请求体、原始响应体的 POST（Workers AI 文生图等 2xx 直接返回二进制、不走 CF 信封的端点）。
    /// 非 2xx 仍由 performRequest 统一抛 APIError（含 CF 业务错误信息）。
    func postRaw<B: Codable & Sendable>(_ path: String, body: B) async throws -> Data {
        let encoded = try JSONEncoder().encode(body)
        return try await performRequest(
            method: "POST", path: path, queryItems: [], body: encoded, contentType: "application/json"
        ).0
    }

    /// 原始字节 PUT（R2 对象上传等），自带 Content-Type
    func putRaw<T: Codable & Sendable>(_ path: String, body: Data, contentType: String) async throws -> T {
        let (data, _) = try await performRequest(
            method: "PUT", path: path, queryItems: [], body: body, contentType: contentType
        )
        return try Self.decode(data, path: path)
    }

    // MARK: - 流式文件传输（R2 大对象 copy/move：过临时文件，不把整个对象灌进内存）

    /// 流式下载到临时文件（不进内存）。返回我们自管的临时文件 URL，调用方负责删除。
    func downloadToFile(_ path: String, queryItems: [URLQueryItem] = []) async throws -> URL {
        try await streamingDownload(path: path, queryItems: queryItems, isRetry: false)
    }

    private func streamingDownload(path: String, queryItems: [URLQueryItem], isRetry: Bool) async throws -> URL {
        let requestSessionId = await authManager.currentSessionId
        let request = try await buildRequest(method: "GET", path: path, queryItems: queryItems, contentType: nil)
        let (tempURL, response): (URL, URLResponse)
        do {
            (tempURL, response) = try await session.download(for: request)
        } catch {
            Self.logTransportError("GET", path, "download error", error)
            throw APIError.networkError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }
        if http.statusCode == 401 && !isRetry {
            guard let sid = requestSessionId, await authManager.currentSessionId == sid else {
                try? FileManager.default.removeItem(at: tempURL)
                throw APIError.unauthorized
            }
            do {
                _ = try await authManager.refreshAccessToken(expectedSessionId: sid)
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                throw APIError.unauthorized
            }
            return try await streamingDownload(path: path, queryItems: queryItems, isRetry: true)
        }
        guard (200...299).contains(http.statusCode) else {
            let data = (try? Data(contentsOf: tempURL)) ?? Data()
            try? FileManager.default.removeItem(at: tempURL)
            Self.logHTTPFailure("GET /\(Self.logPath(path)) -> \(http.statusCode)\(Self.cfErrorSummary(data))",
                                status: http.statusCode, path: path, data: data)
            throw Self.mapHTTPError(status: http.statusCode, data: data)
        }
        // download 返回的系统临时文件在本调用返回后会被清理，须立刻搬到自管位置
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("oc-transfer-\(UUID().uuidString)")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }

    /// 流式上传文件（不进内存），自带 Content-Type；onProgress 回报 0...1（上传腿）。
    func putFile<T: Codable & Sendable>(
        _ path: String,
        fileURL: URL,
        contentType: String,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> T {
        try await streamingUpload(path: path, fileURL: fileURL, contentType: contentType, onProgress: onProgress, isRetry: false)
    }

    private func streamingUpload<T: Codable & Sendable>(
        path: String,
        fileURL: URL,
        contentType: String,
        onProgress: (@Sendable (Double) -> Void)?,
        isRetry: Bool
    ) async throws -> T {
        let requestSessionId = await authManager.currentSessionId
        let request = try await buildRequest(method: "PUT", path: path, queryItems: [], contentType: contentType)
        let delegate = onProgress.map { UploadProgressDelegate(onProgress: $0) }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.upload(for: request, fromFile: fileURL, delegate: delegate)
        } catch {
            Self.logTransportError("PUT", path, "upload error", error)
            throw APIError.networkError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }
        if http.statusCode == 401 && !isRetry {
            guard let sid = requestSessionId, await authManager.currentSessionId == sid else {
                throw APIError.unauthorized
            }
            do {
                _ = try await authManager.refreshAccessToken(expectedSessionId: sid)
            } catch {
                throw APIError.unauthorized
            }
            return try await streamingUpload(path: path, fileURL: fileURL, contentType: contentType, onProgress: onProgress, isRetry: true)
        }
        guard (200...299).contains(http.statusCode) else {
            Self.logHTTPFailure("PUT /\(Self.logPath(path)) -> \(http.statusCode)\(Self.cfErrorSummary(data))",
                                status: http.statusCode, path: path, data: data)
            throw Self.mapHTTPError(status: http.statusCode, data: data)
        }
        return try Self.decode(data, path: path)
    }

    /// 构造带 Bearer 的 URLRequest（流式传输用，复用 path 已编码约定 + 临期刷新）
    private func buildRequest(method: String, path: String, queryItems: [URLQueryItem], contentType: String?) async throws -> URLRequest {
        let token = try await validAccessToken()
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath += "/" + path
        if !queryItems.isEmpty { components.queryItems = queryItems }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        return request
    }

    /// multipart/form-data 写入（KV 写值要求 value + metadata 两个 part）
    func putMultipart<T: Codable & Sendable>(_ path: String, fields: [String: String]) async throws -> T {
        let boundary = "OrangeCloud-\(UUID().uuidString)"
        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        let (data, _) = try await performRequest(
            method: "PUT", path: path, queryItems: [], body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
        return try Self.decode(data, path: path)
    }

    /// multipart/form-data 写入带文件 part（Snippets 上传 JS 模块）。
    /// metadata part 为 JSON（如 {"main_module":"snippet.js"}）；文件 part 的字段名即文件名，
    /// 与 main_module 引用一致，Content-Type 由调用方给（JS 模块用 application/javascript+module）。
    func putMultipartFile<T: Codable & Sendable>(
        _ path: String,
        metadata: [String: String],
        fileName: String,
        fileContent: Data,
        fileContentType: String
    ) async throws -> T {
        let boundary = "OrangeCloud-\(UUID().uuidString)"
        var body = Data()

        // metadata part
        let metadataJSON = try JSONEncoder().encode(metadata)
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"metadata\"\r\n".utf8))
        body.append(Data("Content-Type: application/json\r\n\r\n".utf8))
        body.append(metadataJSON)
        body.append(Data("\r\n".utf8))

        // 文件 part（字段名 = filename = fileName，main_module 引用它）
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(fileName)\"; filename=\"\(fileName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(fileContentType)\r\n\r\n".utf8))
        body.append(fileContent)
        body.append(Data("\r\n".utf8))

        body.append(Data("--\(boundary)--\r\n".utf8))

        let (data, _) = try await performRequest(
            method: "PUT", path: path, queryItems: [], body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
        return try Self.decode(data, path: path)
    }

    /// 通用 multipart 请求：一个 JSON part（metadata / settings）+ 可选单个文件 part，支持 method 与 query。
    /// Worker 上传（PUT，metadata + 模块文件，带 ?bindings_inherit=strict）与改设置（PATCH，settings）共用。
    func multipartRequest<T: Codable & Sendable, M: Encodable & Sendable>(
        method: String,
        _ path: String,
        queryItems: [URLQueryItem] = [],
        jsonPartName: String,
        jsonPart: M,
        file: (name: String, contentType: String, content: Data)? = nil
    ) async throws -> T {
        let boundary = "OrangeCloud-\(UUID().uuidString)"
        var body = Data()

        // JSON part（metadata / settings）
        let json = try JSONEncoder().encode(jsonPart)
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(jsonPartName)\"\r\n".utf8))
        body.append(Data("Content-Type: application/json\r\n\r\n".utf8))
        body.append(json)
        body.append(Data("\r\n".utf8))

        // 可选文件 part（脚本模块；字段名 = filename，main_module/body_part 引用它）
        if let file {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.name)\"\r\n".utf8))
            body.append(Data("Content-Type: \(file.contentType)\r\n\r\n".utf8))
            body.append(file.content)
            body.append(Data("\r\n".utf8))
        }

        body.append(Data("--\(boundary)--\r\n".utf8))

        let (data, _) = try await performRequest(
            method: method, path: path, queryItems: queryItems, body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
        return try Self.decode(data, path: path, method: method)
    }

    /// 用外部 Bearer（Pages 资源上传 JWT 等，非 OAuth token）发 JSON 请求，返回 2xx 原始响应体。
    /// 不做 token 刷新 / 401 重试——JWT 自带短有效期，失败即抛由调用方处理。
    func bearerJSON(method: String, path: String, bearer: String, body: Data) async throws -> Data {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath += "/" + path
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Self.logTransportError(method, path, "(jwt) network error", error)
            throw APIError.networkError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }
        guard (200...299).contains(http.statusCode) else {
            Self.logHTTPFailure("\(method) /\(Self.logPath(path)) (jwt) -> \(http.statusCode)\(Self.cfErrorSummary(data))",
                                status: http.statusCode, path: path, data: data)
            throw Self.mapHTTPError(status: http.statusCode, data: data)
        }
        return data
    }

    /// 对 Cloudflare 系外部主机（如 R2 SQL 的 api.sql.cloudflarestorage.com）发 JSON POST，
    /// 复用 OAuth Bearer 与临期刷新，返回 2xx 原始响应体。
    /// 注意：这些主机不一定走 client/v4 信封，错误体也交给 mapHTTPError 尽力解析。
    func postExternalJSON<B: Codable & Sendable>(url: URL, body: B) async throws -> Data {
        let token = try await validAccessToken()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Self.logTransportError("POST", url.absoluteString, "(external) network error", error)
            throw APIError.networkError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }
        guard (200...299).contains(http.statusCode) else {
            Self.logHTTPFailure("POST \(url.host ?? "")\(url.path) (external) -> \(http.statusCode)\(Self.cfErrorSummary(data))",
                                status: http.statusCode, path: url.path, data: data)
            throw Self.mapHTTPError(status: http.statusCode, data: data)
        }
        return data
    }

    /// multipart/form-data 表单字段写入，指定 method（Pages 创建部署：POST 一个 manifest 字段）
    func multipartFields<T: Codable & Sendable>(method: String, _ path: String, fields: [String: String]) async throws -> T {
        let boundary = "OrangeCloud-\(UUID().uuidString)"
        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data(value.utf8))
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        let (data, _) = try await performRequest(
            method: method, path: path, queryItems: [], body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
        return try Self.decode(data, path: path, method: method)
    }

    /// 一个 JSON part + 多个文件 part 的 multipart（多模块 Worker 上传：metadata + 各模块）
    func multipartRequest<T: Codable & Sendable, M: Encodable & Sendable>(
        method: String,
        _ path: String,
        queryItems: [URLQueryItem] = [],
        jsonPartName: String,
        jsonPart: M,
        files: [(name: String, contentType: String, content: Data)]
    ) async throws -> T {
        let boundary = "OrangeCloud-\(UUID().uuidString)"
        var body = Data()

        let json = try JSONEncoder().encode(jsonPart)
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(jsonPartName)\"\r\n".utf8))
        body.append(Data("Content-Type: application/json\r\n\r\n".utf8))
        body.append(json)
        body.append(Data("\r\n".utf8))

        for file in files {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.name)\"\r\n".utf8))
            body.append(Data("Content-Type: \(file.contentType)\r\n\r\n".utf8))
            body.append(file.content)
            body.append(Data("\r\n".utf8))
        }

        body.append(Data("--\(boundary)--\r\n".utf8))

        let (data, _) = try await performRequest(
            method: method, path: path, queryItems: queryItems, body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
        return try Self.decode(data, path: path, method: method)
    }

    /// 用外部 Bearer（Workers 资源上传 session JWT）发 multipart 表单，返回 2xx 原始响应体。
    /// 每个 part 的字段名 = 文件名 = 资源哈希；body 已是 base64 文本（配合 ?base64=true）。
    func bearerMultipart(
        method: String,
        path: String,
        queryItems: [URLQueryItem],
        bearer: String,
        parts: [(name: String, contentType: String, body: Data)]
    ) async throws -> Data {
        let boundary = "OrangeCloud-\(UUID().uuidString)"
        var body = Data()
        for part in parts {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(part.name)\"\r\n".utf8))
            body.append(Data("Content-Type: \(part.contentType)\r\n\r\n".utf8))
            body.append(part.body)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath += "/" + path
        if !queryItems.isEmpty { components.queryItems = queryItems }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Self.logTransportError(method, path, "(jwt mp) network error", error)
            throw APIError.networkError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }
        guard (200...299).contains(http.statusCode) else {
            Self.logHTTPFailure("\(method) /\(Self.logPath(path)) (jwt mp) -> \(http.statusCode)\(Self.cfErrorSummary(data))",
                                status: http.statusCode, path: path, data: data)
            throw Self.mapHTTPError(status: http.statusCode, data: data)
        }
        return data
    }

    /// GraphQL Analytics API。信封是 {data, errors}（GraphQL 错误时 HTTP 仍为 200），
    /// 与 REST 的 {result, success} 不同。复用 request 自动获得 Token 刷新与 401 重试。
    func graphQL<D: Codable & Sendable, V: Codable & Sendable>(
        query: String,
        variables: V
    ) async throws -> D {
        try await graphQLAllowingPartialAuthz(query: query, variables: variables).data
    }

    /// 同 graphQL，但把「部分字段 authz、其余字段照常返回」这一情况回给调用方，
    /// 便于 UI 区分「整账号无账户级数据」与「只是某些时间窗/数据集缺」（见下方说明）。
    func graphQLAllowingPartialAuthz<D: Codable & Sendable, V: Codable & Sendable>(
        query: String,
        variables: V
    ) async throws -> (data: D, partialAuthz: Bool) {
        let body = try JSONEncoder().encode(GraphQLRequest(query: query, variables: variables))
        let envelope: GraphQLResponse<D> = try await request(
            method: "POST", path: "graphql", queryItems: [], body: body
        )
        if let first = envelope.errors?.first {
            // GraphQL 错误时 HTTP 仍为 200——网络层只看状态码看不到这层，这里单独记，
            // 便于排查「请求 200 但数据没出来」（如数据集权限/字段不可用）。
            // authz（免费账号查账户级数据集的常态）与限流不是故障：UI 已按降级/重试处理，
            // 记 notice 不进遥测；其余 GraphQL 错误仍是 error（多为查询/字段写错了）。
            let line = "graphQL error (\(envelope.errors?.count ?? 1)): \(first.message)"
            if envelope.errors?.contains(where: \.isAuthz) == true || first.message.contains("Rate limiter") {
                AppLog.network.notice("\(line)")
            } else {
                AppLog.network.error("\(line)")
            }
            if envelope.errors?.contains(where: \.isAuthz) == true {
                // GraphQL 允许「部分字段 authz、其余字段照常返回」——免费账号最典型：
                // today 窗口有数据、month 窗口 authz。此时 data 已经解出来了，整包丢掉
                // 等于把手上的数据扔了（概览用量会整块误降级成「无账户级数据」）。
                // 故：解出 data 就返回（并标 partialAuthz），只有 data 为空才是真·整账号
                // 无账户级数据权限 → 抛给调用方降级并停发其余注定失败的账户级查询。
                if let data = envelope.data {
                    AppLog.network.info("graphQL partial authz: 返回已授权字段，缺失字段按空处理")
                    return (data, true)
                }
                throw APIError.accountNotAuthorized
            }
            throw APIError.cloudflareError(code: 0, message: first.message)
        }
        guard let data = envelope.data else {
            throw APIError.decodingError(URLError(.cannotDecodeContentData))
        }
        return (data, false)
    }

    // MARK: - 内部实现

    private func request<T: Codable & Sendable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem],
        body: Data?
    ) async throws -> T {
        let (data, _) = try await performRequest(
            method: method, path: path, queryItems: queryItems, body: body, contentType: "application/json"
        )
        // 少数端点（如 Workers 自定义域名 DELETE）2xx 时返回空 body 而非 CF 标准信封，
        // 期待 EmptyResponse 时空体即成功，别硬解 JSON（Sentry APPLE-IOS-C）。
        if data.isEmpty, let empty = EmptyResponse() as? T {
            return empty
        }
        return try Self.decode(data, path: path, method: method)
    }

    /// 统一的 HTTP 执行：Token 注入与刷新、401 重试一次、HTTP 错误映射，返回原始 Data + 响应
    private func performRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem],
        body: Data?,
        contentType: String?,
        isRetry: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {

        // 0. 绑定发起身份：401 重试 / 刷新只针对此刻这个身份；期间切账号则丢弃（陈旧请求）
        let requestSessionId = await authManager.currentSessionId

        // 1. 检查 Token 是否临期，如需则先刷新
        let token = try await validAccessToken()

        // 2. 构造请求。path 视为已编码（KV key 等特殊字符由调用方预先百分号编码，
        //    不能用 appendingPathComponent——它会把 % 二次编码）
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath += "/" + path
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let contentType {
            urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        urlRequest.httpBody = body

        // 3. 执行请求
        let start = Date()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            Self.logTransportError(method, path, "network error", error)
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            AppLog.network.error("\(method) /\(Self.logPath(path)) bad response (not HTTP)")
            throw APIError.networkError(URLError(.badServerResponse))
        }

        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)

        // 4. 401：Token 过期，刷新后重试一次
        if http.statusCode == 401 && !isRetry {
            // 切账号竞态：若已不是发起时的身份，丢弃这次（上个账号的陈旧请求），不刷新不重试
            guard let sid = requestSessionId, await authManager.currentSessionId == sid else {
                AppLog.network.notice("\(method) /\(Self.logPath(path)) -> 401, session changed, drop")
                throw APIError.unauthorized
            }
            AppLog.network.notice("\(method) /\(Self.logPath(path)) -> 401, refresh & retry")
            do {
                _ = try await authManager.refreshAccessToken(expectedSessionId: sid)
            } catch {
                throw APIError.unauthorized   // 刷新失败/身份已变：保留身份，按未授权失败
            }
            return try await performRequest(
                method: method, path: path, queryItems: queryItems,
                body: body, contentType: contentType, isRetry: true
            )
        }

        // 结果各记一行（2xx → info 带响应体大小；其余按 failureLevel 定级），便于排查。
        if (200...299).contains(http.statusCode) {
            AppLog.network.info("\(method) /\(Self.logPath(path)) -> \(http.statusCode) (\(elapsedMs)ms, \(Self.sizeLabel(data.count)))")
        } else {
            Self.logHTTPFailure("\(method) /\(Self.logPath(path)) -> \(http.statusCode) (\(elapsedMs)ms)\(Self.cfErrorSummary(data))",
                                status: http.statusCode, path: path, data: data)
        }

        // 5. HTTP 错误处理（优先透出 CF 返回的业务错误信息）
        switch http.statusCode {
        case 200...299:
            return (data, http)
        case 401:
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimited
        default:
            if let envelope = try? JSONDecoder().decode(CFAPIResponse<EmptyResponse>.self, from: data),
               let first = envelope.errors.first {
                throw APIError.cloudflareError(code: first.code, message: first.message)
            }
            switch http.statusCode {
            case 403:       throw APIError.forbidden
            case 404:       throw APIError.notFound
            case 500...599: throw APIError.serverError(statusCode: http.statusCode)
            default:        throw APIError.serverError(statusCode: http.statusCode)
            }
        }
    }

    /// 返回当前身份的有效 Token（临期则先刷新）
    private func validAccessToken() async throws -> String {
        guard let token = await authManager.currentToken else {
            throw APIError.unauthorized
        }
        let valid: String
        if token.expiresAt.timeIntervalSinceNow < 60 {  // 提前 60 秒刷新
            do {
                valid = try await authManager.refreshAccessToken()
            } catch AuthError.notLoggedIn {
                throw APIError.unauthorized          // 刷新令牌确已失效：不再使用旧 token
            } catch {
                // 刷新瞬时失败但旧 token 仍在有效期内：先用旧 token，真过期了由 401 重试兜底
                if token.expiresAt.timeIntervalSinceNow > 0 {
                    valid = token.accessToken
                } else {
                    throw error
                }
            }
        } else {
            valid = token.accessToken
        }
        return valid
    }

    /// 日志用路径：截断，避免把超长 KV key 等用户数据完整写进日志
    private static func logPath(_ path: String) -> String {
        path.count > 80 ? String(path.prefix(80)) + "…" : path
    }

    // MARK: - 日志降噪（取消与预期业务状态不按故障记）

    /// 用户侧取消（滑走页面 / 下拉刷新中断 / Task 取消）：预期行为，
    /// 降级 info——error 级会被遥测升为 Sentry 事件，取消类曾是噪音大头。
    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    /// 链路环境问题（超时 / 连接中断 / 无网 / DNS / TLS 握手失败）：取决于用户当时的网络，
    /// App 侧无可修，UI 已提示重试。记 notice——留在本地日志供反馈排查，但不进遥测。
    private static func isEnvironmentalNetworkFailure(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .secureConnectionFailed, .internationalRoamingOff, .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    /// 传输层失败统一记录：取消降级 info，环境类降级 notice，其余保持 error
    private static func logTransportError(_ method: String, _ path: String, _ label: String, _ error: Error) {
        let line = "\(method) /\(logPath(path)) \(label): \(error.localizedDescription)"
        if isCancellation(error) {
            AppLog.network.info("\(line)")
        } else if isEnvironmentalNetworkFailure(error) {
            AppLog.network.notice("\(line)")
        } else {
            AppLog.network.error("\(line)")
        }
    }

    private enum FailureLogLevel { case info, notice, error }

    /// 非 2xx 的记录级别。分三档：
    /// - info：日常空态，连看都不用看——账号未开通 R2（403 cf=10042）、zone 该阶段还没有
    ///   entrypoint ruleset（404 cf=10003，Snippets / WAF / 速率限制首次进入的常态）、
    ///   OAuth token 无账单读权限（subscriptions 403 cf=10000）。
    /// - notice：4xx 且 CF 给了业务错误码——接口明确告知这次操作不被接受（记录被 Email
    ///   Routing 托管、存在非 CF 的 MX、缺 filters、邮箱未验证、token 无该权限……），
    ///   原因已经原样展示给用户了。属预期结果而非故障，留在本地日志但不进遥测。
    /// - error：无业务码的 4xx（接口没说为什么，多半是我们请求构造错了）与全部 5xx。
    ///   这两类才是该在 Sentry 里看见的。
    private static func failureLevel(status: Int, path: String, data: Data) -> FailureLogLevel {
        // URL Scanner v2 错误体不是 CF 标准信封（无 code），按路径判定：
        // 结果轮询 404 = 扫描未完成（每次扫描都会来几次）、提交 409 = 主机名近期已扫过，都是预期态
        if path.contains("/urlscanner/v2/") && (status == 404 || status == 409) { return .info }
        guard let code = cfErrorCode(data) else { return .error }
        switch (status, code) {
        case (403, 10042): return .info
        case (404, 10003): return .info
        case (404, 10059): return .info   // R2 桶尚未配置 CORS，空态而非故障
        case (403, 10000) where path.hasSuffix("/subscriptions"): return .info
        default: return (400...499).contains(status) ? .notice : .error
        }
    }

    /// 非 2xx 统一记一行，级别由 failureLevel 判定
    private static func logHTTPFailure(_ line: String, status: Int, path: String, data: Data) {
        switch failureLevel(status: status, path: path, data: data) {
        case .info:   AppLog.network.info("\(line)")
        case .notice: AppLog.network.notice("\(line)")
        case .error:  AppLog.network.error("\(line)")
        }
    }

    private static func cfErrorCode(_ data: Data) -> Int? {
        guard let env = try? JSONDecoder().decode(CFAPIResponse<EmptyResponse>.self, from: data) else { return nil }
        return env.errors.first?.code
    }

    // MARK: - 解码与诊断（统一记日志，绝不写入数据值，仅字段路径/错误码）

    /// 统一 JSON 解码：失败时记一行（含失败字段路径与类型，不含数据值）再抛 decodingError。
    /// 「请求 200 但数据没出来」多半在这里现形。
    private static func decode<T: Decodable>(_ data: Data, path: String, method: String = "PUT") throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            AppLog.network.error("\(method) /\(logPath(path)) decode \(T.self) failed: \(decodeErrorSummary(error))")
            throw APIError.decodingError(error)
        }
    }

    /// 把 DecodingError 浓缩成一句（字段名是 API schema，非用户隐私，可记）
    private static func decodeErrorSummary(_ error: Error) -> String {
        guard let de = error as? DecodingError else { return error.localizedDescription }
        switch de {
        case .keyNotFound(let key, let ctx):    return "missing '\(key.stringValue)' at [\(codingPath(ctx))]"
        case .typeMismatch(let type, let ctx):  return "type mismatch \(type) at [\(codingPath(ctx))]"
        case .valueNotFound(let type, let ctx): return "null \(type) at [\(codingPath(ctx))]"
        case .dataCorrupted(let ctx):           return "corrupted at [\(codingPath(ctx))]"
        @unknown default:                       return "decoding error"
        }
    }

    private static func codingPath(_ ctx: DecodingError.Context) -> String {
        ctx.codingPath.map(\.stringValue).joined(separator: ".")
    }

    /// 非 2xx 时尽力解出 CF 业务错误码/消息（消息是接口级文案，非用户隐私）；解不出返回空串。
    private static func cfErrorSummary(_ data: Data) -> String {
        guard let env = try? JSONDecoder().decode(CFAPIResponse<EmptyResponse>.self, from: data),
              let first = env.errors.first else { return "" }
        // documentation_url（2026-08-20 起 CF 在 4xx 回的所需权限文档）与 source.pointer
        // （出错字段的 JSON Pointer）都进日志：403/权限类问题排查时这两条最省事。
        var line = " cf=\(first.code) \(first.message)"
        if let pointer = first.source?.pointer { line += " at \(pointer)" }
        if let doc = first.documentationURL { line += " doc=\(doc)" }
        return line
    }

    /// 响应体大小（便于发现「200 但空结果」）
    private static func sizeLabel(_ bytes: Int) -> String {
        bytes < 1024 ? "\(bytes)B" : String(format: "%.1fKB", Double(bytes) / 1024)
    }

    /// 非 2xx → APIError（流式传输复用，优先透出 CF 业务错误）。与 performRequest 内联映射对齐。
    private static func mapHTTPError(status: Int, data: Data) -> APIError {
        if let envelope = try? JSONDecoder().decode(CFAPIResponse<EmptyResponse>.self, from: data),
           let first = envelope.errors.first {
            return .cloudflareError(code: first.code, message: first.message,
                                    documentationURL: first.documentationURL)
        }
        switch status {
        case 401:       return .unauthorized
        case 403:       return .forbidden
        case 404:       return .notFound
        case 429:       return .rateLimited
        case 500...599: return .serverError(statusCode: status)
        default:        return .serverError(statusCode: status)
        }
    }
}

/// 上传进度转发：URLSession 流式上传的 didSendBodyData → 回调（0...1）。
/// 独立 NSObject，回调在 URLSession 代理队列，不触 actor 隔离。
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
