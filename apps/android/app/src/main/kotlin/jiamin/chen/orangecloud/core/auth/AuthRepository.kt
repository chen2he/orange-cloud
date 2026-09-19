package jiamin.chen.orangecloud.core.auth

import android.content.Context
import android.net.Uri
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import dagger.hilt.android.qualifiers.ApplicationContext
import jiamin.chen.orangecloud.R
import jiamin.chen.orangecloud.core.di.ApplicationScope
import jiamin.chen.orangecloud.core.network.AccessTokenProvider
import jiamin.chen.orangecloud.core.network.ApiError
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** 认证 UI 状态（sessions + 当前身份）。 */
data class AuthState(
    val sessions: List<AuthSessionMeta> = emptyList(),
    val currentSessionId: String? = null,
    /** 持久化已读取完毕（用于启动期决定显示登录页还是主界面，避免闪烁） */
    val isReady: Boolean = false,
    /** 最近一次回调失败原因（UI 映射为本地化文案后展示），成功登录或重试时清空 */
    val redirectError: String? = null,
) {
    val isLoggedIn: Boolean get() = currentSessionId != null
    val currentSession: AuthSessionMeta? get() = sessions.firstOrNull { it.id == currentSessionId }
    val grantedScopes: List<String> get() = currentSession?.scopes.orEmpty()
}

/**
 * OAuth 2.0 + PKCE 多身份认证编排（对应 iOS AuthManager）。
 * - 每次登录新增一个身份；退出单身份只移除它；全部退出回登录页。
 * - 实现 AccessTokenProvider 供 CfApiClient 取 token / 刷新。
 */
