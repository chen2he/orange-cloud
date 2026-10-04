//
//  ZoneActionsViewModel.swift
//  Orange Cloud
//
//  Zone 详情页「操作」区：Under Attack / 开发模式 / 暂停 Cloudflare 开关 + 缓存清理，
//  以及「AI 内容控制」区：AI 训练重定向 / 面向 Agent 的 Markdown。
//
//  注意暂停态与另两个开关的数据源不同：Under Attack / 开发模式读写 zone settings
//  （zone-settings.read/.write），暂停读写 zone 本身（zone.read / zone.write），
//  两条链路的权限与加载态各自独立，别合并。
//

import Foundation
import Observation

@Observable
@MainActor
final class ZoneActionsViewModel {

    private(set) var underAttack = false
    private(set) var devMode = false
    private(set) var settingsLoaded = false
    /// 是否暂停 Cloudflare 代理。初值取自本地缓存，进页后再用 API 校准。
    private(set) var paused: Bool

    // MARK: AI 内容控制（Pro 起；免费套餐读得到但不可改，对应开关隐藏）

    /// Redirects for AI Training —— 把 AI 训练类爬虫重定向走
    private(set) var aiTrainingRedirect = false
    /// Markdown for Agents —— 按 Accept: text/markdown 把 HTML 转 Markdown 供 agent 消费
    private(set) var markdownForAgents = false
    /// 上面两项各自读到且可改才显示
    private(set) var aiTrainingRedirectAvailable = false
    private(set) var markdownForAgentsAvailable = false
    var aiSettingsAvailable: Bool { aiTrainingRedirectAvailable || markdownForAgentsAvailable }

    // MARK: 机器人管控（bot-management.read/.write，全套餐可用）

    /// AI 爬虫处置：全站拦 / 仅广告页 / 放行
    private(set) var aiBotsProtection: AIBotsProtection = .disabled
    /// 链接迷宫（AI Labyrinth）
    private(set) var crawlerProtection = false
    /// 拦内容机器人
    private(set) var contentBotsProtection = false
    /// Robots 访问控制许可证
    private(set) var robotsLicense = false
    /// 托管 robots.txt
    private(set) var managedRobotsTxt = false
    private(set) var botConfigLoaded = false

    var isTogglingUnderAttack = false
    var isTogglingDevMode = false
    var isTogglingAITrainingRedirect = false
    var isTogglingMarkdownForAgents = false
    /// 机器人管控五项共用一个忙态：同一个端点，串行改更安全
    var isUpdatingBotConfig = false
    var isTogglingPause = false
    var isPurging = false
    var didPurge = false       // sensoryFeedback / 提示触发器
    var error: String?

    private let service: ZoneSettingsService
    private let zoneService: ZoneService
    private let botService: BotManagementService
    private let zoneId: String

    init(
        service: ZoneSettingsService,
        zoneService: ZoneService,
        botService: BotManagementService,
        zoneId: String,
        paused: Bool = false
    ) {
        self.service = service
        self.zoneService = zoneService
        self.botService = botService
        self.zoneId = zoneId
        self.paused = paused
    }

    func loadSettings() async {
        guard !settingsLoaded else { return }
        async let securityTask = service.getSetting(zoneId: zoneId, setting: "security_level")
        async let devTask = service.getSetting(zoneId: zoneId, setting: "development_mode")
        // 读不到（无 zone-settings.read 等）就保持未加载态，开关显示为锁定
        guard let security = try? await securityTask, let dev = try? await devTask else { return }
        underAttack = security == "under_attack"
        devMode = dev == "on"
        settingsLoaded = true
    }

    /// 读 AI 内容控制两项。免费套餐也读得到值，只是 editable == false、一写就 400——
    /// 读不到或不可改都当不支持，隐藏对应开关，不给用户一个永远打不开的锁。
    func loadAISettings() async {
        guard !aiSettingsAvailable else { return }
        async let redirectTask = service.getSettingIfEditable(zoneId: zoneId, setting: "redirects_for_ai_training")
        async let converterTask = service.getSettingIfEditable(zoneId: zoneId, setting: "content_converter")
        let redirect = try? await redirectTask
        let converter = try? await converterTask
        aiTrainingRedirect = redirect == "on"
        markdownForAgents = converter == "on"
        aiTrainingRedirectAvailable = redirect != nil
        markdownForAgentsAvailable = converter != nil
    }

    /// 读机器人管控配置。四种套餐形态共用 base_config，任何套餐都能读到。
    func loadBotConfig() async {
        guard !botConfigLoaded else { return }
        guard let config = try? await botService.config(zoneId: zoneId) else { return }
        apply(config)
        botConfigLoaded = true
    }

    private func apply(_ config: BotManagementConfig) {
        aiBotsProtection      = AIBotsProtection(apiValue: config.aiBotsProtection)
        crawlerProtection     = config.crawlerProtection == "enabled"
        contentBotsProtection = config.contentBotsProtection == "block"
        robotsLicense         = config.cfRobotsVariant == "policy_only"
        managedRobotsTxt      = config.isRobotsTxtManaged == true
    }

    /// 写单个字段。PUT 是合并语义，只发改动的那一个，不会动 sbfm_* 等套餐专属配置。
    private func updateBot<Value: Codable & Sendable>(
        _ field: BotManagementField,
        _ value: Value
    ) async {
        guard !isUpdatingBotConfig else { return }
        isUpdatingBotConfig = true
        error = nil
        do {
            apply(try await botService.update(zoneId: zoneId, field: field, value: value))
        } catch {
            self.error = error.localizedDescription
        }
        isUpdatingBotConfig = false
    }

