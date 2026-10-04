//
//  WorkerIssuesViewModel.swift
//  Orange Cloud
//
//  Workers Issues：问题列表（按状态分段、可按 Worker 过滤、页码续页）+ 汇总行，
//  以及单个问题详情（发生记录游标续页、改状态）。
//

import Foundation
import Observation

@Observable
@MainActor
final class WorkerIssuesViewModel {

    private(set) var issues: [WorkerIssue] = []
    private(set) var summary: WorkerIssueSummary?
    private(set) var loaded = false
    private(set) var canLoadMore = false
    var isLoading = false
    var isLoadingMore = false
    var error: String?

    /// 状态分段，默认「活跃」；改了要重查
    var status: WorkerIssueStatus = .active

    /// nil = 全账户；非 nil = 只看这个 Worker（Worker 详情页进来）
    let service: String?

    private let api: WorkerIssuesService
    private let accountId: String
    private var page = 1

    /// 每次 load 递增；切分段时晚到的旧结果丢弃（同 WorkerLogsViewModel）
    private var loadGeneration = 0

    init(service api: WorkerIssuesService, accountId: String, scriptName: String?) {
        self.api = api
        self.accountId = accountId
        self.service = scriptName
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        error = nil
        // 汇总与列表并行；汇总失败不影响列表（只少一行概况）
        async let summaryTask = try? api.summary(accountId: accountId, service: service)
        do {
            let result = try await api.issues(accountId: accountId, status: status, service: service, page: 1)
            guard generation == loadGeneration else { return }
            issues = result.issues
            canLoadMore = result.hasMore
            page = 1
            loaded = true
        } catch {
            guard generation == loadGeneration, !error.isCancellation else { return }
            self.error = error.localizedDescription
            issues = []
            canLoadMore = false
        }
        let fetchedSummary = await summaryTask
        guard generation == loadGeneration else { return }
        if let fetchedSummary { summary = fetchedSummary }
        isLoading = false
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, canLoadMore else { return }
        let generation = loadGeneration
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let next = page + 1
            let result = try await api.issues(accountId: accountId, status: status, service: service, page: next)
            guard generation == loadGeneration else { return }
            let known = Set(issues.map(\.id))
            issues.append(contentsOf: result.issues.filter { !known.contains($0.id) })
            page = next
            canLoadMore = result.hasMore
        } catch {
            guard generation == loadGeneration, !error.isCancellation else { return }
            self.error = error.localizedDescription
            canLoadMore = false
        }
    }

    /// 详情页改完状态后回写：不再属于当前分段的从列表移走，并刷新汇总
    func apply(updated issue: WorkerIssue) async {
        if issue.knownStatus == status {
            if let index = issues.firstIndex(where: { $0.id == issue.id }) { issues[index] = issue }
        } else {
            issues.removeAll { $0.id == issue.id }
        }
        if let fresh = try? await api.summary(accountId: accountId, service: service) {
            summary = fresh
        }
    }
}

// MARK: - 问题详情

@Observable
@MainActor
final class WorkerIssueDetailViewModel {

    private(set) var issue: WorkerIssue
    private(set) var occurrences: [WorkerIssueOccurrence] = []
    private(set) var occurrencesLoaded = false
    private(set) var nextCursor: String?
    var isLoadingOccurrences = false
    var isUpdating = false
    /// 发生记录加载失败（页内展示）
    var error: String?
    /// 改状态失败（弹窗展示），与加载错误分开，免得互相覆盖
    var actionError: String?
    var didUpdate = false      // sensoryFeedback 触发器

    private let api: WorkerIssuesService
    private let accountId: String

    init(issue: WorkerIssue, service api: WorkerIssuesService, accountId: String) {
        self.issue = issue
        self.api = api
        self.accountId = accountId
    }

    /// 刷新问题本体 + 首页发生记录
    func load() async {
        isLoadingOccurrences = true
        error = nil
        if let fresh = try? await api.issue(accountId: accountId, issueId: issue.id) {
            issue = fresh
        }
        do {
            let page = try await api.occurrences(accountId: accountId, issueId: issue.id, cursor: nil)
            occurrences = page.occurrences
            nextCursor = page.nextCursor
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
        }
        occurrencesLoaded = true
        isLoadingOccurrences = false
    }

    func loadMoreOccurrences() async {
        guard let cursor = nextCursor, !isLoadingOccurrences else { return }
        isLoadingOccurrences = true
        defer { isLoadingOccurrences = false }
        do {
            let page = try await api.occurrences(accountId: accountId, issueId: issue.id, cursor: cursor)
            let known = Set(occurrences.map(\.id))
            occurrences.append(contentsOf: page.occurrences.filter { !known.contains($0.id) })
            // 游标不前进时停止续页，防死循环
            nextCursor = page.nextCursor == cursor ? nil : page.nextCursor
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
            nextCursor = nil
        }
    }

    /// 标记为已解决 / 忽略 / 重新打开。返回更新后的问题（失败为 nil）。
    func setStatus(_ status: WorkerIssueStatus) async -> WorkerIssue? {
        guard !isUpdating else { return nil }
        isUpdating = true
        actionError = nil
        defer { isUpdating = false }
        do {
            let updated = try await api.setStatus(accountId: accountId, issueId: issue.id, status: status)
            issue = updated ?? issue.with(status: status)
            didUpdate.toggle()
            return issue
        } catch {
            actionError = error.localizedDescription
            return nil
        }
    }
}
