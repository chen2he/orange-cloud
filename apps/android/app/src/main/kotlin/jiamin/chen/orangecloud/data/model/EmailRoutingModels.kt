package jiamin.chen.orangecloud.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// MARK: - Email Routing：域名级路由规则 + 设置 + 账号级目的地址。对应 iOS EmailRoutingModels。
// 规则/设置 scope email-routing-rule.*；地址 scope email-routing-address.*。

/** GET /zones/{id}/email/routing —— 域名的 Email Routing 总开关与状态。 */
@Serializable
data class EmailRoutingSettings(
    val id: String? = null,
    val tag: String? = null,
    val name: String? = null,
    val enabled: Boolean? = null,
    val status: String? = null, // ready / unconfigured / misconfigured ...
) {
    val isEnabled: Boolean get() = enabled ?: false
}

/** 匹配条件：type=literal 时 field/value 有值（如 field=to）；type=all 为 catch-all。 */
@Serializable
data class EmailRoutingMatcher(
    val type: String,
    val field: String? = null,
    val value: String? = null,
)

/** 动作：forward → value 为目的邮箱数组；worker → value 为 worker 名；drop → 无 value。 */
@Serializable
data class EmailRoutingAction(
    val type: String,
    val value: List<String>? = null,
)

@Serializable
data class EmailRoutingRule(
    val id: String,
    val tag: String? = null,
    val name: String? = null,
    val enabled: Boolean? = null,
    val priority: Int? = null,
    val matchers: List<EmailRoutingMatcher> = emptyList(),
    val actions: List<EmailRoutingAction> = emptyList(),
) {
    val isEnabled: Boolean get() = enabled ?: false
    val isCatchAll: Boolean get() = matchers.any { it.type == "all" }
    /** 第一个 literal 匹配的收件地址（catch-all 规则返回 null）。 */
    val matchAddress: String? get() = matchers.firstOrNull { it.type == "literal" }?.value
}

/** 创建/更新规则请求体。 */
@Serializable
data class EmailRoutingRuleInput(
    val name: String? = null,
    val enabled: Boolean,
    val matchers: List<EmailRoutingMatcher>,
    val actions: List<EmailRoutingAction>,
) {
    companion object {
        /** 转发规则便捷构造：把 to 地址转发到一个已验证的目的地址。 */
        fun forward(name: String?, matchAddress: String, destination: String, enabled: Boolean) =
            EmailRoutingRuleInput(
                name = name,
                enabled = enabled,
                matchers = listOf(EmailRoutingMatcher(type = "literal", field = "to", value = matchAddress)),
                actions = listOf(EmailRoutingAction(type = "forward", value = listOf(destination))),
            )
    }
}

/** GET /accounts/{id}/email/routing/addresses 的目的地址（账号级共享）。 */
@Serializable
data class EmailDestinationAddress(
    val id: String,
    val tag: String? = null,
    val email: String,
    val verified: String? = null, // 验证通过的时间戳；未验证为 null
    val created: String? = null,
) {
    val isVerified: Boolean get() = verified != null
}

@Serializable
data class EmailDestinationCreate(val email: String)

/**
 * 被抑制的收件地址：硬退信/投诉后 Cloudflare 不再向其转发。
 * GET/POST /zones/{zone_id}/email/routing/suppression
 *
 * 与「路由规则」是两回事：规则决定往哪转，抑制决定不往哪转——
 * 用户常见困惑「规则明明配了却收不到」多半就是命中了这里。
 */
@Serializable
data class EmailSuppression(
    val id: String,
    val email: String? = null,
    /** hard_bounce / soft_bounce / complaint / manual */
    val reason: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    /** 到期后自动解除；null 表示永久 */
    @SerialName("expires_at") val expiresAt: String? = null,
    val zones: List<String>? = null,
)

/** GET suppression 的顶层结构（非标准信封：无 success/errors） */
@Serializable
data class EmailSuppressionPage(
    val result: List<EmailSuppression>? = null,
    val page: Int? = null,
    @SerialName("per_page") val perPage: Int? = null,
    val total: Int? = null,
)

@Serializable
data class EmailSuppressionCreate(val email: String)
