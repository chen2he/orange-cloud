//
//  WorkerService.swift
//  Orange Cloud
//

import Foundation

struct WorkerService {

    private let client: CFAPIClient

    init(client: CFAPIClient) {
        self.client = client
    }

    /// 账号下全部 Workers 脚本（该端点不分页）
    func listScripts(accountId: String) async throws -> [WorkerScript] {
        let response: CFAPIResponseArray<WorkerScript> = try await client.get(
            "accounts/\(accountId)/workers/scripts"
        )
        guard response.success else {
            throw response.toAPIError()
        }
        return response.result ?? []
    }

    // MARK: - 脚本源码与设置

    /// 脚本源码（模块→multipart 解析为各模块；service worker→raw JS）。
    /// 必须走 /content/v2：v1 的 `/content` 对 OAuth 认证方案返回 405 cf=10405
    /// （Method not allowed for this authentication scheme），v2 与裸 GET 才放行
    /// （真机实测 2026-07-14，issue #55）。响应仍是 multipart/form-data，解码口径不变。
    func content(accountId: String, scriptName: String) async throws -> WorkerContent {
        let (data, response) = try await client.getRawResponse(
            "accounts/\(accountId)/workers/scripts/\(scriptName)/content/v2"
        )
        let contentType = response.value(forHTTPHeaderField: "Content-Type")
        // 打包产物可达数 MB，multipart 切分不放主线程（本类型默认 MainActor 隔离）
        return await Task.detached(priority: .userInitiated) {
            WorkerContent.parse(data: data, contentType: contentType)
        }.value
    }

    /// 脚本设置（绑定 + 兼容性日期/标志）
    func settings(accountId: String, scriptName: String) async throws -> WorkerSettings {
        let response: CFAPIResponse<WorkerSettings> = try await client.get(
            "accounts/\(accountId)/workers/scripts/\(scriptName)/settings"
        )
        guard response.success, let settings = response.result else { throw response.toAPIError() }
        return settings
    }

    /// 安全保存脚本代码：仅替换正文，全部绑定以 inherit 按名保留（密钥值读不到也能保住），
    /// 兼容性日期/标志沿用旧值；带 ?bindings_inherit=strict，缺绑定时直接报错而非静默丢弃。
    func uploadScript(
        accountId: String,
        scriptName: String,
        content: WorkerContent,
        newCode: String,
        settings: WorkerSettings
    ) async throws {
        guard let module = content.mainModule else {
            throw APIError.cloudflareError(code: 0, message: String(localized: "无法定位脚本主模块"))
        }
        let metadata = WorkerUploadMetadata(
            mainModule:         content.isModule ? module.name : nil,
            bodyPart:           content.isModule ? nil : module.name,
            compatibilityDate:  settings.compatibilityDate,
            compatibilityFlags: settings.compatibilityFlags,
            bindings:           settings.bindings.map { $0.asInherit() }
        )
        let response: CFAPIResponse<EmptyResponse> = try await client.multipartRequest(
            method: "PUT",
            "accounts/\(accountId)/workers/scripts/\(scriptName)",
            queryItems: [URLQueryItem(name: "bindings_inherit", value: "strict")],
            jsonPartName: "metadata",
            jsonPart: metadata,
            file: (name: module.name, contentType: module.contentType, content: Data(newCode.utf8))
        )
        guard response.success else { throw response.toAPIError() }
    }

    /// 新建 / 整体替换脚本（PUT 即「不存在则建、存在则覆盖」）。主模块名由我们定，
    /// 新建无需读旧码（原地编辑改走 content() 读 /content/v2 预填）；
    /// 替换时传 inheritBindings（现有绑定按名 inherit，连同读不到值的密钥一并保住），带
    /// ?bindings_inherit=strict 缺绑定即报错而非静默丢弃。
    func deployScript(
        accountId: String,
        scriptName: String,
        code: String,
        isModule: Bool,
        compatibilityDate: String,
        compatibilityFlags: [String]? = nil,
        inheritBindings: [WorkerBindingInput]? = nil
    ) async throws {
        let moduleName = "worker.js"
        let metadata = WorkerUploadMetadata(
            mainModule:         isModule ? moduleName : nil,
            bodyPart:           isModule ? nil : moduleName,
            compatibilityDate:  compatibilityDate,
            compatibilityFlags: compatibilityFlags,
            bindings:           inheritBindings ?? []
        )
        var query: [URLQueryItem] = []
        if inheritBindings != nil {
            query.append(URLQueryItem(name: "bindings_inherit", value: "strict"))
        }
        let response: CFAPIResponse<EmptyResponse> = try await client.multipartRequest(
            method: "PUT",
            "accounts/\(accountId)/workers/scripts/\(scriptName)",
            queryItems: query,
            jsonPartName: "metadata",
            jsonPart: metadata,
            file: (
                name: moduleName,
                contentType: isModule ? "application/javascript+module" : "application/javascript",
                content: Data(code.utf8)
            )
        )
        guard response.success else { throw response.toAPIError() }
    }

