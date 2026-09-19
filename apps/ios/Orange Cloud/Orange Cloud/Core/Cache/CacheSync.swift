//
//  CacheSync.swift
//  Orange Cloud
//
//  Zone / Worker 列表 → SwiftData 缓存的共享同步逻辑。
//  Dashboard 首屏与各列表页都会拉取同一份数据，这里收口避免两份 upsert 代码。
//

import Foundation
import SwiftData
import WidgetKit

@MainActor
enum CacheSync {

    /// Zone 列表 upsert 进缓存（删掉远端已不存在的条目），
    /// 并同步主屏 Widget 快照与 Spotlight 索引。
    /// 缓存写失败（含 iOS 17.x 的 CoreData NSException）静默放弃：数据已在手，UI 不受影响。
    static func syncZones(_ zones: [Zone], accountId: String, accountName: String, context: ModelContext) {
        SafeCache.perform("syncZones") {
            // 仅在当前账号范围内 upsert：删除远端已不存在的条目时不能波及其它账号的缓存，
            // 否则切换账号会清空别的账号的域名（连带丢失它们的 pinned 状态）。
            let predicate = #Predicate<CachedZone> { $0.accountId == accountId }
            let existing = try context.fetch(FetchDescriptor<CachedZone>(predicate: predicate))
            let fetchedIDs = Set(zones.map(\.id))

            for cached in existing where !fetchedIDs.contains(cached.id) {
                context.delete(cached)
            }
            // 去掉 @Attribute(.unique) 后唯一性只是尽力而为：同 id 的重复行（前台 save 失败残留 + 后台
            // 另一个 ModelContext 写入）会让 uniqueKeysWithValues 直接 fatalError，且每次启动必崩。
            // 撞上就把多余的那行删掉，留第一行。
            let existingByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, duplicate in
                context.delete(duplicate)
                return first
            })
            for zone in zones {
                if let cached = existingByID[zone.id] {
                    cached.update(from: zone)
                } else {
                    context.insert(CachedZone(from: zone, accountId: accountId))
                }
            }
            try context.save()
        }

        WidgetSnapshot(
            accountId: accountId,
            accountName: accountName,
            totalZones: zones.count,
            activeZones: zones.filter { $0.status == "active" }.count,
            updatedAt: Date()
        ).save()
        WidgetCenter.shared.reloadTimelines(ofKind: "ZoneStatusWidget")

        SpotlightIndexer.indexZones(zones)
    }

    /// Worker 脚本列表 upsert 进缓存（仅限当前账号）；写失败静默放弃（同上）。
    static func syncWorkers(_ scripts: [WorkerScript], accountId: String, context: ModelContext) {
        SafeCache.perform("syncWorkers") {
            let predicate = #Predicate<CachedWorkerScript> { $0.accountId == accountId }
            let existing = try context.fetch(FetchDescriptor<CachedWorkerScript>(predicate: predicate))
            let fetchedIDs = Set(scripts.map(\.id))

            for cached in existing where !fetchedIDs.contains(cached.id) {
                context.delete(cached)
            }
            // 去掉 @Attribute(.unique) 后唯一性只是尽力而为：同 id 的重复行（前台 save 失败残留 + 后台
            // 另一个 ModelContext 写入）会让 uniqueKeysWithValues 直接 fatalError，且每次启动必崩。
            // 撞上就把多余的那行删掉，留第一行。
            let existingByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, duplicate in
                context.delete(duplicate)
                return first
            })
            for script in scripts {
                if let cached = existingByID[script.id] {
                    cached.update(from: script)
                } else {
                    context.insert(CachedWorkerScript(from: script, accountId: accountId))
                }
            }
            try context.save()
        }
    }
}
