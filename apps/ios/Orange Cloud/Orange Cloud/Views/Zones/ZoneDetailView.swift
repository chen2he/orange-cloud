//
//  ZoneDetailView.swift
//  Orange Cloud
//
//  单域名中枢（设计稿 zone-detail.jsx）：
//  hero 卡（头像 + 域名 + 状态/套餐 + 24h 流量统计）+ 管理 / 分析 / 操作分组 + 区域 ID。
//

import SwiftUI
import SwiftData

struct ZoneDetailView: View {

    let zone: CachedZone
    let session: SessionStore

    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [CachedDNSRecord]

    // 分析区（内嵌第一层级，ViewModel 由本页持有，下拉刷新共用）
    @State private var analyticsViewModel: ZoneAnalyticsViewModel
    // 访问明细 / 安全事件（adaptive 数据集，跟随分析区所选范围）
    @State private var trafficDetailsViewModel: ZoneTrafficDetailsViewModel

    // 操作区
    @State private var actionsViewModel: ZoneActionsViewModel
    @State private var showPurgeConfirm = false
    @State private var showInvalidateConfirm = false
    @State private var showPurgeSheet = false
    @State private var showPurgeDone = false
    @State private var showInvalidateDone = false
    @State private var showActionDenied = false
    @State private var deniedScopeHint = ""
    /// 开关类操作先收口到这里，confirmationDialog 确认后才调 API
    @State private var pendingAction: PendingZoneAction?