    /// 多模块上传：metadata.main_module 指向入口，每个模块作为独立文件 part。
    func deployModules(
        accountId: String,
        scriptName: String,
        modules: [WorkerUploadModule],
        entryName: String,
        compatibilityDate: String,
        compatibilityFlags: [String]? = nil,
        inheritBindings: [WorkerBindingInput]? = nil
    ) async throws {
        let metadata = WorkerUploadMetadata(
            mainModule:         entryName,
            bodyPart:           nil,
            compatibilityDate:  compatibilityDate,
            compatibilityFlags: compatibilityFlags,
            bindings:           inheritBindings ?? []
        )
        var query: [URLQueryItem] = []
        if inheritBindings != nil { query.append(URLQueryItem(name: "bindings_inherit", value: "strict")) }
        let response: CFAPIResponse<EmptyResponse> = try await client.multipartRequest(
            method: "PUT",
            "accounts/\(accountId)/workers/scripts/\(scriptName)",
            queryItems: query,
            jsonPartName: "metadata",
            jsonPart: metadata,
            files: modules.map { (name: $0.name, contentType: $0.contentType, content: $0.data) }
        )
        guard response.success else { throw response.toAPIError() }
    }

    /// 删除整个 Worker 脚本（连同其部署、路由绑定）。OAuth 下放行（真机实测 issue #55）。
    /// 需 workers-scripts.write。不可撤销。
    func deleteScript(accountId: String, scriptName: String) async throws {
        try await client.delete("accounts/\(accountId)/workers/scripts/\(scriptName)")
    }

    // MARK: - 部署历史

    /// 部署列表（result.deployments，首项为活跃部署）。
    func listDeployments(accountId: String, scriptName: String) async throws -> [WorkerDeployment] {
        let response: CFAPIResponse<WorkerDeploymentsResult> = try await client.get(
            "accounts/\(accountId)/workers/scripts/\(scriptName)/deployments"
        )
        guard response.success, let result = response.result else { throw response.toAPIError() }
        return result.deployments
    }

    /// 删除某次部署。当前活跃（最新）部署 Cloudflare 会拒绝删除。需 workers-scripts.write。
    func deleteDeployment(accountId: String, scriptName: String, deploymentId: String) async throws {
        try await client.delete("accounts/\(accountId)/workers/scripts/\(scriptName)/deployments/\(deploymentId)")
    }

    // MARK: - 预览（beta，workers-scripts.read）

    /// 该 Worker 的预览，按部署时间倒序取前 20 个。worker_id 段接受 Worker 名。
    func previews(accountId: String, scriptName: String) async throws -> [WorkerPreview] {
        let response: CFAPIResponseArray<WorkerPreview> = try await client.get(
            "accounts/\(accountId)/workers/workers/\(scriptName)/previews",
            queryItems: [
                URLQueryItem(name: "per_page", value: "20"),
                URLQueryItem(name: "order_by", value: "deployed_on"),
                URLQueryItem(name: "order", value: "desc"),
            ]
        )
        guard response.success else { throw response.toAPIError() }
        return response.result ?? []
    }

    // MARK: - 静态资源（Workers Assets）
    //
    // 流程：① assets-upload-session 提交 manifest（路径→{hash,size}）拿 jwt + 待传分桶
    // → ② 按桶把资源 base64 传到 workers/assets/upload（用 session jwt）→ 末桶回完成令牌
    // → ③ PUT 脚本，metadata.assets.jwt = 完成令牌（assets-only 时不带 main_module）。
    //

    func createAssetsUploadSession(
        accountId: String,
        scriptName: String,
        manifest: [String: WorkerAssetManifestEntry]
    ) async throws -> WorkerAssetsUploadSession {
        let response: CFAPIResponse<WorkerAssetsUploadSession> = try await client.post(
            "accounts/\(accountId)/workers/scripts/\(scriptName)/assets-upload-session",
            body: WorkerAssetsUploadSessionRequest(manifest: manifest)
        )
        guard response.success, let session = response.result else { throw response.toAPIError() }
        return session
    }

