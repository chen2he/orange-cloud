//
//  AuthManager.swift
//  Orange Cloud
//
//  OAuth 2.0 + PKCE，多登录身份：
//  - 每次 login 新增一个身份会话（独立 token，互不挤占）
//  - 退出单个身份只移除它；全部退出后回登录页
//  - Token 存 Keychain（按身份 UUID），身份索引（标签/scope）存 UserDefaults
//

import Foundation
import AuthenticationServices
import UIKit
import WidgetKit

nonisolated enum AuthError: LocalizedError {
    case invalidCallback
    case stateMismatch
    case oauthError(String)
    /// 授权页被回退 / 刷新后再回到回调，Hydra 判定 consent verifier 已被消费。
    /// 一次性状态，重来即可，不是配置问题（Sentry APPLE-IOS-5）。
    case consentExpired
    case tokenExchangeFailed(String)
    /// token 端点返回非 2xx。status 用于区分「刷新令牌确已失效」（400）与瞬时错误（5xx/429）。
    case tokenEndpointError(status: Int, body: String)
    case notLoggedIn

    var errorDescription: String? {
        switch self {
        case .invalidCallback:              return String(localized: "授权回调格式错误")
        case .stateMismatch:                return String(localized: "state 校验失败，请重试")
        case .oauthError(let message):      return message
        case .consentExpired:               return String(localized: "授权页面已失效，请重新发起登录。")
        case .tokenExchangeFailed(let msg): return String(localized: "换取 Token 失败：\(msg)")
        case .tokenEndpointError(let status, let body):
            return String(localized: "换取 Token 失败：\(body.isEmpty ? "HTTP \(status)" : body)")
        case .notLoggedIn:                  return String(localized: "登录已过期，请重新登录")
        }
    }

    /// 授权流里「重来一次就好」的一次性状态：计入本地日志，但不该占遥测的故障额度。
    var isRetriableFlowState: Bool {
        switch self {
        case .consentExpired, .stateMismatch: return true
        default:                              return false
        }
    }
}

/// 登录身份的展示信息（token 本体在 Keychain）
nonisolated struct AuthSessionMeta: Codable, Identifiable, Hashable, Sendable {
    let id:     UUID
    var label:  String       // 邮箱或占位名，展示用
    var scopes: [String]
}

@Observable
@MainActor
final class AuthManager {

    private(set) var sessions: [AuthSessionMeta] = []
    private(set) var currentSessionId: UUID?
    var isLoading = false
    var errorMessage: String?

    /// 存储的 token 缺少 refresh token 的身份（token 端点当次未发 refresh_token，
    /// access token 到期后无从续期）。UI 据此把泛化的「刷新失败」升级为「重新授权」引导；
    /// 重新授权拿到带 refresh token 的新令牌后自动摘除。
    private(set) var sessionsNeedingReauth: Set<UUID> = []

    var isLoggedIn: Bool { currentSessionId != nil }

    var currentSession: AuthSessionMeta? {
        sessions.first { $0.id == currentSessionId }
    }

    /// 当前身份的 scope（展示与权限门控用）
    var grantedScopes: [String] { currentSession?.scopes ?? [] }

    func hasScope(_ scope: String) -> Bool {
        grantedScopes.contains(scope)
    }

    /// 当前身份的 token（CFAPIClient 取用）
    var currentToken: TokenStore.StoredToken? {
        currentSessionId.flatMap { TokenStore.load(sessionId: $0) }
    }

