package jiamin.chen.orangecloud.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// MARK: - Cache Rules（Rulesets API，phase http_request_cache_settings，动作 set_cache_settings）。
// 读 cache-settings.read，写 cache-settings.write。结构同 Transform Rules（entrypoint + 规则数组）。
// 对应 iOS CacheRuleModels。
//
// action_parameters 只开放常用字段（缓存资格 / 边缘·浏览器 TTL / serve stale / 强 ETag / 源站错误页透传）。
// 含高级设置（自定义缓存键、Cache Reserve、读超时、源站 Cache-Control、额外可缓存端口）的规则编辑器只读，
// 避免 PATCH 覆盖时丢配置；status_code_ttl 不可编辑但会原样保留。

@Serializable
data class CacheRuleset(
    val id: String,
    val name: String? = null,
    val phase: String? = null,
    val rules: List<CacheRule>? = null,
)

@Serializable
data class CacheRule(
    val id: String,
    val expression: String? = null,
    val description: String? = null,
    val enabled: Boolean? = null,
    val action: String? = null, // 恒 "set_cache_settings"
    @SerialName("action_parameters") val actionParameters: CacheActionParameters? = null,
)

@Serializable
data class CacheActionParameters(
    // —— 开放编辑的字段 ——
    val cache: Boolean? = null,
    @SerialName("edge_ttl") val edgeTtl: CacheEdgeTTL? = null,
    @SerialName("browser_ttl") val browserTtl: CacheBrowserTTL? = null,
    @SerialName("serve_stale") val serveStale: CacheServeStale? = null,
    @SerialName("respect_strong_etags") val respectStrongEtags: Boolean? = null,
    @SerialName("origin_error_page_passthru") val originErrorPagePassthru: Boolean? = null,
    // —— 仅解码，用于「是否含高级设置」探测（含这些设置的规则编辑器只读）——
    @SerialName("cache_key") val cacheKey: kotlinx.serialization.json.JsonElement? = null,
    @SerialName("cache_reserve") val cacheReserve: kotlinx.serialization.json.JsonElement? = null,
    @SerialName("read_timeout") val readTimeout: Int? = null,
    @SerialName("origin_cache_control") val originCacheControl: Boolean? = null,
    @SerialName("additional_cacheable_ports") val additionalCacheablePorts: List<Int>? = null,
    /** 2026-07-02 新增：按 Vary 响应头缓存多版本（仅探测存在性，防止编辑覆盖丢配置） */
    val vary: kotlinx.serialization.json.JsonElement? = null,
) {
    /** 含未开放的高级设置 → 编辑器只读（status_code_ttl 不计入，编辑时原样保留）。 */
    val hasAdvancedSettings: Boolean
        get() = cacheKey != null || cacheReserve != null || readTimeout != null ||
            originCacheControl != null || (additionalCacheablePorts?.isNotEmpty() == true) ||
            vary != null
}

@Serializable
data class CacheEdgeTTL(
    val mode: String, // respect_origin | override_origin | bypass_by_default
    @SerialName("default") val defaultTtl: Int? = null,
    @SerialName("status_code_ttl") val statusCodeTtl: List<CacheStatusCodeTTL>? = null,
)

@Serializable
data class CacheBrowserTTL(
    val mode: String,
    @SerialName("default") val defaultTtl: Int? = null,
)

@Serializable
data class CacheStatusCodeTTL(
    @SerialName("status_code_range") val statusCodeRange: CacheStatusCodeRange? = null,
    @SerialName("status_code") val statusCode: Int? = null,
    val value: Int,
)

@Serializable
data class CacheStatusCodeRange(val from: Int? = null, val to: Int? = null)

@Serializable
data class CacheServeStale(
    @SerialName("disable_stale_while_updating") val disableStaleWhileUpdating: Boolean,
)

// MARK: - 写入载荷（POST rules / PATCH rule / PUT entrypoint 共用）

@Serializable
data class CacheRuleCreate(
    val action: String, // 恒 "set_cache_settings"
    val expression: String,
    val description: String? = null,
    val enabled: Boolean,
    @SerialName("action_parameters") val actionParameters: CacheActionParameters? = null,
)

@Serializable
data class CacheRuleToggle(val enabled: Boolean)

@Serializable
data class CacheEntrypointUpdate(val rules: List<CacheRuleCreate>)

// MARK: - 缓存响应规则（phase http_response_cache_settings，2026 秋季新增）
// 与请求阶段的 Cache Rules 同属 cache-settings.*。动作参数形态多样且仍在演进，
// 这里不做强类型建模：action_parameters 原样保留为 JsonElement，界面尽力摘要，认不出的只显示表达式。

@Serializable
data class CacheResponseRuleset(
    val id: String,
    val name: String? = null,
    val phase: String? = null,
    val rules: List<CacheResponseRule>? = null,
)

@Serializable
data class CacheResponseRule(
    val id: String,
    val expression: String? = null,
    val description: String? = null,
    val enabled: Boolean? = null,
    val action: String? = null,
    @SerialName("action_parameters") val actionParameters: kotlinx.serialization.json.JsonElement? = null,
)
