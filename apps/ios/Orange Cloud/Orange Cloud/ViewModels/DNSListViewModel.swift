//
//  DNSListViewModel.swift
//  Orange Cloud
//
//  DNS 记录的拉取与增删改，全部同步进 SwiftData 缓存。
//

import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class DNSListViewModel {

    var isLoading = false
    var isSaving  = false
    var error: String?
    var didSave = false      // sensoryFeedback 触发器

    private let dnsService: DNSService
    private let zoneId: String
    private let zoneName: String
    /// 进行中的加载任务（见 ZoneListViewModel：独立 Task 承载加载，避免下拉手势取消导致 .cancelled 误报）
    private var loadTask: Task<Void, Never>?

    init(dnsService: DNSService, zoneId: String, zoneName: String = "") {
        self.dnsService = dnsService
        self.zoneId = zoneId
        self.zoneName = zoneName
    }

    func refresh(context: ModelContext, force: Bool = false) async {
        // 非强制（首屏/切 Tab）且缓存仍新鲜：用缓存（@Query 已渲染），不重发请求
        if !force, CachePolicy.dnsFresh(zoneId: zoneId, context: context) { return }
        // 复用进行中的加载，并把网络加载放进独立 Task：下拉手势 / searchable 取消
        // .refreshable 子任务时不波及加载，避免 URLError.cancelled 误报为加载失败
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.load(context: context)
        }
        loadTask = task
        defer { loadTask = nil }
        await task.value
    }

    private func load(context: ModelContext) async {
        isLoading = true
        error = nil
        do {
            let records = try await dnsService.listRecords(zoneId: zoneId)
            sync(records: records, context: context)
            SpotlightIndexer.indexDNSRecords(records, zoneId: zoneId, zoneName: zoneName)
        } catch is CancellationError {
            // 任务取消属正常生命周期，不算加载失败
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession 把任务取消转成 .cancelled，同样不展示为错误
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// 新建或更新记录；recordId == nil 表示新建。成功返回 true。
    func save(recordId: String?, record: CreateDNSRecord, context: ModelContext) async -> Bool {
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let saved: DNSRecord
            if let recordId {
                saved = try await dnsService.updateRecord(zoneId: zoneId, recordId: recordId, record: record)
            } else {
                saved = try await dnsService.createRecord(zoneId: zoneId, record: record)
            }
            upsert(saved, context: context)
            didSave.toggle()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    // MARK: - 设备端 AI 生成（自然语言 → 结构化 → 记录草稿）

    var isGenerating = false
    var generationError: String?

    /// 用自然语言生成一条记录草稿；失败时写入 generationError 并返回 nil。
    func generateRecord(from naturalLanguage: String, locale: Locale = .current) async -> GeneratedDNSRecord? {
        let trimmed = naturalLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return nil }
        isGenerating = true
        generationError = nil
        defer { isGenerating = false }
        do {
            return try await DNSAssistant.generateRecord(from: trimmed, locale: locale)
        } catch {
            generationError = error.localizedDescription
            return nil
        }
    }

    func delete(recordId: String, context: ModelContext) async {
        error = nil
        do {
            try await dnsService.deleteRecord(zoneId: zoneId, recordId: recordId)
            SafeCache.perform("DNS 缓存删除") {
                let descriptor = FetchDescriptor<CachedDNSRecord>(
                    predicate: #Predicate { $0.id == recordId }
                )
                for cached in try context.fetch(descriptor) {
                    context.delete(cached)
                }
                try context.save()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - 缓存同步（写失败静默放弃：API 数据已在手，UI 不受影响）

    private func sync(records: [DNSRecord], context: ModelContext) {
        let zoneId = self.zoneId
        SafeCache.perform("DNS 缓存同步") {
            let descriptor = FetchDescriptor<CachedDNSRecord>(
                predicate: #Predicate { $0.zoneId == zoneId }
            )
            let existing = try context.fetch(descriptor)
            let fetchedIDs = Set(records.map(\.id))

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
            for record in records {
                if let cached = existingByID[record.id] {
                    cached.update(from: record)
                } else {
                    context.insert(CachedDNSRecord(from: record, zoneId: zoneId))
                }
            }
            try context.save()
        }
    }

    private func upsert(_ record: DNSRecord, context: ModelContext) {
        let recordId = record.id
        SafeCache.perform("DNS 缓存 upsert") {
            let descriptor = FetchDescriptor<CachedDNSRecord>(
                predicate: #Predicate { $0.id == recordId }
            )
            if let cached = try context.fetch(descriptor).first {
                cached.update(from: record)
            } else {
                context.insert(CachedDNSRecord(from: record, zoneId: zoneId))
            }
            try context.save()
        }
    }
}
