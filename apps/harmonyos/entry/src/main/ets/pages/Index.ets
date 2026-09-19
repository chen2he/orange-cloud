// 根页面：按登录态切换 登录页 / 主壳（5 Tab + 单栈下钻）。
// pageMap 是全应用路由表；各批次模块落地后在此登记，未登记路由走 ComingSoonPage 兜底。
import { HdsNavigation } from '@kit.UIDesignKit';
import { authManager } from '../core/auth/AuthManager';
import { entitlement } from '../core/purchase/EntitlementStore';
import { Routes } from '../models/Routes';
import { LoginView } from '../views/auth/LoginView';
import { WebAuthPage } from '../views/auth/WebAuthPage';
import { MainShell } from '../views/MainShell';
import { OCSkyBackground } from '../views/common/OCSky';
import { ComingSoonPage } from '../views/common/ComingSoonPage';
import { DNSListPage } from '../views/zones/DNSListPage';
import { ZoneDetailPage } from '../views/zones/ZoneDetailPage';
import { ZoneAnalyticsPage } from '../views/zones/ZoneAnalyticsPage';
import { HealthCheckPage } from '../views/zones/HealthCheckPage';
import { ZoneDnsSettingsPage } from '../views/zones/ZoneDnsSettingsPage';
import { RegistrarPage } from '../views/account/RegistrarPage';
import { RequestTracerPage } from '../views/account/RequestTracerPage';
import { WorkerBuildsPage } from '../views/workers/WorkerBuildsPage';
import { ManagedHeadersPage } from '../views/zones/ManagedHeadersPage';
import { URLScannerPage } from '../views/account/URLScannerPage';
import { ZoneSettingsPage } from '../views/zones/ZoneSettingsPage';
import { ZonePerformancePage } from '../views/zones/ZonePerformancePage';
import { ZoneSslPage } from '../views/zones/ZoneSslPage';
import { SslCertsPage } from '../views/zones/SslCertsPage';
import { WafRulesPage } from '../views/zones/WafRulesPage';
import { CacheRulesPage } from '../views/zones/CacheRulesPage';
import { RateLimitPage } from '../views/zones/RateLimitPage';
import { TransformRulesPage } from '../views/zones/TransformRulesPage';
import { AccessRulesPage } from '../views/zones/AccessRulesPage';
import { SnippetsPage } from '../views/zones/SnippetsPage';
import { SnippetEditPage } from '../views/zones/SnippetEditPage';
import { EmailRoutingPage } from '../views/zones/EmailRoutingPage';
import { WorkerListPage } from '../views/workers/WorkerListPage';
import { WorkerDetailPage } from '../views/workers/WorkerDetailPage';
import { WorkerCreatePage } from '../views/workers/WorkerCreatePage';
import { WorkerTailPage } from '../views/workers/WorkerTailPage';
import { WorkerLogsPage } from '../views/workers/WorkerLogsPage';
import { WorkerBindingsPage } from '../views/workers/WorkerBindingsPage';
import { WorkerTriggersPage } from '../views/workers/WorkerTriggersPage';
import { WorkerDeploymentsPage } from '../views/workers/WorkerDeploymentsPage';
import { WorkerDomainsPage } from '../views/workers/WorkerDomainsPage';
import { QueuesPage, QueueDetailPage, AIGatewayPage, AIGatewayDetailPage, DurableObjectsPage, DurableObjectDetailPage, HyperdrivePage, HyperdriveDetailPage, WorkersAIPage } from '../views/devhub/DevPlatformPages';
import { PagesListPage } from '../views/pages/PagesListPage';
import { PagesDetailPage } from '../views/pages/PagesDetailPage';
import { R2BucketsPage, R2ObjectsPage } from '../views/storage/R2Pages';
import { D1DatabasesPage, D1QueryPage, D1TablePage } from '../views/storage/D1Pages';
import { KVNamespacesPage, KVKeysPage } from '../views/storage/KVPages';
import { TunnelListPage, TunnelDetailPage } from '../views/account/TunnelPages';
import { ZeroTrustPage, AccessAppDetailPage } from '../views/account/ZeroTrustPage';
import { AuditLogPage } from '../views/account/AuditLogPage';
import { AlertingPage } from '../views/account/AlertingPage';
import { StatusPage } from '../views/account/StatusPage';
import { RedirectListsPage, RedirectItemsPage } from '../views/account/RedirectsPages';
import { LoadBalancerPage } from '../views/zones/LoadBalancerPage';
import { WorkerRoutesPage } from '../views/zones/WorkerRoutesPage';
import { RulesHubPage } from '../views/zones/RulesHubPage';
import { PhaseRulesPage } from '../views/zones/PhaseRulesPage';
import { PageRulesPage } from '../views/zones/PageRulesPage';
import { UrlNormalizationPage } from '../views/zones/UrlNormalizationPage';
import { LBPoolsPage } from '../views/account/LBPoolsPage';
import { LBMonitorsPage } from '../views/account/LBMonitorsPage';
import { R2SettingsPage } from '../views/storage/R2SettingsPage';
import { PagesDeploymentPage } from '../views/pages/PagesDeploymentPage';
import { PagesDomainsPage } from '../views/pages/PagesDomainsPage';
import { TurnstileListPage, TurnstileDetailPage } from '../views/turnstile/TurnstilePages';
import { ToolboxPage } from '../views/toolbox/ToolboxPage';
import { GuidesListPage } from '../views/guides/GuidesListPage';
import { GuideArticlePage } from '../views/guides/GuideArticlePage';
import { IdentityDetailPage } from '../views/settings/IdentityDetailPage';
import { PaywallPage } from '../views/paywall/PaywallPage';
import { PrivacyConsentPage } from '../views/common/PrivacyConsentPage';
import { AppPrefs } from '../core/system/AppPrefs';
import { motionPrefs } from '../views/common/Daybreak';