    /// 上传一桶资源（base64）。返回该桶响应里的完成令牌（仅末桶有）。
    func uploadAssetsBucket(
        accountId: String,
        sessionJWT: String,
        files: [(hash: String, base64: String, contentType: String)]
    ) async throws -> String? {
        let parts = files.map { (name: $0.hash, contentType: $0.contentType, body: Data($0.base64.utf8)) }
        let data = try await client.bearerMultipart(
            method: "POST",
            path: "accounts/\(accountId)/workers/assets/upload",
            queryItems: [URLQueryItem(name: "base64", value: "true")],
            bearer: sessionJWT,
            parts: parts
        )
        let response = try JSONDecoder().decode(CFAPIResponse<WorkerAssetsUploadResult>.self, from: data)
        guard response.success else { throw response.toAPIError() }
        return response.result?.jwt
    }

    /// PUT 脚本并挂上静态资源（completionJWT 来自资源上传末桶 / 无需上传时来自 session）。
    /// mainModule 为 nil 即 assets-only（纯静态站）。
    func deployWithAssets(
        accountId: String,
        scriptName: String,
        completionJWT: String,
        compatibilityDate: String,
        htmlHandling: String,
        notFoundHandling: String,
        mainModule: (name: String, contentType: String, content: Data)? = nil
    ) async throws {
        let metadata = WorkerAssetsUploadMetadata(
            mainModule:         mainModule?.name,
            compatibilityDate:  compatibilityDate,
            compatibilityFlags: nil,
            assets: WorkerAssetsConfig(
                jwt: completionJWT,
                config: WorkerAssetsRoutingConfig(htmlHandling: htmlHandling, notFoundHandling: notFoundHandling)
            ),
            bindings: []
        )
        let files: [(name: String, contentType: String, content: Data)] = mainModule.map {
            [(name: $0.name, contentType: $0.contentType, content: $0.content)]
        } ?? []
        let response: CFAPIResponse<EmptyResponse> = try await client.multipartRequest(
            method: "PUT",
            "accounts/\(accountId)/workers/scripts/\(scriptName)",
            jsonPartName: "metadata",
            jsonPart: metadata,
            files: files
        )
        guard response.success else { throw response.toAPIError() }
    }

    /// 改绑定（变量）：传入完整新 bindings（变更项为实体，其余 inherit），PATCH settings 不动代码。
    func patchSettings(
        accountId: String,
        scriptName: String,
        bindings: [WorkerBindingInput],
        settings: WorkerSettings
    ) async throws {
        let patch = WorkerSettingsPatch(
            bindings:           bindings,
            compatibilityDate:  settings.compatibilityDate,
            compatibilityFlags: settings.compatibilityFlags
        )
        let response: CFAPIResponse<EmptyResponse> = try await client.multipartRequest(
            method: "PATCH",
            "accounts/\(accountId)/workers/scripts/\(scriptName)/settings",
            jsonPartName: "settings",
            jsonPart: patch
        )
        guard response.success else { throw response.toAPIError() }
    }

    // MARK: - 密钥

    /// 密钥列表（仅名 + 类型，永不含值）
    func listSecrets(accountId: String, scriptName: String) async throws -> [WorkerSecret] {
        let response: CFAPIResponseArray<WorkerSecret> = try await client.get(
            "accounts/\(accountId)/workers/scripts/\(scriptName)/secrets"
        )
        guard response.success else { throw response.toAPIError() }
        return response.result ?? []
    }

    /// 新建 / 更新密钥
    func putSecret(accountId: String, scriptName: String, name: String, text: String) async throws {
        let response: CFAPIResponse<EmptyResponse> = try await client.put(
            "accounts/\(accountId)/workers/scripts/\(scriptName)/secrets",
            body: WorkerSecretInput(name: name, text: text)
        )
        guard response.success else { throw response.toAPIError() }
    }

    /// 删除密钥
    func deleteSecret(accountId: String, scriptName: String, name: String) async throws {
        try await client.delete("accounts/\(accountId)/workers/scripts/\(scriptName)/secrets/\(name)")
    }

    /// 批量写密钥（2026-06 新端点，单次 ≤100 项，原子生效）。
    /// JSON Merge Patch：对象 → 新建/覆盖，null → 删除；未提及的密钥不受影响。
    func bulkPatchSecrets(
        accountId: String,
        scriptName: String,
        upserts: [(name: String, text: String)],
        deletes: [String] = []
    ) async throws {
        var secrets: [String: WorkerSecretInput?] = [:]
        for item in upserts {
            secrets[item.name] = WorkerSecretInput(name: item.name, text: item.text)
        }
        for name in deletes {
            // 双重可选陷阱：subscript 赋 nil 会移除键，须 updateValue 才能存下「值为 null」
            secrets.updateValue(nil, forKey: name)
        }
        let response: CFAPIResponse<EmptyResponse> = try await client.patch(
            "accounts/\(accountId)/workers/scripts/\(scriptName)/secrets-bulk",
            body: WorkerSecretsBulkPatch(secrets: secrets)
        )
        guard response.success else { throw response.toAPIError() }
    }

