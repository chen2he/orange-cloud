//
//  ZoneSettingsService.swift
//  Orange Cloud
//
//  Zone 设置读写（Under Attack / 开发模式）+ 缓存清除 / 标记过期。
//

import Foundation

struct ZoneSettingsService {

    private let client: CFAPIClient

    init(client: CFAPIClient) {
        self.client = client
    }

    /// 读单项设置的当前值（如 security_level → "medium"，development_mode → "on"/"off"）
    func getSetting(zoneId: String, setting: String) async throws -> String {
        try await fetchSetting(zoneId: zoneId, setting: setting).value
    }

    /// 读单项设置的当前值；当前套餐不允许修改这项（editable == false）时返回 nil，调用方据此隐藏开关
    func getSettingIfEditable(zoneId: String, setting: String) async throws -> String? {
        let result = try await fetchSetting(zoneId: zoneId, setting: setting)
        return result.editable == false ? nil : result.value
    }

    private func fetchSetting(zoneId: String, setting: String) async throws -> ZoneSetting {
        let response: CFAPIResponse<ZoneSetting> = try await client.get(
            "zones/\(zoneId)/settings/\(setting)"
        )
        guard response.success, let result = response.result else {
            throw response.toAPIError()
        }
        return result
    }

    /// 写单项设置，返回生效后的值
    func setSetting(zoneId: String, setting: String, value: String) async throws -> String {
        let response: CFAPIResponse<ZoneSetting> = try await client.patch(
            "zones/\(zoneId)/settings/\(setting)",
            body: ZoneSettingUpdate(value: value)
        )
        guard response.success, let result = response.result else {
            throw response.toAPIError()
        }
        return result.value
    }

    /// 全部缓存：清除（purge_cache）或标记过期（invalidate_cache），请求体相同
    func purgeAllCache(zoneId: String, action: CacheClearAction = .purge) async throws {
        try await clearCache(zoneId: zoneId, action: action, body: PurgeRequest(purgeEverything: true))
    }

    /// 按 URL 清理 / 标记过期（单文件，单次最多 30 个 URL；2025-04 起所有套餐可用）
    func purgeFiles(zoneId: String, urls: [String], action: CacheClearAction = .purge) async throws {
        try await clearCache(zoneId: zoneId, action: action, body: PurgeFilesRequest(files: urls))
    }

    /// 按 URL 前缀清理 / 标记过期（单次最多 30 个；2025-04 起所有套餐可用）
    func purgePrefixes(zoneId: String, prefixes: [String], action: CacheClearAction = .purge) async throws {
        try await clearCache(zoneId: zoneId, action: action, body: PurgePrefixesRequest(prefixes: prefixes))
    }

    /// 按主机名清理 / 标记过期（单次最多 30 个；2025-04 起所有套餐可用）
    func purgeHosts(zoneId: String, hosts: [String], action: CacheClearAction = .purge) async throws {
        try await clearCache(zoneId: zoneId, action: action, body: PurgeHostsRequest(hosts: hosts))
    }

    /// 按 Cache-Tag 清理 / 标记过期（单次最多 30 个；2025-04 起所有套餐可用）
    func purgeTags(zoneId: String, tags: [String], action: CacheClearAction = .purge) async throws {
        try await clearCache(zoneId: zoneId, action: action, body: PurgeTagsRequest(tags: tags))
    }

    /// purge_cache / invalidate_cache 共用：只差端点名
    private func clearCache<B: Codable & Sendable>(zoneId: String, action: CacheClearAction, body: B) async throws {
        let response: CFAPIResponse<PurgeResult> = try await client.post(
            "zones/\(zoneId)/\(action.endpoint)",
            body: body
        )
        guard response.success else {
            throw response.toAPIError()
        }
    }
}