    private var currentWebSession: ASWebAuthenticationSession?
    /// 进行中的刷新任务（按身份键）：同一身份的并发 401/临期请求复用同一次刷新，避免刷新令牌
    /// 轮换下的竞态；不同身份各自独立，切账号后旧身份的在途刷新不会串到新身份。
    private var refreshTasks: [UUID: Task<String, Error>] = [:]
    private let contextProvider = WebAuthContextProvider()
    private static let sessionsKey = "authSessions"
    private static let currentSessionKey = "currentSessionId"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.sessionsKey),
           let list = try? JSONDecoder().decode([AuthSessionMeta].self, from: data) {
            sessions = list
        }
        if let idString = UserDefaults.standard.string(forKey: Self.currentSessionKey),
           let id = UUID(uuidString: idString),
           sessions.contains(where: { $0.id == id }) {
            currentSessionId = id
        } else {
            currentSessionId = sessions.first?.id
        }
        migrateLegacyTokenIfNeeded()
        migrateToSharedKeychainGroupIfNeeded()
        migrateOffICloudSyncIfNeeded()
        // 诊断：打印当前身份 token 实际授权的 scope（排查 GraphQL "not authorized"——
        // 看 workers-observability.read 等是否真在 token 里）。重启即可见，无需重新登录。
        if let current = currentSession {
            AppLog.auth.info("active session scopes (\(current.scopes.count))=[\(current.scopes.joined(separator: " "))]")
        }
        // 启动即标记「缺 refresh token」的身份（不等到 access token 过期刷新失败才发现），
        // Dashboard 能在第一时间给出「重新授权」引导而非泛化的刷新失败。
        for meta in sessions {
            if let token = TokenStore.load(sessionId: meta.id), token.refreshToken == nil {
                sessionsNeedingReauth.insert(meta.id)
                AppLog.auth.error("stored token has no refresh token at launch. session=\(meta.id.uuidString)")
            }
        }
        // 自愈：清掉 App Group 里已不再登录的身份残留的 Widget 数据（历史登出未清等）
        WidgetDataStore.reconcile(liveSessionIds: Set(sessions.map { $0.id.uuidString }))
    }

    /// 一次性迁移：移除 iCloud 同步功能后，把已登录身份的 token 从「可同步」钥匙串条目
    /// 迁回本机（不再随 iCloud 钥匙串跨设备同步）。重存即触发 TokenStore 删旧增新。
    private func migrateOffICloudSyncIfNeeded() {
        let key = "iCloudSyncRemovedMigrated"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        for meta in sessions {
            if let token = TokenStore.load(sessionId: meta.id) {
                TokenStore.save(token, sessionId: meta.id)
            }
        }
        UserDefaults.standard.removeObject(forKey: "iCloudSyncEnabled")
        UserDefaults.standard.set(true, forKey: key)
    }

    /// 旧版单 token → 第一个身份会话
    private func migrateLegacyTokenIfNeeded() {
        guard sessions.isEmpty, let legacy = TokenStore.loadLegacy() else { return }
        let id = UUID()
        TokenStore.save(legacy, sessionId: id)
        TokenStore.clearLegacy()
        let scopes = UserDefaults.standard.stringArray(forKey: "grantedScopes")
            ?? legacy.scope.components(separatedBy: " ").filter { !$0.isEmpty }.sorted()
        UserDefaults.standard.removeObject(forKey: "grantedScopes")
        sessions = [AuthSessionMeta(id: id, label: String(localized: "Cloudflare 账号"), scopes: scopes)]
        currentSessionId = id
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: Self.sessionsKey)
        }
        // 当前选中身份是设备级状态，不参与同步；同时写入 App Group 供 Widget 定位 token
        UserDefaults.standard.set(currentSessionId?.uuidString, forKey: Self.currentSessionKey)
        UserDefaults(suiteName: WidgetSnapshot.appGroupID)?
            .set(currentSessionId?.uuidString, forKey: Self.currentSessionKey)
        // 身份/登录态变化后把当前 token 推给 Apple Watch（未配对/未激活时静默 no-op）
        WatchSessionManager.shared.pushCurrentState()
    }

    /// 一次性迁移：把既有 token 重存进共享钥匙串组（Widget 可读）
    private func migrateToSharedKeychainGroupIfNeeded() {
        let migrationKey = "keychainSharedGroupMigrated"
        guard !UserDefaults.standard.bool(forKey: migrationKey), !sessions.isEmpty else { return }
        for meta in sessions {
            if let token = TokenStore.load(sessionId: meta.id) {
                TokenStore.save(token, sessionId: meta.id)
            }
        }
        UserDefaults.standard.set(true, forKey: migrationKey)
        persist()   // 顺带写入 App Group 的当前身份指针
    }

    // MARK: - 身份切换

    func switchSession(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        AppLog.auth.notice("switch session=\(id.uuidString)")
        currentSessionId = id
        persist()
    }

    /// 账号列表加载后回填真实账号名（与 Dashboard 同源），账号重命名时保持同步
    func updateSessionLabel(_ label: String, for id: UUID) {
        guard !label.isEmpty,
              let index = sessions.firstIndex(where: { $0.id == id }),
              sessions[index].label != label else { return }
        sessions[index].label = label
        persist()
    }

    // MARK: - 登录（新增身份）

    /// 发起 OAuth 登录并作为新身份加入。freshLogin 强制全新登录页（添加第二个身份时
    /// 必须为 true，否则浏览器 Cookie 会自动复用上一个 Cloudflare 登录态）。
    func login(scopeString: String, freshLogin: Bool = false) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        AppLog.auth.notice("login start freshLogin=\(freshLogin) scopeCount=\(scopeString.split(separator: " ").count)")

        do {
            let token = try await runAuthorizationFlow(scopeString: scopeString, ephemeral: freshLogin)

            let id = UUID()
            TokenStore.save(token, sessionId: id)
            AuthDiagnostics.recordWrite(refreshToken: token.refreshToken, sessionId: id)
            noteRefreshTokenPresence(token, sessionId: id, phase: "login")
            let scopes = token.scope.components(separatedBy: " ").filter { !$0.isEmpty }.sorted()
            AppLog.auth.info("login stored session=\(id.uuidString) granted scopes=[\(scopes.joined(separator: " "))]")
            let label = await fetchIdentityLabel(accessToken: token.accessToken)
                ?? String(localized: "Cloudflare 账号 \(sessions.count + 1)")
            sessions.append(AuthSessionMeta(id: id, label: label, scopes: scopes))
            currentSessionId = id
            persist()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // 用户主动取消，不算错误
            AppLog.auth.notice("login canceled by user")
        } catch let error as AuthError where error.isRetriableFlowState {
            // 用户重来一次就好，不是故障：记 notice 不进遥测
            AppLog.auth.notice("login aborted (retriable): \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        } catch {
            AppLog.auth.error("login failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// 重新授权一个已存在的身份：请求 union(已授权, 新增) 的 scope，原地更新**同一身份**
    /// （同 UUID，不新建账号、不触发 ContentView 按 currentSessionId 重建 SessionStore）。
    /// 用于「缺失 scope → 一键补齐」。复用登录态（非 ephemeral）做到一键无感；换 token 后
    /// 用 userinfo 邮箱校验，防止浏览器里恰好登着另一个 Cloudflare 账号时把错 token 绑到当前身份。
    func reauthorize(sessionId: UUID, additionalScopes: [String]) async {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let merged = Set(sessions[index].scopes).union(additionalScopes)
        let scopeString = merged.sorted().joined(separator: " ")
        AppLog.auth.notice("reauthorize session=\(sessionId.uuidString) scopeCount=\(merged.count)")

        do {
            let token = try await runAuthorizationFlow(scopeString: scopeString, ephemeral: false)

            // 防串号：能取到邮箱、两边都是邮箱且不一致 → 中止，不写入 token
            let currentLabel = sessions[index].label
            if let newLabel = await fetchIdentityLabel(accessToken: token.accessToken),
               currentLabel.contains("@"), newLabel.contains("@"), newLabel != currentLabel {
                AppLog.auth.error("reauthorize identity mismatch expected=\(currentLabel) got=\(newLabel) → aborted")
                errorMessage = String(localized: "重新授权返回了不同的账号（\(newLabel)），已取消以保护当前账号。请先在系统浏览器退出其它 Cloudflare 账号后重试。")
                return
            }

            TokenStore.save(token, sessionId: sessionId)
            AuthDiagnostics.recordWrite(refreshToken: token.refreshToken, sessionId: sessionId)
            noteRefreshTokenPresence(token, sessionId: sessionId, phase: "reauthorize")
            let granted = token.scope.components(separatedBy: " ").filter { !$0.isEmpty }.sorted()
            AppLog.auth.info("reauthorize stored session=\(sessionId.uuidString) granted scopes=[\(granted.joined(separator: " "))]")
            sessions[index].scopes = granted
            persist()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            AppLog.auth.notice("reauthorize canceled by user")
        } catch let error as AuthError where error.isRetriableFlowState {
            AppLog.auth.notice("reauthorize aborted (retriable): \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        } catch {
            AppLog.auth.error("reauthorize failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// 跑一遍 OAuth 授权码 + PKCE 流程，返回换到的 token。登录与重新授权共用。
    private func runAuthorizationFlow(scopeString: String, ephemeral: Bool) async throws -> TokenStore.StoredToken {
        let verifier  = PKCEHelper.generateCodeVerifier()
        let challenge = PKCEHelper.generateCodeChallenge(from: verifier)
        let state     = UUID().uuidString

        // CF dash OAuth（Hydra 系）只在请求 offline_access 时才签发 refresh token；
        // 2026-06-29 client 轮换后不带它的新登录拿不到 refresh token，access token
        // 到期即会话搁浅（重授权横幅反复出现的根因）。在此单一咽喉点统一追加，
        // 覆盖登录与重授权两条流，勿在 UI 层散落。wrangler 同样携带该 scope。
        let scopeWithOffline = scopeString.components(separatedBy: " ").contains("offline_access")
            ? scopeString
            : scopeString + " offline_access"

        var components = URLComponents(url: OAuthConfig.authorizationURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "client_id",             value: OAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri",          value: OAuthConfig.redirectURI),
            URLQueryItem(name: "scope",                 value: scopeWithOffline),
            URLQueryItem(name: "state",                 value: state),
            URLQueryItem(name: "code_challenge",        value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        let callbackURL = try await authenticate(with: components.url!, ephemeral: ephemeral)
        let code = try Self.extractCode(from: callbackURL, expectedState: state)
        return try await exchangeCodeForToken(code: code, verifier: verifier)
    }

    /// 打开系统授权窗口，等待 orangecloud:// 回调
    private func authenticate(with url: URL, ephemeral: Bool) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            // 一次性闸门：iOS 27.0 beta 的 ASWebAuthenticationSession 存在边缘场景下二次回调
            // （TF 崩溃点 DJnovd2VRb7MLu8RZc6FmU，二次 resume 直接 trap），第二次到达只记日志。
            var resumed = false
            let completion: (URL?, (any Error)?) -> Void = { callbackURL, error in
                guard !resumed else {
                    AppLog.auth.error("ASWebAuthenticationSession completion 二次回调，已忽略")
                    return
                }
                resumed = true
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    // 无 URL 也无 error 的收尾只发生在窗口被系统侧解散等边缘场景，按用户取消
                    // 处理（静默返回），不报「回调格式错误」
                    continuation.resume(throwing: error ?? ASWebAuthenticationSessionError(.canceledLogin))
                }
            }
            // iOS 17.4+ 用 callback API；iOS 17.0–17.3 回退旧的 callbackURLScheme 初始化器
            let session: ASWebAuthenticationSession
            if #available(iOS 17.4, *) {
                session = ASWebAuthenticationSession(
                    url: url,
                    callback: .customScheme(OAuthConfig.callbackScheme),
                    completionHandler: completion
                )
            } else {
                session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: OAuthConfig.callbackScheme,
                    completionHandler: completion
                )
            }
            session.presentationContextProvider = contextProvider
            session.prefersEphemeralWebBrowserSession = ephemeral
            currentWebSession = session
            session.start()
        }
    }

    /// 从回调 URL 提取授权码并校验 state
    nonisolated private static func extractCode(from callbackURL: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let items = components.queryItems else {
            throw AuthError.invalidCallback
        }
        if let error = items.first(where: { $0.name == "error" })?.value {
            let description = items.first(where: { $0.name == "error_description" })?.value ?? ""
            // invalid_scope = 请求了 OAuth client 未登记的 scope（client 配置变更 / 旧版 App
            // 请求新权限时的高危场景），给明确引导而非裸错误码
            if error == "invalid_scope" {
                var message = String(localized: "授权请求包含 Cloudflare 尚未对本 App 开放的权限，无法完成登录。请更新到最新版本后重试。")
                if !description.isEmpty { message += "\n\(description)" }
                throw AuthError.oauthError(message)
            }
            // Hydra 的一次性 consent verifier 被重复消费（授权途中后退 / 刷新过），
            // 重新走一遍即可——别把英文原文甩给用户（Sentry APPLE-IOS-5 占登录失败大头）。
            if description.contains("consent verifier has already been used") {
                throw AuthError.consentExpired
            }
            throw AuthError.oauthError(description.isEmpty ? error : "\(error): \(description)")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value,
              let state = items.first(where: { $0.name == "state" })?.value else {
            throw AuthError.invalidCallback
        }
        guard state == expectedState else {
            throw AuthError.stateMismatch
        }
        return code
    }

    /// 身份标签：userinfo 端点取邮箱（best-effort）
    private func fetchIdentityLabel(accessToken: String) async -> String? {
        var request = URLRequest(url: OAuthConfig.userInfoURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let info = try? JSONDecoder().decode(UserInfo.self, from: data) else {
            return nil
        }
        return info.email ?? info.name
    }

    nonisolated private struct UserInfo: Codable {
        let email: String?
        let name:  String?
    }

    // MARK: - Token 交换与刷新

    nonisolated private struct TokenResponse: Codable {
        let accessToken:  String
        let expiresIn:    Int
        let refreshToken: String?
        let scope:        String?

        enum CodingKeys: String, CodingKey {
            case accessToken  = "access_token"
            case expiresIn    = "expires_in"
            case refreshToken = "refresh_token"
            case scope
        }
    }

    private func exchangeCodeForToken(code: String, verifier: String) async throws -> TokenStore.StoredToken {
        let response = try await requestToken(parameters: [
            "grant_type":    "authorization_code",
            "client_id":     OAuthConfig.clientID,
            "code":          code,
            "redirect_uri":  OAuthConfig.redirectURI,
            "code_verifier": verifier,
        ])
        return TokenStore.StoredToken(
            accessToken:  response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt:    Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            scope:        response.scope ?? ""
        )
    }

    /// 刷新当前身份的 access_token。两条铁律：
    /// ① 并发去重 + 按身份隔离：同一身份的多个临期/401 请求只触发一次网络刷新（刷新令牌轮换下
    ///    避免并发请求互相作废），不同身份互不影响。
    /// ② 绑定发起身份：调用方可传发起请求时的 `expectedSessionId`；若此刻已切到别的身份，说明这是
    ///    上个账号的陈旧请求，直接放弃刷新——更不会误删任何身份（多账号雪崩登出的根因）。
    func refreshAccessToken(expectedSessionId: UUID? = nil) async throws -> String {
        guard let sessionId = currentSessionId else { throw AuthError.notLoggedIn }
        if let expected = expectedSessionId, expected != sessionId {
            throw AuthError.notLoggedIn
        }
        if let inFlight = refreshTasks[sessionId] {
            return try await inFlight.value
        }
        let task = Task<String, Error> { [weak self] in
            guard let self else { throw AuthError.notLoggedIn }
            return try await self.performTokenRefresh(sessionId: sessionId)
        }
        refreshTasks[sessionId] = task
        defer { refreshTasks[sessionId] = nil }
        return try await task.value
    }

    /// 实际刷新逻辑。三条铁律：
    /// ① **跨进程串行化**：先抢共享 App Group 文件锁（[[RefreshGate]]），避免与「文件」扩展并发刷新
    ///    同一个轮转 refresh token——并发会触发 Cloudflare 复用检测吊销整条令牌链（卡死登录态的根因）。
    /// ② **服务端明确拒绝（token 端点 4xx）才登出**：400/401/403 = 刷新令牌失效/被撤销/被复用吊销，
    ///    登出该身份回登录页（一键重授权恢复），不再卡死；网络/超时/5xx/429 等瞬时失败保留身份原样抛出。
    /// ③ **轮换自愈**：拿锁后才读 token（用钥匙串里最新一份去刷新，而非调用时手里的陈旧令牌）；被拒时
    ///    若发现 refresh token 已被别的进程轮换走，用新令牌重试一次再判定，避免良性竞态误登出。
    private func performTokenRefresh(sessionId: UUID) async throws -> String {
        // 0xdead10cc 防线（TF 崩溃点 Dcm1DbRURSxqamd0_K0IG5）：进程若在持有共享容器
        // fcntl 锁时被挂起（BGAppRefresh 被掐 / 用户刚退后台），RunningBoard 直接杀进程。
        // 用后台任务断言把「拿锁→刷新→放锁」整段罩住，把挂起推迟到锁释放之后。
        var assertion = UIBackgroundTaskIdentifier.invalid
        assertion = UIApplication.shared.beginBackgroundTask(withName: "token-refresh-lock") {
            if assertion != .invalid {
                UIApplication.shared.endBackgroundTask(assertion)
                assertion = .invalid
            }
        }
        defer {
            if assertion != .invalid {
                UIApplication.shared.endBackgroundTask(assertion)
                assertion = .invalid
            }
        }

        // 跨进程独占锁（best-effort，拿不到也照常刷）
        let lock = await RefreshGate.acquire(sessionId: sessionId.uuidString)
        defer { RefreshGate.release(lock) }

        // 拿到锁后才读 token：等锁期间另一进程可能已把令牌轮换掉，这里读到的是最新一份，
        // 用它去刷新（而非调用时手里那份陈旧令牌），避免拿着旧令牌去刷触发复用检测。
        guard let stored = TokenStore.load(sessionId: sessionId) else {
            // 钥匙串读不到该身份 token：多半是切账号竞态下的陈旧请求，或确已被清。
            // 保留身份、抛出由调用方当未授权处理——绝不在此删身份（曾导致多账号雪崩登出）。
            AppLog.auth.error("token missing from keychain (session kept). session=\(sessionId.uuidString)")
            throw AuthError.notLoggedIn
        }
        guard let refreshToken = stored.refreshToken else {
            // 无刷新令牌则无从续期。同样保留身份，标记「需重新授权」（Dashboard 出引导横幅，
            // 一键重授权同 UUID 原地换新令牌），不删身份，避免一次 401 把会话连锁清空。
            sessionsNeedingReauth.insert(sessionId)
            AppLog.auth.error("stored token has no refresh token (session kept). session=\(sessionId.uuidString)")
            throw AuthError.notLoggedIn
        }

        // 诊断（issue #5 历史）：对比当前刷新令牌指纹与「我们最后写入」的基线。
        // 移除 iCloud 同步后正常应恒等；不一致说明令牌被本进程之外改写过。
        let usedFP = AuthDiagnostics.fingerprint(refreshToken)
        let baselineFP = AuthDiagnostics.lastWrittenFingerprint(sessionId)
        AppLog.auth.info("refresh attempt session=\(sessionId.uuidString) usedRefreshFP=\(usedFP) lastWrittenFP=\(baselineFP ?? "nil") accessExpiresInSec=\(Int(stored.expiresAt.timeIntervalSinceNow))")
        if let baselineFP, baselineFP != usedFP {
            AppLog.auth.error("⚠️ refresh token changed externally since our last write. expected=\(baselineFP) got=\(usedFP)")
        }

        do {
            return try await requestAndStoreRefresh(sessionId: sessionId, refreshToken: refreshToken, previousScope: stored.scope)
        } catch let AuthError.tokenEndpointError(status, body) where (400...403).contains(status) && Self.isOAuthErrorBody(body) {
            // token 端点 4xx **且带 OAuth 错误体** = 服务端明确拒绝该刷新令牌。先看是否被别的进程轮换走了：
            // 钥匙串里若已出现不同的 refresh token，用它重试一次（多账号 / 扩展并发下的良性竞态）。
            if let latest = TokenStore.load(sessionId: sessionId),
               let rotated = latest.refreshToken, rotated != refreshToken,
               let token = try? await requestAndStoreRefresh(sessionId: sessionId, refreshToken: rotated, previousScope: latest.scope) {
                AppLog.auth.notice("refresh rejected \(status) but keychain rotated by another process → recovered with fresh token. session=\(sessionId.uuidString)")
                return token
            }
            // 确属失效：登出该身份（回登录页，一键重授权恢复），不再卡死登录态
            AppLog.auth.error("refresh rejected \(status) (invalid_grant) → logout. usedRefreshFP=\(usedFP) lastWrittenFP=\(baselineFP ?? "nil")")
            removeSession(sessionId)
            throw AuthError.notLoggedIn
        }
        // 其它错误（网络 / 超时 / 5xx / 429）：保留身份，原样向上抛出
    }

    /// token 端点的 4xx 只有带 OAuth 错误体（{"error":"invalid_grant",…}）才算「服务端明确拒绝该刷新令牌」。
    /// WAF 挑战页 / 强制门户 / 运营商劫持返回的 403 HTML 同样落在 400...403，但那是网络层问题：
    /// 不能据此删钥匙串把用户踢回登录页（后台刷新每 4h 一次，误判一次就丢掉仍有效的 refresh token）。
    /// 非 OAuth 错误体的 4xx 与网络错误同待遇：保留身份、原样上抛。
    nonisolated static func isOAuthErrorBody(_ body: String) -> Bool {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["error"] is String
    }

    /// 用给定 refresh token 向 token 端点换新令牌、写回钥匙串并返回新 access token。
    private func requestAndStoreRefresh(sessionId: UUID, refreshToken: String, previousScope: String) async throws -> String {
        let response = try await requestToken(parameters: [
            "grant_type":    "refresh_token",
            "client_id":     OAuthConfig.clientID,
            "refresh_token": refreshToken,
        ])
        let newToken = TokenStore.StoredToken(
            accessToken:  response.accessToken,
            refreshToken: response.refreshToken ?? refreshToken,
            expiresAt:    Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            scope:        response.scope ?? previousScope
        )
        TokenStore.save(newToken, sessionId: sessionId)
        AuthDiagnostics.recordWrite(refreshToken: newToken.refreshToken, sessionId: sessionId)
        sessionsNeedingReauth.remove(sessionId)   // 能刷新成功即链路健康，摘除陈旧标记
        AppLog.auth.info("refresh ok session=\(sessionId.uuidString) newRefreshFP=\(AuthDiagnostics.fingerprint(newToken.refreshToken))")
        return newToken.accessToken
    }

    private func requestToken(parameters: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: OAuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(parameters)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.tokenExchangeFailed(String(localized: "无效响应"))
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.tokenEndpointError(status: http.statusCode, body: body)
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw AuthError.tokenExchangeFailed(String(localized: "响应解析失败"))
        }
    }

    // MARK: - 身份级偏好键

    /// 该身份「默认进入的账号」的 UserDefaults 键（SessionStore 读写，身份移除时清）
    nonisolated static func defaultAccountKey(_ sessionId: UUID) -> String {
        "defaultAccountId_\(sessionId.uuidString)"
    }

    // MARK: - 退出单个身份

    func logout(sessionId: UUID, revoke: Bool = true) async {
        AppLog.auth.notice("logout session=\(sessionId.uuidString) revoke=\(revoke)")
        if revoke, let token = TokenStore.load(sessionId: sessionId) {
            // 尽力撤销，失败不阻塞
            var request = URLRequest(url: OAuthConfig.revokeURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formBody([
                "client_id": OAuthConfig.clientID,
                "token":     token.refreshToken ?? token.accessToken,
            ])
            _ = try? await URLSession.shared.data(for: request)
        }
        removeSession(sessionId)
    }

    /// 记录本次交换是否带回 refresh token：缺失时标记该身份「需重新授权」并留证据日志
    /// （granted scope 一并记录，便于核对 OAuth client 配置）；带回则摘除标记。
    private func noteRefreshTokenPresence(_ token: TokenStore.StoredToken, sessionId: UUID, phase: String) {
        if token.refreshToken == nil {
            sessionsNeedingReauth.insert(sessionId)
            AppLog.auth.error("token exchange returned NO refresh_token (\(phase)). session=\(sessionId.uuidString) scope=[\(token.scope)] — access token 到期后将无法续期，请核对 OAuth client 配置")
        } else {
            sessionsNeedingReauth.remove(sessionId)
        }
    }

    private func removeSession(_ id: UUID) {
        TokenStore.clear(sessionId: id)
        AuthDiagnostics.clearBaseline(id)
        sessionsNeedingReauth.remove(id)
        // 该身份记住的默认账号一并清掉，重新登录不带上一轮的选择
        UserDefaults.standard.removeObject(forKey: Self.defaultAccountKey(id))
        sessions.removeAll { $0.id == id }
        AppLog.auth.notice("session removed=\(id.uuidString) remaining=\(sessions.count)")
        if currentSessionId == id {
            currentSessionId = sessions.first?.id
        }
        persist()
        // 清掉该身份在 App Group 的 Widget 数据，否则其账号 / 域名仍会出现在 Widget 选择器
        WidgetDataStore.purge(sessionId: id.uuidString)
        WidgetCenter.shared.reloadAllTimelines()
        if sessions.isEmpty {
            SpotlightIndexer.deleteAll()
        }
    }

    // MARK: - 工具

    nonisolated private static func formBody(_ parameters: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)!
    }
}

// MARK: - ASWebAuthenticationSession 展示锚点

@MainActor
private final class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return keyWindow
        }
        // 登录界面可见时必然有前台 scene
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            preconditionFailure("发起 OAuth 时找不到可用的 UIWindowScene")
        }
        return UIWindow(windowScene: scene)
    }
}
