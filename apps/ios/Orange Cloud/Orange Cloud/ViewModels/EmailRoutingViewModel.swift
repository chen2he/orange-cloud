//
//  EmailRoutingViewModel.swift
//  Orange Cloud
//
//  Email Routing：加载设置/规则/地址，开关、规则增删改、新增目的地址。
//

import Foundation
import Observation

@Observable
@MainActor
final class EmailRoutingViewModel {

    private(set) var settings:  EmailRoutingSettings?
    private(set) var rules:     [EmailRoutingRule] = []
    private(set) var addresses: [EmailDestinationAddress] = []
    /// 抑制列表：独立 scope，读不到不连累主加载
    private(set) var suppressions: [EmailSuppression] = []
    private(set) var suppressionsAvailable = false
    var isLoading = false
    var isMutating = false
    var error: String?

    private let service:   EmailRoutingService
    private let zoneId:    String
    private let accountId: String?   // 缺 account scope / 无账号上下文时地址不可用

    init(service: EmailRoutingService, zoneId: String, accountId: String?) {
        self.service = service
        self.zoneId = zoneId
        self.accountId = accountId
    }

    /// 已验证的目的地址（只有它们能被规则转发到）
    var verifiedAddresses: [EmailDestinationAddress] { addresses.filter(\.isVerified) }

    var hasAddressScope: Bool { accountId != nil }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        do {
            async let settingsTask = service.settings(zoneId: zoneId)
            async let rulesTask = service.rules(zoneId: zoneId)
            settings = try await settingsTask
            rules = try await rulesTask
        } catch {
            self.error = error.localizedDescription
        }
        // 地址是账号级、独立 scope，单独容错不连累主加载
        if let accountId {
            addresses = (try? await service.addresses(accountId: accountId)) ?? addresses
        }
        // 抑制列表同理：email-routing-suppression.read 未授权时静默跳过
        if let list = try? await service.suppressions(zoneId: zoneId) {
            suppressions = list
            suppressionsAvailable = true
        }
        isLoading = false
    }

    func setEnabled(_ enabled: Bool) async {
        await mutate {
            try await service.setEnabled(zoneId: zoneId, enabled: enabled)
            settings = try await service.settings(zoneId: zoneId)
        }
    }

    func setRuleEnabled(_ rule: EmailRoutingRule, enabled: Bool) async {
        await mutate {
            let input = EmailRoutingRuleInput(
                name: rule.name, enabled: enabled,
                matchers: rule.matchers, actions: rule.actions
            )
            _ = try await service.updateRule(zoneId: zoneId, ruleId: rule.id, input: input)
            rules = try await service.rules(zoneId: zoneId)
        }
    }

    func deleteRule(_ rule: EmailRoutingRule) async {
        await mutate {
            try await service.deleteRule(zoneId: zoneId, ruleId: rule.id)
            rules.removeAll { $0.id == rule.id }
        }
    }

    /// 新建转发规则：把 matchAddress 转发到已验证的 destination
    func createForwardRule(matchAddress: String, destination: String, name: String?) async {
        await mutate {
            let input = EmailRoutingRuleInput.forward(
                name: name, to: matchAddress, destination: destination, enabled: true
            )
            _ = try await service.createRule(zoneId: zoneId, input: input)
            rules = try await service.rules(zoneId: zoneId)
        }
    }

    /// 更新已有转发规则的收件/目的地址
    func updateForwardRule(_ rule: EmailRoutingRule, matchAddress: String, destination: String, name: String?) async {
        await mutate {
            let input = EmailRoutingRuleInput.forward(
                name: name, to: matchAddress, destination: destination, enabled: rule.isEnabled
            )
            _ = try await service.updateRule(zoneId: zoneId, ruleId: rule.id, input: input)
            rules = try await service.rules(zoneId: zoneId)
        }
    }

    /// 新增目的地址（触发验证邮件）
    func createAddress(_ email: String) async {
        guard let accountId else { return }
        await mutate {
            _ = try await service.createAddress(accountId: accountId, email: email)
            addresses = try await service.addresses(accountId: accountId)
        }
    }

    func deleteAddress(_ address: EmailDestinationAddress) async {
        guard let accountId else { return }
        await mutate {
            try await service.deleteAddress(accountId: accountId, addressId: address.id)
            addresses.removeAll { $0.id == address.id }
        }
    }

    private func mutate(_ op: () async throws -> Void) async {
        guard !isMutating else { return }
        isMutating = true
        error = nil
        do {
            try await op()
        } catch {
            self.error = error.localizedDescription
        }
        isMutating = false
    }

    /// 解除抑制。成功后本地移除，不必整页重载。
    func removeSuppression(_ item: EmailSuppression) async {
        await mutate {
            try await service.deleteSuppression(zoneId: zoneId, id: item.id)
            // 只有服务端确认删除才从本地移除；以前写在 mutate 外面，接口失败 / 正在进行别的
            // 变更被跳过时行也会消失，下次加载又冒出来。
            suppressions.removeAll { $0.id == item.id }
        }
    }

}
