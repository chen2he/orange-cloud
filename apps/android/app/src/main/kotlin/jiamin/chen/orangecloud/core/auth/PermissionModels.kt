package jiamin.chen.orangecloud.core.auth

import jiamin.chen.orangecloud.R

/**
 * 可按功能勾选的权限项（对应 iOS PermissionModels.allFeatures）。
 * 勾选即纳入该功能的 read + edit scope；required 功能强制勾选。
 */
data class PermissionFeature(
    val id: String,
    val nameRes: Int,
    val descRes: Int,
    val readScopes: List<String>,
    val editScopes: List<String> = emptyList(),
    val required: Boolean = false,
)

object PermissionCatalog {
    val features: List<PermissionFeature> = listOf(
        PermissionFeature("account", R.string.perm_account, R.string.perm_account_desc, listOf(Scopes.ACCOUNT_READ)),
        PermissionFeature("zones", R.string.perm_zones, R.string.perm_zones_desc, listOf(Scopes.ZONE_READ), listOf(Scopes.ZONE_WRITE), required = true),
        PermissionFeature("dns", R.string.perm_dns, R.string.perm_dns_desc, listOf(Scopes.DNS_READ), listOf(Scopes.DNS_WRITE)),
        // workers-observability.write：Workers Issues 改状态，随 Workers 的编辑级别一起申请
        PermissionFeature("workers", R.string.perm_workers, R.string.perm_workers_desc, listOf(Scopes.WORKERS_READ, Scopes.WORKERS_ROUTES_READ, Scopes.WORKERS_OBSERVABILITY_READ), listOf(Scopes.WORKERS_WRITE, Scopes.WORKERS_ROUTES_WRITE, Scopes.WORKERS_OBSERVABILITY_WRITE)),
        PermissionFeature("workers_tail", R.string.perm_tail, R.string.perm_tail_desc, listOf(Scopes.WORKERS_TAIL_READ)),
        PermissionFeature("snippets", R.string.perm_snippets, R.string.perm_snippets_desc, listOf(Scopes.SNIPPETS_READ), listOf(Scopes.SNIPPETS_WRITE)),
        PermissionFeature("r2", R.string.perm_r2, R.string.perm_r2_desc, listOf(Scopes.R2_READ), listOf(Scopes.R2_WRITE)),
        PermissionFeature("d1", R.string.perm_d1, R.string.perm_d1_desc, listOf(Scopes.D1_READ), listOf(Scopes.D1_WRITE)),
        PermissionFeature("kv", R.string.perm_kv, R.string.perm_kv_desc, listOf(Scopes.KV_READ), listOf(Scopes.KV_WRITE)),
        PermissionFeature("tunnels", R.string.perm_tunnels, R.string.perm_tunnels_desc, listOf(Scopes.TUNNEL_READ), listOf(Scopes.TUNNEL_WRITE)),
        PermissionFeature("waf", R.string.perm_waf, R.string.perm_waf_desc, listOf(Scopes.WAF_READ), listOf(Scopes.WAF_WRITE)),
        PermissionFeature("bot_management", R.string.perm_bots, R.string.perm_bots_desc, listOf(Scopes.BOT_MANAGEMENT_READ), listOf(Scopes.BOT_MANAGEMENT_WRITE)),
        PermissionFeature("health_checks", R.string.perm_healthcheck, R.string.perm_healthcheck_desc, listOf(Scopes.HEALTHCHECK_READ), listOf(Scopes.HEALTHCHECK_WRITE)),
        PermissionFeature("dns_settings", R.string.perm_dns_settings, R.string.perm_dns_settings_desc, listOf(Scopes.ZONE_DNS_SETTINGS_READ), listOf(Scopes.ZONE_DNS_SETTINGS_WRITE)),
        PermissionFeature("registrar", R.string.perm_registrar, R.string.perm_registrar_desc, listOf(Scopes.REGISTRAR_READ), listOf(Scopes.REGISTRAR_ADMIN)),
        PermissionFeature("request_tracer", R.string.perm_tracer, R.string.perm_tracer_desc, listOf(Scopes.REQUEST_TRACER_READ)),
        PermissionFeature("r2_catalog", R.string.perm_r2_catalog, R.string.perm_r2_catalog_desc, listOf(Scopes.R2_CATALOG_READ, Scopes.R2_CATALOG_SQL_READ), listOf(Scopes.R2_CATALOG_WRITE)),
        PermissionFeature("workers_builds", R.string.perm_builds, R.string.perm_builds_desc, listOf(Scopes.WORKERS_CI_READ), listOf(Scopes.WORKERS_CI_WRITE)),
        PermissionFeature("managed_headers", R.string.perm_managed_headers, R.string.perm_managed_headers_desc, listOf(Scopes.MANAGED_HEADERS_READ), listOf(Scopes.MANAGED_HEADERS_WRITE)),
        PermissionFeature("url_scanner", R.string.perm_url_scanner, R.string.perm_url_scanner_desc, listOf(Scopes.URL_SCANNER_READ), listOf(Scopes.URL_SCANNER_WRITE)),
        PermissionFeature("zone_settings", R.string.perm_zone_settings, R.string.perm_zone_settings_desc, listOf(Scopes.ZONE_SETTINGS_READ), listOf(Scopes.ZONE_SETTINGS_WRITE, Scopes.CACHE_PURGE)),
        PermissionFeature("ssl_certs", R.string.perm_ssl_certs, R.string.perm_ssl_certs_desc, listOf(Scopes.SSL_CERTS_READ), listOf(Scopes.SSL_CERTS_WRITE)),
        PermissionFeature("transform_rules", R.string.perm_transform, R.string.perm_transform_desc, listOf(Scopes.TRANSFORM_READ), listOf(Scopes.TRANSFORM_WRITE)),
        PermissionFeature("ip_access_rules", R.string.perm_ip_rules, R.string.perm_ip_rules_desc, listOf(Scopes.FIREWALL_READ), listOf(Scopes.FIREWALL_WRITE)),
        // 账号用量（workersInvocationsAdaptive 等 adaptive 数据集）需 workers-observability.read；
        // account-analytics.read 会被 CF 从授权丢弃，仅作请求项占位（与 iOS PermissionModels 对齐）。
        PermissionFeature("analytics", R.string.perm_analytics, R.string.perm_analytics_desc, listOf(Scopes.ACCOUNT_ANALYTICS_READ, Scopes.ANALYTICS_READ, Scopes.WORKERS_OBSERVABILITY_READ)),
        // —— 1.4「G–J 爆发」新增功能（与 iOS PermissionModels 对齐）——
        PermissionFeature("cache_rules", R.string.perm_cache_rules, R.string.perm_cache_rules_desc, listOf(Scopes.CACHE_RULES_READ), listOf(Scopes.CACHE_RULES_WRITE)),
        PermissionFeature("email_routing", R.string.perm_email_routing, R.string.perm_email_routing_desc, listOf(Scopes.EMAIL_ADDR_READ, Scopes.EMAIL_RULE_READ, Scopes.EMAIL_SUPPRESSION_READ), listOf(Scopes.EMAIL_ADDR_WRITE, Scopes.EMAIL_RULE_WRITE, Scopes.EMAIL_SUPPRESSION_WRITE)),
        PermissionFeature("bulk_redirects", R.string.perm_bulk_redirects, R.string.perm_bulk_redirects_desc, listOf(Scopes.REDIRECTS_READ, Scopes.RULE_LISTS_READ), listOf(Scopes.REDIRECTS_WRITE, Scopes.RULE_LISTS_WRITE)),
        PermissionFeature("load_balancer", R.string.perm_load_balancer, R.string.perm_load_balancer_desc, listOf(Scopes.LB_READ, Scopes.LB_POOLS_READ), listOf(Scopes.LB_WRITE, Scopes.LB_POOLS_WRITE)),
        PermissionFeature("zero_trust", R.string.perm_zero_trust, R.string.perm_zero_trust_desc, listOf(Scopes.ACCESS_READ, Scopes.TEAMS_READ), listOf(Scopes.ACCESS_WRITE, Scopes.TEAMS_WRITE)),
        PermissionFeature("pages", R.string.perm_pages, R.string.perm_pages_desc, listOf(Scopes.PAGES_READ), listOf(Scopes.PAGES_WRITE)),
        PermissionFeature("workers_ai", R.string.perm_workers_ai, R.string.perm_workers_ai_desc, listOf(Scopes.AI_READ), listOf(Scopes.AI_WRITE)),
        PermissionFeature("ai_gateway", R.string.perm_ai_gateway, R.string.perm_ai_gateway_desc, listOf(Scopes.AIG_READ), listOf(Scopes.AIG_WRITE)),
        PermissionFeature("queues", R.string.perm_queues, R.string.perm_queues_desc, listOf(Scopes.QUEUES_READ), listOf(Scopes.QUEUES_WRITE)),
        PermissionFeature("hyperdrive", R.string.perm_hyperdrive, R.string.perm_hyperdrive_desc, listOf(Scopes.HYPERDRIVE_READ), listOf(Scopes.HYPERDRIVE_WRITE)),
        PermissionFeature("turnstile", R.string.perm_turnstile, R.string.perm_turnstile_desc, listOf(Scopes.CHALLENGE_WIDGETS_READ), listOf(Scopes.CHALLENGE_WIDGETS_WRITE)),
        PermissionFeature("notifications", R.string.perm_notifications, R.string.perm_notifications_desc, listOf(Scopes.NOTIFICATIONS_READ), listOf(Scopes.NOTIFICATIONS_WRITE)),
    )

    /** 默认全选的功能 id 集合。 */
    val defaultSelectedIds: Set<String> = features.map { it.id }.toSet()

    /** 由勾选的功能 id 计算 scope 字符串（read + edit，排序去重，空格分隔）。 */
    fun scopeString(selectedIds: Set<String>): String {
        val scopes = sortedSetOf<String>()
        for (feature in features) {
            if (feature.required || feature.id in selectedIds) {
                scopes += feature.readScopes
                scopes += feature.editScopes
            }
        }
        return scopes.joinToString(" ")
    }

    /**
     * 按访问级别计算 scope：levels[id] = true 表示读写（read + edit），false 表示只读（仅 read）。
     * 未在 map 中的功能不申请；required 功能强制至少只读。
     */
    fun scopeString(levels: Map<String, Boolean>): String {
        val scopes = sortedSetOf<String>()
        for (feature in features) {
            val included = feature.required || feature.id in levels
            if (!included) continue
            scopes += feature.readScopes
            if (levels[feature.id] == true) scopes += feature.editScopes
        }
        return scopes.joinToString(" ")
    }
}
