//
//  TunnelWAFViewModels.swift
//  Orange Cloud
//
//  P5：Tunnel 列表与 WAF 自定义规则的 ViewModel。实时拉取，不进 SwiftData。
//

import Foundation
import Observation

@Observable
@MainActor
final class TunnelListViewModel {

    var tunnels: [Tunnel] = []
    var isLoading = false
    var isSaving = false
    var error: String?

    private let service: TunnelService

    init(service: TunnelService) {
        self.service = service
    }

    func load(accountId: String) async {
        isLoading = true
        error = nil
        do {
            tunnels = try await service.listTunnels(accountId: accountId)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// 新建远程托管隧道，成功返回新隧道（供随后展示连接令牌）。
    func createTunnel(name: String, accountId: String) async -> Tunnel? {
        guard !isSaving else { return nil }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let tunnel = try await service.createTunnel(accountId: accountId, name: name)
            tunnels.insert(tunnel, at: 0)
            return tunnel
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// 删除隧道（先清理连接）。成功返回 true。
    func deleteTunnel(_ tunnel: Tunnel, accountId: String) async -> Bool {
        error = nil
        do {
            try await service.deleteTunnel(accountId: accountId, tunnelId: tunnel.id)
            tunnels.removeAll { $0.id == tunnel.id }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

@Observable
@MainActor
final class TunnelDetailViewModel {

    let tunnel: Tunnel

    var token: String?
    var config: TunnelConfig?
    /// 活跃连接。首帧用列表响应内嵌的数组占位，随后由专用端点覆盖
    /// （内嵌字段 CF 将于 2026-10-05 移除，届时占位恒为空、完全依赖端点）。
    var connections: [TunnelConnection]
    var isLoadingToken = false
    var isLoadingConfig = false
    var isLoadingConnections = false
    var configLoaded = false
    var isSaving = false
    var error: String?
    /// 保存公共主机名后的 DNS 提示（自动建 CNAME 成功，或需手动添加）
    var dnsNotice: String?

    private let accountId: String
    private let tunnelService: TunnelService
    private let dnsService: DNSService
    private let zoneService: ZoneService
    private let canWriteDNS: Bool
    private var zonesCache: [Zone]?

    init(tunnel: Tunnel, accountId: String, session: SessionStore, canWriteDNS: Bool) {
        self.tunnel = tunnel
        self.connections = tunnel.connections ?? []
        self.accountId = accountId
        self.tunnelService = session.tunnelService
        self.dnsService = session.dnsService
        self.zoneService = session.zoneService
        self.canWriteDNS = canWriteDNS
    }

    /// CNAME 目标：<隧道ID>.cfargotunnel.com
    var cnameTarget: String { "\(tunnel.id).cfargotunnel.com" }

    /// 非 catch-all 的公共主机名规则（供 UI 列表）
    var publicHostnames: [IngressRule] {
        (config?.ingress ?? []).filter { !$0.isCatchAll }
    }

    // MARK: - 加载

    func loadToken() async {
        guard token == nil, !isLoadingToken else { return }
        isLoadingToken = true
        defer { isLoadingToken = false }
        do {
            token = try await tunnelService.tunnelToken(accountId: accountId, tunnelId: tunnel.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadConfiguration() async {
        isLoadingConfig = true
        error = nil
        do {
            config = try await tunnelService.configuration(accountId: accountId, tunnelId: tunnel.id)
            configLoaded = true
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingConfig = false
    }

    /// 删除本隧道（危险区）。成功返回 true，视图随即 dismiss 回列表（列表 .task 会重拉）。
    func deleteTunnel() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await tunnelService.deleteTunnel(accountId: accountId, tunnelId: tunnel.id)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// 清理失活连接（危险区）。活跃的 cloudflared 会自动重连。
    /// 拉取活跃连接。失败不弹错误框——详情页其余内容仍可用，保留占位数据即可。
    func loadConnections() async {
        guard !isLoadingConnections else { return }
        isLoadingConnections = true
        defer { isLoadingConnections = false }
        do {
            connections = try await tunnelService.connections(accountId: accountId, tunnelId: tunnel.id)
        } catch {
            AppLog.network.info("tunnel connections fetch failed for tunnel=\(self.tunnel.id); keeping placeholder")
        }
    }

    func cleanupConnections() async {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await tunnelService.deleteConnections(accountId: accountId, tunnelId: tunnel.id)
            // 清理后立刻回读，避免列表还显示已被移除的失活连接
            await loadConnections()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - 公共主机名（整组 PUT，catch-all 守末尾）

    /// 新增或更新一条公共主机名。index 为 nil 时新增（并尝试自动建 CNAME）。
    func saveHostname(_ rule: IngressRule, at index: Int?) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        error = nil
        dnsNotice = nil
        defer { isSaving = false }

        var rules = publicHostnames
        if let index, rules.indices.contains(index) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        guard await saveIngress(rules) else { return false }
        if index == nil, let hostname = rule.hostname {
            await ensureCNAME(for: hostname)   // 仅新增时建 DNS
        }
        return true
    }

    func deleteHostname(at index: Int) async {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        var rules = publicHostnames
        guard rules.indices.contains(index) else { return }
        rules.remove(at: index)
        _ = await saveIngress(rules)
        // 不自动删 DNS 记录，避免误删用户其它用途的记录
    }

    /// 拼装整份 ingress（编辑后的规则 + 原 catch-all）并回写。
    private func saveIngress(_ rules: [IngressRule]) async -> Bool {
        let catchAll = (config?.ingress ?? []).first { $0.isCatchAll } ?? .catchAll
        var newConfig = config ?? TunnelConfig()
        newConfig.ingress = rules + [catchAll]
        do {
            config = try await tunnelService.updateConfiguration(
                accountId: accountId, tunnelId: tunnel.id, config: newConfig
            )
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// 为公共主机名自动建代理 CNAME；无 dns.write 或找不到域名时给出手动提示。
    private func ensureCNAME(for hostname: String) async {
        guard canWriteDNS else {
            dnsNotice = String(localized: "请在 DNS 中为 \(hostname) 添加代理 CNAME，目标 \(cnameTarget)")
            return
        }
        do {
            let zones = try await loadZones()
            guard let zone = bestZone(for: hostname, in: zones) else {
                dnsNotice = String(localized: "未找到 \(hostname) 所属域名，请手动添加代理 CNAME，目标 \(cnameTarget)")
                return
            }
            let record = CreateDNSRecord(
                type: "CNAME", name: hostname, content: cnameTarget,
                proxied: true, ttl: 1, priority: nil,
                comment: String(localized: "Cloudflare Tunnel")
            )
            _ = try await dnsService.createRecord(zoneId: zone.id, record: record)
            dnsNotice = String(localized: "已自动添加代理 CNAME：\(hostname) → \(cnameTarget)")
        } catch {
            dnsNotice = String(localized: "DNS 记录未自动创建，请手动添加代理 CNAME，目标 \(cnameTarget)")
        }
    }

    private func loadZones() async throws -> [Zone] {
        if let zonesCache { return zonesCache }
        let zones = try await zoneService.listZones(accountId: accountId)
        zonesCache = zones
        return zones
    }

    /// hostname 所属 zone：取名字最长的后缀匹配项（处理多级子域名/多 zone）。
    private func bestZone(for hostname: String, in zones: [Zone]) -> Zone? {
        zones
            .filter { hostname == $0.name || hostname.hasSuffix("." + $0.name) }
            .max { $0.name.count < $1.name.count }
    }
}

@Observable
@MainActor
final class WAFRulesViewModel {

    private(set) var ruleset: WAFRuleset?
    private(set) var loaded = false        // 区分"未加载"与"加载过但没有规则"
    var isLoading = false
    var error: String?
    var togglingRuleId: String?

    var rules: [WAFRule] { ruleset?.rules ?? [] }

    private let service: WAFService
    private let zoneId: String

    init(service: WAFService, zoneId: String) {
        self.service = service
        self.zoneId = zoneId
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            ruleset = try await service.customRuleset(zoneId: zoneId)
            loaded = true
        } catch is CancellationError {
            // 下拉刷新 / searchable 取消 .refreshable 子任务，不算加载失败
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// 启停规则；失败时回滚由 ruleset 整体替换保证
    func toggle(rule: WAFRule, enabled: Bool) async {
        guard let rulesetId = ruleset?.id, togglingRuleId == nil else { return }
        togglingRuleId = rule.id
        error = nil
        do {
            ruleset = try await service.setRuleEnabled(
                zoneId: zoneId, rulesetId: rulesetId, ruleId: rule.id, enabled: enabled
            )
        } catch {
            self.error = error.localizedDescription
        }
        togglingRuleId = nil
    }

    // MARK: - 设备端 AI 生成（自然语言 → 结构化 → 表达式）

    var isGenerating = false
    var generationError: String?

    /// 用自然语言生成一条规则草稿；失败时写入 generationError 并返回 nil。
    func generate(from naturalLanguage: String, locale: Locale = .current) async -> GeneratedWAFRule? {
        let trimmed = naturalLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return nil }
        isGenerating = true
        generationError = nil
        defer { isGenerating = false }
        do {
            return try await WAFAssistant.generateRule(from: trimmed, locale: locale)
        } catch {
            generationError = error.localizedDescription
            return nil
        }
    }

    /// 新建规则：已有规则集则追加，否则创建 entrypoint。成功返回 true。
    var isSaving = false

    func addRule(_ draft: WAFRuleCreate) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            if let rulesetId = ruleset?.id {
                ruleset = try await service.addRule(zoneId: zoneId, rulesetId: rulesetId, rule: draft)
            } else {
                ruleset = try await service.createRuleset(zoneId: zoneId, rule: draft)
            }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// 编辑既有规则（整条 PATCH）。成功返回 true。
    func updateRule(ruleId: String, draft: WAFRuleCreate) async -> Bool {
        guard let rulesetId = ruleset?.id, !isSaving else { return false }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            ruleset = try await service.updateRule(
                zoneId: zoneId, rulesetId: rulesetId, ruleId: ruleId, rule: draft
            )
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    // MARK: - 规则校验（dry_run，不落库、不改保存流程）

    var isValidating = false
    /// 最近一次校验通过（编辑器显示「规则校验通过」）；改动草稿后由视图清掉
    var validationPassed = false

    /// 用保存同款请求带 ?dry_run=true 校验。失败写入 error（与保存失败同处展示）。
    func validate(ruleId: String?, draft: WAFRuleCreate) async {
        guard !isValidating, !isSaving else { return }
        isValidating = true
        validationPassed = false
        error = nil
        defer { isValidating = false }
        do {
            try await service.validateRule(
                zoneId: zoneId, rulesetId: ruleset?.id, ruleId: ruleId, rule: draft
            )
            validationPassed = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(rule: WAFRule) async {
        guard let rulesetId = ruleset?.id else { return }
        error = nil
        do {
            try await service.deleteRule(zoneId: zoneId, rulesetId: rulesetId, ruleId: rule.id)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
