//
//  WorkerBindingsViewModel.swift
//  Orange Cloud
//
//  Worker 密钥（secret_text，专用端点）+ 环境变量（plain_text，PATCH settings）+ 只读绑定清单。
//  改变量一律 read-modify-write：变更项为实体、其余绑定 inherit，绝不丢失既有绑定/密钥。
//

import Foundation
import Observation

@Observable
@MainActor
final class WorkerBindingsViewModel {

    private(set) var secrets:  [WorkerSecret] = []
    private(set) var settings: WorkerSettings?
    private(set) var loaded = false
    var isLoading = false
    var isSaving  = false
    var error: String?

    // 快速绑定用的可选资源（打开绑定选择器时惰性加载）
    private(set) var d1Databases:  [D1Database] = []
    private(set) var kvNamespaces: [KVNamespace] = []
    private(set) var r2Buckets:    [R2Bucket] = []
    private(set) var resourcesLoaded = false
    var loadingResources = false

    private let service:   WorkerService
    private let d1Service: D1Service
    private let kvService: KVService
    private let r2Service: R2Service
    let accountId:  String
    let scriptName: String

    init(
        service: WorkerService, d1Service: D1Service, kvService: KVService, r2Service: R2Service,
        accountId: String, scriptName: String
    ) {
        self.service    = service
        self.d1Service  = d1Service
        self.kvService  = kvService
        self.r2Service  = r2Service
        self.accountId  = accountId
        self.scriptName = scriptName
    }

    /// 环境变量（plain_text）
    var variables: [WorkerBinding] {
        (settings?.bindings ?? []).filter(\.isPlainText).sorted { $0.name < $1.name }
    }

