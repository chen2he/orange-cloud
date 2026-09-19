// OAuth scope ID 全集（来自 GET /v4/oauth/scopes 的 id 字段，与 Android Scopes.kt 对齐）。
// 铁律：新增 scope 必须是合法 ID 且已在 OAuth client 注册，否则会崩登录。

/// 功能模块分组（对齐 iOS FeaturePermission.allFeatures）：
/// 登录前权限选择 Sheet 与身份详情「升级授权」共用的元数据。
export interface ScopeModule {
  id: string;
  title: string;
  desc: string;
  icon: string;
  /// 只读所需 scope（模块启用即申请）
  readScopes: string[];
  /// 读写所需 scope（空数组 = 不支持编辑）
  writeScopes: string[];
  /// 必选模块不可关闭（账号信息 + 域名读是全 App 基础）
  required: boolean;
}

export class Scopes {
  static readonly ACCOUNT_READ = 'account-settings.read';
  static readonly ZONE_READ = 'zone.read';
  static readonly ZONE_WRITE = 'zone.write';
  static readonly DNS_READ = 'dns.read';
  static readonly DNS_WRITE = 'dns.write';
  static readonly WORKERS_READ = 'workers-scripts.read';
  static readonly WORKERS_WRITE = 'workers-scripts.write';
  static readonly WORKERS_ROUTES_READ = 'workers-routes.read';
  static readonly WORKERS_ROUTES_WRITE = 'workers-routes.write';
  static readonly WORKERS_TAIL_READ = 'workers-tail.read';
  static readonly SNIPPETS_READ = 'snippets.read';
  static readonly SNIPPETS_WRITE = 'snippets.write';
  static readonly R2_READ = 'workers-r2.read';
  static readonly R2_WRITE = 'workers-r2.write';
  static readonly D1_READ = 'd1.read';
  static readonly D1_WRITE = 'd1.write';
  static readonly KV_READ = 'workers-kv-storage.read';
  static readonly KV_WRITE = 'workers-kv-storage.write';
  static readonly TUNNEL_READ = 'argotunnel.read';
  static readonly TUNNEL_WRITE = 'argotunnel.write';
  static readonly WAF_READ = 'zone-waf.read';
  static readonly WAF_WRITE = 'zone-waf.write';
  /// 机器人管控（GET/PUT /zones/{id}/bot_management）。全套餐可用，含免费版。
  static readonly BOT_MANAGEMENT_READ = 'bot-management.read';
  static readonly BOT_MANAGEMENT_WRITE = 'bot-management.write';
  /// 独立健康检查（/zones/{id}/healthchecks）。免费版不可用。
  static readonly HEALTHCHECK_READ = 'healthcheck.read';
  static readonly HEALTHCHECK_WRITE = 'healthcheck.write';
  /// Zone DNS 设置（/zones/{id}/dns_settings）。DNSSEC 走 dns.read/.write。
  static readonly ZONE_DNS_SETTINGS_READ = 'zone-dns-settings.read';
  static readonly ZONE_DNS_SETTINGS_WRITE = 'zone-dns-settings.write';
  /// Cloudflare Registrar。用新版 /registrar/registrations，旧 /registrar/domains 2026-09-27 停用。
  static readonly REGISTRAR_READ = 'registrar-domains.read';
  static readonly REGISTRAR_ADMIN = 'registrar-domains.admin';
  /// Cloudflare Trace。全套餐可用，但要求管理员角色。
  static readonly REQUEST_TRACER_READ = 'request-tracer.read';
  /// R2 Data Catalog（Iceberg）。2026-08-03 起按目录操作计费。
  static readonly R2_CATALOG_READ = 'r2-catalog.read';
  static readonly R2_CATALOG_WRITE = 'r2-catalog.write';
  /// Workers Builds（CI 构建记录与日志）。
  static readonly WORKERS_CI_READ = 'workers-ci.read';
  static readonly WORKERS_CI_WRITE = 'workers-ci.write';
  /// 托管请求/响应头（Managed Transforms）。
  static readonly MANAGED_HEADERS_READ = 'managed-headers.read';
  static readonly MANAGED_HEADERS_WRITE = 'managed-headers.write';
  /// URL Scanner v2（提交链接做安全扫描）。
  static readonly URL_SCANNER_READ = 'url-scanner.read';
  static readonly URL_SCANNER_WRITE = 'url-scanner.write';
  static readonly ZONE_SETTINGS_READ = 'zone-settings.read';
  static readonly ZONE_SETTINGS_WRITE = 'zone-settings.write';
  static readonly CACHE_PURGE = 'cache.purge';
  static readonly SSL_CERTS_READ = 'ssl-and-certificates.read';
  static readonly SSL_CERTS_WRITE = 'ssl-and-certificates.write';
  static readonly TRANSFORM_READ = 'zone-transform-rules.read';
  static readonly TRANSFORM_WRITE = 'zone-transform-rules.write';
  static readonly FIREWALL_READ = 'firewall-services.read';
  static readonly FIREWALL_WRITE = 'firewall-services.write';
  static readonly ACCOUNT_ANALYTICS_READ = 'account-analytics.read';
  static readonly ANALYTICS_READ = 'analytics.read';
  static readonly CACHE_RULES_READ = 'cache-settings.read';
  static readonly CACHE_RULES_WRITE = 'cache-settings.write';
  static readonly EMAIL_ADDR_READ = 'email-routing-address.read';
  static readonly EMAIL_ADDR_WRITE = 'email-routing-address.write';
  static readonly EMAIL_RULE_READ = 'email-routing-rule.read';
  static readonly EMAIL_RULE_WRITE = 'email-routing-rule.write';
  /// 抑制列表
  static readonly EMAIL_SUPPRESSION_READ = 'email-routing-suppression.read';
  static readonly EMAIL_SUPPRESSION_WRITE = 'email-routing-suppression.write';
  static readonly REDIRECTS_READ = 'mass-url-redirects.read';
  static readonly REDIRECTS_WRITE = 'mass-url-redirects.write';
  static readonly RULE_LISTS_READ = 'account-rule-lists.read';
  static readonly RULE_LISTS_WRITE = 'account-rule-lists.write';
  static readonly LB_READ = 'load-balancers.read';
  static readonly LB_WRITE = 'load-balancers.write';
  static readonly LB_POOLS_READ = 'load-balancing-monitors-and-pools.read';
  static readonly LB_POOLS_WRITE = 'load-balancing-monitors-and-pools.write';
  static readonly ACCESS_READ = 'access.read';
  static readonly ACCESS_WRITE = 'access.write';
  static readonly TEAMS_READ = 'teams.read';
  static readonly TEAMS_WRITE = 'teams.write';
  static readonly PAGES_READ = 'page.read';
  static readonly PAGES_WRITE = 'page.write';
  static readonly AI_READ = 'ai.read';
  static readonly AI_WRITE = 'ai.write';
  static readonly AIG_READ = 'aig.read';
  static readonly AIG_WRITE = 'aig.write';
  static readonly QUEUES_READ = 'queues.read';
  static readonly QUEUES_WRITE = 'queues.write';
  static readonly HYPERDRIVE_READ = 'query-cache.read';
  static readonly HYPERDRIVE_WRITE = 'query-cache.write';
  static readonly WORKERS_OBSERVABILITY_READ = 'workers-observability.read';
  static readonly SINGLE_REDIRECT_READ = 'dynamic-redirect.read';
  static readonly SINGLE_REDIRECT_WRITE = 'dynamic-redirect.write';
  static readonly ORIGIN_RULES_READ = 'origin.read';
  static readonly ORIGIN_RULES_WRITE = 'origin.write';
  static readonly CONFIG_RULES_READ = 'config-settings.read';
  static readonly CONFIG_RULES_WRITE = 'config-settings.write';
  static readonly COMPRESSION_RULES_READ = 'response-compression.read';
  static readonly COMPRESSION_RULES_WRITE = 'response-compression.write';
  static readonly CUSTOM_ERRORS_READ = 'custom-errors.read';
  static readonly CUSTOM_ERRORS_WRITE = 'custom-errors.write';
  static readonly PAGE_RULES_READ = 'page-rules.read';
  static readonly PAGE_RULES_WRITE = 'page-rules.write';
  /// Turnstile 人机验证组件（/accounts/{id}/challenges/widgets）。
  static readonly CHALLENGE_WIDGETS_READ = 'challenge-widgets.read';
  static readonly CHALLENGE_WIDGETS_WRITE = 'challenge-widgets.write';
  /// R2 SQL 查询（api.sql.cloudflarestorage.com，与 r2-catalog.read 配套）
  static readonly R2_CATALOG_SQL_READ = 'r2-catalog-sql.read';
  static readonly NOTIFICATIONS_READ = 'notifications.read';
  static readonly NOTIFICATIONS_WRITE = 'notifications.write';
  /// Hydra 只在请求 offline_access 时才签发 refresh token（iOS 1.8.2 / Android 1.6.2 同修）
  static readonly OFFLINE_ACCESS = 'offline_access';