@Entry
@ComponentV2
struct Index {
  @Local pathStack: NavPathStack = new NavPathStack();
  /// 隐私同意门：'checking'（读偏好中，只画天色防闪）| 'needed' | 'accepted'
  @Local privacyGate: string = 'checking';

  aboutToAppear(): void {
    AppPrefs.getPrivacyAccepted().then((accepted: boolean) => {
      if (accepted) {
        this.privacyGate = 'accepted';
        this.startApp();
      } else {
        this.privacyGate = 'needed';
      }
    }).catch(() => {
      // 偏好读取失败按未同意处理（宁可多问一次，不可跳过合规门）
      this.privacyGate = 'needed';
    });
  }

  /// 同意后才启动会话恢复（其中可能有 token 刷新网络请求）
  private startApp(): void {
    // 减少动画偏好要在首屏画之前就位，否则第一屏仍会做浮现过渡
    AppPrefs.getReduceMotion().then((on: boolean) => {
      motionPrefs.reduced = on;
    }).catch(() => {
    });
    // 「新功能」的「老用户升级 vs 全新安装」快照由 AuthManager.bootstrap 在翻 status 前置位
    authManager.bootstrap().catch(() => {
      // 失败时 status 停留在 loggedOut，由登录页兜底
    });
    // Pro 权益：先按本机已发放记录点亮（无网络，避免付过款的用户启动瞬间是免费态），
    // 再走 IAP 查询补齐 + 补发漏单（含网络请求，必须在隐私同意之后）
    entitlement.loadCached().catch(() => {
    });
    entitlement.bootstrap().catch(() => {
      // 失败时权益停留在本机记录，用户可在付费墙点「恢复购买」重试
    });
  }

  private acceptPrivacy(): void {
    AppPrefs.setPrivacyAccepted().catch(() => {
      // 落盘失败下次启动会再问一次，不阻断本次使用
    });
    this.privacyGate = 'accepted';
    this.startApp();
  }

