//
//  WorkerConfigModels.swift
//  Orange Cloud
//
//  Workers 脚本管理（编辑 / 变量 / 密钥 / 触发器）相关模型。
//  GET  /accounts/{a}/workers/scripts/{n}/content/v2  源码（模块→multipart，service worker→raw JS；v1 /content 被 OAuth 10405 挡，必须 v2）
//  PUT  /accounts/{a}/workers/scripts/{n}             上传（multipart：metadata + 模块 part），保留绑定用 inherit
//  GET  /accounts/{a}/workers/scripts/{n}/settings    绑定 + 兼容性日期/标志
//  PATCH .../settings                                 改绑定（变量），其余绑定回传 inherit
//  GET/PUT/DELETE .../secrets                          密钥（仅名+类型，无值）
//  GET/PUT .../schedules                               Cron 触发器（整组替换）
//

import Foundation

// MARK: - 部署历史

/// 一次部署（GET /workers/scripts/{n}/deployments 的 result.deployments 元素）。
/// 列表首项为当前正在服务的活跃部署（Cloudflare 不允许删除活跃部署）。
nonisolated struct WorkerDeployment: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let createdOn: String?
    let source: String?
    let authorEmail: String?
    let annotations: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id, source, annotations
        case createdOn   = "created_on"
        case authorEmail = "author_email"
    }

    /// annotations["workers/message"]（部署备注）
    var message: String? { annotations?["workers/message"] }

    var createdDate: Date? { WorkerScript.parseDate(createdOn) }
}

/// Worker 预览（beta）：GET /workers/workers/{name}/previews 的 result 元素。全部可选、宽容解码。
nonisolated struct WorkerPreview: Codable, Identifiable, Hashable, Sendable {
    let id:         String
    let name:       String?
    let slug:       String?
    let urls:       [String]?
    let createdOn:  String?
    let updatedOn:  String?
    let deployedOn: String?

    enum CodingKeys: String, CodingKey {
        case id, name, slug, urls
        case createdOn  = "created_on"
        case updatedOn  = "updated_on"
        case deployedOn = "deployed_on"
    }

    var displayName: String { name ?? slug ?? id }

    /// 首个可打开的 http(s) 地址
    var firstURL: URL? {
        (urls ?? []).lazy.compactMap { raw -> URL? in
            let text = raw.hasPrefix("http") ? raw : "https://" + raw
            guard let url = URL(string: text), url.host != nil else { return nil }
            return url
        }.first
    }

    var deployedDate: Date? { ISO8601Parse.date(deployedOn ?? updatedOn ?? createdOn) }
}

/// deployments 端点信封的 result（{ deployments: [...] }）
nonisolated struct WorkerDeploymentsResult: Codable, Sendable {
    let deployments: [WorkerDeployment]
}

// MARK: - 脚本源码

/// 单个脚本模块（multipart 的一个 part；service worker 视为单条）
nonisolated struct WorkerModule: Identifiable, Hashable, Sendable {
    let name:        String      // part 名 / 文件名（上传时 main_module / body_part 引用它）
    let contentType: String      // application/javascript+module 或 application/javascript
    let body:        String

    var id: String { name }
}