    /// 其它只读绑定（KV / D1 / R2 / DO 等，非变量非密钥）
    var otherBindings: [WorkerBinding] {
        (settings?.bindings ?? []).filter { !$0.isPlainText && !$0.isSecret }.sorted { $0.name < $1.name }
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            async let secretsTask  = service.listSecrets(accountId: accountId, scriptName: scriptName)
            async let settingsTask = service.settings(accountId: accountId, scriptName: scriptName)
            secrets  = try await secretsTask
            settings = try await settingsTask
            loaded = true
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - 密钥

    func addSecret(name: String, text: String) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await service.putSecret(accountId: accountId, scriptName: scriptName, name: name, text: text)
            secrets = (try? await service.listSecrets(accountId: accountId, scriptName: scriptName)) ?? secrets
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func deleteSecret(_ secret: WorkerSecret) async {
        error = nil
        do {
            try await service.deleteSecret(accountId: accountId, scriptName: scriptName, name: secret.name)
            secrets.removeAll { $0.name == secret.name }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - 环境变量（PATCH settings，其余绑定 inherit）

    func setVariable(name: String, value: String) async -> Bool {
        guard let settings, !isSaving else { return false }
        isSaving = true
        error = nil
        defer { isSaving = false }
        var bindings = settings.inheritedBindings(excludingName: name)
        bindings.append(WorkerBindingInput(type: "plain_text", name: name, text: value))
        do {
            try await service.patchSettings(accountId: accountId, scriptName: scriptName, bindings: bindings, settings: settings)
            self.settings = try? await service.settings(accountId: accountId, scriptName: scriptName)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func deleteVariable(_ binding: WorkerBinding) async {
        guard let settings else { return }
        error = nil
        let bindings = settings.inheritedBindings(excludingName: binding.name)
        do {
            try await service.patchSettings(accountId: accountId, scriptName: scriptName, bindings: bindings, settings: settings)
            self.settings = try? await service.settings(accountId: accountId, scriptName: scriptName)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - 快速绑定 D1 / KV

    /// 打开绑定选择器时按需加载可选资源（各类型读权限缺失时静默跳过对应列表）
    func loadResources(canReadD1: Bool, canReadKV: Bool, canReadR2: Bool) async {
        guard !loadingResources else { return }
        loadingResources = true
        defer { loadingResources = false }
        if canReadD1 {
            d1Databases = (try? await d1Service.listDatabases(accountId: accountId)) ?? d1Databases
        }
        if canReadKV {
            kvNamespaces = (try? await kvService.listNamespaces(accountId: accountId)) ?? kvNamespaces
        }
        if canReadR2 {
            // 绑定只按桶名引用；区域限制桶的绑定还要带 jurisdiction 字段（本页不支持），
            // 只列默认辖区的桶，免得选了 EU / US 桶部署出一个指向错误辖区的绑定
            r2Buckets = (try? await r2Service.listBuckets(accountId: accountId))?
                .filter { $0.jurisdictionHeader == nil } ?? r2Buckets
        }
        resourcesLoaded = true
    }

    /// 已被本 Worker 绑定的绑定变量名（用于校验重名）
    var boundNames: Set<String> { Set((settings?.bindings ?? []).map(\.name)) }

    /// 绑定一个 D1 数据库 / KV 命名空间：新绑定为实体、其余绑定 inherit，单次 PATCH，原子保留既有。
    func bindResource(_ resource: WorkerBindingInput) async -> Bool {
        guard let settings, !isSaving else { return false }
        isSaving = true
        error = nil
        defer { isSaving = false }
        var bindings = settings.inheritedBindings(excludingName: resource.name)
        bindings.append(resource)
        do {
            try await service.patchSettings(accountId: accountId, scriptName: scriptName, bindings: bindings, settings: settings)
            self.settings = try? await service.settings(accountId: accountId, scriptName: scriptName)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// 解除某个 D1 / KV 绑定（其余绑定 inherit 回写）
    func unbindResource(_ binding: WorkerBinding) async {
        guard let settings else { return }
        error = nil
        let bindings = settings.inheritedBindings(excludingName: binding.name)
        do {
            try await service.patchSettings(accountId: accountId, scriptName: scriptName, bindings: bindings, settings: settings)
            self.settings = try? await service.settings(accountId: accountId, scriptName: scriptName)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - 批量导入（JSON）

    /// 批量导入变量（plain_text）：单次 PATCH，导入项设为实体、其余绑定 inherit，同名覆盖。原子。
    func bulkImportVariables(_ pairs: [(name: String, value: String)]) async -> Bool {
        guard let settings, !isSaving, !pairs.isEmpty else { return false }
        isSaving = true
        error = nil
        defer { isSaving = false }
        let importedNames = Set(pairs.map(\.name))
        var bindings = settings.bindings
            .filter { !importedNames.contains($0.name) }
            .map { $0.asInherit() }
        for pair in pairs {
            bindings.append(WorkerBindingInput(type: "plain_text", name: pair.name, text: pair.value))
        }
        do {
            try await service.patchSettings(accountId: accountId, scriptName: scriptName, bindings: bindings, settings: settings)
            self.settings = try? await service.settings(accountId: accountId, scriptName: scriptName)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// 批量导入密钥（secret_text）：走 secrets-bulk 端点单次 PATCH 原子生效，同名覆盖。
    /// 超过 100 项自动分批（每批各自原子）。
    func bulkImportSecrets(_ pairs: [(name: String, value: String)]) async -> Bool {
        guard !isSaving, !pairs.isEmpty else { return false }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            // secrets-bulk（2026-06 新端点）：单次 PATCH 原子生效，不再逐个 PUT（单次上限 100 项）
            for chunk in pairs.chunked(into: 100) {
                try await service.bulkPatchSecrets(
                    accountId: accountId, scriptName: scriptName,
                    upserts: chunk.map { (name: $0.name, text: $0.value) }
                )
            }
            secrets = (try? await service.listSecrets(accountId: accountId, scriptName: scriptName)) ?? secrets
            return true
        } catch {
            self.error = error.localizedDescription
            secrets = (try? await service.listSecrets(accountId: accountId, scriptName: scriptName)) ?? secrets
            return false
        }
    }
}

// MARK: - 分块工具（secrets-bulk 单次上限 100 项）

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