  /// 默认申请的全量权限集（对齐 Android Scopes.defaultP0 + offline_access）
  static readonly defaultScopes: string[] = [
    Scopes.ACCOUNT_READ,
    Scopes.ZONE_READ, Scopes.ZONE_WRITE,
    Scopes.DNS_READ, Scopes.DNS_WRITE,
    Scopes.WORKERS_READ, Scopes.WORKERS_WRITE,
    Scopes.WORKERS_ROUTES_READ, Scopes.WORKERS_ROUTES_WRITE,
    Scopes.WORKERS_TAIL_READ,
    Scopes.SNIPPETS_READ, Scopes.SNIPPETS_WRITE,
    Scopes.R2_READ, Scopes.R2_WRITE,
    Scopes.D1_READ, Scopes.D1_WRITE,
    Scopes.KV_READ, Scopes.KV_WRITE,
    Scopes.TUNNEL_READ, Scopes.TUNNEL_WRITE,
    Scopes.WAF_READ, Scopes.WAF_WRITE,
    Scopes.BOT_MANAGEMENT_READ, Scopes.BOT_MANAGEMENT_WRITE,
    Scopes.HEALTHCHECK_READ, Scopes.HEALTHCHECK_WRITE,
    Scopes.ZONE_DNS_SETTINGS_READ, Scopes.ZONE_DNS_SETTINGS_WRITE,
    Scopes.REGISTRAR_READ, Scopes.REGISTRAR_ADMIN,
    Scopes.REQUEST_TRACER_READ,
    Scopes.R2_CATALOG_READ, Scopes.R2_CATALOG_WRITE,
    Scopes.WORKERS_CI_READ, Scopes.WORKERS_CI_WRITE,
    Scopes.MANAGED_HEADERS_READ, Scopes.MANAGED_HEADERS_WRITE,
    Scopes.URL_SCANNER_READ, Scopes.URL_SCANNER_WRITE,
    Scopes.ZONE_SETTINGS_READ, Scopes.ZONE_SETTINGS_WRITE, Scopes.CACHE_PURGE,
    Scopes.SSL_CERTS_READ, Scopes.SSL_CERTS_WRITE,
    Scopes.TRANSFORM_READ, Scopes.TRANSFORM_WRITE,
    Scopes.FIREWALL_READ, Scopes.FIREWALL_WRITE,
    Scopes.ACCOUNT_ANALYTICS_READ, Scopes.ANALYTICS_READ,
    Scopes.CACHE_RULES_READ, Scopes.CACHE_RULES_WRITE,
    Scopes.EMAIL_ADDR_READ, Scopes.EMAIL_ADDR_WRITE,
    Scopes.EMAIL_RULE_READ, Scopes.EMAIL_RULE_WRITE,
    Scopes.EMAIL_SUPPRESSION_READ, Scopes.EMAIL_SUPPRESSION_WRITE,
    Scopes.REDIRECTS_READ, Scopes.REDIRECTS_WRITE,
    Scopes.RULE_LISTS_READ, Scopes.RULE_LISTS_WRITE,
    Scopes.LB_READ, Scopes.LB_WRITE,
    Scopes.LB_POOLS_READ, Scopes.LB_POOLS_WRITE,
    Scopes.ACCESS_READ, Scopes.ACCESS_WRITE,
    Scopes.TEAMS_READ, Scopes.TEAMS_WRITE,
    Scopes.PAGES_READ, Scopes.PAGES_WRITE,
    Scopes.AI_READ, Scopes.AI_WRITE,
    Scopes.AIG_READ, Scopes.AIG_WRITE,
    Scopes.QUEUES_READ, Scopes.QUEUES_WRITE,
    Scopes.HYPERDRIVE_READ, Scopes.HYPERDRIVE_WRITE,
    Scopes.WORKERS_OBSERVABILITY_READ,
    Scopes.NOTIFICATIONS_READ, Scopes.NOTIFICATIONS_WRITE,
    Scopes.CHALLENGE_WIDGETS_READ, Scopes.CHALLENGE_WIDGETS_WRITE,
    Scopes.R2_CATALOG_SQL_READ,
    Scopes.SINGLE_REDIRECT_READ, Scopes.SINGLE_REDIRECT_WRITE,
    Scopes.ORIGIN_RULES_READ, Scopes.ORIGIN_RULES_WRITE,
    Scopes.CONFIG_RULES_READ, Scopes.CONFIG_RULES_WRITE,
    Scopes.COMPRESSION_RULES_READ, Scopes.COMPRESSION_RULES_WRITE,
    Scopes.CUSTOM_ERRORS_READ, Scopes.CUSTOM_ERRORS_WRITE,
    Scopes.PAGE_RULES_READ, Scopes.PAGE_RULES_WRITE,
    Scopes.OFFLINE_ACCESS,
  ];

