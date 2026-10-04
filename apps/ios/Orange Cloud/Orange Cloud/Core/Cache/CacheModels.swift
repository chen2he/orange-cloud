//
//  CacheModels.swift
//  Orange Cloud
//
//  SwiftData 本地缓存：View 通过 @Query 读取，ViewModel 刷新 API 后写入，离线可读。
//
//  唯一性由各 upsert 路径（先按 id/key fetch，再 update-or-insert）在代码层保证——
//  **不要**用 @Attribute(.unique)：该约束在部分 iOS 17.0 设备上会让 SwiftData 建容器即
//  报 SwiftDataError、并在 @Query 读 / 写入时硬崩（do/catch 接不住）。1.3.2 build 13 实测坐实。
//

import Foundation
import SwiftData

@Model
final class CachedZone {
    var id: String
    var name:        String
    var status:      String
    var planName:    String
    var nameServers: [String]
    var accountId:   String
    var updatedAt:   Date
    var pinned:      Bool = false    // 固定到 Dashboard 首页（用户手动控制，刷新不重置）
    // DNS 记录总数（Dashboard 轻量 total_count 回写 / 详情页兜底拉取），nil = 尚未统计。
    // 可选新增字段走轻量迁移；detail 页首屏优先读它，避免默认显示 0 条。
    var dnsRecordCount: Int?
    // 是否暂停 Cloudflare 代理。API 里与 status 正交（暂停时 status 仍是 active），
    // 展示状态一律读 displayStatus，别直接读 status。默认值走轻量迁移。
    var paused: Bool = false

    init(from zone: Zone, accountId: String) {
        self.id          = zone.id
        self.name        = zone.name
        self.status      = zone.status
        self.planName    = zone.plan?.name ?? "—"
        self.nameServers = zone.nameServers ?? []
        self.accountId   = accountId
        self.updatedAt   = Date()
        self.paused      = zone.paused ?? false
    }

    func update(from zone: Zone) {
        name        = zone.name
        status      = zone.status
        planName    = zone.plan?.name ?? "—"
        nameServers = zone.nameServers ?? []
        paused      = zone.paused ?? false
        updatedAt   = Date()
    }

    /// 对外展示用状态：暂停优先于 status（Cloudflare 暂停时 status 仍报 active）
    var displayStatus: String { paused ? "paused" : status }
}

@Model
final class CachedWorkerScript {
    // 脚本名只在账号内唯一，全局唯一键用 accountId/scriptId 复合（代码层 upsert 去重）
    var key: String
    var id:         String          // 脚本名
    var accountId:  String
    var createdOn:  String?
    var modifiedOn: String?
    var usageModel: String?
    var handlers:   [String]
    var logpush:    Bool
    var updatedAt:  Date

    init(from script: WorkerScript, accountId: String) {
        self.key        = "\(accountId)/\(script.id)"
        self.id         = script.id
        self.accountId  = accountId
        self.createdOn  = script.createdOn
        self.modifiedOn = script.modifiedOn
        self.usageModel = script.usageModel
        self.handlers   = script.handlers ?? []
        self.logpush    = script.logpush ?? false
        self.updatedAt  = Date()
    }

    func update(from script: WorkerScript) {
        createdOn  = script.createdOn
        modifiedOn = script.modifiedOn
        usageModel = script.usageModel
        handlers   = script.handlers ?? []
        logpush    = script.logpush ?? false
        updatedAt  = Date()
    }
}

@Model
final class CachedDNSRecord {
    var id: String
    var type:      String
    var name:      String
    var content:   String
    var proxied:   Bool
    var ttl:       Int
    var priority:  Int?
    var comment:   String?
    var zoneId:    String
    var updatedAt: Date
    // 遮蔽信息（列表带 include_shadow_metadata=true 时回写）。带默认值的新增字段走轻量迁移，
    // 与 CachedZone.paused 同做法；老缓存在下次刷新前按「未遮蔽」显示。
    /// 该名称已被 NS 委派遮蔽，Cloudflare 不会响应这条记录
    var isShadowed: Bool = false
    /// NS 委派记录遮蔽了多少条记录
    var shadowedRecordsCount: Int = 0

    init(from record: DNSRecord, zoneId: String) {
        self.id        = record.id
        self.type      = record.type
        self.name      = record.name
        self.content   = record.content
        self.proxied   = record.isProxied
        self.ttl       = record.ttl
        self.priority  = record.priority
        self.comment   = record.comment
        self.zoneId    = zoneId
        self.updatedAt = Date()
        self.isShadowed = record.isShadowed
        self.shadowedRecordsCount = record.shadowedRecordsCount
    }

    /// includesShadowMetadata：列表刷新（带 include_shadow_metadata）时为 true，以响应为准覆盖；
    /// 单条增改（POST/PUT 响应）不带遮蔽信息，保留已知值，等下次列表刷新再校准。
    func update(from record: DNSRecord, includesShadowMetadata: Bool = false) {
        type      = record.type
        name      = record.name
        content   = record.content
        proxied   = record.isProxied
        ttl       = record.ttl
        priority  = record.priority
        comment   = record.comment
        updatedAt = Date()
        if includesShadowMetadata {
            isShadowed = record.isShadowed
            shadowedRecordsCount = record.shadowedRecordsCount
        }
    }
}
