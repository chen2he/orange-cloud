//
//  CFAlertingViewModel.swift
//  Orange Cloud
//
//  CF 告警管理：把所选账号的告警类型，按需建/删指向推送端点的策略。
//  自带 CFAPIClient（由 AuthManager 造），不依赖 SessionStore——从工具箱 cover 也能用。
//

import Foundation
import Observation

@Observable
@MainActor
final class CFAlertingViewModel {

    private let auth: AuthManager
    private let endpointURL: String   // push.o-c.do/{key}

    private(set) var accounts: [Account] = []
    private(set) var selectedAccountId: String?
    private(set) var groups: [(category: String, alerts: [CFAvailableAlert])] = []
    private(set) var policies: [CFAlertPolicy] = []
    private(set) var pushWebhookId: String?
    var isLoading = false
    var error: String?
    var busyAlertType: String?

    init(auth: AuthManager, endpointURL: String) {
        self.auth = auth
        self.endpointURL = endpointURL
    }

    /// CF webhook 投递目标 = 端点的 /cf（中继把 CF 的 name/text 转成推送）
    var cfWebhookURL: String { "\(endpointURL)/cf" }

    private var service: AlertingService { AlertingService(client: CFAPIClient(authManager: auth)) }
    private var accountService: AccountService { AccountService(client: CFAPIClient(authManager: auth)) }

    func load() async {
        isLoading = true
        error = nil
        do {
            if accounts.isEmpty {
                accounts = try await accountService.listAccounts()
                if selectedAccountId == nil { selectedAccountId = accounts.first?.id }
            }
            guard let accountId = selectedAccountId else { isLoading = false; return }

            async let availableFetch = service.availableAlerts(accountId: accountId)
            async let policiesFetch = service.policies(accountId: accountId)
            async let webhooksFetch = service.webhooks(accountId: accountId)
            let (available, pols, hooks) = try await (availableFetch, policiesFetch, webhooksFetch)

            // 等待期间用户可能已切到别的账号（selectAccount 起的是不取消的 Task）：
            // A 账号慢到的策略 / webhook id 不能顶在 B 名下，否则后续开关告警会打到错误账号的 webhook。
            guard accountId == selectedAccountId else { return }
            groups = available.map { (category: $0.key, alerts: $0.value) }.sorted { $0.category < $1.category }
            policies = pols
            pushWebhookId = hooks.first(where: { $0.url == cfWebhookURL })?.id
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func selectAccount(_ id: String) {
        guard id != selectedAccountId else { return }
        selectedAccountId = id
        groups = []
        policies = []
        pushWebhookId = nil
        Task { await load() }
    }

    /// 该告警类型是否已有指向我们 webhook 的策略
    func policy(for alertType: String) -> CFAlertPolicy? {
        policies.first {
            $0.alertType == alertType && ($0.mechanisms?.webhooks?.contains { $0.id == pushWebhookId } ?? false)
        }
    }

    /// 确保有指向端点的 webhook destination，返回其 id
    private func ensureWebhook(accountId: String) async throws -> String {
        if let id = pushWebhookId { return id }
        let id = try await service.createWebhook(accountId: accountId, name: "Orange Cloud Push", url: cfWebhookURL)
        pushWebhookId = id
        return id
    }

    /// 开/关某告警类型（开=建策略指向端点；关=删策略）
    func toggle(alertType: String, displayName: String) async {
        guard let accountId = selectedAccountId else { return }
        busyAlertType = alertType
        error = nil
        do {
            if let existing = policy(for: alertType) {
                try await service.deletePolicy(accountId: accountId, id: existing.id)
            } else {
                let webhookId = try await ensureWebhook(accountId: accountId)
                _ = try await service.createPolicy(
                    accountId: accountId, name: "OC: \(displayName)", alertType: alertType, webhookId: webhookId
                )
            }
            policies = try await service.policies(accountId: accountId)
        } catch {
            self.error = error.localizedDescription
        }
        busyAlertType = nil
    }
}
