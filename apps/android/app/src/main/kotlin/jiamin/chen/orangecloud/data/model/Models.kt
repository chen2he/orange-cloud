package jiamin.chen.orangecloud.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Cloudflare 账号（与 iOS Models/Account.swift 对应）。 */
@Serializable
data class Account(
    val id: String,
    val name: String,
    val type: String? = null,
)

/** 域名 Zone（与 iOS Models/Zone.swift 对应）。 */
@Serializable
data class Zone(
    val id: String,
    val name: String,
    val status: String, // "active" | "pending" | "initializing" | "moved" 等
    /**
     * 是否暂停 Cloudflare 代理（Dashboard 的「Pause Cloudflare on Site」）。
     * 与 status 正交：暂停时 status 多半仍是 active，展示态一律读 displayStatus。
     */
    val paused: Boolean? = null,
    val plan: ZonePlan? = null,
    @SerialName("name_servers") val nameServers: List<String>? = null,
) {
    val isPaused: Boolean get() = paused == true

    val isActive: Boolean get() = status == "active" && !isPaused

    /** 对外展示用状态：暂停优先于 status。 */
    val displayStatus: String get() = if (isPaused) "paused" else status
}

/** PATCH /zones/{id} 请求体：暂停 / 恢复 Cloudflare 代理。 */
@Serializable
data class PauseZoneRequest(val paused: Boolean)

@Serializable
data class ZonePlan(val name: String)

/**
 * 新建 Zone（POST /zones）请求体。type="full"——Cloudflare 作权威 DNS，
 * 响应返回分配的 name_servers，状态 pending，待用户在注册商处更换 NS 后激活。
 */
@Serializable
data class CreateZoneRequest(
    val name: String,
    val type: String = "full",
    val account: AccountRef,
) {
    @Serializable
    data class AccountRef(val id: String)
}

/** DNS 记录（与 iOS Models/DNSRecord.swift 对应）。 */
@Serializable
data class DnsRecord(
    val id: String,
    val type: String,              // A / AAAA / CNAME / TXT / MX / NS 等
    val name: String,
    val content: String,
    val proxied: Boolean? = null,  // 仅 A/AAAA/CNAME 可代理
    val ttl: Int = 1,              // 1 = 自动
    val priority: Int? = null,     // MX / SRV 需要
    val comment: String? = null,
    @SerialName("created_on") val createdOn: String? = null,
    /** 仅在列表请求带 include_shadow_metadata=true 时有遮蔽信息；不入 Room 缓存。 */
    val meta: DnsRecordMeta? = null,
) {
    val isProxied: Boolean get() = proxied ?: false
}

/**
 * DNS 记录的 meta 里与「被遮蔽」相关的两项（include_shadow_metadata=true）。
 * shadowed_by：把该名称委派出去的 NS 记录 id（非空 = Cloudflare 不会响应这条记录）；
 * shadowed_records_count：NS 委派记录上，被它遮蔽的记录数。其余 meta 字段不建模。
 */
@Serializable
data class DnsRecordMeta(
    @SerialName("shadowed_by") val shadowedBy: List<kotlinx.serialization.json.JsonElement>? = null,
    @SerialName("shadowed_records_count") val shadowedRecordsCount: Int? = null,
)

/** 归一化后的遮蔽信息（按记录 id 存在内存里，随列表刷新更新）。 */
data class DnsShadowInfo(
    /** 本记录被 NS 委派遮蔽。 */
    val shadowed: Boolean,
    /** 本条（NS）记录遮蔽了多少条记录。 */
    val shadowsCount: Int,
)

/**
 * 新建 / 更新 DNS 记录的请求体（与 iOS CreateDNSRecord 对应）。
 * priority/comment 为 null 时不编码进 JSON（Json explicitNulls=false），
 * 避免给非 MX 记录传 priority:null 被 Cloudflare 拒绝。
 */
@Serializable
data class CreateDnsRecord(
    val type: String,
    val name: String,
    val content: String,
    val proxied: Boolean,
    val ttl: Int,
    val priority: Int? = null,
    val comment: String? = null,
)

/** Workers 脚本（与 iOS Models/WorkerScript.swift 对应）。GET /accounts/{id}/workers/scripts */
@Serializable
data class WorkerScript(
    val id: String,                                    // 即脚本名，账号内唯一
    val etag: String? = null,
    @SerialName("created_on") val createdOn: String? = null,
    @SerialName("modified_on") val modifiedOn: String? = null,
    @SerialName("usage_model") val usageModel: String? = null,
    val handlers: List<String>? = null,                // ["fetch", "scheduled"] 等
    val logpush: Boolean? = null,
)