    func setAIBotsProtection(_ mode: AIBotsProtection) async {
        await updateBot(.aiBotsProtection, mode.rawValue)
    }

    func setCrawlerProtection(_ on: Bool) async {
        await updateBot(.crawlerProtection, on ? "enabled" : "disabled")
    }

    func setContentBotsProtection(_ on: Bool) async {
        await updateBot(.contentBotsProtection, on ? "block" : "disabled")
    }

    func setRobotsLicense(_ on: Bool) async {
        await updateBot(.cfRobotsVariant, on ? "policy_only" : "off")
    }

    func setManagedRobotsTxt(_ on: Bool) async {
        await updateBot(.isRobotsTxtManaged, on)
    }

    func setAITrainingRedirect(_ on: Bool) async {
        guard !isTogglingAITrainingRedirect else { return }
        isTogglingAITrainingRedirect = true
        error = nil
        do {
            let value = try await service.setSetting(
                zoneId: zoneId, setting: "redirects_for_ai_training",
                value: on ? "on" : "off"
            )
            aiTrainingRedirect = value == "on"
        } catch {
            self.error = error.localizedDescription
        }
        isTogglingAITrainingRedirect = false
    }

    func setMarkdownForAgents(_ on: Bool) async {
        guard !isTogglingMarkdownForAgents else { return }
        isTogglingMarkdownForAgents = true
        error = nil
        do {
            let value = try await service.setSetting(
                zoneId: zoneId, setting: "content_converter",
                value: on ? "on" : "off"
            )
            markdownForAgents = value == "on"
        } catch {
            self.error = error.localizedDescription
        }
        isTogglingMarkdownForAgents = false
    }

    func setUnderAttack(_ on: Bool) async {
        guard !isTogglingUnderAttack else { return }
        isTogglingUnderAttack = true
        error = nil
        do {
            // 关闭时恢复为 medium（Cloudflare 默认安全级别；API 不记录开启前的旧值）
            let value = try await service.setSetting(
                zoneId: zoneId, setting: "security_level",
                value: on ? "under_attack" : "medium"
            )
            underAttack = value == "under_attack"
        } catch {
            self.error = error.localizedDescription
        }
        isTogglingUnderAttack = false
    }

    func setDevMode(_ on: Bool) async {
        guard !isTogglingDevMode else { return }
        isTogglingDevMode = true
        error = nil
        do {
            let value = try await service.setSetting(
                zoneId: zoneId, setting: "development_mode",
                value: on ? "on" : "off"
            )
            devMode = value == "on"
        } catch {
            self.error = error.localizedDescription
        }
        isTogglingDevMode = false
    }

    /// 校准暂停态（只需 zone.read，与 loadSettings 的 zone-settings.read 无关）。
    /// 返回最新值，调用方据此回写本地缓存；读失败保持缓存值不动。
    @discardableResult
    func refreshPaused() async -> Bool? {
        guard let zone = try? await zoneService.getZone(zoneId: zoneId) else { return nil }
        paused = zone.paused ?? false
        return paused
    }

    /// 暂停 / 恢复 Cloudflare 代理。返回是否成功，供调用方回写缓存。
    @discardableResult
    func setPaused(_ on: Bool) async -> Bool {
        guard !isTogglingPause else { return false }
        isTogglingPause = true
        error = nil
        defer { isTogglingPause = false }
        do {
            let zone = try await zoneService.setPaused(zoneId: zoneId, paused: on)
            // 少数情况下响应不带 paused，按请求值兜底
            paused = zone.paused ?? on
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func purgeCache() async {
        guard !isPurging else { return }
        isPurging = true
        error = nil
        do {
            try await service.purgeAllCache(zoneId: zoneId)
            didPurge.toggle()
        } catch {
            self.error = error.localizedDescription
        }
        isPurging = false
    }

    /// 按 URL 清理缓存（单文件 purge，调用方负责限制 ≤ 30 个 URL）
    func purgeURLs(_ urls: [String]) async {
        await runPurge(urls) { try await service.purgeFiles(zoneId: zoneId, urls: $0) }
    }

    /// 按 URL 前缀清理缓存（调用方负责限制 ≤ 30 个）
    func purgePrefixes(_ prefixes: [String]) async {
        await runPurge(prefixes) { try await service.purgePrefixes(zoneId: zoneId, prefixes: $0) }
    }

    /// 按主机名清理缓存（调用方负责限制 ≤ 30 个）
    func purgeHosts(_ hosts: [String]) async {
        await runPurge(hosts) { try await service.purgeHosts(zoneId: zoneId, hosts: $0) }
    }

    /// 按 Cache-Tag 清理缓存（调用方负责限制 ≤ 30 个）
    func purgeTags(_ tags: [String]) async {
        await runPurge(tags) { try await service.purgeTags(zoneId: zoneId, tags: $0) }
    }

    /// 缓存清理统一执行：去重并发、清空错误、成功翻 didPurge 触发反馈
    private func runPurge(_ items: [String], _ op: ([String]) async throws -> Void) async {
        guard !isPurging, !items.isEmpty else { return }
        isPurging = true
        error = nil
        do {
            try await op(items)
            didPurge.toggle()
        } catch {
            self.error = error.localizedDescription
        }
        isPurging = false
    }
}
