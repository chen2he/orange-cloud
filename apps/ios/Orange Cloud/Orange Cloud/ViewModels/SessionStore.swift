//
//  SessionStore.swift
//  Orange Cloud
//
//  登录后的会话容器：持有 CFAPIClient 与各 Service，管理账号选择。
//  默认选中该身份上次选定的账号（没有记录才退回第一个）。
//

import Foundation
import Observation

@Observable
@MainActor
final class SessionStore {

    let accountService:    AccountService
    let zoneService:       ZoneService
    let dnsService:        DNSService
    let workerService:     WorkerService
    let workerTailService: WorkerTailService
    let workerLogsService: WorkerLogsService
    let analyticsService:  AnalyticsService
    let r2Service:         R2Service
    let d1Service:         D1Service
    let kvService:         KVService
    let tunnelService:     TunnelService
    let wafService:        WAFService
    let snippetService:    SnippetService
    let zoneSettingsService: ZoneSettingsService
    let botManagementService:      BotManagementService
    let healthCheckService:        HealthCheckService
    let dnsSettingsService:        DNSSettingsService
    let registrarService:          RegistrarService
    let requestTracerService:      RequestTracerService
    let r2CatalogService:          R2CatalogService
    let workerBuildService:        WorkerBuildService
    let alertingService:           AlertingService
    let managedHeaderService:      ManagedHeaderService
    let urlScannerService:         URLScannerService
    let sslCertificateService:     SSLCertificateService
    let transformRuleService:      TransformRuleService
    let firewallAccessRuleService: FirewallAccessRuleService
    let cacheRuleService:          CacheRuleService
    let pagesService:              PagesService
    let loadBalancerService:       LoadBalancerService
    let bulkRedirectService:       BulkRedirectService
    let auditLogService:           AuditLogService
    let emailRoutingService:       EmailRoutingService
    let rateLimitService:          RateLimitService
    let zeroTrustService:          ZeroTrustService
    let queueService:              QueueService
    let aiGatewayService:          AIGatewayService
    let durableObjectService:      DurableObjectService
    let workersAIService:          WorkersAIService
    let hyperdriveService:         HyperdriveService
    let zoneRulesetService:        ZoneRulesetService
    let turnstileService:          TurnstileService
    let r2SQLService:              R2SQLService
    let workerIssuesService:       WorkerIssuesService
    let securityInsightService:    SecurityInsightService
    let zoneAdaptiveAnalyticsService: ZoneAdaptiveAnalyticsService
    let precursorService:          PrecursorService

    var accounts: [Account] = []
    var selectedAccount: Account? {
        didSet {
            // Widget 自取用量数据需要知道当前账户
            UserDefaults(suiteName: WidgetSnapshot.appGroupID)?
                .set(selectedAccount?.id, forKey: "currentAccountId")
            // 记住本身份默认进入的账号，下次冷启动直接进它（issue #71）
            if let sessionId, let id = selectedAccount?.id {
                UserDefaults.standard.set(id, forKey: AuthManager.defaultAccountKey(sessionId))
            }
        }
    }
    var isLoadingAccounts = false
    var error: String?

    private let authManager: AuthManager
    /// 本会话对应的登录身份（SessionStore 按身份重建，加载完成回填账号名时
    /// 不能临时取 currentSessionId——异步期间用户可能已切到别的身份）
    private let sessionId: UUID?

    init(authManager: AuthManager) {
        self.authManager = authManager
        self.sessionId = authManager.currentSessionId
        let client = CFAPIClient(authManager: authManager)
        self.accountService    = AccountService(client: client)
        self.zoneService       = ZoneService(client: client)
        self.dnsService        = DNSService(client: client)
        self.workerService     = WorkerService(client: client)
        self.workerTailService = WorkerTailService(client: client)
        self.workerLogsService = WorkerLogsService(client: client)
        self.analyticsService  = AnalyticsService(client: client)
        self.r2Service         = R2Service(client: client)
        self.d1Service         = D1Service(client: client)
        self.kvService         = KVService(client: client)
        self.tunnelService     = TunnelService(client: client)
        self.wafService        = WAFService(client: client)
        self.snippetService    = SnippetService(client: client)
        self.zoneSettingsService = ZoneSettingsService(client: client)
        self.botManagementService      = BotManagementService(client: client)
        self.healthCheckService        = HealthCheckService(client: client)
        self.dnsSettingsService        = DNSSettingsService(client: client)
        self.registrarService          = RegistrarService(client: client)
        self.requestTracerService      = RequestTracerService(client: client)
        self.r2CatalogService          = R2CatalogService(client: client)
        self.workerBuildService        = WorkerBuildService(client: client)
        self.alertingService           = AlertingService(client: client)
        self.managedHeaderService      = ManagedHeaderService(client: client)
        self.urlScannerService         = URLScannerService(client: client)
        self.sslCertificateService     = SSLCertificateService(client: client)
        self.transformRuleService      = TransformRuleService(client: client)
        self.firewallAccessRuleService = FirewallAccessRuleService(client: client)
        self.cacheRuleService          = CacheRuleService(client: client)
        self.pagesService              = PagesService(client: client)
        self.loadBalancerService       = LoadBalancerService(client: client)
        self.bulkRedirectService       = BulkRedirectService(client: client)
        self.auditLogService           = AuditLogService(client: client)
        self.emailRoutingService       = EmailRoutingService(client: client)
        self.rateLimitService          = RateLimitService(client: client)
        self.zeroTrustService          = ZeroTrustService(client: client)
        self.queueService              = QueueService(client: client)
        self.aiGatewayService          = AIGatewayService(client: client)
        self.durableObjectService      = DurableObjectService(client: client)
        self.workersAIService          = WorkersAIService(client: client)
        self.hyperdriveService         = HyperdriveService(client: client)
        self.zoneRulesetService        = ZoneRulesetService(client: client)
        self.turnstileService          = TurnstileService(client: client)
        self.r2SQLService              = R2SQLService(client: client)
        self.workerIssuesService       = WorkerIssuesService(client: client)
        self.securityInsightService    = SecurityInsightService(client: client)
        self.zoneAdaptiveAnalyticsService = ZoneAdaptiveAnalyticsService(client: client)
        self.precursorService          = PrecursorService(client: client)
    }

    /// 幂等加载账号列表，选中上次选定的账号（没有则首个）
    func ensureAccounts() async {
        guard accounts.isEmpty, !isLoadingAccounts else { return }
        isLoadingAccounts = true
        error = nil
        do {
            accounts = try await accountService.listAccounts()
            if selectedAccount == nil {
                // 优先用用户上次选定的默认账号，落空（首次登录 / 账号已被移除）才回退首个
                let preferred = sessionId.flatMap {
                    UserDefaults.standard.string(forKey: AuthManager.defaultAccountKey($0))
                }
                selectedAccount = accounts.first { $0.id == preferred } ?? accounts.first
            }
            // 登录身份的展示名同步为真实账号名（设置页与 Dashboard 一致）
            if let name = accounts.first?.name, let sessionId {
                authManager.updateSessionLabel(name, for: sessionId)
            }
            // 把本身份的账号并入 Widget 账号目录（小组件「选择账号」picker 数据源）
            if let sessionId {
                WidgetDataStore.mergeAccounts(
                    accounts.map { WidgetAccount(id: $0.id, name: $0.name, sessionId: sessionId.uuidString) },
                    sessionId: sessionId.uuidString
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingAccounts = false
    }
}
