package jiamin.chen.orangecloud.data.repository

import jiamin.chen.orangecloud.core.network.CfApiClient
import jiamin.chen.orangecloud.data.model.EmailDestinationAddress
import jiamin.chen.orangecloud.data.model.EmailDestinationCreate
import jiamin.chen.orangecloud.data.model.EmailRoutingRule
import jiamin.chen.orangecloud.data.model.EmailSuppression
import jiamin.chen.orangecloud.data.model.EmailSuppressionPage
import jiamin.chen.orangecloud.data.model.EmailSuppressionCreate
import jiamin.chen.orangecloud.data.model.EmailRoutingRuleInput
import jiamin.chen.orangecloud.data.model.EmailRoutingSettings
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Email Routing：域名级设置/规则（email-routing-rule.*）+ 账号级目的地址（email-routing-address.*）。
 * 对应 iOS EmailRoutingService。
 */
@Singleton
class EmailRoutingRepository @Inject constructor(
    private val api: CfApiClient,
) {
    // MARK: - 设置（域名级）

    suspend fun settings(zoneId: String): EmailRoutingSettings =
        api.get("zones/$zoneId/email/routing")

    /** 开启 / 关闭 Email Routing（空 body POST 到 enable/disable）。 */
    suspend fun setEnabled(zoneId: String, enabled: Boolean) {
        val action = if (enabled) "enable" else "disable"
        api.postChecked("zones/$zoneId/email/routing/$action", emptyMap<String, String>())
    }

    // MARK: - 规则（域名级）

    suspend fun rules(zoneId: String): List<EmailRoutingRule> =
        api.getList<EmailRoutingRule>("zones/$zoneId/email/routing/rules").items

    suspend fun createRule(zoneId: String, input: EmailRoutingRuleInput): EmailRoutingRule =
        api.post("zones/$zoneId/email/routing/rules", input)

    suspend fun updateRule(zoneId: String, ruleId: String, input: EmailRoutingRuleInput): EmailRoutingRule =
        api.put("zones/$zoneId/email/routing/rules/$ruleId", input)

    suspend fun deleteRule(zoneId: String, ruleId: String) =
        api.delete("zones/$zoneId/email/routing/rules/$ruleId")

    // MARK: - 目的地址（账号级）

    suspend fun addresses(accountId: String): List<EmailDestinationAddress> =
        api.getList<EmailDestinationAddress>("accounts/$accountId/email/routing/addresses").items

    /** 新增目的地址（提交后 Cloudflare 向该邮箱发验证信）。 */
    suspend fun createAddress(accountId: String, email: String): EmailDestinationAddress =
        api.post("accounts/$accountId/email/routing/addresses", EmailDestinationCreate(email))

    suspend fun deleteAddress(accountId: String, addressId: String) =
        api.delete("accounts/$accountId/email/routing/addresses/$addressId")
    // MARK: - 抑制列表（email-routing-suppression.read / .write）

    /**
     * 被抑制的收件地址。⚠️ 该端点 2xx 时不走 CF 标准信封：顶层是 { page, per_page, total, result }，
     * 没有 success/errors（OpenAPI 规范如此，iOS 同款 Sentry APPLE-IOS-AB 坐实）。
     */
    suspend fun suppressions(zoneId: String): List<EmailSuppression> =
        api.getBare<EmailSuppressionPage>(
            "zones/$zoneId/email/routing/suppression",
            listOf("per_page" to "100"),
        ).result.orEmpty()

    /** 手动抑制一个地址（此后不再向它转发） */
    suspend fun addSuppression(zoneId: String, email: String): EmailSuppression =
        api.post("zones/$zoneId/email/routing/suppression", EmailSuppressionCreate(email))

    /** 解除抑制 */
    suspend fun deleteSuppression(zoneId: String, id: String) =
        api.delete("zones/$zoneId/email/routing/suppression/$id")

}