  /// 功能模块分组全集（覆盖 defaultScopes 除 offline_access 外的每一个 scope；
  /// offline_access 不进模块——授权流咽喉点无条件追加，见 AuthManager.buildAuthorizeURL）
  static readonly modules: ScopeModule[] = [
    {
      id: 'account', title: '账号信息', desc: '查看账号基本信息和设置', icon: '👤',
      readScopes: [Scopes.ACCOUNT_READ], writeScopes: [], required: true,
    },
    {
      id: 'zones', title: '域名', desc: '查看和管理你的域名', icon: '🌐',
      readScopes: [Scopes.ZONE_READ], writeScopes: [Scopes.ZONE_WRITE], required: true,
    },
    {
      id: 'dns', title: 'DNS 记录', desc: '查看和修改 DNS 解析记录', icon: '🧭',
      readScopes: [Scopes.DNS_READ], writeScopes: [Scopes.DNS_WRITE], required: false,
    },
    {
      id: 'workers', title: 'Workers 脚本', desc: '查看和管理 Workers 与路由', icon: '⚡',
      readScopes: [Scopes.WORKERS_READ, Scopes.WORKERS_ROUTES_READ],
      writeScopes: [Scopes.WORKERS_WRITE, Scopes.WORKERS_ROUTES_WRITE], required: false,
    },
    {
      id: 'workers_tail', title: 'Workers 实时日志', desc: '查看 Workers 的实时执行日志', icon: '📜',
      readScopes: [Scopes.WORKERS_TAIL_READ], writeScopes: [], required: false,
    },
    {
      id: 'snippets', title: 'Snippets', desc: '查看和编辑域名的边缘代码片段', icon: '✂️',
      readScopes: [Scopes.SNIPPETS_READ], writeScopes: [Scopes.SNIPPETS_WRITE], required: false,
    },
    {
      id: 'r2', title: 'R2 对象存储', desc: '浏览和管理 R2 存储桶', icon: '🗄️',
      readScopes: [Scopes.R2_READ], writeScopes: [Scopes.R2_WRITE], required: false,
    },
    {
      id: 'd1', title: 'D1 数据库', desc: '查询和管理 D1 SQLite 数据库', icon: '🛢️',
      readScopes: [Scopes.D1_READ], writeScopes: [Scopes.D1_WRITE], required: false,
    },
    {
      id: 'kv', title: 'KV 存储', desc: '查看和管理 Workers KV 键值对', icon: '🔑',
      readScopes: [Scopes.KV_READ], writeScopes: [Scopes.KV_WRITE], required: false,
    },
    {
      id: 'tunnels', title: 'Cloudflare Tunnel', desc: '查看隧道与连接状态；读写可新建与配置', icon: '🚇',
      readScopes: [Scopes.TUNNEL_READ], writeScopes: [Scopes.TUNNEL_WRITE], required: false,
    },
    {
      id: 'waf', title: 'WAF 防火墙', desc: '查看和启停自定义防火墙规则', icon: '🛡️',
      readScopes: [Scopes.WAF_READ], writeScopes: [Scopes.WAF_WRITE], required: false,
    },
    {
      id: 'bot_management', title: 'AI 与机器人', desc: '管控 AI 爬虫、内容机器人与 robots.txt', icon: '🐜',
      readScopes: [Scopes.BOT_MANAGEMENT_READ], writeScopes: [Scopes.BOT_MANAGEMENT_WRITE], required: false,
    },
    {
      id: 'url_scanner', title: 'URL 扫描', desc: '提交链接做安全扫描并查看报告', icon: '🔍',
      readScopes: [Scopes.URL_SCANNER_READ], writeScopes: [Scopes.URL_SCANNER_WRITE], required: false,
    },
    {
      id: 'managed_headers', title: '托管头', desc: 'Cloudflare 维护的请求/响应头改写开关', icon: '🔀',
      readScopes: [Scopes.MANAGED_HEADERS_READ], writeScopes: [Scopes.MANAGED_HEADERS_WRITE], required: false,
    },
    {
      id: 'workers_builds', title: 'Workers 构建', desc: '查看 CI 构建记录与日志；读写可取消构建', icon: '🔨',
      readScopes: [Scopes.WORKERS_CI_READ], writeScopes: [Scopes.WORKERS_CI_WRITE], required: false,
    },
    {
      id: 'r2_catalog', title: 'R2 数据目录', desc: '把 R2 桶启用为 Iceberg 数据仓库', icon: '🧊',
      readScopes: [Scopes.R2_CATALOG_READ, Scopes.R2_CATALOG_SQL_READ], writeScopes: [Scopes.R2_CATALOG_WRITE], required: false,
    },
    {
      id: 'request_tracer', title: '请求追踪', desc: '模拟请求，查看它命中了哪些规则', icon: '🔎',
      readScopes: [Scopes.REQUEST_TRACER_READ], writeScopes: [], required: false,
    },
    {
      id: 'registrar', title: '域名注册', desc: '查看在 Cloudflare 注册的域名与到期日；读写可改自动续费', icon: '🏷️',
      readScopes: [Scopes.REGISTRAR_READ], writeScopes: [Scopes.REGISTRAR_ADMIN], required: false,
    },
    {
      id: 'dns_settings', title: 'DNS 设置', desc: 'DNSSEC、CNAME 展平与名称服务器', icon: '🧭',
      readScopes: [Scopes.ZONE_DNS_SETTINGS_READ], writeScopes: [Scopes.ZONE_DNS_SETTINGS_WRITE], required: false,
    },
    {
      id: 'health_checks', title: '健康检查', desc: '监控源站是否在线；读写可暂停与删除', icon: '💓',
      readScopes: [Scopes.HEALTHCHECK_READ], writeScopes: [Scopes.HEALTHCHECK_WRITE], required: false,
    },
    {
      id: 'zone_settings', title: '缓存与防护', desc: '缓存清理、开发模式与域名设置', icon: '⚙️',
      readScopes: [Scopes.ZONE_SETTINGS_READ],
      writeScopes: [Scopes.ZONE_SETTINGS_WRITE, Scopes.CACHE_PURGE], required: false,
    },
    {
      id: 'cache_rules', title: '缓存规则', desc: '按 URL 覆盖缓存时长或绕过缓存', icon: '🗂️',
      readScopes: [Scopes.CACHE_RULES_READ], writeScopes: [Scopes.CACHE_RULES_WRITE], required: false,
    },
    {
      id: 'ssl_certs', title: 'SSL 证书', desc: '查看证书与 Universal SSL 开关', icon: '🔏',
      readScopes: [Scopes.SSL_CERTS_READ], writeScopes: [Scopes.SSL_CERTS_WRITE], required: false,
    },
    {
      id: 'transform_rules', title: 'Transform Rules', desc: 'URL 重写与请求/响应头规则', icon: '🔀',
      readScopes: [Scopes.TRANSFORM_READ], writeScopes: [Scopes.TRANSFORM_WRITE], required: false,
    },
    {
      id: 'ip_access_rules', title: 'IP 访问规则', desc: 'IP / ASN / 国家或地区访问规则', icon: '✋',
      readScopes: [Scopes.FIREWALL_READ], writeScopes: [Scopes.FIREWALL_WRITE], required: false,
    },
    {
      id: 'zone_rules', title: '规则中心', desc: '重定向、源站、配置、压缩、自定义错误与 Page Rules', icon: '📐',
      readScopes: [Scopes.SINGLE_REDIRECT_READ, Scopes.ORIGIN_RULES_READ, Scopes.CONFIG_RULES_READ,
        Scopes.COMPRESSION_RULES_READ, Scopes.CUSTOM_ERRORS_READ, Scopes.PAGE_RULES_READ],
      writeScopes: [Scopes.SINGLE_REDIRECT_WRITE, Scopes.ORIGIN_RULES_WRITE, Scopes.CONFIG_RULES_WRITE,
        Scopes.COMPRESSION_RULES_WRITE, Scopes.CUSTOM_ERRORS_WRITE, Scopes.PAGE_RULES_WRITE], required: false,
    },
    {
      id: 'email_routing', title: 'Email Routing', desc: '邮件路由规则与目的地址', icon: '✉️',
      readScopes: [Scopes.EMAIL_RULE_READ, Scopes.EMAIL_ADDR_READ],
      writeScopes: [Scopes.EMAIL_RULE_WRITE, Scopes.EMAIL_ADDR_WRITE], required: false,
    },
    {
      id: 'bulk_redirects', title: 'Bulk Redirects', desc: '批量 URL 重定向列表与条目', icon: '↪️',
      readScopes: [Scopes.RULE_LISTS_READ, Scopes.REDIRECTS_READ],
      writeScopes: [Scopes.RULE_LISTS_WRITE, Scopes.REDIRECTS_WRITE], required: false,
    },
    {
      id: 'load_balancing', title: '负载均衡', desc: '负载均衡器、源站池与健康监测', icon: '⚖️',
      readScopes: [Scopes.LB_READ, Scopes.LB_POOLS_READ],
      writeScopes: [Scopes.LB_WRITE, Scopes.LB_POOLS_WRITE], required: false,
    },
    {
      id: 'zt_access', title: 'Zero Trust Access', desc: '查看受 Access 保护的应用', icon: '🔒',
      readScopes: [Scopes.ACCESS_READ], writeScopes: [Scopes.ACCESS_WRITE], required: false,
    },
    {
      id: 'zt_gateway', title: 'Zero Trust Gateway', desc: '查看 Gateway 过滤策略', icon: '🚦',
      readScopes: [Scopes.TEAMS_READ], writeScopes: [Scopes.TEAMS_WRITE], required: false,
    },
    {
      id: 'pages', title: 'Cloudflare Pages', desc: '查看与管理 Pages 项目与部署', icon: '📄',
      readScopes: [Scopes.PAGES_READ], writeScopes: [Scopes.PAGES_WRITE], required: false,
    },
    {
      id: 'analytics', title: '流量分析', desc: '账号与域名的流量和安全分析', icon: '📊',
      readScopes: [Scopes.ACCOUNT_ANALYTICS_READ, Scopes.ANALYTICS_READ, Scopes.WORKERS_OBSERVABILITY_READ],
      writeScopes: [], required: false,
    },
    {
      id: 'queues', title: 'Queues', desc: '查看与管理消息队列', icon: '📥',
      readScopes: [Scopes.QUEUES_READ], writeScopes: [Scopes.QUEUES_WRITE], required: false,
    },
    {
      id: 'ai_gateway', title: 'AI Gateway', desc: '查看与管理 AI Gateway 网关', icon: '🧠',
      readScopes: [Scopes.AIG_READ], writeScopes: [Scopes.AIG_WRITE], required: false,
    },
    {
      id: 'workers_ai', title: 'Workers AI', desc: '浏览模型目录并试运行模型', icon: '🤖',
      readScopes: [Scopes.AI_READ], writeScopes: [Scopes.AI_WRITE], required: false,
    },
    {
      id: 'hyperdrive', title: 'Hyperdrive', desc: '查看与管理数据库加速配置', icon: '🚀',
      readScopes: [Scopes.HYPERDRIVE_READ], writeScopes: [Scopes.HYPERDRIVE_WRITE], required: false,
    },
    {
      id: 'notifications', title: '通知 / 告警', desc: '管理 Cloudflare 告警策略', icon: '🔔',
      readScopes: [Scopes.NOTIFICATIONS_READ], writeScopes: [Scopes.NOTIFICATIONS_WRITE], required: false,
    },
    {
      id: 'turnstile', title: 'Turnstile', desc: '人机验证组件与密钥轮换', icon: '🛂',
      readScopes: [Scopes.CHALLENGE_WIDGETS_READ], writeScopes: [Scopes.CHALLENGE_WIDGETS_WRITE], required: false,
    },
  ];

