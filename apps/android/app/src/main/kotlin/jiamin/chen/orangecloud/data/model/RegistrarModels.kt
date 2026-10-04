package jiamin.chen.orangecloud.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Cloudflare Registrar 注册的域名。
 *
 * ⚠️ 必须用新版 API：旧的 /accounts/{id}/registrar/domains 于 2026-06-29 弃用、
 * **2026-09-27 停用**；新版在 /accounts/{id}/registrar/registrations 下。
 *
 * 两个由接口决定的边界：
 * · PATCH **只支持 auto_renew**（规范原文：currently supports updating auto_renew only），
 *   [locked] 转移锁是只读的，不要做成开关
 * · PATCH 返回异步 workflow 状态而非更新后的对象，写入后需回读列表
 */
@Serializable
data class DomainRegistration(
    @SerialName("domain_name") val domainName: String,
    /** 到期时间。registration_pending 期间可能为 null */
    @SerialName("expires_at") val expiresAt: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    /** 自动续费：开启即授权 Cloudflare 在到期前 30 天内扣默认支付方式 */
    @SerialName("auto_renew") val autoRenew: Boolean? = null,
    /** 是否锁定转移。**只读** */
    val locked: Boolean? = null,
    @SerialName("privacy_mode") val privacyMode: String? = null,
    /** active / registration_pending / expired / suspended / redemption_period */
    val status: String? = null,
)

/** PATCH 体。接口目前只认 auto_renew。 */
@Serializable
data class RegistrationUpdate(@SerialName("auto_renew") val autoRenew: Boolean)

/** PATCH 的异步 workflow 结果，只取判定完成所需字段 */
@Serializable
data class RegistrarWorkflowStatus(
    val completed: Boolean? = null,
    val state: String? = null,
)

// MARK: - 搜索新域名（domain-search 有缓存可能滞后；domain-check 实时向注册局确认）
// 只做查询，不在 App 内购买：可注册时引导到 Cloudflare 控制台完成注册。

/** domain-search / domain-check 的 result：{ domains: [...] }。 */
@Serializable
data class DomainAvailabilityResult(val domains: List<DomainAvailability>? = null)

@Serializable
data class DomainAvailability(
    val name: String,
    val registrable: Boolean? = null,
    /** standard / premium */
    val tier: String? = null,
    /** 不可注册的原因：extension_not_supported_via_api / extension_not_supported / … */
    val reason: String? = null,
    val pricing: DomainPricing? = null,
) {
    val isPremium: Boolean get() = tier.equals("premium", ignoreCase = true)
}

/** 价格字段文档里是字符串；按 JsonElement 宽松接住，数字形态也能显示。 */
@Serializable
data class DomainPricing(
    val currency: String? = null,
    @SerialName("registration_cost") val registrationCost: kotlinx.serialization.json.JsonElement? = null,
    @SerialName("renewal_cost") val renewalCost: kotlinx.serialization.json.JsonElement? = null,
) {
    val registration: String? get() = registrationCost.priceText()
    val renewal: String? get() = renewalCost.priceText()
}

private fun kotlinx.serialization.json.JsonElement?.priceText(): String? =
    (this as? kotlinx.serialization.json.JsonPrimitive)
        ?.takeIf { it !is kotlinx.serialization.json.JsonNull }
        ?.content?.takeIf { it.isNotBlank() }

/** POST domain-check 请求体（单次最多 20 个）。 */
@Serializable
data class DomainCheckRequest(val domains: List<String>)
