//
//  WatchSessionManager.swift
//  Orange Cloud
//
//  iPhone 侧 WatchConnectivity 桥：把当前身份 token + 最新快照推给 Apple Watch，
//  并响应 watch 的「要新 token」请求。
//
//  铁律：Cloudflare 的 refresh_token 是轮转式的，只能在 iPhone 这一处刷新——
//  watch 永远不自行刷新，临期时经此通道向 iPhone 索取（与 Widget 的 SharedAuth 同纪律）。
//

import Foundation
import WatchConnectivity

/// 把非 Sendable 的 WC 回调安全带过 actor 边界（replyHandler 可在任意线程被调用）
private struct UncheckedSendableBox<T>: @unchecked Sendable { let value: T }

@MainActor
final class WatchSessionManager: NSObject {

    static let shared = WatchSessionManager()

    private weak var authManager: AuthManager?

    private override init() { super.init() }

    /// App 启动时调用一次：绑定 AuthManager 并激活会话
    func start(authManager: AuthManager) {
        guard WCSession.isSupported() else { return }
        self.authManager = authManager
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// 推送当前身份 token + 最新快照（最新状态语义；未配对/未激活时静默 no-op）
    func pushCurrentState() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        try? session.updateApplicationContext(currentPayload().asContext())
    }

    private func currentPayload() -> WatchBridgePayload {
        let token = authManager?.currentToken
        return WatchBridgePayload(
            accessToken: token?.accessToken,
            expiresAt:   token?.expiresAt,
            sessionId:   authManager?.currentSessionId?.uuidString,
            accountName: authManager?.currentSession?.label,
            zones:       Array(WidgetDataStore.loadZones().prefix(12)),
            usage:       WidgetDataStore.loadUsage(),
            accountAnalyticsUnavailable: !WidgetDataStore.loadAccountAnalyticsAvailable(),
            updatedAt:   Date()
        )
    }

    /// 响应 watch 的「要新 token」：iPhone 是唯一刷新点
    private func replyWithFreshToken() async -> [String: Any] {
        guard let authManager else { return ["error": "no_session"] }
        // 手表每次前台都会来要 token。access token 还有富余就直接给，别为此轮换 refresh token：
        // refresh token 单次有效且与 File Provider 扩展共用，多余的轮换只会放大并发窗口
        // （与 CFAPIClient.validAccessToken 同一口径：不足 60 秒才刷新）。
        if let token = authManager.currentToken, token.expiresAt.timeIntervalSinceNow > 60 {
            return currentPayload().asContext()
        }
        do {
            _ = try await authManager.refreshAccessToken()
            return currentPayload().asContext()
        } catch {
            return ["error": "refresh_failed"]
        }
    }
}

extension WatchSessionManager: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in self.pushCurrentState() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // 切换配对设备：需重新激活
        WCSession.default.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.pushCurrentState() }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard message["request"] as? String == "freshToken" else {
            replyHandler([:]); return
        }
        let box = UncheckedSendableBox(value: replyHandler)
        Task { @MainActor in
            let reply = await self.replyWithFreshToken()
            box.value(reply)
        }
    }
}