  @Builder
  pageMap(name: string) {
    if (name === Routes.DNS) {
      DNSListPage()
    } else if (name === Routes.ZONE_DETAIL) {
      ZoneDetailPage()
    } else if (name === Routes.ANALYTICS) {
      ZoneAnalyticsPage()
    } else if (name === Routes.HEALTH_CHECK) {
      HealthCheckPage()
    } else if (name === Routes.DNS_SETTINGS) {
      ZoneDnsSettingsPage()
    } else if (name === Routes.REGISTRAR) {
      RegistrarPage()
    } else if (name === Routes.REQUEST_TRACER) {
      RequestTracerPage()
    } else if (name === Routes.WORKER_BUILDS) {
      WorkerBuildsPage()
    } else if (name === Routes.MANAGED_HEADERS) {
      ManagedHeadersPage()
    } else if (name === Routes.URL_SCANNER) {
      URLScannerPage()
    } else if (name === Routes.ZONE_SETTINGS) {
      ZoneSettingsPage()
    } else if (name === Routes.PERFORMANCE) {
      ZonePerformancePage()
    } else if (name === Routes.SSL) {
      ZoneSslPage()
    } else if (name === Routes.SSL_CERTS) {
      SslCertsPage()
    } else if (name === Routes.WAF) {
      WafRulesPage()
    } else if (name === Routes.CACHE_RULES) {
      CacheRulesPage()
    } else if (name === Routes.RATE_LIMIT) {
      RateLimitPage()
    } else if (name === Routes.TRANSFORM) {
      TransformRulesPage()
    } else if (name === Routes.ACCESS_RULES) {
      AccessRulesPage()
    } else if (name === Routes.SNIPPETS) {
      SnippetsPage()
    } else if (name === Routes.SNIPPET_EDIT) {
      SnippetEditPage()
    } else if (name === Routes.EMAIL_ROUTING) {
      EmailRoutingPage()
    } else if (name === Routes.WORKERS) {
      WorkerListPage()
    } else if (name === Routes.WORKER_DETAIL) {
      WorkerDetailPage()
    } else if (name === Routes.WORKER_CREATE) {
      WorkerCreatePage()
    } else if (name === Routes.TAIL) {
      WorkerTailPage()
    } else if (name === Routes.WORKER_LOGS) {
      WorkerLogsPage()
    } else if (name === Routes.WORKER_SECRETS) {
      WorkerBindingsPage()
    } else if (name === Routes.WORKER_TRIGGERS) {
      WorkerTriggersPage()
    } else if (name === Routes.WORKER_DEPLOYMENTS) {
      WorkerDeploymentsPage()
    } else if (name === Routes.WORKER_DOMAINS) {
      WorkerDomainsPage()
    } else if (name === Routes.DEV_QUEUES) {
      QueuesPage()
    } else if (name === Routes.QUEUE_DETAIL) {
      QueueDetailPage()
    } else if (name === Routes.DEV_AI_GATEWAY) {
      AIGatewayPage()
    } else if (name === Routes.AI_GATEWAY_DETAIL) {
      AIGatewayDetailPage()
    } else if (name === Routes.DEV_DO) {
      DurableObjectsPage()
    } else if (name === Routes.DO_DETAIL) {
      DurableObjectDetailPage()
    } else if (name === Routes.DEV_HYPERDRIVE) {
      HyperdrivePage()
    } else if (name === Routes.HYPERDRIVE_DETAIL) {
      HyperdriveDetailPage()
    } else if (name === Routes.DEV_AI) {
      WorkersAIPage()
    } else if (name === Routes.PAGES) {
      PagesListPage()
    } else if (name === Routes.PAGES_DETAIL) {
      PagesDetailPage()
    } else if (name === Routes.R2_BUCKETS) {
      R2BucketsPage()
    } else if (name === Routes.R2_OBJECTS) {
      R2ObjectsPage()
    } else if (name === Routes.D1_DATABASES) {
      D1DatabasesPage()
    } else if (name === Routes.D1_QUERY) {
      D1QueryPage()
    } else if (name === Routes.D1_TABLE) {
      D1TablePage()
    } else if (name === Routes.KV_NAMESPACES) {
      KVNamespacesPage()
    } else if (name === Routes.KV_KEYS) {
      KVKeysPage()
    } else if (name === Routes.TUNNELS) {
      TunnelListPage()
    } else if (name === Routes.TUNNEL_DETAIL) {
      TunnelDetailPage()
    } else if (name === Routes.ZERO_TRUST) {
      ZeroTrustPage()
    } else if (name === Routes.ACCESS_APP_DETAIL) {
      AccessAppDetailPage()
    } else if (name === Routes.AUDIT) {
      AuditLogPage()
    } else if (name === Routes.ALERTING) {
      AlertingPage()
    } else if (name === Routes.STATUS) {
      StatusPage()
    } else if (name === Routes.REDIRECTS) {
      RedirectListsPage()
    } else if (name === Routes.REDIRECT_ITEMS) {
      RedirectItemsPage()
    } else if (name === Routes.LOAD_BALANCER) {
      LoadBalancerPage()
    } else if (name === Routes.LB_POOLS) {
      LBPoolsPage()
    } else if (name === Routes.LB_MONITORS) {
      LBMonitorsPage()
    } else if (name === Routes.RULES_HUB) {
      RulesHubPage()
    } else if (name === Routes.PHASE_RULES) {
      PhaseRulesPage()
    } else if (name === Routes.PAGE_RULES) {
      PageRulesPage()
    } else if (name === Routes.URL_NORMALIZATION) {
      UrlNormalizationPage()
    } else if (name === Routes.R2_SETTINGS) {
      R2SettingsPage()
    } else if (name === Routes.PAGES_DEPLOYMENT) {
      PagesDeploymentPage()
    } else if (name === Routes.PAGES_DOMAINS) {
      PagesDomainsPage()
    } else if (name === Routes.WORKER_ROUTES) {
      WorkerRoutesPage()
    } else if (name === Routes.TURNSTILE) {
      TurnstileListPage()
    } else if (name === Routes.TURNSTILE_DETAIL) {
      TurnstileDetailPage()
    } else if (name === Routes.TOOLBOX) {
      ToolboxPage()
    } else if (name === Routes.GUIDES) {
      GuidesListPage()
    } else if (name === Routes.GUIDE_ARTICLE) {
      GuideArticlePage()
    } else if (name === Routes.WEB_AUTH) {
      WebAuthPage()
    } else if (name === Routes.IDENTITY_DETAIL) {
      IdentityDetailPage()
    } else if (name === Routes.PAYWALL) {
      PaywallPage()
    } else {
      ComingSoonPage()
    }
  }

  build() {
    Stack() {
      if (this.privacyGate === 'checking') {
        OCSkyBackground()
      } else if (this.privacyGate === 'needed') {
        PrivacyConsentPage({ onAccept: (): void => this.acceptPrivacy() })
      } else if (authManager.status === 'loggedIn') {
        // 兜底天色：Tab 页由 MainShell 自绘天，下钻二级页各自不透明 oc_bg 兜底；
        // 这层是 push/pop 过渡瞬间的最底垫，避免透明页在动画中露出上一页（画面重叠）。
        OCSkyBackground()
        HdsNavigation(this.pathStack) {
          MainShell({ pathStack: this.pathStack })
        }
        .navDestination(this.pageMap)
        .mode(NavigationMode.Stack)
        .hideTitleBar(true)
      } else {
        LoginView()
      }
    }
    .width('100%')
    .height('100%')
  }
}