/// 解析后的脚本内容。仅单模块（或 service worker）支持编辑，多模块只读。
nonisolated struct WorkerContent: Sendable {
    let modules:    [WorkerModule]
    let isModule:   Bool         // true = ES module（main_module）；false = 经典 service worker（body_part）

    /// 单模块 / service worker 才可在客户端安全往返编辑；多模块（捆绑产物）只读
    var isEditable: Bool { modules.count <= 1 }

    /// 编辑目标模块（可编辑时即唯一模块）
    var mainModule: WorkerModule? { modules.first }

    /// 从 content 端点的原始响应解析（按 Content-Type 的 boundary 切分 multipart）
    nonisolated static func parse(data: Data, contentType: String?) -> WorkerContent {
        let ct = contentType ?? ""
        guard let boundary = Self.boundary(from: ct) else {
            // 非 multipart = 经典 service worker，整体即正文
            let body = String(decoding: data, as: UTF8.self)
            let module = WorkerModule(name: "worker.js", contentType: "application/javascript", body: body)
            return WorkerContent(modules: [module], isModule: false)
        }
        let modules = Self.parseParts(String(decoding: data, as: UTF8.self), boundary: boundary)
        return WorkerContent(modules: modules, isModule: true)
    }

    private nonisolated static func boundary(from contentType: String) -> String? {
        guard contentType.localizedCaseInsensitiveContains("multipart/"),
              let range = contentType.range(of: "boundary=") else { return nil }
        var value = String(contentType[range.upperBound...])
        if let semi = value.firstIndex(of: ";") { value = String(value[..<semi]) }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
    }

    /// 朴素 multipart/form-data 解析：按分隔符切块，块内首个空行分隔头与正文。
    /// 脚本模块均为文本（JS），按 UTF-8 处理；二进制模块（如 WASM）只读展示用占位。
    private nonisolated static func parseParts(_ raw: String, boundary: String) -> [WorkerModule] {
        let delimiter = "--\(boundary)"
        var modules: [WorkerModule] = []
        for chunk in raw.components(separatedBy: delimiter) {
            let part = chunk.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
            guard !part.isEmpty, part != "--" else { continue }       // 跳过前导/收尾
            guard let sep = part.range(of: "\r\n\r\n") ?? part.range(of: "\n\n") else { continue }
            let headers = String(part[..<sep.lowerBound])
            let body    = String(part[sep.upperBound...])
            let name = Self.headerValue(headers, key: "name") ?? Self.headerValue(headers, key: "filename") ?? "module"
            let type = Self.contentTypeHeader(headers) ?? "application/javascript+module"
            modules.append(WorkerModule(name: name, contentType: type, body: body))
        }
        return modules
    }

    /// 取 Content-Disposition 里形如 name="x" 的值
    private nonisolated static func headerValue(_ headers: String, key: String) -> String? {
        guard let range = headers.range(of: "\(key)=\"") else { return nil }
        let rest = headers[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    private nonisolated static func contentTypeHeader(_ headers: String) -> String? {
        for line in headers.components(separatedBy: CharacterSet.newlines) {
            if line.lowercased().hasPrefix("content-type:") {
                return line.dropFirst("content-type:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}

// MARK: - 绑定与设置

/// 脚本绑定（KV / D1 / R2 / 密钥 / 变量 等）。读展示与 inherit 回传只需 type/name；变量另读 text。
/// 容错解码：未建模的新绑定类型不致整页失败（缺字段降级为空串，调用方过滤空名）。
nonisolated struct WorkerBinding: Codable, Identifiable, Hashable, Sendable {
    let type: String
    let name: String
    let text: String?       // plain_text 变量的值；其余类型为 nil

    var id: String { "\(type)/\(name)" }

    enum CodingKeys: String, CodingKey { case type, name, text }

    init(type: String, name: String, text: String? = nil) {
        self.type = type
        self.name = name
        self.text = text
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(String.self, forKey: .type)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        text = try? c.decode(String.self, forKey: .text)
    }

    var isSecret:    Bool { type == "secret_text" || type == "secrets_store_secret" }
    var isPlainText: Bool { type == "plain_text" }
    /// 本客户端可原地增删的资源绑定（D1 / KV / R2）——其余类型仍只读
    var isQuickManaged: Bool { type == "kv_namespace" || type == "d1" || type == "r2_bucket" }

    /// 人类可读的绑定类型标签
    var typeLabel: String {
        switch type {
        case "plain_text":           String(localized: "变量")
        case "secret_text",
             "secrets_store_secret": String(localized: "密钥")
        case "kv_namespace":         "KV"
        case "d1":                   "D1"
        case "r2_bucket":            "R2"
        case "queue":                String(localized: "队列")
        case "durable_object_namespace": "Durable Object"
        case "service":              String(localized: "Service 绑定")
        case "ai":                   "Workers AI"
        case "vectorize":            "Vectorize"
        case "analytics_engine":     "Analytics Engine"
        case "browser":              String(localized: "浏览器渲染")
        default:                     type
        }
    }

    /// 回传时转为 inherit（按名保留旧绑定，密钥值我们读不到也能保住）
    func asInherit() -> WorkerBindingInput { WorkerBindingInput(type: "inherit", name: name) }
}

/// 脚本设置（GET .../settings）。绑定逐个容错解码、过滤空名。
nonisolated struct WorkerSettings: Codable, Sendable {
    let bindings:           [WorkerBinding]
    let compatibilityDate:  String?
    let compatibilityFlags: [String]?
    let usageModel:         String?
    let logpush:            Bool?

    enum CodingKeys: String, CodingKey {
        case bindings, logpush
        case compatibilityDate  = "compatibility_date"
        case compatibilityFlags = "compatibility_flags"
        case usageModel         = "usage_model"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decode([WorkerBinding].self, forKey: .bindings)) ?? []
        bindings           = raw.filter { !$0.name.isEmpty }
        compatibilityDate  = try? c.decode(String.self, forKey: .compatibilityDate)
        compatibilityFlags = try? c.decode([String].self, forKey: .compatibilityFlags)
        usageModel         = try? c.decode(String.self, forKey: .usageModel)
        logpush            = try? c.decode(Bool.self, forKey: .logpush)
    }

    /// 把现有绑定整组转为 inherit，供「只改代码/某个变量、其余保持」的安全回传
    func inheritedBindings(excludingName: String? = nil) -> [WorkerBindingInput] {
        bindings
            .filter { $0.name != excludingName }
            .map { $0.asInherit() }
    }
}

// MARK: - 上传 / 写入请求体

/// 上传 / patch settings 时的单条绑定。inherit 只发 {type,name}；plain_text 发 {type,name,text}；
/// kv_namespace 发 {type,name,namespace_id}；d1 发 {type,name,id}；r2_bucket 发 {type,name,bucket_name}
/// （R2 按**桶名**引用，不是 ID）。可选字段为 nil 时不编码（omitted）。
nonisolated struct WorkerBindingInput: Codable, Sendable {
    let type: String
    let name: String
    let text: String?
    let namespaceId: String?    // kv_namespace 绑定的命名空间 ID
    let id: String?             // d1 绑定的数据库 UUID
    let bucketName: String?     // r2_bucket 绑定的桶名

    init(
        type: String, name: String, text: String? = nil,
        namespaceId: String? = nil, id: String? = nil, bucketName: String? = nil
    ) {
        self.type = type
        self.name = name
        self.text = text
        self.namespaceId = namespaceId
        self.id = id
        self.bucketName = bucketName
    }

    enum CodingKeys: String, CodingKey {
        case type, name, text, id
        case namespaceId = "namespace_id"
        case bucketName  = "bucket_name"
    }

    /// 绑定既有 KV 命名空间
    static func kv(name: String, namespaceId: String) -> WorkerBindingInput {
        WorkerBindingInput(type: "kv_namespace", name: name, namespaceId: namespaceId)
    }

    /// 绑定既有 D1 数据库
    static func d1(name: String, databaseId: String) -> WorkerBindingInput {
        WorkerBindingInput(type: "d1", name: name, id: databaseId)
    }

    /// 绑定既有 R2 存储桶（按桶名）
    static func r2(name: String, bucketName: String) -> WorkerBindingInput {
        WorkerBindingInput(type: "r2_bucket", name: name, bucketName: bucketName)
    }
}

/// 脚本上传 multipart 的 metadata part。module 用 main_module；service worker 用 body_part。
nonisolated struct WorkerUploadMetadata: Codable, Sendable {
    let mainModule:         String?
    let bodyPart:           String?
    let compatibilityDate:  String?
    let compatibilityFlags: [String]?
    let bindings:           [WorkerBindingInput]

    enum CodingKeys: String, CodingKey {
        case bindings
        case mainModule         = "main_module"
        case bodyPart           = "body_part"
        case compatibilityDate  = "compatibility_date"
        case compatibilityFlags = "compatibility_flags"
    }
}

// MARK: - 多模块上传

/// 上传时的单个模块文件（可为二进制，如 .wasm，故用 Data）
nonisolated struct WorkerUploadModule: Identifiable, Sendable {
    let name:        String      // 模块说明符 / 文件名（main_module 引用它）
    let data:        Data
    let contentType: String

    var id: String { name }
}

/// 按扩展名推断模块 Content-Type（决定 Workers 如何解析该模块）
nonisolated enum WorkerModuleType {
    static func contentType(forName name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "js", "mjs": "application/javascript+module"
        case "cjs":       "application/javascript"
        case "wasm":      "application/wasm"
        case "json":      "application/json"
        case "py":        "text/x-python"
        case "txt":       "text/plain"
        default:          "application/octet-stream"   // data 模块（二进制资源）
        }
    }

    /// 可作为入口（main_module）的模块：JS / Python
    static func canBeEntry(_ name: String) -> Bool {
        ["js", "mjs", "cjs", "py"].contains((name as NSString).pathExtension.lowercased())
    }
}

// MARK: - 静态资源（Workers Assets）上传

/// assets manifest 单条：hash 为 sha256(base64(内容)+扩展名) 前 32 位，size 为原始字节数
nonisolated struct WorkerAssetManifestEntry: Codable, Sendable {
    let hash: String
    let size: Int
}

/// POST .../assets-upload-session 请求体
nonisolated struct WorkerAssetsUploadSessionRequest: Codable, Sendable {
    let manifest: [String: WorkerAssetManifestEntry]
}

/// assets-upload-session 响应 result：jwt（上传/完成令牌）+ buckets（每桶为待传 hash 列表）
nonisolated struct WorkerAssetsUploadSession: Codable, Sendable {
    let jwt:     String?
    let buckets: [[String]]?
}

/// assets/upload 每桶上传的响应 result（最后一桶含完成令牌 jwt）
nonisolated struct WorkerAssetsUploadResult: Codable, Sendable {
    let jwt: String?
}

/// PUT 脚本（带静态资源）的 metadata part。assets.jwt 为完成令牌；assets-only 时 mainModule 省略。
nonisolated struct WorkerAssetsUploadMetadata: Codable, Sendable {
    let mainModule:         String?
    let compatibilityDate:  String?
    let compatibilityFlags: [String]?
    let assets:             WorkerAssetsConfig
    let bindings:           [WorkerBindingInput]

    enum CodingKeys: String, CodingKey {
        case assets, bindings
        case mainModule         = "main_module"
        case compatibilityDate  = "compatibility_date"
        case compatibilityFlags = "compatibility_flags"
    }
}

nonisolated struct WorkerAssetsConfig: Codable, Sendable {
    let jwt:    String
    let config: WorkerAssetsRoutingConfig
}

nonisolated struct WorkerAssetsRoutingConfig: Codable, Sendable {
    let htmlHandling:     String?
    let notFoundHandling: String?

    enum CodingKeys: String, CodingKey {
        case htmlHandling     = "html_handling"
        case notFoundHandling = "not_found_handling"
    }
}

/// PATCH settings 的 settings part（改变量时回传：变更项 + 其余 inherit）
nonisolated struct WorkerSettingsPatch: Codable, Sendable {
    let bindings:           [WorkerBindingInput]
    let compatibilityDate:  String?
    let compatibilityFlags: [String]?

    enum CodingKeys: String, CodingKey {
        case bindings
        case compatibilityDate  = "compatibility_date"
        case compatibilityFlags = "compatibility_flags"
    }
}

// MARK: - 密钥

/// 密钥（GET .../secrets，仅名 + 类型，永不含值）
nonisolated struct WorkerSecret: Codable, Identifiable, Hashable, Sendable {
    let name: String
    let type: String?
    var id: String { name }
}

/// 新建 / 更新密钥（PUT .../secrets）
nonisolated struct WorkerSecretInput: Codable, Sendable {
    let name: String
    let text: String
    let type: String

    init(name: String, text: String) {
        self.name = name
        self.text = text
        self.type = "secret_text"
    }
}

/// 批量增删密钥（PATCH .../secrets-bulk，2026-06 新端点，单次 ≤100 项）。
/// JSON Merge Patch 语义：值为密钥对象 → 新建/覆盖，值为 null → 删除，未提及 → 不动。
nonisolated struct WorkerSecretsBulkPatch: Codable, Sendable {
    let secrets: [String: WorkerSecretInput?]
}

// MARK: - Cron 触发器

/// 单条 Cron 触发器（GET .../schedules）
nonisolated struct WorkerSchedule: Codable, Identifiable, Hashable, Sendable {
    let cron:       String
    let createdOn:  String?
    let modifiedOn: String?

    var id: String { cron }

    enum CodingKeys: String, CodingKey {
        case cron
        case createdOn  = "created_on"
        case modifiedOn = "modified_on"
    }
}

/// schedules 端点 result 形态 { schedules: [...] }
nonisolated struct WorkerSchedulesResult: Codable, Sendable {
    let schedules: [WorkerSchedule]
}

/// PUT .../schedules 的单条（整组替换，请求体是裸数组 [{cron}]）
nonisolated struct WorkerScheduleInput: Codable, Sendable {
    let cron: String
}
