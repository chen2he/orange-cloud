//
//  ZoneSettingsModels.swift
//  Orange Cloud
//
//  Zone 设置（security_level / development_mode）与缓存清理。
//

import Foundation

/// GET/PATCH /zones/{id}/settings/{setting} 的 result
nonisolated struct ZoneSetting: Codable, Sendable {
    let id:       String?
    let value:    String
    /// 当前套餐能否修改这项。套餐不够时照样读得到值，只是 editable == false、PATCH 一律 400
    let editable: Bool?
}

nonisolated struct ZoneSettingUpdate: Codable, Sendable {
    let value: String
}

/// POST /zones/{id}/purge_cache —— 全量清理
nonisolated struct PurgeRequest: Codable, Sendable {
    let purgeEverything: Bool

    enum CodingKeys: String, CodingKey {
        case purgeEverything = "purge_everything"
    }
}

/// POST /zones/{id}/purge_cache —— 按单文件 URL 清理
/// （2025-04 起所有套餐可用，单次最多 30 个 URL）
nonisolated struct PurgeFilesRequest: Codable, Sendable {
    let files: [String]
}

/// POST /zones/{id}/purge_cache —— 按 URL 前缀清理（如 example.com/news），2025-04 起所有套餐可用
nonisolated struct PurgePrefixesRequest: Codable, Sendable {
    let prefixes: [String]
}

/// POST /zones/{id}/purge_cache —— 按主机名清理（如 assets.example.com），2025-04 起所有套餐可用
nonisolated struct PurgeHostsRequest: Codable, Sendable {
    let hosts: [String]
}

/// POST /zones/{id}/purge_cache —— 按 Cache-Tag 清理，2025-04 起所有套餐可用
nonisolated struct PurgeTagsRequest: Codable, Sendable {
    let tags: [String]
}

nonisolated struct PurgeResult: Codable, Sendable {
    let id: String?
}