    init(zone: CachedZone, session: SessionStore) {
        self.zone = zone
        self.session = session
        let zoneId = zone.id
        _records = Query(filter: #Predicate<CachedDNSRecord> { $0.zoneId == zoneId })
        _analyticsViewModel = State(initialValue: ZoneAnalyticsViewModel(
            analyticsService: session.analyticsService, zoneId: zoneId
        ))
        _trafficDetailsViewModel = State(initialValue: ZoneTrafficDetailsViewModel(
            service: session.zoneAdaptiveAnalyticsService, zoneId: zoneId
        ))
        _actionsViewModel = State(initialValue: ZoneActionsViewModel(
            service: session.zoneSettingsService,
            zoneService: session.zoneService,
            botService: session.botManagementService,
            precursorService: session.precursorService,
            zoneId: zoneId,
            paused: zone.paused
        ))
    }

    /// 跨资源类型的置顶存储（域名的固定状态以它为准，CachedZone.pinned 仅作镜像）
    private let pinnedStore = PinnedResourceStore.shared

    private var isPinned: Bool {
        pinnedStore.isPinned(PinnedResource(type: .zone, resourceId: zone.id), accountId: zone.accountId)
    }

    private var canReadSettings: Bool { auth.hasScope("zone-settings.read") }
    private var canEditSettings: Bool { auth.hasScope("zone-settings.write") }
    private var canReadBots: Bool { auth.hasScope("bot-management.read") }
    private var canEditBots: Bool { auth.hasScope("bot-management.write") }
    private var canReadPrecursor: Bool { auth.hasScope("precursor.read") }
    private var canEditPrecursor: Bool { auth.hasScope("precursor.write") }
    private var canPurge: Bool { auth.hasScope("cache.purge") }
    /// 暂停 / 恢复走 zone 本身，权限与 zone-settings 那条链路无关
    private var canEditZone: Bool { auth.hasScope("zone.write") }

    /// DNS 记录数：本地已同步过记录用实时缓存计数；否则用 Dashboard/入页回写的
    /// total_count（CachedZone.dnsRecordCount），避免首进详情页默认显示 0 条。
    private var dnsRecordDisplayCount: Int {
        records.isEmpty ? (zone.dnsRecordCount ?? 0) : records.count
    }

    /// hero 卡状态：暂停优先于 status（暂停时 API 的 status 仍是 active），
    /// 且以 ViewModel 的实时值为准，切换后立刻翻牌
    private var displayStatus: String {
        actionsViewModel.paused ? "paused" : zone.status
    }

    private var statusText: String {
        switch displayStatus {
        case "active":                  String(localized: "已启用")
        case "pending", "initializing": String(localized: "待激活")
        default:                        String(localized: "已暂停")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heroCard

                // 分析：图表直接内嵌第一层级，置于管理之前
                VStack(alignment: .leading, spacing: 8) {
                    Text("分析")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)
                    if auth.hasScope("analytics.read") {
                        ZoneAnalyticsSection(viewModel: analyticsViewModel)
                        // 上方图表保持原数据集；明细与安全事件走 adaptive 数据集，范围跟随上方选择器
                        ZoneTrafficDetailsSection(
                            viewModel: trafficDetailsViewModel,
                            range: analyticsViewModel.selectedRange
                        )
                        .padding(.top, 6)   // 与分析区内部卡片间距（14）对齐
                    } else {
                        Label("需要「流量分析」权限才能展示流量图表", systemImage: "lock")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                            .glassIsland(cornerRadius: OCLayout.chipRadius)
                    }
                }

                // 本卡内 eager 门控行的保留判据：目的页是叶子（内部只开 sheet、不再 push）。
                // 「规则」「负载均衡」的目的页还要继续 push，已改值式（ZoneRoute + 栈根 navdest）；
                // 其余若日后加内层 push，必须同步改值式。
                sectionCard(String(localized: "管理")) {
                    PermissionGatedNavigationLink(
                        label: String(localized: "DNS 记录"),
                        systemImage: "network",
                        requiredScope: "dns.read",
                        showsChevron: true
                    ) {
                        DNSListView(zoneId: zone.id, zoneName: zone.name, session: session)
                    }
                    .listRowStyleValue(String(localized: "\(dnsRecordDisplayCount) 条"))

                    // zone 级 DNS 策略（DNSSEC / CNAME 展平 / NS 类型），与逐条记录分开
                    PermissionGatedValueLink(
                        label: String(localized: "DNS 设置"),
                        systemImage: "gearshape.2",
                        requiredScope: "zone-dns-settings.read",
                        tint: .indigo,
                        showsChevron: true,
                        value: ZoneRoute.dnsSettings(zoneId: zone.id, zoneName: zone.name)
                    )

                    ProGatedNavigationLink(
                        label: String(localized: "WAF 防火墙"),
                        systemImage: "shield",
                        requiredScope: "zone-waf.read",
                        feature: .waf,
                        tint: .purple,
                        showsChevron: true
                    ) {
                        WAFRuleListView(zoneId: zone.id, zoneName: zone.name, session: session)
                    }

                    ProGatedNavigationLink(
                        label: "Rate Limiting",
                        systemImage: "gauge.with.dots.needle.bottom.50percent",
                        requiredScope: "zone-waf.read",
                        feature: .rateLimit,
                        tint: .pink,
                        showsChevron: true
                    ) {
                        RateLimitRulesView(zoneId: zone.id, zoneName: zone.name, session: session)
                    }

                    // 规则族（Transform / 缓存 / Snippets / 重定向 / 源站 / 配置 / 压缩 /
                    // 自定义错误 / Page Rules / URL 规范化）统一收进「规则」二级入口
                    PermissionGatedValueLink(
                        label: String(localized: "规则"),
                        systemImage: "list.bullet.rectangle",
                        requiredScope: "zone.read",
                        tint: .orange,
                        showsChevron: true,
                        value: ZoneRoute.rulesHub(zoneId: zone.id, zoneName: zone.name)
                    )

                    ProGatedNavigationLink(
                        label: "Email Routing",
                        systemImage: "envelope",
                        requiredScope: "email-routing-rule.read",
                        feature: .emailRouting,
                        tint: .pink,
                        showsChevron: true
                    ) {
                        EmailRoutingView(zoneId: zone.id, zoneName: zone.name, session: session)
                    }

                    PermissionGatedNavigationLink(
                        label: "SSL/TLS",
                        systemImage: "lock.shield",
                        requiredScope: "zone-settings.read",
                        tint: .green,
                        showsChevron: true
                    ) {
                        ZoneSSLSettingsView(zoneId: zone.id, zoneName: zone.name, session: session)
                    }

                    PermissionGatedNavigationLink(
                        label: String(localized: "性能与缓存"),
                        systemImage: "speedometer",
                        requiredScope: "zone-settings.read",
                        tint: .teal,
                        showsChevron: true
                    ) {
                        ZonePerformanceView(zoneId: zone.id, session: session)
                    }

                    PermissionGatedNavigationLink(
                        label: String(localized: "SSL 证书"),
                        systemImage: "checkmark.seal",
                        requiredScope: "ssl-and-certificates.read",
                        tint: .green,
                        showsChevron: true
                    ) {
                        ZoneSSLCertsView(zoneId: zone.id, session: session)
                    }

                    PermissionGatedNavigationLink(
                        label: String(localized: "IP 访问规则"),
                        systemImage: "hand.raised",
                        requiredScope: "firewall-services.read",
                        tint: .red,
                        showsChevron: true
                    ) {
                        ZoneAccessRulesView(zoneId: zone.id, session: session)
                    }

                    // 安全洞察（Security Center Insights）：全套餐免费，读写同 zone-settings.*；
                    // 目的页是叶子（处理链接外跳浏览器，不再 push），eager 门控行即可
                    PermissionGatedNavigationLink(
                        label: String(localized: "安全洞察"),
                        systemImage: "exclamationmark.shield",
                        requiredScope: "zone-settings.read",
                        tint: .red,
                        showsChevron: true
                    ) {
                        SecurityInsightsView(zoneId: zone.id, zoneName: zone.name, session: session)
                    }

                    // 与负载均衡的监控器不同源：这里监控单个源站，单源站也能用
                    PermissionGatedValueLink(
                        label: String(localized: "健康检查"),
                        systemImage: "waveform.path.ecg",
                        requiredScope: "healthcheck.read",
                        tint: .green,
                        showsChevron: true,
                        value: ZoneRoute.healthChecks(zoneId: zone.id, zoneName: zone.name)
                    )

                    ProGatedValueLink(
                        label: String(localized: "负载均衡"),
                        systemImage: "arrow.left.arrow.right",
                        requiredScope: "load-balancers.read",
                        feature: .loadBalancing,
                        tint: .pink,
                        showsChevron: true,
                        value: ZoneRoute.loadBalancers(zoneId: zone.id, zoneName: zone.name)
                    )
                }

                // 整卡仅在读到任一组配置时出现：
                // 机器人管控全套餐可用但需 bot-management.read；
                // 两个 zone setting 是 Pro 起，免费套餐读得到但不可改（editable == false）。
                // 与其给用户一排永远打不开的锁，不如不显示。
                if actionsViewModel.botConfigLoaded || actionsViewModel.aiSettingsAvailable {
                    sectionCard(String(localized: "AI 内容控制")) {
                        if actionsViewModel.botConfigLoaded {
                            // 2026-09-15 起 ai_bots_protection 拆成三类：响应带任一新字段就换成三个选择行，
                            // 否则保留旧的单选作回退
                            if actionsViewModel.usesAICrawlerPolicies {
                                aiCrawlerPolicyRows
                            } else {
                                settingPickerRow(
                                    title: String(localized: "AI 爬虫"),
                                    subtitle: String(localized: "抓取内容用于训练或问答的机器人"),
                                    icon: "ant",
                                    tint: .indigo,
                                    options: AIBotsProtection.allCases,
                                    selection: actionsViewModel.aiBotsProtection,
                                    selectionLabel: actionsViewModel.aiBotsProtection.label,
                                    optionLabel: \.label,
                                    isBusy: actionsViewModel.isUpdatingBotConfig,
                                    canEdit: canEditBots,
                                    deniedScope: "bot-management.write",
                                    requestChange: { mode in
                                        Task { await actionsViewModel.setAIBotsProtection(mode) }
                                    }
                                )
                            }

                            settingToggleRow(
                                title: String(localized: "链接迷宫"),
                                subtitle: String(localized: "用无尽链接消耗违规爬虫"),
                                icon: "arrow.triangle.turn.up.right.diamond",
                                tint: .indigo,
                                isOn: actionsViewModel.crawlerProtection,
                                isBusy: actionsViewModel.isUpdatingBotConfig,
                                canEdit: canEditBots,
                                isLoaded: true,
                                deniedScope: "bot-management.write",
                                requestToggle: { on in
                                    Task { await actionsViewModel.setCrawlerProtection(on) }
                                }
                            )

                            settingToggleRow(
                                title: String(localized: "拦截内容机器人"),
                                subtitle: String(localized: "拦下低可信自动流量，已验证的机器人除外"),
                                icon: "person.badge.shield.checkmark",
                                tint: .indigo,
                                isOn: actionsViewModel.contentBotsProtection,
                                isBusy: actionsViewModel.isUpdatingBotConfig,
                                canEdit: canEditBots,
                                isLoaded: true,
                                deniedScope: "bot-management.write",
                                requestToggle: { on in
                                    Task { await actionsViewModel.setContentBotsProtection(on) }
                                }
                            )

                            // Bot Preference Sync 取代托管 robots.txt：响应带该字段才换，否则保留旧开关
                            if let syncOn = actionsViewModel.botPreferenceSync {
                                settingToggleRow(
                                    title: String(localized: "按偏好生成 robots.txt"),
                                    subtitle: String(localized: "根据以上三项，由 Cloudflare 生成 robots.txt 规则"),
                                    icon: "list.bullet.rectangle",
                                    tint: .teal,
                                    isOn: syncOn,
                                    isBusy: actionsViewModel.isUpdatingBotConfig,
                                    canEdit: canEditBots,
                                    isLoaded: true,
                                    deniedScope: "bot-management.write",
                                    requestToggle: { on in
                                        Task { await actionsViewModel.setBotPreferenceSync(on) }
                                    }
                                )
                            } else {
                                settingToggleRow(
                                    title: String(localized: "托管 robots.txt"),
                                    subtitle: String(localized: "由 Cloudflare 维护，置于现有内容之前"),
                                    icon: "list.bullet.rectangle",
                                    tint: .teal,
                                    isOn: actionsViewModel.managedRobotsTxt,
                                    isBusy: actionsViewModel.isUpdatingBotConfig,
                                    canEdit: canEditBots,
                                    isLoaded: true,
                                    deniedScope: "bot-management.write",
                                    requestToggle: { on in
                                        Task { await actionsViewModel.setManagedRobotsTxt(on) }
                                    }
                                )
                            }

                            settingToggleRow(
                                title: String(localized: "内容使用声明"),
                                subtitle: String(localized: "在 robots.txt 中声明内容的使用许可"),
                                icon: "doc.badge.gearshape",
                                tint: .teal,
                                isOn: actionsViewModel.robotsLicense,
                                isBusy: actionsViewModel.isUpdatingBotConfig,
                                canEdit: canEditBots,
                                isLoaded: true,
                                deniedScope: "bot-management.write",
                                requestToggle: { on in
                                    Task { await actionsViewModel.setRobotsLicense(on) }
                                }
                            )
                        }

                        if actionsViewModel.aiTrainingRedirectAvailable {
                            settingToggleRow(
                                title: String(localized: "AI 训练重定向"),
                                subtitle: String(localized: "把用于模型训练的爬虫引走"),
                                icon: "arrow.triangle.branch",
                                tint: .purple,
                                isOn: actionsViewModel.aiTrainingRedirect,
                                isBusy: actionsViewModel.isTogglingAITrainingRedirect,
                                canEdit: canEditSettings,
                                isLoaded: true,
                                deniedScope: "zone-settings.write",
                                requestToggle: { on in
                                    Task { await actionsViewModel.setAITrainingRedirect(on) }
                                }
                            )
                        }

                        if actionsViewModel.markdownForAgentsAvailable {
                            settingToggleRow(
                                title: String(localized: "面向 Agent 的 Markdown"),
                                subtitle: String(localized: "按请求把页面转成 Markdown 返回"),
                                icon: "doc.plaintext",
                                tint: .teal,
                                isOn: actionsViewModel.markdownForAgents,
                                isBusy: actionsViewModel.isTogglingMarkdownForAgents,
                                canEdit: canEditSettings,
                                isLoaded: true,
                                deniedScope: "zone-settings.write",
                                requestToggle: { on in
                                    Task { await actionsViewModel.setMarkdownForAgents(on) }
                                }
                            )
                        }
                    }
                }

                sectionCard(String(localized: "操作")) {
                    settingToggleRow(
                        title: String(localized: "Under Attack 模式"),
                        subtitle: String(localized: "对所有访客启用质询页"),
                        icon: "shield.lefthalf.filled",
                        tint: .red,
                        isOn: actionsViewModel.underAttack,
                        isBusy: actionsViewModel.isTogglingUnderAttack,
                        canEdit: canEditSettings,
                        isLoaded: actionsViewModel.settingsLoaded,
                        deniedScope: canReadSettings ? "zone-settings.write" : "zone-settings.read",
                        requestToggle: { on in pendingAction = .underAttack(on) }
                    )

                    precursorRow

                    settingToggleRow(
                        title: String(localized: "开发模式"),
                        subtitle: String(localized: "临时绕过缓存（3 小时后自动关闭）"),
                        icon: "hammer",
                        tint: .blue,
                        isOn: actionsViewModel.devMode,
                        isBusy: actionsViewModel.isTogglingDevMode,
                        canEdit: canEditSettings,
                        isLoaded: actionsViewModel.settingsLoaded,
                        deniedScope: canReadSettings ? "zone-settings.write" : "zone-settings.read",
                        requestToggle: { on in pendingAction = .devMode(on) }
                    )

                    // 暂停态一直可读（zone.read 是登录基础权限），故 isLoaded 恒 true：
                    // 无 zone.write 时行内显示当前开/关而非锁，符合「能看不能改」的一致语义。
                    settingToggleRow(
                        title: String(localized: "暂停 Cloudflare"),
                        subtitle: String(localized: "流量绕过 Cloudflare，仅保留 DNS 解析"),
                        icon: "pause.circle",
                        tint: .gray,
                        isOn: actionsViewModel.paused,
                        isBusy: actionsViewModel.isTogglingPause,
                        canEdit: canEditZone,
                        isLoaded: true,
                        deniedScope: "zone.write",
                        requestToggle: { on in pendingAction = .pause(on) }
                    )

                    Button {
                        if canPurge {
                            showPurgeConfirm = true
                        } else {
                            deniedScopeHint = "cache.purge"
                            showActionDenied = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "trash", color: .ocOrange)
                            Text("清理全部缓存")
                                .foregroundStyle(.primary)
                            Spacer()
                            if actionsViewModel.isPurging {
                                ProgressView()
                            } else if !canPurge {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .disabled(actionsViewModel.isPurging)

                    // 标记过期（invalidate_cache，2026-09-28 GA）：与清除同权限（cache.purge）、同门槛（免费）
                    Button {
                        if canPurge {
                            showInvalidateConfirm = true
                        } else {
                            deniedScopeHint = "cache.purge"
                            showActionDenied = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "clock.arrow.circlepath", color: .ocOrange)
                            Text("标记过期")
                                .foregroundStyle(.primary)
                            Spacer()
                            if !canPurge {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .disabled(actionsViewModel.isPurging)

                    Button {
                        if canPurge {
                            showPurgeSheet = true
                        } else {
                            deniedScopeHint = "cache.purge"
                            showActionDenied = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            TintIcon(systemImage: "scissors", color: .ocOrange)
                            Text("按目标清理缓存")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: canPurge ? "chevron.right" : "lock.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .disabled(actionsViewModel.isPurging)
                }

                if !zone.nameServers.isEmpty {
                    sectionCard("Name Servers") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(zone.nameServers, id: \.self) { server in
                                Text(server)
                                    .font(.callout.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Zone ID footer
                Text("Zone ID · \(zone.id)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 8)
            }
            .padding()
        }
        .background { SkyBackground() }
        .navigationTitle(zone.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // 置顶以 PinnedResourceStore 为准（跨资源类型统一）；同时把旧的
                // CachedZone.pinned 字段镜像写回，老数据/其它入口读它时不至于分裂。
                Button(isPinned ? String(localized: "取消固定") : String(localized: "固定到首页"),
                       systemImage: isPinned ? "pin.fill" : "pin") {
                    let nowPinned = pinnedStore.toggle(
                        PinnedResource(type: .zone, resourceId: zone.id),
                        accountId: zone.accountId
                    )
                    withAnimation(.smooth) {
                        zone.pinned = nowPinned
                    }
                    SafeCache.perform("pin 状态保存") { try modelContext.save() }
                }
                .contentTransition(.symbolEffect(.replace))
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: zone.pinned)
        .sensoryFeedback(.success, trigger: actionsViewModel.didPurge)
        .sensoryFeedback(.success, trigger: actionsViewModel.didInvalidate)
        .task {
            if canReadSettings {
                await actionsViewModel.loadSettings()
                await actionsViewModel.loadAISettings()
            }
            if canReadBots {
                await actionsViewModel.loadBotConfig()
            }
            if canReadPrecursor {
                await actionsViewModel.loadPrecursor()
            }
        }
        .task {
            // 暂停态只需 zone.read（登录必备），与上面的 settings 权限无关：
            // 进页用 API 校准一次，纠正列表缓存里过期的暂停态
            await syncPausedFromAPI()
        }
        .task {
            // 该 zone 尚未统计过记录数（前 50 个之外 / Dashboard 未加载完就进来）：
            // 入页轻量拉一次 total_count 回写缓存，首屏不显示 0 条
            if zone.dnsRecordCount == nil, records.isEmpty, auth.hasScope("dns.read"),
               let count = try? await session.dnsService.recordCount(zoneId: zone.id) {
                zone.dnsRecordCount = count
                SafeCache.perform("dnsRecordCount 保存") { try modelContext.save() }
            }
        }
        .refreshable {
            if auth.hasScope("analytics.read") {
                await analyticsViewModel.refresh()
                await trafficDetailsViewModel.refresh(range: analyticsViewModel.selectedRange)
            }
            if canReadSettings {
                await actionsViewModel.loadSettings()
                await actionsViewModel.loadAISettings()
            }
            if canReadBots {
                await actionsViewModel.loadBotConfig()
            }
            if canReadPrecursor {
                await actionsViewModel.loadPrecursor()
            }
            await syncPausedFromAPI()
        }
        .confirmationDialog(
            pendingAction?.title ?? "",
            isPresented: .init(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            Button(action.confirmLabel) {
                Task {
                    switch action {
                    case .underAttack(let on): await actionsViewModel.setUnderAttack(on)
                    case .devMode(let on):     await actionsViewModel.setDevMode(on)
                    case .pause(let on):
                        if await actionsViewModel.setPaused(on) {
                            writeBackPaused(actionsViewModel.paused)
                        }
                    }
                }
            }
        } message: { action in
            Text(action.message(zoneName: zone.name))
        }
        .confirmationDialog("清理全部缓存？", isPresented: $showPurgeConfirm, titleVisibility: .visible) {
            Button("清理", role: .destructive) {
                Task { await actionsViewModel.purgeCache() }
            }
        } message: {
            Text("将清空 \(zone.name) 在 Cloudflare 边缘的所有缓存，回源流量会短暂上升。")
        }
        .alert("缓存已清理", isPresented: $showPurgeDone) {
            Button("好", role: .cancel) {}
        } message: {
            Text("边缘节点将在数秒内完成清理。")
        }
        .confirmationDialog("标记过期", isPresented: $showInvalidateConfirm, titleVisibility: .visible) {
            Button("标记过期") {
                Task { await actionsViewModel.purgeCache(action: .invalidate) }
            }
        } message: {
            Text(String(localized: "将把该域名的全部缓存标记为过期。") + "\n"
                 + String(localized: "保留缓存但标记为过期，下次请求时向源站校验；内容没变（304）就继续用缓存。需要源站返回 ETag 或 Last-Modified。"))
        }
        .alert("已标记为过期", isPresented: $showInvalidateDone) {
            Button("好", role: .cancel) {}
        } message: {
            Text("保留缓存但标记为过期，下次请求时向源站校验；内容没变（304）就继续用缓存。需要源站返回 ETag 或 Last-Modified。")
        }
        .sheet(isPresented: $showPurgeSheet) {
            PurgeCacheSheet(zoneName: zone.name) { mode, items, action in
                switch mode {
                case .url:    await actionsViewModel.purgeURLs(items, action: action)
                case .prefix: await actionsViewModel.purgePrefixes(items, action: action)
                case .host:   await actionsViewModel.purgeHosts(items, action: action)
                case .tag:    await actionsViewModel.purgeTags(items, action: action)
                }
            }
        }
        .onChange(of: actionsViewModel.didPurge) {
            showPurgeDone = true
        }
        .onChange(of: actionsViewModel.didInvalidate) {
            showInvalidateDone = true
        }
        .alert("权限不足", isPresented: $showActionDenied) {
            if let sessionId = auth.currentSessionId, !deniedScopeHint.isEmpty {
                Button("一键重授权") {
                    let scope = deniedScopeHint
                    Task { await auth.reauthorize(sessionId: sessionId, additionalScopes: [scope]) }
                }
            }
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含此操作所需权限（\(deniedScopeHint)）。点「一键重授权」补齐，无需退出登录。")
        }
        .alert("操作失败", isPresented: .init(
            get: { actionsViewModel.error != nil },
            set: { if !$0 { actionsViewModel.error = nil } }
        )) {
            apiErrorDocButton(for: actionsViewModel.error)
            Button("好", role: .cancel) {}
        } message: {
            Text(actionsViewModel.error ?? "")
        }
    }

    // MARK: - 暂停态与缓存同步

    /// 从 API 校准暂停态并回写缓存（列表/首页读的是同一份 CachedZone）
    private func syncPausedFromAPI() async {
        guard let paused = await actionsViewModel.refreshPaused() else { return }
        writeBackPaused(paused)
    }

    private func writeBackPaused(_ paused: Bool) {
        guard zone.paused != paused else { return }
        zone.paused = paused
        SafeCache.perform("暂停状态保存") { try modelContext.save() }
    }

    // MARK: - 设置开关行

    /// 会话级机器人检测（Precursor）：缺读权限显示锁定行（点按走一键重授权）；
    /// 有权限但读取失败（字段已 deprecated、该 zone 无此能力）整行隐藏。
    @ViewBuilder
    private var precursorRow: some View {
        if !canReadPrecursor {
            settingPickerRow(
                title: String(localized: "会话级机器人检测"),
                subtitle: String(localized: "在整个会话中持续评估访客行为（Precursor）"),
                icon: "person.badge.clock",
                tint: .indigo,
                options: PrecursorMode.allCases,
                selection: nil,
                selectionLabel: "",
                optionLabel: \.label,
                isBusy: false,
                canEdit: false,
                isLoaded: false,
                deniedScope: "precursor.read",
                requestChange: { _ in }
            )
        } else if let raw = actionsViewModel.precursorMode {
            settingPickerRow(
                title: String(localized: "会话级机器人检测"),
                subtitle: String(localized: "在整个会话中持续评估访客行为（Precursor）"),
                icon: "person.badge.clock",
                tint: .indigo,
                options: PrecursorMode.allCases,
                selection: PrecursorMode(rawValue: raw),
                selectionLabel: PrecursorMode.displayLabel(for: raw),
                optionLabel: \.label,
                isBusy: actionsViewModel.isUpdatingPrecursor,
                canEdit: canEditPrecursor,
                deniedScope: "precursor.write",
                requestChange: { mode in
                    Task { await actionsViewModel.setPrecursorMode(mode) }
                }
            )
        }
    }

    /// 2026-09 拆分后的三项 AI 爬虫策略（搜索 / 助手与 Agent / 训练），共用同一个 PUT 端点与忙态
    @ViewBuilder
    private var aiCrawlerPolicyRows: some View {
        aiCrawlerPolicyRow(
            title: String(localized: "AI 搜索"),
            subtitle: String(localized: "为回答问题而索引内容的爬虫"),
            icon: "magnifyingglass",
            raw: actionsViewModel.aiSearch,
            options: AICrawlerPolicy.searchOptions
        ) { policy in await actionsViewModel.setAISearch(policy) }

        aiCrawlerPolicyRow(
            title: String(localized: "AI 助手与 Agent"),
            subtitle: String(localized: "代表用户实时抓取页面的机器人"),
            icon: "person.crop.circle.badge.questionmark",
            raw: actionsViewModel.aiUser,
            options: AICrawlerPolicy.searchOptions
        ) { policy in await actionsViewModel.setAIUser(policy) }

        aiCrawlerPolicyRow(
            title: String(localized: "AI 训练"),
            subtitle: String(localized: "抓取内容用于训练或微调模型的爬虫"),
            icon: "ant",
            raw: actionsViewModel.aiTraining,
            options: AICrawlerPolicy.trainingOptions
        ) { policy in await actionsViewModel.setAITraining(policy) }
    }

    private func aiCrawlerPolicyRow(
        title: String,
        subtitle: String,
        icon: String,
        raw: String?,
        options: [AICrawlerPolicy],
        change: @escaping (AICrawlerPolicy) async -> Void
    ) -> some View {
        // 缺省视作「允许」打勾；未知档位不勾任何项，文案原样显示
        let selection: AICrawlerPolicy? = if let raw { AICrawlerPolicy(rawValue: raw) } else { .disabled }
        return settingPickerRow(
            title: title,
            subtitle: subtitle,
            icon: icon,
            tint: .indigo,
            options: options,
            selection: selection,
            selectionLabel: AICrawlerPolicy.displayLabel(for: raw),
            optionLabel: \.label,
            isBusy: actionsViewModel.isUpdatingBotConfig,
            canEdit: canEditBots,
            deniedScope: "bot-management.write",
            requestChange: { policy in Task { await change(policy) } }
        )
    }

    /// canEdit / isLoaded / deniedScope 由调用方给：Under Attack 与开发模式走
    /// zone-settings.*，暂停走 zone.write，两条权限链路不共用。
    /// 多档选择行。与 settingToggleRow 同构，只是右侧从开关换成菜单；
    /// 无写权限时显示当前档位并在点击时提示缺失 scope。
    /// selection 为 nil 表示当前值不在 options 里（未知档位），菜单不打勾、只显示 selectionLabel。
    private func settingPickerRow<Option: Identifiable & Equatable>(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        options: [Option],
        selection: Option?,
        selectionLabel: String,
        optionLabel: @escaping (Option) -> String,
        isBusy: Bool,
        canEdit: Bool,
        isLoaded: Bool = true,
        deniedScope: String,
        requestChange: @escaping (Option) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            TintIcon(systemImage: icon, color: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isBusy {
                ProgressView()
            } else if canEdit {
                Menu {
                    ForEach(options) { option in
                        Button {
                            requestChange(option)
                        } label: {
                            if option == selection {
                                Label(optionLabel(option), systemImage: "checkmark")
                            } else {
                                Text(optionLabel(option))
                            }
                        }
                    }
                } label: {
                    Text(selectionLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityLabel(title)
            } else {
                Button {
                    deniedScopeHint = deniedScope
                    showActionDenied = true
                } label: {
                    if isLoaded {
                        Text(selectionLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    } else {
                        // 缺读权限：只显示锁，点按提示补授权
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel(title)
            }
        }
    }

    private func settingToggleRow(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        isOn: Bool,
        isBusy: Bool,
        canEdit: Bool,
        isLoaded: Bool,
        deniedScope: String,
        requestToggle: @escaping (Bool) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            TintIcon(systemImage: icon, color: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isBusy {
                ProgressView()
            } else if canEdit && isLoaded {
                Toggle("", isOn: Binding(
                    get: { isOn },
                    set: { on in requestToggle(on) }
                ))
                .labelsHidden()
                .accessibilityLabel(title)
            } else {
                Button {
                    deniedScopeHint = deniedScope
                    showActionDenied = true
                } label: {
                    if isLoaded {
                        // 只读授权：显示当前状态
                        Text(isOn ? String(localized: "开") : String(localized: "关"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityValue(isLoaded ? (isOn ? String(localized: "开") : String(localized: "关")) : "")
                .accessibilityHint("需要额外授权才能修改")
            }
        }
    }

    // MARK: - Hero 卡

    private var heroCard: some View {
        VStack(spacing: 10) {
            ZoneAvatar(domain: zone.name, size: 52)
            Text(zone.name)
                .font(.system(.title2, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    StatusDot(status: displayStatus, size: 7)
                        .accessibilityHidden(true)
                    Text(statusText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(displayStatus == "active" ? Color.green : Color.secondary)
                }
                .accessibilityElement(children: .combine)
                PlanBadge(planName: zone.planName)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .glassIsland()
    }

    // MARK: - 分组卡

    private func sectionCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                content()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
            }
            .glassIsland(cornerRadius: OCLayout.chipRadius)
        }
    }

}

// MARK: - 操作区待确认动作

/// 「操作」区的开关动作：先弹确认说明影响，确认后才调 API
private nonisolated enum PendingZoneAction: Identifiable {
    case underAttack(Bool)
    case devMode(Bool)
    /// true = 暂停 Cloudflare，false = 恢复
    case pause(Bool)

    var id: String {
        switch self {
        case .underAttack(let on): "underAttack-\(on)"
        case .devMode(let on):     "devMode-\(on)"
        case .pause(let on):       "pause-\(on)"
        }
    }

    var title: String {
        switch self {
        case .underAttack(true):  String(localized: "开启 Under Attack 模式？")
        case .underAttack(false): String(localized: "关闭 Under Attack 模式？")
        case .devMode(true):      String(localized: "开启开发模式？")
        case .devMode(false):     String(localized: "关闭开发模式？")
        case .pause(true):        String(localized: "暂停 Cloudflare？")
        case .pause(false):       String(localized: "恢复 Cloudflare？")
        }
    }

    var confirmLabel: String {
        switch self {
        case .underAttack(true), .devMode(true):   String(localized: "确认开启")
        case .underAttack(false), .devMode(false): String(localized: "确认关闭")
        case .pause(true):                         String(localized: "确认暂停")
        case .pause(false):                        String(localized: "确认恢复")
        }
    }

    func message(zoneName: String) -> String {
        switch self {
        case .underAttack(true):
            String(localized: "开启后，访问 \(zoneName) 的所有访客都会先看到约 5 秒的质询页，可能影响正常用户体验。适合正在遭受攻击时使用。")
        case .underAttack(false):
            String(localized: "关闭后，\(zoneName) 的安全级别将恢复为「中」。")
        case .devMode(true):
            String(localized: "开启后，\(zoneName) 将临时绕过 Cloudflare 缓存，源站负载会上升；3 小时后自动关闭。")
        case .devMode(false):
            String(localized: "关闭后，\(zoneName) 立即恢复缓存加速。")
        case .pause(true):
            String(localized: "暂停后，\(zoneName) 的流量不再经过 Cloudflare：WAF、缓存加速与源站 IP 隐藏都会失效，DNS 仍由 Cloudflare 解析。生效约需 5 分钟。")
        case .pause(false):
            String(localized: "恢复后，\(zoneName) 的流量重新经由 Cloudflare 代理，缓存与安全防护随之生效。生效约需 5 分钟。")
        }
    }
}

// MARK: - 行尾 value 标注

private extension View {
    /// 给 PermissionGatedNavigationLink 行附加右侧 value 文本的轻量包装
    func listRowStyleValue(_ value: String) -> some View {
        overlay(alignment: .trailing) {
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.trailing, 24)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - 域名子树的值式路由

/// 域名详情子树里「目的页自身还要继续 push」的入口路由。
/// ZoneDetailView 有三个宿主栈（Dashboard 栈 / 网域 compact 栈 / iPad split detail 栈），
/// 本路由的 navdest 必须在三处栈根都注册——统一走 `zoneRouteDestinations(session:)`。
enum ZoneRoute: Hashable {
    case rulesHub(zoneId: String, zoneName: String)
    case loadBalancers(zoneId: String, zoneName: String)
    case healthChecks(zoneId: String, zoneName: String)
    case dnsSettings(zoneId: String, zoneName: String)
    case snippets(zoneId: String, zoneName: String)
    case bulkRedirects
}

extension View {
    /// 在宿主栈根注册域名子树路由（挂栈根直接子级、`.id()` 内侧，铁律见 DashboardView 外壳注释）
    func zoneRouteDestinations(session: SessionStore) -> some View {
        navigationDestination(for: ZoneRoute.self) { route in
            switch route {
            case .rulesHub(let zoneId, let zoneName):
                ZoneRulesHubView(zoneId: zoneId, zoneName: zoneName, session: session)
            case .loadBalancers(let zoneId, let zoneName):
                LoadBalancerListView(zoneId: zoneId, zoneName: zoneName, session: session)
            case .healthChecks(let zoneId, let zoneName):
                HealthCheckListView(zoneId: zoneId, zoneName: zoneName, session: session)
            case .dnsSettings(let zoneId, let zoneName):
                ZoneDNSSettingsView(zoneId: zoneId, zoneName: zoneName, session: session)
            case .snippets(let zoneId, let zoneName):
                SnippetsListView(zoneId: zoneId, zoneName: zoneName, session: session)
            case .bulkRedirects:
                BulkRedirectListsView(session: session)
            }
        }
    }
}
