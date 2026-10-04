//
//  ZoneSettingsService.swift
//  Orange Cloud
//
//  Zone 设置读写（Under Attack / 开发模式）+ 全量缓存清理。
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

    /// 清空该 Zone 在边缘的全部缓存
    func purgeAllCache(zoneId: String) async throws {
        let response: CFAPIResponse<PurgeResult> = try await client.post(
            "zones/\(zoneId)/purge_cache",
            body: PurgeRequest(purgeEverything: true)
        )
        guard response.success else {
            throw response.toAPIError()
        }
    }

    /// 按 URL 清理缓存（单文件 purge，单次最多 30 个 URL；2025-04 起所有套餐可用）
    func purgeFiles(zoneId: String, urls: [String]) async throws {
        let response: CFAPIResponse<PurgeResult> = try await client.post(
            "zones/\(zoneId)/purge_cache",
            body: PurgeFilesRequest(files: urls)
        )
        guard response.success else {
            throw response.toAPIError()
        }
    }

    /// 按 URL 前缀清理缓存（单次最多 30 个；2025-04 起所有套餐可用）
    func purgePrefixes(zoneId: String, prefixes: [String]) async throws {
        let response: CFAPIResponse<PurgeResult> = try await client.post(
            "zones/\(zoneId)/purge_cache",
            body: PurgePrefixesRequest(prefixes: prefixes)
        )
        guard response.success else {
            throw response.toAPIError()
        }
    }

    /// 按主机名清理缓存（单次最多 30 个；2025-04 起所有套餐可用）
    func purgeHosts(zoneId: String, hosts: [String]) async throws {
        let response: CFAPIResponse<PurgeResult> = try await client.post(
            "zones/\(zoneId)/purge_cache",
            body: PurgeHostsRequest(hosts: hosts)
        )
        guard response.success else {
            throw response.toAPIError()
        }
    }

    /// 按 Cache-Tag 清理缓存（单次最多 30 个；2025-04 起所有套餐可用）
    func purgeTags(zoneId: String, tags: [String]) async throws {
        let response: CFAPIResponse<PurgeResult> = try await client.post(
            "zones/\(zoneId)/purge_cache",
            body: PurgeTagsRequest(tags: tags)
        )
        guard response.success else {
            throw response.toAPIError()
        }
    }
}
