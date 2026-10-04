package jiamin.chen.orangecloud.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

// MARK: - WAF 自定义规则（Rulesets，phase = http_request_firewall_custom）

@Serializable
data class WafRuleset(
    val id: String,
    val name: String? = null,
    val phase: String? = null,
    val rules: List<WafRule>? = null,
)

@Serializable
data class WafRule(
    val id: String,
    val action: String? = null,          // block | challenge | managed_challenge | js_challenge | log | skip
    val expression: String? = null,
    val description: String? = null,
    val enabled: Boolean? = null,
    @SerialName("last_updated") val lastUpdated: String? = null,
)

/** PATCH 规则只更新 enabled。 */
@Serializable
data class WafRuleToggle(val enabled: Boolean)

/** 新建规则（POST rules / PUT entrypoint 共用），对齐 iOS WAFRuleCreate。 */
@Serializable
data class WafRuleCreate(
    val action: String,
    val expression: String,
    val description: String? = null,
    val enabled: Boolean,
)

/** PUT entrypoint 创建规则集（Zone 首条自定义规则时）。 */
@Serializable
data class WafEntrypointUpdate(val rules: List<WafRuleCreate>)

// MARK: - Cloudflare Tunnel（cfd_tunnel）

@Serializable
data class Tunnel(
    val id: String,
    val name: String,
    val status: String? = null,          // inactive | degraded | healthy | down
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("conns_active_at") val connsActiveAt: String? = null,
    @SerialName("tun_type") val tunType: String? = null,
    /** 已弃用：用 [configSrc]。仅在 config_src 缺失时作兜底。 */
    @SerialName("remote_config") val remoteConfig: Boolean? = null,
    /** 配置来源：local（本地 config.yml）/ cloudflare（远程托管）。取代 remote_config。 */
    @SerialName("config_src") val configSrc: String? = null,
    /**
     * 过渡期字段：CF 将于 **2026-10-05** 从 list/get 响应移除（2026-07-09 公告）。
     * 只用来在详情页首帧占位，真实数据以 SecurityRepository.tunnelConnections(...) 为准。
     */
    val connections: List<TunnelConnection>? = null,
) {
    val activeConnections: Int get() = connections?.size ?: 0

    /**
     * 是否远程托管（ingress 可经 API 管理）。以 config_src == "cloudflare" 为准；
     * 只有 config_src 缺失时才回退到已弃用的 remote_config。两者都缺失为 null（未知）。
     */
    val isRemotelyManaged: Boolean?
        get() = configSrc?.let { it.equals("cloudflare", ignoreCase = true) } ?: remoteConfig
}

/**
 * Zone 机器人管控配置（GET/PUT /zones/{id}/bot_management）。
 *
 * 响应 result 是四种套餐形态的 oneOf（Bot Fight Mode / SBFM Definitely / SBFM Likely /
 * BM Enterprise），四者都 allOf 引用同一个 base_config。此处只建模 base_config 里
 * 与 AI / 爬虫相关的字段，套餐专属字段（sbfm_* / fight_mode 等）一律不碰——
 * 因此全部可选，任何套餐的响应都能安全解码。
 *
 * 写入用 PUT 但是**合并语义**：官方示例就是只发要改的字段（如 {"fight_mode": false}），
 * base_config 无 required 字段。故 [BotManagementUpdate] 每次只带一个非 null 项，
 * 既不覆盖其它设置，也不会把只读字段回写过去。
 */
@Serializable
data class BotManagementConfig(
    /** block（全站）/ only_on_ad_pages（仅带广告页）/ disabled（放行） */
    @SerialName("ai_bots_protection") val aiBotsProtection: String? = null,
    /** enabled / disabled —— 链接迷宫（AI Labyrinth） */
    @SerialName("crawler_protection") val crawlerProtection: String? = null,
    /** block / disabled —— 内容机器人 */
    @SerialName("content_bots_protection") val contentBotsProtection: String? = null,
    /** off / policy_only —— Robots 访问控制许可证 */
    @SerialName("cf_robots_variant") val cfRobotsVariant: String? = null,
    /** 托管 robots.txt */
    @SerialName("is_robots_txt_managed") val isRobotsTxtManaged: Boolean? = null,
    // —— 2026-09-15 起（全套餐）：ai_bots_protection 拆成三类 AI 爬虫，各自一档 ——
    /** AI 搜索爬虫：disabled / block / only_on_ad_pages */
    @SerialName("ai_search") val aiSearch: String? = null,
    /** AI 助手与 Agent：disabled / block / only_on_ad_pages */
    @SerialName("ai_user") val aiUser: String? = null,
    /** AI 训练爬虫：disabled / disallow（只在 robots.txt 声明）/ block / only_on_ad_pages */
    @SerialName("ai_training") val aiTraining: String? = null,
    /** Bot Preference Sync：按以上三项由 Cloudflare 生成 robots.txt（取代托管 robots.txt） */
    @SerialName("bot_preference_sync_enabled") val botPreferenceSyncEnabled: Boolean? = null,
) {
    /** 响应里出现任一新字段即视为已上新版，界面改用三项选择替代旧的「AI 爬虫」。 */
    val hasAiPreferences: Boolean
        get() = aiSearch != null || aiUser != null || aiTraining != null
}

