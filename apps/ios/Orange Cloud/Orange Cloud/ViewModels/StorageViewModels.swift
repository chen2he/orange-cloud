//
//  StorageViewModels.swift
//  Orange Cloud
//
//  P2 存储模块的 ViewModel 集合。存储数据实时拉取，不进 SwiftData
//  （低频浏览场景，缓存收益低）。
//

import Foundation
import Observation
import UIKit

// MARK: - R2

@Observable
@MainActor
final class R2BucketListViewModel {

    var buckets: [R2Bucket] = []
    var usageByBucket: [String: R2BucketUsage] = [:]
    var isLoading = false
    var error: String?
    var isCreating = false
    var didCreate = false      // sensoryFeedback 触发器
    var isDeleting = false
    var didDelete = false      // sensoryFeedback 触发器

    private let service: R2Service
    private let analyticsService: AnalyticsService

    init(service: R2Service, analyticsService: AnalyticsService) {
        self.service = service
        self.analyticsService = analyticsService
    }

    /// 创建桶：成功后插到列表顶端，返回 true。
    func create(accountId: String, name: String, locationHint: String?, storageClass: String?) async -> Bool {
        guard !isCreating else { return false }
        isCreating = true
        error = nil
        defer { isCreating = false }
        do {
            let created = try await service.createBucket(
                accountId: accountId, name: name,
                locationHint: locationHint, storageClass: storageClass
            )
            buckets.insert(created, at: 0)
            didCreate.toggle()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// 删除桶：成功后从列表移除，返回 true。Cloudflare 要求桶为空，删除前须经二次确认。
    func delete(accountId: String, bucket: R2Bucket) async -> Bool {
        guard !isDeleting else { return false }
        isDeleting = true
        error = nil
        defer { isDeleting = false }
        do {
            try await service.deleteBucket(accountId: accountId, name: bucket.name)
            buckets.removeAll { $0.name == bucket.name }
            usageByBucket[bucket.name] = nil
            didDelete.toggle()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func load(accountId: String) async {
        isLoading = true
        error = nil
        do {
            buckets = try await service.listBuckets(accountId: accountId)
            isLoading = false
            // 用量 best-effort：免费账号账户级 GraphQL 常被 authz 挡，失败不影响桶列表
            usageByBucket = (try? await analyticsService.r2UsageByBucket(accountId: accountId)) ?? [:]
        } catch {
            // 切分段 / 离开页面取消的请求不算失败（.task(id: kind) 切换会取消飞行中的列表请求）
            if !error.isCancellation { self.error = error.localizedDescription }
            isLoading = false
        }
    }
}

@Observable
@MainActor
final class R2ObjectListViewModel {

    var objects: [R2Object] = []
    var folders: [R2Folder] = []
    var currentPrefix = ""
    var isLoading = false
    var isLoadingMore = false
    var error: String?
    private(set) var nextCursor: String?

    var hasMore: Bool { nextCursor != nil }
    var isContentEmpty: Bool { folders.isEmpty && objects.isEmpty }
    /// 导航标题：根层显示桶名，进文件夹后显示「桶名/当前前缀」
    var displayTitle: String {
        guard !currentPrefix.isEmpty else { return bucketName }
        return "\(bucketName)/\(currentPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
    }

    private let service: R2Service
    private let accountId: String
    let bucketName: String

    init(service: R2Service, accountId: String, bucketName: String) {
        self.service = service
        self.accountId = accountId
        self.bucketName = bucketName
    }

    /// 每次整页加载（进文件夹 / 返回上级 / 刷新）递增；晚到的旧一代结果一律丢弃。
    /// 以前点进一个慢文件夹再立刻返回，慢到的响应会把上级目录替换成子文件夹的内容与游标，
    /// 「加载更多」也接着翻错的目录。
    private var loadGeneration = 0

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        error = nil
        do {
            let page = try await service.listObjects(listOptions())
            guard generation == loadGeneration else { return }
            apply(page, reset: true)
        } catch {
            guard generation == loadGeneration, !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
        if generation == loadGeneration { isLoading = false }
    }

    func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore else { return }
        let generation = loadGeneration
        isLoadingMore = true
        // 旧一代提前 return 也必须复位：否则翻页途中换目录，isLoadingMore 永远卡在 true，本页再也翻不动
        defer { isLoadingMore = false }
        do {
            let page = try await service.listObjects(listOptions(cursor: cursor))
            guard generation == loadGeneration else { return }   // 期间已换目录 / 刷新：这页不属于当前列表
            apply(page, reset: false)
        } catch {
            guard generation == loadGeneration, !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    // MARK: - 文件夹导航

    func open(folder: R2Folder) async {
        guard currentPrefix != folder.prefix else { return }
        currentPrefix = folder.prefix
        await load()
    }

    func openParentFolder() async {
        guard !currentPrefix.isEmpty else { return }
        currentPrefix = R2Folder.parentPrefix(of: currentPrefix)
        await load()
    }

    private func listOptions(cursor: String? = nil) -> R2ObjectListOptions {
        R2ObjectListOptions(
            accountId: accountId,
            bucketName: bucketName,
            prefix: currentPrefix,
            cursor: cursor
        )
    }

    private func apply(_ page: R2ObjectPage, reset: Bool) {
        let pageFolders = R2Folder.makeList(from: page.folderPrefixes, parentPrefix: currentPrefix)
        folders = reset ? pageFolders : Self.mergedFolders(folders, pageFolders)
        objects = reset ? page.objects : objects + page.objects
        nextCursor = page.nextCursor
    }

    private static func mergedFolders(_ current: [R2Folder], _ incoming: [R2Folder]) -> [R2Folder] {
        Array(Set(current + incoming)).sorted { $0.prefix < $1.prefix }
    }

    // MARK: - 对象读写

    var isUploading = false
    var isDownloading = false
    var didUpload = false      // sensoryFeedback 触发器

    /// 下载对象到临时文件（QuickLook 预览用），文件名保留原始扩展名
    func downloadToTemp(object: R2Object) async -> URL? {
        guard !isDownloading else { return nil }
        isDownloading = true
        defer { isDownloading = false }
        do {
            let data = try await service.getObjectData(
                accountId: accountId, bucketName: bucketName, key: object.key
            )
            var filename = (object.key as NSString).lastPathComponent
            if filename.isEmpty { filename = "file" }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(filename)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url)
            return url
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// 上传成功后刷新首页列表。文件落到当前所在文件夹（currentPrefix）。
    func upload(data: Data, filename: String, contentType: String) async -> Bool {
        guard !isUploading else { return false }
        isUploading = true
        error = nil
        defer { isUploading = false }
        do {
            try await service.putObject(
                accountId: accountId, bucketName: bucketName,
                key: currentPrefix + filename, data: data, contentType: contentType
            )
            didUpload.toggle()
            await load()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// 删除成功后从列表移除
    func delete(key: String) async -> Bool {
        do {
            try await service.deleteObject(accountId: accountId, bucketName: bucketName, key: key)
            objects.removeAll { $0.key == key }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    // MARK: - 复制 / 移动（流式 + iOS 26 连续后台任务）

    var isTransferring = false
    var transferProgress: Double = 0
    var transferLabel: String?
    var didTransfer = false     // sensoryFeedback 触发器

    /// 是否可复制/移动：受 client/v4 单次 PUT ~300MB 上限约束
    func canTransfer(_ object: R2Object) -> Bool {
        (object.size ?? 0) <= R2Service.maxUploadBytes
    }

    /// 复制对象到 destinationKey（同桶，可含 / 表示文件夹）
    func copyObject(_ object: R2Object, to destinationKey: String) async -> Bool {
        let contentType = object.httpMetadata?.contentType ?? "application/octet-stream"
        return await runTransfer(object: object, label: String(localized: "复制中…")) { [service, accountId, bucketName] progress in
            try await service.copyObject(
                accountId: accountId, bucketName: bucketName,
                sourceKey: object.key, destinationKey: destinationKey,
                contentType: contentType, onProgress: progress
            )
        }
    }

    /// 移动 / 重命名对象到 destinationKey（同桶）
    func moveObject(_ object: R2Object, to destinationKey: String) async -> Bool {
        let contentType = object.httpMetadata?.contentType ?? "application/octet-stream"
        return await runTransfer(object: object, label: String(localized: "移动中…")) { [service, accountId, bucketName] progress in
            try await service.moveObject(
                accountId: accountId, bucketName: bucketName,
                sourceKey: object.key, destinationKey: destinationKey,
                contentType: contentType, onProgress: progress
            )
        }
    }

    /// 统一执行：iOS 26 且对象较大走系统连续后台任务（系统进度条 + 可取消），
    /// 否则前台执行并回报 transferProgress。提交失败自动回退前台。
    private func runTransfer(
        object: R2Object,
        label: String,
        operation: @escaping @Sendable (@escaping @Sendable (Double) -> Void) async throws -> Void
    ) async -> Bool {
        guard !isTransferring else { return false }
        guard canTransfer(object) else {
            error = String(localized: "对象超过 300 MB，受 Cloudflare API 限制无法在 App 内复制或移动")
            return false
        }
        isTransferring = true
        transferProgress = 0
        transferLabel = label
        error = nil
        defer { isTransferring = false; transferLabel = nil; transferProgress = 0 }

        let foreground: @Sendable (Double) -> Void = { fraction in
            Task { @MainActor in self.transferProgress = fraction }
        }
        do {
            if #available(iOS 26.0, *), (object.size ?? 0) > 8 * 1024 * 1024 {
                do {
                    try await ContinuedTaskRunner.run(title: label, subtitle: bucketName) { progress, _ in
                        try await operation(progress)
                    }
                } catch is ContinuedTaskRunner.SubmitFailed {
                    try await operation(foreground)     // 不支持 / 已有任务在跑 → 前台执行
                }
            } else {
                try await operation(foreground)
            }
            didTransfer.toggle()
            await load()
            return true
        } catch is CancellationError {
            return false
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

// MARK: - R2 桶设置（公开访问 / CORS）

@Observable
@MainActor
final class R2BucketSettingsViewModel {

    var managedDomain: R2ManagedDomain?
    var customDomains: [R2CustomDomain] = []
    var corsRules: [R2CorsRule] = []
    var isLoading = false
    var isSaving = false
    var error: String?
    var didChange = false      // sensoryFeedback 触发器

    private let service: R2Service
    private let accountId: String
    let bucketName: String

    init(service: R2Service, accountId: String, bucketName: String) {
        self.service = service
        self.accountId = accountId
        self.bucketName = bucketName
    }

    func load() async {
        isLoading = true
        error = nil
        // 三块各自 best-effort：某块不可用（如桶从未设过 CORS 回 404）不连累其余
        managedDomain = try? await service.managedDomain(accountId: accountId, bucketName: bucketName)
        customDomains = (try? await service.customDomains(accountId: accountId, bucketName: bucketName)) ?? []
        corsRules = ((try? await service.corsPolicy(accountId: accountId, bucketName: bucketName))?.rules) ?? []
        isLoading = false
    }

    func setManagedEnabled(_ enabled: Bool) async {
        await mutate {
            try await service.setManagedDomainEnabled(accountId: accountId, bucketName: bucketName, enabled: enabled)
            managedDomain = try? await service.managedDomain(accountId: accountId, bucketName: bucketName)
        }
    }

    func removeCustomDomain(_ domain: String) async {
        await mutate {
            try await service.removeCustomDomain(accountId: accountId, bucketName: bucketName, domain: domain)
            customDomains.removeAll { $0.domain == domain }
        }
    }

    /// 追加一条 CORS 规则（R2 是整组 PUT，回写现有 + 新规则）
    func addCorsRule(origins: [String], methods: [String], maxAgeSeconds: Int?) async {
        let rule = R2CorsRule(
            id: nil,
            allowed: R2CorsAllowed(methods: methods, origins: origins, headers: nil),
            exposeHeaders: nil,
            maxAgeSeconds: maxAgeSeconds
        )
        await mutate {
            let next = corsRules + [rule]
            try await service.putCorsPolicy(accountId: accountId, bucketName: bucketName, policy: R2CorsPolicy(rules: next))
            corsRules = next
        }
    }

    func deleteCorsRule(at index: Int) async {
        guard corsRules.indices.contains(index) else { return }
        var next = corsRules
        next.remove(at: index)
        await mutate {
            if next.isEmpty {
                try await service.deleteCorsPolicy(accountId: accountId, bucketName: bucketName)
            } else {
                try await service.putCorsPolicy(accountId: accountId, bucketName: bucketName, policy: R2CorsPolicy(rules: next))
            }
            corsRules = next
        }
    }

    func clearCors() async {
        await mutate {
            try await service.deleteCorsPolicy(accountId: accountId, bucketName: bucketName)
            corsRules = []
        }
    }

    private func mutate(_ body: () async throws -> Void) async {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await body()
            didChange.toggle()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - D1

@Observable
@MainActor
final class D1DatabaseListViewModel {

    var databases: [D1Database] = []
    var isLoading = false
    var error: String?
    var isCreating = false
    var didCreate = false      // sensoryFeedback 触发器
    var isDeleting = false
    var didDelete = false      // sensoryFeedback 触发器

    private let service: D1Service

    init(service: D1Service) {
        self.service = service
    }

    /// 创建数据库：成功后把新库插到列表顶端（新库为空，无需回填详情），返回 true。
    func create(accountId: String, name: String, locationHint: String?) async -> Bool {
        guard !isCreating else { return false }
        isCreating = true
        error = nil
        defer { isCreating = false }
        do {
            let created = try await service.createDatabase(
                accountId: accountId, name: name, locationHint: locationHint
            )
            databases.insert(created, at: 0)
            didCreate.toggle()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// 删除数据库：成功后从列表移除，返回 true。不可恢复，调用前须经二次确认。
    func delete(accountId: String, database: D1Database) async -> Bool {
        guard !isDeleting else { return false }
        isDeleting = true
        error = nil
        defer { isDeleting = false }
        do {
            try await service.deleteDatabase(accountId: accountId, databaseId: database.uuid)
            databases.removeAll { $0.uuid == database.uuid }
            didDelete.toggle()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func load(accountId: String) async {
        isLoading = true
        error = nil
        do {
            let list = try await service.listDatabases(accountId: accountId)
            // 先上列表让行立即可见，再并发拉详情回填表数量与体积
            databases = list
            isLoading = false

            let service = self.service
            let details = await withTaskGroup(of: D1Database?.self) { group in
                for database in list {
                    group.addTask {
                        try? await service.getDatabase(accountId: accountId, databaseId: database.uuid)
                    }
                }
                var byId: [String: D1Database] = [:]
                for await detail in group {
                    if let detail { byId[detail.uuid] = detail }
                }
                return byId
            }
            if !details.isEmpty {
                databases = list.map { details[$0.uuid] ?? $0 }
            }
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
            isLoading = false
        }
    }
}

@Observable
@MainActor
final class D1QueryViewModel {

    var sql = "SELECT name FROM sqlite_master WHERE type='table';"
    var results: [D1QueryResult] = []
    var isRunning = false
    var error: String?
    var didRun = false      // sensoryFeedback 触发器

    /// 结果驻留封顶：单条语句只保留前 maxStoredRows 行（大结果集整包驻留内存
    /// 是概览 hang / 内存告警的源头），原始行数记在 originalRowCounts 供提示
    static let maxStoredRows = 500
    private(set) var originalRowCounts: [Int] = []

    /// SELECT / WITH 且不带 LIMIT：执行前提醒可能返回大量行
    var needsLimitReminder: Bool {
        let statement = sql.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard statement.hasPrefix("select") || statement.hasPrefix("with") else { return false }
        return statement.range(of: #"\blimit\b"#, options: .regularExpression) == nil
    }

    /// 数据库内的用户表（排除 sqlite_* 与 D1 内部表）
    private(set) var tables: [String] = []
    private(set) var tablesLoaded = false

    private let service: D1Service
    private let accountId: String
    private let databaseId: String

    init(service: D1Service, accountId: String, databaseId: String) {
        self.service = service
        self.accountId = accountId
        self.databaseId = databaseId
    }

    func loadTables() async {
        guard !tablesLoaded else { return }
        let sql = """
        SELECT name FROM sqlite_master \
        WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' \
        ORDER BY name
        """
        guard let results = try? await service.query(accountId: accountId, databaseId: databaseId, sql: sql) else { return }
        tables = (results.first?.results ?? []).compactMap { row in
            if case .string(let name) = row["name"] { return name }
            return nil
        }
        tablesLoaded = true
    }

    func run() async {
        let statement = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !statement.isEmpty, !isRunning else { return }
        isRunning = true
        error = nil
        do {
            let raw = try await service.query(accountId: accountId, databaseId: databaseId, sql: statement)
            originalRowCounts = raw.map { $0.results?.count ?? 0 }
            results = raw.map { result in
                guard let rows = result.results, rows.count > Self.maxStoredRows else { return result }
                return D1QueryResult(
                    results: Array(rows.prefix(Self.maxStoredRows)),
                    success: result.success,
                    meta: result.meta
                )
            }
            didRun.toggle()
        } catch {
            self.error = error.localizedDescription
            results = []
            originalRowCounts = []
        }
        isRunning = false
    }

    // MARK: - 删表（DROP TABLE）

    var isDroppingTable = false
    var dropError: String?

    /// 标识符加引号并转义内部双引号，防 SQL 注入（对齐 D1TableViewModel.quoted）
    private func quoted(_ identifier: String) -> String {
        "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// DROP TABLE：删除整张表及其全部数据（d1.write 门控，标识符加引号防注入）
    func dropTable(_ name: String) async -> Bool {
        guard !isDroppingTable else { return false }
        isDroppingTable = true
        dropError = nil
        defer { isDroppingTable = false }
        do {
            _ = try await service.query(accountId: accountId, databaseId: databaseId, sql: "DROP TABLE IF EXISTS \(quoted(name))")
            tables.removeAll { $0 == name }
            return true
        } catch {
            dropError = error.localizedDescription
            return false
        }
    }
}

@Observable
@MainActor
final class D1TableViewModel {

    private(set) var columns: [D1Column] = []
    private(set) var rows: [[String: JSONValue]] = []
    private(set) var hasMore = false
    /// 各列展示宽度（首页数据采样一次算定，懒加载行直接用定宽保证列对齐）
    private(set) var columnWidths: [String: CGFloat] = [:]
    var isLoading = false
    var isSaving = false
    var error: String?
    var didSave = false

    /// 行编辑用的 rowid 键（别名避免与同名列冲突）
    static let rowidKey = "_oc_rowid_"
    /// 单元格取数截断长度：分页 SQL 里 substr 只取前 cellLimit+1 个字符，
    /// 防大 TEXT/BLOB 字段拖爆网络包 / JSON 解码内存 / CoreText 排版（主线程 hang 源）
    static let cellLimit = 256
    /// 已加载行数上限：到顶停止翻页，引导用查询控制台加 WHERE 筛选
    static let maxLoadedRows = 1000

    var reachedCap: Bool { rows.count >= Self.maxLoadedRows }

    private var offset = 0
    private let pageSize = 50
    private let service: D1Service
    private let accountId: String
    private let databaseId: String
    let tableName: String

    init(service: D1Service, accountId: String, databaseId: String, tableName: String) {
        self.service = service
        self.accountId = accountId
        self.databaseId = databaseId
        self.tableName = tableName
    }

    private var quotedTable: String {
        "\"" + tableName.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func quoted(_ identifier: String) -> String {
        "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// 整页重载递增；飞行中的「加载更多」若跨过一次重载，其结果不能再 append（会重复行并让 offset 跳页）。
    private var loadGeneration = 0

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        error = nil
        do {
            if columns.isEmpty {
                let info = try await service.query(
                    accountId: accountId, databaseId: databaseId,
                    sql: "PRAGMA table_info(\(quotedTable))"
                )
                columns = (info.first?.results ?? []).compactMap { row in
                    guard case .string(let name) = row["name"] else { return nil }
                    let type = row["type"]?.displayText ?? ""
                    let pk = (row["pk"]?.displayText ?? "0") != "0"
                    return D1Column(name: name, type: type, isPrimaryKey: pk)
                }
            }
            let first = try await fetchPage(offset: 0)
            guard generation == loadGeneration else { return }
            offset = 0
            rows = first
            computeColumnWidths()
        } catch {
            guard generation == loadGeneration, !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
        if generation == loadGeneration { isLoading = false }
    }

    func loadMore() async {
        guard hasMore, !isLoading, !reachedCap else { return }
        let generation = loadGeneration
        isLoading = true
        do {
            // 先取下一页，成功后再推进 offset；否则瞬时失败会永久跳过这一页
            let next = try await fetchPage(offset: offset + pageSize)
            guard generation == loadGeneration else { return }
            offset += pageSize
            rows.append(contentsOf: next)
        } catch {
            guard generation == loadGeneration, !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
        if generation == loadGeneration { isLoading = false }
    }

    private func fetchPage(offset: Int) async throws -> [[String: JSONValue]] {
        // 多取 1 行用于判断是否还有下一页
        let sql = "SELECT rowid AS \(Self.rowidKey), \(projection) FROM \(quotedTable) LIMIT \(pageSize + 1) OFFSET \(offset)"
        let results = try await service.query(accountId: accountId, databaseId: databaseId, sql: sql)
        var page = results.first?.results ?? []
        hasMore = page.count > pageSize
        if hasMore { page.removeLast() }
        return page
    }

    /// 分页查询的列投影：TEXT/BLOB 亲和列只取前 cellLimit+1 个字符（+1 用于判断
    /// 原值是否更长），数值/时间列取原值。完整值在行编辑时按 rowid 单独取。
    private var projection: String {
        guard !columns.isEmpty else { return "*" }
        return columns.map { column in
            let q = quoted(column.name)
            return Self.isTruncatable(declaredType: column.type)
                ? "substr(\(q), 1, \(Self.cellLimit + 1)) AS \(q)"
                : q
        }.joined(separator: ", ")
    }

    /// 数值/布尔/时间列值天然短，取原值；TEXT / BLOB / 无声明类型才截断
    nonisolated static func isTruncatable(declaredType: String) -> Bool {
        let type = declaredType.uppercased()
        if type.contains("INT") || type.contains("REAL") || type.contains("FLOA")
            || type.contains("DOUB") || type.contains("DEC") || type.contains("NUM")
            || type.contains("BOOL") || type.contains("DATE") || type.contains("TIME") {
            return false
        }
        return true
    }

    /// 单元格展示文本（含截断省略号），列表与列宽测量共用同一口径
    nonisolated static func displayText(for value: JSONValue?) -> String {
        guard let value else { return "NULL" }
        if case .null = value { return "NULL" }
        let text = value.displayText
        if text.count > cellLimit { return String(text.prefix(cellLimit)) + "…" }
        return text.isEmpty ? "''" : text
    }

    /// 行编辑前取整行完整值（列表里大字段是截断的）。无截断单元格直接复用当前行，
    /// 免一次网络往返；取失败置 error 并返回 nil。
    func fullRow(from row: [String: JSONValue]) async -> [String: JSONValue]? {
        let hasTruncated = row.values.contains { value in
            if case .string(let text) = value { return text.count > Self.cellLimit }
            return false
        }
        guard hasTruncated, let rowid = row[Self.rowidKey]?.displayText, !rowid.isEmpty else {
            return row
        }
        error = nil
        do {
            let results = try await service.query(
                accountId: accountId, databaseId: databaseId,
                sql: "SELECT rowid AS \(Self.rowidKey), * FROM \(quotedTable) WHERE rowid = ?",
                params: [rowid]
            )
            return results.first?.results?.first ?? row
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// 列宽 = 表头与首页采样行的理想宽度取大，夹在 44...180pt；只在首次加载后算一次
    private func computeColumnWidths() {
        let size = UIFont.preferredFont(forTextStyle: .caption1).pointSize
        let cellFont = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let headerFont = UIFont.systemFont(ofSize: size, weight: .bold)
        var widths: [String: CGFloat] = [:]
        for column in columns {
            // 主键列头多一个钥匙图标的余量
            var maxWidth = (column.name as NSString)
                .size(withAttributes: [.font: headerFont]).width + (column.isPrimaryKey ? 14 : 0)
            for row in rows.prefix(50) {
                let text = Self.displayText(for: row[column.name])
                let width = (text as NSString).size(withAttributes: [.font: cellFont]).width
                if width > maxWidth { maxWidth = width }
                if maxWidth >= 180 { break }
            }
            widths[column.name] = min(180, max(44, ceil(maxWidth)))
        }
        columnWidths = widths
    }

    /// 仅更新变更列（参数化，rowid 定位）。成功返回 true 并重载当前数据。
    func updateRow(rowid: String, changes: [String: String]) async -> Bool {
        guard !changes.isEmpty, !isSaving else { return changes.isEmpty }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let assignments = changes.keys.map { "\(quoted($0)) = ?" }.joined(separator: ", ")
            let sql = "UPDATE \(quotedTable) SET \(assignments) WHERE rowid = ?"
            let params = changes.keys.map { changes[$0]! } + [rowid]
            _ = try await service.query(accountId: accountId, databaseId: databaseId, sql: sql, params: params)
            didSave.toggle()
            await load()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func deleteRow(rowid: String) async -> Bool {
        error = nil
        do {
            _ = try await service.query(
                accountId: accountId, databaseId: databaseId,
                sql: "DELETE FROM \(quotedTable) WHERE rowid = ?",
                params: [rowid]
            )
            await load()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

// MARK: - KV

@Observable
@MainActor
final class KVNamespaceListViewModel {

    var namespaces: [KVNamespace] = []
    var isLoading = false
    var error: String?
    var isCreating = false
    var didCreate = false      // sensoryFeedback 触发器
    var isDeleting = false
    var didDelete = false      // sensoryFeedback 触发器

    private let service: KVService

    init(service: KVService) {
        self.service = service
    }

    /// 创建命名空间：成功后插到列表顶端，返回 true。
    func create(accountId: String, title: String) async -> Bool {
        guard !isCreating else { return false }
        isCreating = true
        error = nil
        defer { isCreating = false }
        do {
            let created = try await service.createNamespace(accountId: accountId, title: title)
            namespaces.insert(created, at: 0)
            didCreate.toggle()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// 删除命名空间：成功后从列表移除，返回 true。连同全部键值不可恢复，删除前须经二次确认。
    func delete(accountId: String, namespace: KVNamespace) async -> Bool {
        guard !isDeleting else { return false }
        isDeleting = true
        error = nil
        defer { isDeleting = false }
        do {
            try await service.deleteNamespace(accountId: accountId, namespaceId: namespace.id)
            namespaces.removeAll { $0.id == namespace.id }
            didDelete.toggle()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func load(accountId: String) async {
        isLoading = true
        error = nil
        do {
            namespaces = try await service.listNamespaces(accountId: accountId)
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
        }
        isLoading = false
    }
}

@Observable
@MainActor
final class KVKeyListViewModel {

    var keys: [KVKey] = []
    var isLoading = false
    var isLoadingMore = false
    var error: String?
    private(set) var nextCursor: String?

    var hasMore: Bool { nextCursor != nil }

    private let service: KVService
    private let accountId: String
    private let namespaceId: String
    /// 进行中的加载任务（见 ZoneListViewModel：独立 Task 承载加载，避免下拉手势取消导致 .cancelled 误报）
    private var loadTask: Task<Void, Never>?

    init(service: KVService, accountId: String, namespaceId: String) {
        self.service = service
        self.accountId = accountId
        self.namespaceId = namespaceId
    }

    func load() async {
        // 复用进行中的加载，并把网络加载放进独立 Task：下拉手势 / searchable 取消
        // .refreshable 子任务时不波及加载，避免 URLError.cancelled 误报为加载失败
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.fetchKeys()
        }
        loadTask = task
        defer { loadTask = nil }
        await task.value
    }

    /// 每次整页刷新递增；刷新期间还在飞的「加载更多」据此丢弃，
    /// 否则旧游标的下一页会被追加到刷新后的第一页后面（键重复、游标错乱）。
    private var loadGeneration = 0

    private func fetchKeys() async {
        loadGeneration += 1
        isLoading = true
        error = nil
        do {
            let page = try await service.listKeys(accountId: accountId, namespaceId: namespaceId)
            keys = page.keys
            nextCursor = page.nextCursor
        } catch is CancellationError {
            // 任务取消属正常生命周期，不算加载失败
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession 把任务取消转成 .cancelled，同样不展示为错误
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore, !isLoading else { return }
        let generation = loadGeneration
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await service.listKeys(accountId: accountId, namespaceId: namespaceId, cursor: cursor)
            guard generation == loadGeneration else { return }
            keys.append(contentsOf: page.keys)
            nextCursor = page.nextCursor
        } catch {
            guard generation == loadGeneration, !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    /// 删除成功返回 true 并从列表移除
    func delete(key: String) async -> Bool {
        do {
            try await service.deleteKey(accountId: accountId, namespaceId: namespaceId, key: key)
            keys.removeAll { $0.name == key }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

@Observable
@MainActor
final class KVValueViewModel {

    var valueText = ""
    var isBinary = false
    var byteCount = 0
    var isLoading = false
    var isSaving = false
    var error: String?
    var didSave = false     // sensoryFeedback 触发器

    private let service: KVService
    private let accountId: String
    private let namespaceId: String
    let key: String

    init(service: KVService, accountId: String, namespaceId: String, key: String) {
        self.service = service
        self.accountId = accountId
        self.namespaceId = namespaceId
        self.key = key
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            let data = try await service.getValue(accountId: accountId, namespaceId: namespaceId, key: key)
            byteCount = data.count
            if let text = String(data: data, encoding: .utf8) {
                valueText = text
                isBinary = false
            } else {
                valueText = ""
                isBinary = true
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// 保存成功返回 true
    func save() async -> Bool {
        guard !isBinary, !isSaving else { return false }
        isSaving = true
        error = nil
        do {
            try await service.putValue(accountId: accountId, namespaceId: namespaceId, key: key, value: valueText)
            byteCount = valueText.utf8.count
            didSave.toggle()
            isSaving = false
            return true
        } catch {
            self.error = error.localizedDescription
            isSaving = false
            return false
        }
    }
}
