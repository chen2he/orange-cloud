//
//  DomainSearchViewModel.swift
//  Orange Cloud
//
//  搜索新域名：关键词搜索（结果可能有延迟）→ 点开单个域名实时确认（domain-check）。
//  只查不买：可注册时引导去 Cloudflare 控制台注册，App 内不发起任何购买。
//

import Foundation
import Observation

@Observable
@MainActor
final class DomainSearchViewModel {

    var query = ""
    private(set) var results: [DomainAvailability] = []
    private(set) var searched = false
    var isSearching = false
    /// 正在实时确认的域名
    private(set) var checkingName: String?
    /// 已实时确认过的域名（行内标记）
    private(set) var checkedNames: Set<String> = []
    var error: String?

    private let service: RegistrarService
    private let accountId: String
    /// 每次搜索递增，晚到的旧结果丢弃
    private var generation = 0

    init(service: RegistrarService, accountId: String) {
        self.service = service
        self.accountId = accountId
    }

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        generation += 1
        let current = generation
        isSearching = true
        error = nil
        do {
            let found = try await service.searchDomains(accountId: accountId, query: trimmed)
            guard current == generation else { return }
            results = found
            checkedNames = []
            searched = true
        } catch {
            guard current == generation, !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
        isSearching = false
    }

    /// 实时确认单个域名，结果替换列表里的那一行
    func check(_ domain: DomainAvailability) async {
        guard checkingName == nil else { return }
        checkingName = domain.name
        error = nil
        defer { checkingName = nil }
        do {
            let checked = try await service.checkDomains(accountId: accountId, names: [domain.name])
            if let fresh = checked.first(where: { $0.name.caseInsensitiveCompare(domain.name) == .orderedSame }) ?? checked.first,
               let index = results.firstIndex(where: { $0.name == domain.name }) {
                results[index] = fresh
                checkedNames.insert(fresh.name)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