    // MARK: - Cron 触发器

    func schedules(accountId: String, scriptName: String) async throws -> [WorkerSchedule] {
        let response: CFAPIResponse<WorkerSchedulesResult> = try await client.get(
            "accounts/\(accountId)/workers/scripts/\(scriptName)/schedules"
        )
        guard response.success else { throw response.toAPIError() }
        return response.result?.schedules ?? []
    }

    /// 整组替换 Cron（请求体是裸数组 [{cron}]；漏传即删）
    func putSchedules(accountId: String, scriptName: String, crons: [String]) async throws {
        let body = crons.map { WorkerScheduleInput(cron: $0) }
        let response: CFAPIResponse<WorkerSchedulesResult> = try await client.put(
            "accounts/\(accountId)/workers/scripts/\(scriptName)/schedules",
            body: body
        )
        guard response.success else { throw response.toAPIError() }
    }

    // MARK: - 域名 / 路由

    /// 账号级 workers.dev 子域前缀（拼 <脚本名>.<前缀>.workers.dev）。
    /// 账号未注册子域时端点可能 404 或返回空，调用方以 try? 容错。
    func accountSubdomain(accountId: String) async throws -> String? {
        let response: CFAPIResponse<WorkerAccountSubdomain> = try await client.get(
            "accounts/\(accountId)/workers/subdomain"
        )
        guard response.success else { throw response.toAPIError() }
        return response.result?.subdomain
    }

    /// workers.dev 子域状态
    func subdomain(accountId: String, scriptName: String) async throws -> WorkerSubdomain {
        let response: CFAPIResponse<WorkerSubdomain> = try await client.get(
            "accounts/\(accountId)/workers/scripts/\(scriptName)/subdomain"
        )
        guard response.success, let sub = response.result else { throw response.toAPIError() }
        return sub
    }

    /// 切换 workers.dev 子域
    func setSubdomain(accountId: String, scriptName: String, enabled: Bool) async throws {
        let response: CFAPIResponse<EmptyResponse> = try await client.post(
            "accounts/\(accountId)/workers/scripts/\(scriptName)/subdomain",
            body: WorkerSubdomainInput(enabled: enabled)
        )
        guard response.success else { throw response.toAPIError() }
    }

    /// 该脚本的自定义域（按 service 过滤）
    func customDomains(accountId: String, scriptName: String) async throws -> [WorkerCustomDomain] {
        let response: CFAPIResponseArray<WorkerCustomDomain> = try await client.get(
            "accounts/\(accountId)/workers/domains",
            queryItems: [URLQueryItem(name: "service", value: scriptName)]
        )
        guard response.success else { throw response.toAPIError() }
        return response.result ?? []
    }

    /// 挂载自定义域到该脚本
    func attachDomain(accountId: String, scriptName: String, hostname: String, zoneId: String) async throws {
        let response: CFAPIResponse<WorkerCustomDomain> = try await client.put(
            "accounts/\(accountId)/workers/domains",
            body: WorkerCustomDomainInput(hostname: hostname, service: scriptName, zoneId: zoneId)
        )
        guard response.success else { throw response.toAPIError() }
    }

    /// 卸载自定义域
    func deleteDomain(accountId: String, domainId: String) async throws {
        try await client.delete("accounts/\(accountId)/workers/domains/\(domainId)")
    }

    /// zone 下全部 Worker 路由（调用方按 script 过滤到本脚本）
    func routes(zoneId: String) async throws -> [WorkerRoute] {
        let response: CFAPIResponseArray<WorkerRoute> = try await client.get(
            "zones/\(zoneId)/workers/routes"
        )
        guard response.success else { throw response.toAPIError() }
        return response.result ?? []
    }

    /// 新建路由（pattern → script）
    func createRoute(zoneId: String, pattern: String, scriptName: String) async throws {
        let response: CFAPIResponse<WorkerRoute> = try await client.post(
            "zones/\(zoneId)/workers/routes",
            body: WorkerRouteInput(pattern: pattern, script: scriptName)
        )
        guard response.success else { throw response.toAPIError() }
    }

    /// 删除路由
    func deleteRoute(zoneId: String, routeId: String) async throws {
        try await client.delete("zones/\(zoneId)/workers/routes/\(routeId)")
    }
}