/** 单字段写入体。null 项不参与序列化（encodeDefaults=false 时默认省略）。 */
@Serializable
data class BotManagementUpdate(
    @SerialName("ai_bots_protection") val aiBotsProtection: String? = null,
    @SerialName("crawler_protection") val crawlerProtection: String? = null,
    @SerialName("content_bots_protection") val contentBotsProtection: String? = null,
    @SerialName("cf_robots_variant") val cfRobotsVariant: String? = null,
    @SerialName("is_robots_txt_managed") val isRobotsTxtManaged: Boolean? = null,
    @SerialName("ai_search") val aiSearch: String? = null,
    @SerialName("ai_user") val aiUser: String? = null,
    @SerialName("ai_training") val aiTraining: String? = null,
    @SerialName("bot_preference_sync_enabled") val botPreferenceSyncEnabled: Boolean? = null,
)

/**
 * Precursor 会话级机器人检测（GET/PUT /zones/{id}/precursor）。
 * 官方 schema 已把这些字段标为 deprecated 且没给替代，故只做模式选择；
 * enforcement_rules 不建模，原样留着不碰。default_mode：off / min-friction / max-security。
 */
@Serializable
data class PrecursorConfig(
    @SerialName("default_mode") val defaultMode: String? = null,
    @SerialName("enforcement_rules") val enforcementRules: JsonElement? = null,
)

/** PUT 是局部更新：只发 default_mode，不动 enforcement_rules。 */
@Serializable
data class PrecursorUpdate(@SerialName("default_mode") val defaultMode: String)

@Serializable
data class TunnelConnection(
    val id: String? = null,
    @SerialName("colo_name") val coloName: String? = null,
    @SerialName("origin_ip") val originIp: String? = null,
    @SerialName("opened_at") val openedAt: String? = null,
    @SerialName("client_version") val clientVersion: String? = null,
    /** 仅专用端点返回；旧的内嵌数组没有这两个字段。 */
    @SerialName("client_id") val clientId: String? = null,
    val uuid: String? = null,
)

/**
 * GET /accounts/{id}/cfd_tunnel/{id}/connections 的 result 元素。
 * 一个 client 即一个 cloudflared 进程，其 conns 是它维持的各条连接。
 */
@Serializable
data class TunnelClient(
    val id: String? = null,
    val arch: String? = null,
    val version: String? = null,
    @SerialName("run_at") val runAt: String? = null,
    @SerialName("config_version") val configVersion: Int? = null,
    val features: List<String>? = null,
    val conns: List<TunnelConnection>? = null,
)

/**
 * 摊平成 UI 直接消费的连接列表。
 * client_version 在 conns 里可能缺省，回退用 client 自身的 version 补齐。
 */
fun List<TunnelClient>.flattenedConnections(): List<TunnelConnection> =
    flatMap { client ->
        client.conns.orEmpty().map { conn ->
            conn.copy(
                clientVersion = conn.clientVersion ?: client.version,
                clientId = conn.clientId ?: client.id,
            )
        }
    }

/**
 * 新建隧道（POST /accounts/{id}/cfd_tunnel）。固定远程托管（config_src=cloudflare），
 * 只有远程托管隧道的 ingress 配置能经 API 管理。
 */
@Serializable
data class CreateTunnelRequest(
    val name: String,
    @SerialName("config_src") val configSrc: String = "cloudflare",
)

// MARK: - 隧道配置（公共主机名 / ingress，仅远程托管）

