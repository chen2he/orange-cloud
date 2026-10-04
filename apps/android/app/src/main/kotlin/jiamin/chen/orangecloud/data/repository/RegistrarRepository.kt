package jiamin.chen.orangecloud.data.repository

import jiamin.chen.orangecloud.core.network.CfApiClient
import jiamin.chen.orangecloud.data.model.DomainAvailability
import jiamin.chen.orangecloud.data.model.DomainAvailabilityResult
import jiamin.chen.orangecloud.data.model.DomainCheckRequest
import jiamin.chen.orangecloud.data.model.DomainRegistration
import jiamin.chen.orangecloud.data.model.RegistrarWorkflowStatus
import jiamin.chen.orangecloud.data.model.RegistrationUpdate
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Cloudflare Registrar（registrar-domains.read / .admin）。
 * 用新版 /registrar/registrations —— 旧的 /registrar/domains 于 2026-09-27 停用。
 */
@Singleton
class RegistrarRepository @Inject constructor(
    private val api: CfApiClient,
) {
    /** 该端点是**游标分页**（不是页码），cursor 为空串即到底。 */
    suspend fun registrations(accountId: String): List<DomainRegistration> {
        val all = mutableListOf<DomainRegistration>()
        var cursor: String? = null
        // 兜底上限，防止服务端游标异常导致死循环
        repeat(20) {
            val query = buildList {
                add("per_page" to "50")
                cursor?.takeIf { it.isNotEmpty() }?.let { add("cursor" to it) }
            }
            val paged = api.getList<DomainRegistration>(
                "accounts/$accountId/registrar/registrations", query,
            )
            all += paged.items
            cursor = paged.info?.cursor
            if (cursor.isNullOrEmpty()) return all
        }
        return all
    }

    /** 搜索可注册的新域名（结果可能有延迟，点开后用 [check] 实时确认）。 */
    suspend fun searchDomains(accountId: String, query: String): List<DomainAvailability> =
        api.get<DomainAvailabilityResult>(
            "accounts/$accountId/registrar/domain-search",
            listOf("q" to query, "limit" to "20"),
        ).domains.orEmpty()

    /** 实时向注册局确认可注册性与价格（单次最多 20 个）。 */
    suspend fun checkDomains(accountId: String, names: List<String>): List<DomainAvailability> =
        api.post<DomainAvailabilityResult, DomainCheckRequest>(
            "accounts/$accountId/registrar/domain-check",
            DomainCheckRequest(names.take(20)),
        ).domains.orEmpty()

    /** 设置自动续费。返回异步 workflow 状态，调用方成功后应回读列表。 */
    suspend fun setAutoRenew(accountId: String, domainName: String, enabled: Boolean): RegistrarWorkflowStatus =
        api.patch(
            "accounts/$accountId/registrar/registrations/$domainName",
            RegistrationUpdate(enabled),
        )
}