  /// 模块的全部 scope（读 + 写），用于「补齐授权」并集
  static moduleScopes(module: ScopeModule): string[] {
    const all: string[] = [];
    for (const s of module.readScopes) {
      if (!all.includes(s)) {
        all.push(s);
      }
    }
    for (const s of module.writeScopes) {
      if (!all.includes(s)) {
        all.push(s);
      }
    }
    return all;
  }

  /// 按选择生成 scope 集：启用模块的读 scope + 勾选读写模块的写 scope（必选模块强制启用）
  static buildSelectedScopes(enabledIds: string[], writeIds: string[]): string[] {
    const selected: string[] = [];
    for (const module of Scopes.modules) {
      const enabled = module.required || enabledIds.includes(module.id);
      if (!enabled) {
        continue;
      }
      for (const s of module.readScopes) {
        if (!selected.includes(s)) {
          selected.push(s);
        }
      }
      if (writeIds.includes(module.id)) {
        for (const s of module.writeScopes) {
          if (!selected.includes(s)) {
            selected.push(s);
          }
        }
      }
    }
    selected.sort();
    return selected;
  }

  /// 空格分隔、排序去重，直接用于 OAuth scope 参数
  static scopeString(scopes: string[] = Scopes.defaultScopes): string {
    const unique: string[] = [];
    for (const s of scopes) {
      if (!unique.includes(s)) {
        unique.push(s);
      }
    }
    unique.sort();
    return unique.join(' ');
  }
}
