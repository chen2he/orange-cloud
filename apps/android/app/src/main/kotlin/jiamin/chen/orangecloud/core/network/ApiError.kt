package jiamin.chen.orangecloud.core.network

/**
 * 统一错误类型（与 iOS Core/Network/APIError.swift 对应）。
 * 这里的 message 是开发者向兜底文案；用户可见的本地化文案在 UI 层按类型映射到 strings.xml。
 */
sealed class ApiError(message: String?, cause: Throwable? = null) : Exception(message, cause) {

    /** 401：未授权或登录已过期，触发 token 刷新或重新登录 */
    data object Unauthorized : ApiError("Unauthorized") {
        private fun readResolve(): Any = Unauthorized
    }

    /** 非 2xx 的 HTTP 状态 */
    data class Http(val status: Int, val cfErrors: List<CfError> = emptyList()) :
        ApiError("HTTP $status${cfErrors.firstOrNull()?.let { ": ${it.message}" }.orEmpty()}")

    /** Cloudflare 信封 success=false 的业务错误 */
    data class Cloudflare(val errors: List<CfError>) :
        ApiError(errors.firstOrNull()?.message ?: "Cloudflare API error")

    /** 网络/连接层失败 */
    data class Network(val original: Throwable) : ApiError(original.message, original)

    /** 反序列化失败 */
    data class Decoding(val original: Throwable) : ApiError(original.message, original)

    /**
     * documentationUrl：2026-08-21 起 CF 在 403 等错误体里给的 `documentation_url`
     * （该端点所需角色 / 权限的文档）。老端点没有，故可选。
     */
    data class CfError(val code: Int, val message: String, val documentationUrl: String? = null)

    /** 首个带文档地址的 CF 业务错误的 documentation_url；没有则 null。界面据此给出「查看所需权限」。 */
    val documentationUrl: String?
        get() = when (this) {
            is Cloudflare -> errors.firstNotNullOfOrNull { it.documentationUrl?.takeIf(String::isNotBlank) }
            is Http -> cfErrors.firstNotNullOfOrNull { it.documentationUrl?.takeIf(String::isNotBlank) }
            else -> null
        }
}

/** 任意异常上的 CF 文档地址（非 ApiError 恒为 null），供 UI 层直接从 Throwable 取。 */
val Throwable.cfDocumentationUrl: String?
    get() = (this as? ApiError)?.documentationUrl