@Singleton
class AuthRepository @Inject constructor(
    @ApplicationContext private val context: Context,
    @ApplicationScope private val externalScope: CoroutineScope,
    private val dataStore: DataStore<Preferences>,
    private val tokenStore: TokenStore,
    private val oauthApi: CloudflareOAuthApi,
    private val json: Json,
) : AccessTokenProvider {

    private val _state = MutableStateFlow(AuthState())
    val state: StateFlow<AuthState> = _state.asStateFlow()

    /** 发起授权到回调之间的 PKCE 上下文（持久化以扛进程被杀） */
    private data class Pending(val verifier: String, val state: String)

    init {
        externalScope.launch { loadPersisted() }
    }

    private suspend fun loadPersisted() {
        val prefs = dataStore.data.firstOrNull()
        val sessions = prefs?.get(KEY_SESSIONS)?.let { raw ->
            runCatching { json.decodeFromString(ListSerializer(AuthSessionMeta.serializer()), raw) }.getOrNull()
        }.orEmpty()
        val current = prefs?.get(KEY_CURRENT)?.takeIf { id -> sessions.any { it.id == id } }
            ?: sessions.firstOrNull()?.id
        _state.value = AuthState(sessions = sessions, currentSessionId = current, isReady = true)
    }

    fun hasScope(scope: String): Boolean = _state.value.grantedScopes.contains(scope)

    fun clearRedirectError() {
        if (_state.value.redirectError != null) {
            _state.value = _state.value.copy(redirectError = null)
        }
    }

    // MARK: - 登录

    /**
     * 构造授权 URL（PKCE + state）。
     *
     * freshLogin（添加账号）不再包 `dash.cloudflare.com/logout?to=<authorize>` 登出跳板——
     * 那会把用户系统浏览器里的 Cloudflare 登录态一并登出。现在 freshLogin 由调用方改走
     * 无痕 WebView（[jiamin.chen.orangecloud.core.util.WebAuthActivity]，进出清 Cookie），
     * 授权 URL 本身两种场景一致。（`prompt=login` 被 Cloudflare 忽略、Chrome 不给第三方
     * 开无痕标签，实测均无效，勿走回头路。）
     */
    suspend fun buildAuthorizationUri(scopeString: String): Uri {
        val verifier = PkceHelper.generateCodeVerifier()
        val challenge = PkceHelper.generateCodeChallenge(verifier)
        val state = UUID.randomUUID().toString()
        savePending(Pending(verifier, state))

        // CF dash OAuth（Hydra 系）只在请求 offline_access 时才签发 refresh token；
        // 2026-06-29 client 轮换后不带它的登录拿不到 refresh token，access token 到期后
        // refreshAccessToken 走 removeSession → 用户被「自动退出账号」（issue #44 楼层反馈）。
        // 与 iOS 1.8.2(26) 同修：在唯一咽喉点统一追加，勿在 UI 层散落。
        val scopeWithOffline =
            if (scopeString.split(" ").contains("offline_access")) scopeString
            else "$scopeString offline_access"

        return Uri.parse(OAuthConfig.AUTHORIZATION_URL).buildUpon()
            .appendQueryParameter("response_type", "code")
            .appendQueryParameter("client_id", OAuthConfig.clientId)
            .appendQueryParameter("redirect_uri", OAuthConfig.REDIRECT_URI)
            .appendQueryParameter("scope", scopeWithOffline)
            .appendQueryParameter("state", state)
            .appendQueryParameter("code_challenge", challenge)
            .appendQueryParameter("code_challenge_method", "S256")
            .build()
    }

    /** 处理 orangecloud://oauth/callback：验 state → 换 token → 新增身份并切到它。 */
    suspend fun handleRedirect(uri: Uri): Result<Unit> {
        // authorization code 一次性：换 token 过程中 Activity 重建（转屏）取消了 lifecycleScope，
        // code 已被消费、token 却没存下，用户只能再授权一次。整个交换放进 NonCancellable。
        val result = runCatching { withContext(NonCancellable) { performRedirect(uri) } }
        result.exceptionOrNull()?.let { e ->
            val reason = (e as? OAuthRedirectException)?.reason ?: e.message ?: "error"
            _state.value = _state.value.copy(redirectError = reason)
        }
        return result
    }

    private suspend fun performRedirect(uri: Uri) {
        uri.getQueryParameter("error")?.let { throw OAuthRedirectException(it) }
        val code = uri.getQueryParameter("code") ?: throw OAuthRedirectException("invalid_callback")
        val state = uri.getQueryParameter("state") ?: throw OAuthRedirectException("invalid_callback")
        val pending = loadPending() ?: throw OAuthRedirectException("invalid_callback")
        if (state != pending.state) throw OAuthRedirectException("state_mismatch")

        val token = exchangeCode(code, pending.verifier)
        val id = UUID.randomUUID().toString()
        tokenStore.save(id, token)
        val scopes = token.scope.split(" ").filter { it.isNotEmpty() }.sorted()
        val label = oauthApi.fetchUserInfo(token.accessToken)?.let { it.email ?: it.name }
            ?: context.getString(R.string.default_account_label, _state.value.sessions.size + 1)
        val sessions = _state.value.sessions + AuthSessionMeta(id, label, scopes)
        _state.value = _state.value.copy(sessions = sessions, currentSessionId = id, redirectError = null)
        persist()
        clearPending()
    }

    private suspend fun exchangeCode(code: String, verifier: String): StoredToken =
        oauthApi.requestToken(
            mapOf(
                "grant_type" to "authorization_code",
                "client_id" to OAuthConfig.clientId,
                "code" to code,
                "redirect_uri" to OAuthConfig.REDIRECT_URI,
                "code_verifier" to verifier,
            ),
        ).toStoredToken(previousScope = "", previousRefresh = null)

    // MARK: - AccessTokenProvider

    override suspend fun validAccessToken(): String {
        val sessionId = _state.value.currentSessionId ?: throw ApiError.Unauthorized
        val token = tokenStore.load(sessionId) ?: throw ApiError.Unauthorized
        val secondsLeft = token.expiresAtEpochSeconds - nowSeconds()
        return if (secondsLeft < 60) refreshAccessToken() else token.accessToken
    }

    /**
     * 刷新单飞锁。Dashboard 一次 refresh 会并发十几个请求，access token 临期时它们会同时进来刷新：
     * refresh token 单次有效，Cloudflare 检测到复用会吊销整条令牌链，后来的请求全部 4xx，
     * 以前的 catch 再把身份删掉——用户就这么被静默登出（与 iOS 侧 RefreshGate 同一根因）。
     */
    private val refreshMutex = Mutex()

    override suspend fun refreshAccessToken(): String {
        val sessionId = _state.value.currentSessionId ?: throw ApiError.Unauthorized
        val seenRefresh = tokenStore.load(sessionId)?.refreshToken
        return refreshMutex.withLock {
            val stored = tokenStore.load(sessionId)
            val refresh = stored?.refreshToken
            if (stored == null || refresh == null) {
                removeSession(sessionId)
                throw ApiError.Unauthorized
            }
            // 排队期间别的调用已经换过一轮（refresh token 变了）：直接用新 access token，
            // 别再拿已作废的旧 refresh token 去换。
            if (seenRefresh != null && refresh != seenRefresh) return@withLock stored.accessToken
            // 交换 + 落盘不可被调用方取消：端点已把旧 refresh token 作废，半路取消就会丢掉新令牌、卡死会话。
            withContext(NonCancellable) {
                try {
                    val newToken = oauthApi.requestToken(
                        mapOf(
                            "grant_type" to "refresh_token",
                            "client_id" to OAuthConfig.clientId,
                            "refresh_token" to refresh,
                        ),
                    ).toStoredToken(previousScope = stored.scope, previousRefresh = refresh)
                    tokenStore.save(sessionId, newToken)
                    newToken.accessToken
                } catch (e: TokenExchangeException) {
                    if (isRefreshTokenRejected(e)) {
                        // 服务端明确拒绝该刷新令牌（invalid_grant）：移除该身份（其他身份不受影响）
                        removeSession(sessionId)
                        throw ApiError.Unauthorized
                    }
                    // 5xx / 429 / WAF 挑战页之类：保留身份，按网络错误上抛
                    throw ApiError.Network(e)
                } catch (e: ApiError) {
                    throw e
                } catch (e: Exception) {
                    // 断网 / 超时 / DNS：绝不是「刷新令牌失效」，不能删会话
                    throw ApiError.Network(e)
                }
            }
        }
    }

    /**
     * token 端点回 400/401 且带 OAuth 错误体（{"error":"invalid_grant",…}）才算刷新令牌确已失效。
     * 其它状态（403 的 WAF 页、5xx、429）都是瞬时问题。
     */
    private fun isRefreshTokenRejected(e: TokenExchangeException): Boolean {
        val msg = e.message ?: return false
        val status = Regex("^HTTP (\\d{3})").find(msg)?.groupValues?.get(1)?.toIntOrNull() ?: return false
        return status in setOf(400, 401) && "\"error\"" in msg
    }

    // MARK: - 身份管理

    fun switchSession(id: String) {
        if (_state.value.sessions.none { it.id == id }) return
        _state.value = _state.value.copy(currentSessionId = id)
        externalScope.launch { persist() }
    }

    fun updateSessionLabel(id: String, label: String) {
        if (label.isEmpty()) return
        val updated = _state.value.sessions.map {
            if (it.id == id && it.label != label) it.copy(label = label) else it
        }
        if (updated == _state.value.sessions) return
        _state.value = _state.value.copy(sessions = updated)
        externalScope.launch { persist() }
    }

    suspend fun logout(sessionId: String, revoke: Boolean = true) = withContext(NonCancellable) {
        // 调用方多半是 viewModelScope（设置页）：撤销请求发到一半页面关了不能把「本地删身份」也一起取消
        if (revoke) {
            tokenStore.load(sessionId)?.let { token ->
                oauthApi.revoke(
                    mapOf(
                        "client_id" to OAuthConfig.clientId,
                        "token" to (token.refreshToken ?: token.accessToken),
                    ),
                )
            }
        }
        removeSession(sessionId)
    }

    private suspend fun removeSession(id: String) {
        tokenStore.clear(id)
        val sessions = _state.value.sessions.filterNot { it.id == id }
        val current = if (_state.value.currentSessionId == id) sessions.firstOrNull()?.id
        else _state.value.currentSessionId
        _state.value = _state.value.copy(sessions = sessions, currentSessionId = current)
        persist()
    }

    // MARK: - 持久化

    private suspend fun persist() {
        dataStore.edit { prefs ->
            prefs[KEY_SESSIONS] =
                json.encodeToString(ListSerializer(AuthSessionMeta.serializer()), _state.value.sessions)
            _state.value.currentSessionId?.let { prefs[KEY_CURRENT] = it } ?: prefs.remove(KEY_CURRENT)
        }
    }

    private suspend fun savePending(pending: Pending) {
        dataStore.edit {
            it[KEY_PENDING_VERIFIER] = pending.verifier
            it[KEY_PENDING_STATE] = pending.state
        }
    }

    private suspend fun loadPending(): Pending? {
        val prefs = dataStore.data.firstOrNull() ?: return null
        val v = prefs[KEY_PENDING_VERIFIER] ?: return null
        val s = prefs[KEY_PENDING_STATE] ?: return null
        return Pending(v, s)
    }

    private suspend fun clearPending() {
        dataStore.edit {
            it.remove(KEY_PENDING_VERIFIER)
            it.remove(KEY_PENDING_STATE)
        }
    }

    private fun nowSeconds(): Long = System.currentTimeMillis() / 1000

    companion object {
        private val KEY_SESSIONS = stringPreferencesKey("auth_sessions")
        private val KEY_CURRENT = stringPreferencesKey("auth_current_session")
        private val KEY_PENDING_VERIFIER = stringPreferencesKey("auth_pending_verifier")
        private val KEY_PENDING_STATE = stringPreferencesKey("auth_pending_state")
    }
}

private fun TokenResponse.toStoredToken(previousScope: String, previousRefresh: String?): StoredToken =
    StoredToken(
        accessToken = accessToken,
        refreshToken = refreshToken ?: previousRefresh,
        expiresAtEpochSeconds = System.currentTimeMillis() / 1000 + expiresIn,
        scope = scope ?: previousScope,
    )

/** 回调处理失败原因（reason 由 UI 层映射为本地化文案）。 */
class OAuthRedirectException(val reason: String) : Exception(reason)
