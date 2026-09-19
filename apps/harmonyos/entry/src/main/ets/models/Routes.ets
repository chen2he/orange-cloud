// NavPathStack 路由名与参数类型（对齐 Android OrangeCloudRoot 的 Dest）。
// 所有 zone 级页面共用 ZoneRouteParam；账号级列表页无参或用 IdNameParam。

export class Routes {
  // zone 级
  static readonly ZONE_DETAIL = 'zoneDetail';
  static readonly DNS = 'dnsList';
  static readonly ANALYTICS = 'analytics';
  static readonly WAF = 'waf';
  static readonly SNIPPETS = 'snippets';
  static readonly SNIPPET_EDIT = 'snippetEdit';
  static readonly ZONE_SETTINGS = 'zoneSettings';
  static readonly SSL = 'ssl';
  static readonly SSL_CERTS = 'sslCerts';
  static readonly PERFORMANCE = 'performance';
  static readonly TRANSFORM = 'transform';
  static readonly ACCESS_RULES = 'accessRules';
  static readonly CACHE_RULES = 'cacheRules';
  static readonly RATE_LIMIT = 'rateLimit';
  static readonly EMAIL_ROUTING = 'emailRouting';
  static readonly LOAD_BALANCER = 'loadBalancer';
  static readonly HEALTH_CHECK = 'healthCheck';
  static readonly DNS_SETTINGS = 'dnsSettings';
  static readonly REGISTRAR = 'registrar';
  static readonly REQUEST_TRACER = 'requestTracer';
  static readonly WORKER_BUILDS = 'workerBuilds';
  static readonly MANAGED_HEADERS = 'managedHeaders';
  static readonly URL_SCANNER = 'urlScanner';
  static readonly WORKER_ROUTES = 'workerRoutes';
  static readonly RULES_HUB = 'rulesHub';
  static readonly PHASE_RULES = 'phaseRules';
  static readonly PAGE_RULES = 'pageRules';
  static readonly URL_NORMALIZATION = 'urlNormalization';
  // 账号级
  static readonly TUNNELS = 'tunnels';
  static readonly TUNNEL_DETAIL = 'tunnelDetail';
  static readonly ZERO_TRUST = 'zeroTrust';
  static readonly ZT_ACCESS = 'ztAccess';
  static readonly ZT_GATEWAY = 'ztGateway';
  static readonly ACCESS_APP_DETAIL = 'accessAppDetail';
  static readonly REDIRECTS = 'redirects';
  static readonly REDIRECT_ITEMS = 'redirectItems';
  static readonly AUDIT = 'audit';
  static readonly ALERTING = 'alerting';
  static readonly STATUS = 'status';
  static readonly LB_POOLS = 'lbPools';
  static readonly LB_MONITORS = 'lbMonitors';
  static readonly TURNSTILE = 'turnstile';
  static readonly TURNSTILE_DETAIL = 'turnstileDetail';
  // 开发平台
  static readonly WORKERS = 'workers';
  static readonly WORKER_DETAIL = 'workerDetail';
  static readonly WORKER_CREATE = 'workerCreate';
  static readonly WORKER_SECRETS = 'workerSecrets';
  static readonly WORKER_TRIGGERS = 'workerTriggers';
  static readonly WORKER_DOMAINS = 'workerDomains';
  static readonly WORKER_DEPLOYMENTS = 'workerDeployments';
  static readonly TAIL = 'tail';
  static readonly WORKER_LOGS = 'workerLogs';
  static readonly PAGES = 'pages';
  static readonly PAGES_DETAIL = 'pagesDetail';
  static readonly PAGES_DEPLOYMENT = 'pagesDeployment';
  static readonly PAGES_DOMAINS = 'pagesDomains';
  static readonly DEV_AI = 'devAI';
  static readonly DEV_AI_GATEWAY = 'devAIGateway';
  static readonly DEV_QUEUES = 'devQueues';
  static readonly QUEUE_DETAIL = 'queueDetail';
  static readonly DEV_HYPERDRIVE = 'devHyperdrive';
  static readonly HYPERDRIVE_DETAIL = 'hyperdriveDetail';
  static readonly AI_GATEWAY_DETAIL = 'aiGatewayDetail';
  static readonly DEV_DO = 'devDO';
  static readonly DO_DETAIL = 'doDetail';
  // 存储
  static readonly R2_BUCKETS = 'r2Buckets';
  static readonly R2_OBJECTS = 'r2Objects';
  static readonly R2_SETTINGS = 'r2Settings';
  static readonly D1_DATABASES = 'd1Databases';
  static readonly D1_QUERY = 'd1Query';
  static readonly D1_TABLE = 'd1Table';
  static readonly KV_NAMESPACES = 'kvNamespaces';
  static readonly KV_KEYS = 'kvKeys';
  // 其它
  static readonly IDENTITY_DETAIL = 'identityDetail';
  static readonly WEB_AUTH = 'webAuth';
  static readonly TOOLBOX = 'toolbox';
  static readonly PAYWALL = 'paywall';
}

/// 付费墙：feature = 触发闸门的场景名（空 = 从设置页常驻入口进来）
export interface PaywallParam {
  feature: string;
}

export interface ZoneRouteParam {
  zoneId: string;
  zoneName: string;
}

export interface IdNameParam {
  id: string;
  name: string;
}

export interface NameParam {
  name: string;
}

/// D1 表浏览：库 + 表名
export interface D1TableParam {
  dbId: string;
  dbName: string;
  table: string;
}

/// Snippet 编辑：zone + snippet 名（空 = 新建）
export interface SnippetEditParam {
  zoneId: string;
  zoneName: string;
  snippetName: string;
}

/// Rulesets phase 泛化列表页：zone + phase 标识 + 页面标题
export interface PhaseRulesParam {
  zoneId: string;
  zoneName: string;
  phase: string;
  title: string;
}

/// Pages 部署详情：项目名 + 部署 ID + 是否生产环境
export interface PagesDeploymentParam {
  projectName: string;
  deploymentId: string;
  isProduction: boolean;
}
