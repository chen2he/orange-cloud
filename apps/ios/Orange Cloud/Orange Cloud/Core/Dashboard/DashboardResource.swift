//
//  DashboardResource.swift
//  Orange Cloud
//
//  概览页「跨类型资源」的统一视图模型：把域名 / Workers / R2 / D1 / KV / Tunnel
//  归一成同一种可搜索、可固定、可跳转的条目，供命令搜索面板、置顶区与告警中心共用。
//
//  路由一律走**值式** + 概览栈根的 `.navigationDestination`：
//  这些目的页内部还要继续 push（Worker 详情、R2 对象、D1 表…），
//  eager `NavigationLink(destination:)` 在 iOS 17.0 会整 App 冻结（见 DashboardView 注释）。
//

import Foundation
import SwiftData

/// 概览页可直接 push 的资源目的地（栈根 navdest 承接）。
/// 载荷是 SwiftData 模型 / 值模型，故本枚举跟随工程默认 MainActor 隔离，不标 nonisolated。
enum DashboardResourceRoute: Hashable, Identifiable {
    case zone(CachedZone)
    case worker(CachedWorkerScript)
    case bucket(R2Bucket)
    case database(D1Database)
    case namespace(KVNamespace)
    case tunnel(Tunnel)

    var id: String {
        switch self {
        case .zone(let zone):           "zone|\(zone.id)"
        case .worker(let script):       "worker|\(script.id)"
        case .bucket(let bucket):       "r2|\(bucket.id)"
        case .database(let database):   "d1|\(database.uuid)"
        case .namespace(let namespace): "kv|\(namespace.id)"
        case .tunnel(let tunnel):       "tunnel|\(tunnel.id)"
        }
    }

    /// 打开该资源所需的 Pro 场景；域名与 Workers 详情是免费功能，返回 nil。
    ///
    /// 口径与 Android 对齐：免费层**能搜到**全部资源（清单照拉、告警照出），
    /// 只在「点进去」这一步撞付费墙——所以闸门挂在跳转派发处，不挂在搜索结果行上
    /// （不标灰、不加锁图标，作者已拍板）。
    var proFeature: ProFeature? {
        switch self {
        case .zone, .worker:                 nil
        case .bucket, .database, .namespace: .storage
        case .tunnel:                        .tunnel
        }
    }
}

/// 归一化的资源条目：搜索面板、置顶区共用一行的数据
struct DashboardResourceItem: Identifiable, Hashable {

    /// 持久化标识（type + resourceId），星标直接拿它去 PinnedResourceStore 切换
    let pin: PinnedResource
    let title: String
    let subtitle: String
    let route: DashboardResourceRoute

    var id: String { pin.id }
    var type: PinnedResourceType { pin.type }

    /// 大小写不敏感匹配标题或副标题
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(query)
            || subtitle.localizedCaseInsensitiveContains(query)
    }
}

/// 由各数据源拼出统一条目列表（纯映射，无网络）
enum DashboardResourceCatalog {

    static func items(
        zones: [CachedZone],
        workers: [CachedWorkerScript],
        buckets: [R2Bucket],
        databases: [D1Database],
        namespaces: [KVNamespace],
        tunnels: [Tunnel]
    ) -> [DashboardResourceItem] {
        var items: [DashboardResourceItem] = []
        items.reserveCapacity(zones.count + workers.count + buckets.count + databases.count + namespaces.count + tunnels.count)

        for zone in zones {
            items.append(DashboardResourceItem(
                pin: PinnedResource(type: .zone, resourceId: zone.id),
                title: zone.name,
                subtitle: "\(planShort(zone.planName)) · \(zoneStatusText(zone.displayStatus))",
                route: .zone(zone)
            ))
        }
        for script in workers {
            items.append(DashboardResourceItem(
                pin: PinnedResource(type: .worker, resourceId: script.id),
                title: script.id,
                subtitle: script.handlers.isEmpty
                    ? String(localized: "Workers 脚本")
                    : script.handlers.joined(separator: " · "),
                route: .worker(script)
            ))
        }
        for bucket in buckets {
            // bucket.id：默认辖区即桶名（老置顶不受影响），区域限制桶为「辖区/桶名」，与同名默认桶区分
            let subtitle = bucket.location ?? String(localized: "R2 存储桶")
            items.append(DashboardResourceItem(
                pin: PinnedResource(type: .r2, resourceId: bucket.id),
                title: bucket.name,
                subtitle: bucket.jurisdictionBadge.map { "\($0) · \(subtitle)" } ?? subtitle,
                route: .bucket(bucket)
            ))
        }
        for database in databases {
            items.append(DashboardResourceItem(
                pin: PinnedResource(type: .d1, resourceId: database.uuid),
                title: database.name,
                subtitle: database.numTables.map { String(localized: "\($0) 张表") } ?? String(localized: "D1 数据库"),
                route: .database(database)
            ))
        }
        for namespace in namespaces {
            items.append(DashboardResourceItem(
                pin: PinnedResource(type: .kv, resourceId: namespace.id),
                title: namespace.title,
                subtitle: namespace.id,
                route: .namespace(namespace)
            ))
        }
        for tunnel in tunnels {
            items.append(DashboardResourceItem(
                pin: PinnedResource(type: .tunnel, resourceId: tunnel.id),
                title: tunnel.name,
                subtitle: tunnel.statusText,
                route: .tunnel(tunnel)
            ))
        }
        return items
    }

    /// 套餐取首词（"Free Website" → "Free"），与 DashboardZoneCard 口径一致
    static func planShort(_ planName: String) -> String {
        planName.components(separatedBy: " ").first ?? planName
    }

    /// 与 StatusDot / ZoneDetailView 同一组状态文案
    static func zoneStatusText(_ status: String) -> String {
        switch status {
        case "active":                  String(localized: "已启用")
        case "pending", "initializing": String(localized: "待激活")
        default:                        String(localized: "已暂停")
        }
    }
}
