// OAuth 配置：与 iOS 端 Core/Auth/OAuthConfig.swift 保持一致。
// redirect_uri 必须与 Cloudflare Dashboard 中注册的完全一致；
// Web 后端回调中转会 302 到 orangecloud://oauth/callback（apps/web/src/app/oauth/callback/route.ts）。
export class OAuthConfig {
  /// 官方 OAuth Client（仅供官方构建使用；自编译请自建 Client 与回调中转，见 CONTRIBUTING.md）
  static readonly clientID: string = '102240eb9095a1965ee11813ef4788cd';

  static readonly redirectURI: string = 'https://o-c.do/oauth/callback';

  /// Deep Link 回跳前缀（module.json5 skills 中已注册 scheme）
  static readonly callbackPrefix: string = 'orangecloud://oauth/callback';

  // Cloudflare OAuth 端点
  static readonly authorizationURL: string = 'https://dash.cloudflare.com/oauth2/auth';
  static readonly tokenURL: string = 'https://dash.cloudflare.com/oauth2/token';
  static readonly revokeURL: string = 'https://dash.cloudflare.com/oauth2/revoke';
  static readonly userInfoURL: string = 'https://dash.cloudflare.com/oauth2/userinfo';

  // scope 全集见 core/auth/Scopes.ets（含 offline_access——Hydra 只在请求它时才签发 refresh token）
}