/** GET/PUT /configurations 的 result 外壳。 */
@Serializable
data class TunnelConfigResult(
    @SerialName("tunnel_id") val tunnelId: String? = null,
    val config: TunnelConfig? = null,
)

/**
 * 隧道配置。整组 PUT；未建模的高级字段（originRequest）用 JsonElement 原样保留，避免回写丢失。
 */
@Serializable
data class TunnelConfig(
    val ingress: List<IngressRule>? = null,
    @SerialName("warp-routing") val warpRouting: JsonElement? = null,
    val originRequest: JsonElement? = null,
)

/** 单条 ingress 规则。catch-all（末尾兜底）只有 service、无 hostname。 */
@Serializable
data class IngressRule(
    val hostname: String? = null,
    val service: String,
    val path: String? = null,
    val originRequest: JsonElement? = null,
) {
    /** 是否为兜底规则（无 hostname，或 service 是 http_status 形态）。UI 列表里隐藏它。 */
    val isCatchAll: Boolean
        get() = hostname.isNullOrEmpty() || service.startsWith("http_status:")

    /** 从 service 字符串识别协议种类（用于编辑表单回填）。 */
    val serviceKind: IngressServiceKind
        get() = IngressServiceKind.entries.firstOrNull { it.scheme.isNotEmpty() && service.startsWith(it.scheme) }
            ?: IngressServiceKind.OTHER

    /** 去掉协议前缀后的目标（host:port），OTHER 时为整串。 */
    val serviceTarget: String
        get() = serviceKind.let { if (it == IngressServiceKind.OTHER) service else service.removePrefix(it.scheme) }

    companion object {
        /** catch-all 兜底规则：无 hostname，把其余流量返回 404。 */
        val catchAll = IngressRule(service = "http_status:404")
    }
}

/** 公共主机名表单支持的服务协议。 */
enum class IngressServiceKind(val scheme: String, val label: String) {
    HTTP("http://", "HTTP"),
    HTTPS("https://", "HTTPS"),
    TCP("tcp://", "TCP"),
    SSH("ssh://", "SSH"),
    RDP("rdp://", "RDP"),
    OTHER("", "");

    /** 该协议的默认目标占位。 */
    val targetPlaceholder: String
        get() = when (this) {
            HTTP, HTTPS -> "localhost:8000"
            TCP -> "localhost:5432"
            SSH -> "localhost:22"
            RDP -> "localhost:3389"
            OTHER -> "unix:/path/to.sock"
        }
}

/** PUT /configurations 请求体：{ "config": { … } }。 */
@Serializable
data class TunnelConfigUpdate(val config: TunnelConfig)

/**
 * 独立健康检查（/zones/{zone_id}/healthchecks）。
 *
 * 与负载均衡的 monitor 是两回事：LB monitor 只在负载均衡语境里生效，
 * 这里是独立监控单个 IP / 主机名，单源站也能用。
 * 套餐：免费版不可用（0 个），Pro 10 / Business 50 / Enterprise 1000。
 */
@Serializable
data class HealthCheck(
    val id: String,
    val name: String,
    /** 被监控的源站主机名或 IP */
    val address: String? = null,
    val description: String? = null,
    /** HTTP / HTTPS / TCP */
    val type: String? = null,
    /** healthy / unhealthy / unknown */
    val status: String? = null,
    @SerialName("failure_reason") val failureReason: String? = null,
    /** 暂停后不再向源站发送检查 */
    val suspended: Boolean? = null,
    /** 检查间隔（秒） */
    val interval: Int? = null,
    val timeout: Int? = null,
    val retries: Int? = null,
    @SerialName("consecutive_fails") val consecutiveFails: Int? = null,
    @SerialName("consecutive_successes") val consecutiveSuccesses: Int? = null,
    /** 发起检查的区域；null 表示由 Cloudflare 自选 */
    @SerialName("check_regions") val checkRegions: List<String>? = null,
    @SerialName("created_on") val createdOn: String? = null,
    @SerialName("modified_on") val modifiedOn: String? = null,
) {
    /**
     * 暂停优先于 status——暂停时 CF 不再探测，status 会停在最后一次结果上，直接显示会误导。
     */
    val displayStatus: String
        get() = when {
            suspended == true -> "suspended"
            status == "healthy" -> "healthy"
            status == "unhealthy" -> "unhealthy"
            else -> "unknown"
        }
}

/** PATCH 体：只发暂停位 */
@Serializable
data class HealthCheckSuspendUpdate(val suspended: Boolean)
