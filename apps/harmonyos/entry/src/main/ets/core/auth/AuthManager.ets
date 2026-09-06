// OAuth 2.0 + PKCE 多身份登录管理（对齐 iOS AuthManager sessions / Android AuthRepository+AccountStore）。
// 首次登录：系统浏览器 → o-c.do 中转 302 → orangecloud:// deep link → EntryAbility 收 Want；
// 添加账号：应用内无痕 Web（WebAuthPage）拦截回跳，避免复用上一身份 Cookie。
// 身份索引存 Preferences，token 按身份 UUID 存 Asset Store Kit。
import { common, OpenLinkOptions } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { url, util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { OAuthConfig } from './OAuthConfig';
import { PKCEHelper } from './PKCEHelper';
import { Scopes } from './Scopes';
import { StoredToken, TokenStore } from './TokenStore';
import { TokenRefresher } from './TokenRefresher';
import { GlobalContext } from '../system/GlobalContext';
import { AppPrefs } from '../system/AppPrefs';
import { WhatsNewGate } from '../whatsnew/WhatsNew';

const DOMAIN = 0x0001;
const TAG = 'AuthManager';
const KEY_SESSIONS = 'auth_sessions';
const KEY_CURRENT = 'auth_current_session';

interface TokenResponse {
  access_token: string;
  expires_in: number;
  refresh_token?: string;
  scope?: string;
}

interface UserInfo {
  email?: string;
  name?: string;
}

/// 身份元数据（非敏感，存 Preferences；token 另存 Asset）
export interface AuthSessionMeta {
  id: string;
  label: string;
  createdAtMs: number;
  scope: string;
}

export type AuthStatus = 'loading' | 'loggedOut' | 'authorizing' | 'exchanging' | 'loggedIn';

function formEncode(params: Record<string, string>): string {
  const parts: string[] = [];
  for (const key of Object.keys(params)) {
    parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(params[key])}`);
  }
  return parts.join('&');
}

@ObservedV2
export class AuthManager {
  @Trace status: AuthStatus = 'loading';
  @Trace sessions: AuthSessionMeta[] = [];
  @Trace currentSessionId: string = '';
  @Trace error: string = '';
  /// 登录后添加第二账号的进行中标记（status 保持 loggedIn）
  @Trace isAddingAccount: boolean = false;
  /// 缺 refresh token、需要重新授权的身份 id 列表（bootstrap 与每次 token 交换后维护）。
  /// 缺 refresh token 的会话在 access token 到期后无法续期（Hydra 只对 offline_access 签发）。
  @Trace sessionsNeedingReauth: string[] = [];
  /// 进行中的重授权目标身份（空串 = 无）；ReauthBanner / 身份详情用它做 loading 态
  @Trace reauthSessionId: string = '';
  /// 重授权失败原因（与登录 error 分离，避免污染登录页文案）
  @Trace reauthError: string = '';

  private tokens: Map<string, StoredToken> = new Map();
  private refreshing: Map<string, Promise<void>> = new Map();
  private pendingVerifier: string = '';
  private pendingState: string = '';
  private bootstrapped: boolean = false;

  currentLabel(): string {
    const meta = this.sessions.find((s: AuthSessionMeta) => s.id === this.currentSessionId);
    return meta ? meta.label : '';
  }

  /// 当前身份是否持有某 scope（授权时用户可能在同意页裁剪）
  hasScope(scope: string): boolean {
    const token = this.tokens.get(this.currentSessionId);
    if (!token || token.scope === '') {
      return true; // 未知时不拦，交给 API 403
    }
    return token.scope.split(' ').includes(scope);
  }

  /// 该身份是否被标记「需重新授权」（缺 refresh token）
  needsReauth(sessionId: string): boolean {
    return this.sessionsNeedingReauth.includes(sessionId);
  }

  private markNeedsReauth(sessionId: string): void {
    if (!this.sessionsNeedingReauth.includes(sessionId)) {
      this.sessionsNeedingReauth = this.sessionsNeedingReauth.concat([sessionId]);
    }
  }

  private clearNeedsReauth(sessionId: string): void {
    if (this.sessionsNeedingReauth.includes(sessionId)) {
      this.sessionsNeedingReauth =
        this.sessionsNeedingReauth.filter((id: string) => id !== sessionId);
    }
  }

  /// App 启动时恢复登录态
  async bootstrap(): Promise<void> {
    if (this.bootstrapped) {
      return;
    }
    this.bootstrapped = true;
    try {
      const raw = await AppPrefs.getString(KEY_SESSIONS, '[]');
      const metas = JSON.parse(raw) as AuthSessionMeta[];
      const alive: AuthSessionMeta[] = [];
      for (const meta of metas) {
        const token = await TokenStore.load(meta.id);
        if (token) {
          this.tokens.set(meta.id, token);
          alive.push(meta);
          // 启动即标记缺 refresh token 的身份（不等刷新失败才发现），第一时间给「重新授权」引导
          if (!token.refreshToken) {
            this.markNeedsReauth(meta.id);
            hilog.error(DOMAIN, TAG, 'stored token has no refresh token at bootstrap. session=%{public}s', meta.id);
          }
        }
      }
      this.sessions = alive;
      const savedCurrent = await AppPrefs.getString(KEY_CURRENT, '');
      if (alive.length > 0) {
        this.currentSessionId =
          alive.some((s: AuthSessionMeta) => s.id === savedCurrent) ? savedCurrent : alive[0].id;
        // 启动即已登录 = 老用户升级（区别于全新安装后首次登录）。必须在翻 status 之前置位：
        // status 一变主壳就会挂载并评估「新功能」，晚一拍设置会被读成 false。
        WhatsNewGate.wasLoggedInAtLaunch = true;
        this.status = 'loggedIn';
      } else {
        this.status = 'loggedOut';
      }
    } catch (e) {
      this.status = 'loggedOut';
    }
  }

  /// 构造授权 URL 并记录 PKCE pending（浏览器与无痕 Web 共用）。
  /// 咽喉点铁律：无论调用方传什么 scope，这里**无条件追加 offline_access**——
  /// Hydra 只在请求它时才签发 refresh token，漏掉会导致 access token 到期后会话搁浅
  /// （iOS 1.8.2 / Android 1.6.2 已踩坑同修）。登录 / 添加账号 / 重授权三条流都走此处。
  async buildAuthorizeURL(scopes: string[] = Scopes.defaultScopes): Promise<string> {
    const withOffline = scopes.includes(Scopes.OFFLINE_ACCESS)
      ? scopes
      : scopes.concat([Scopes.OFFLINE_ACCESS]);
    // 新授权流作废残留的重授权 pending，避免回调被误路由到 reauth 分支
    // （reauthorize 在本方法返回后才设 reauthSessionId，不受影响）
    this.reauthSessionId = '';
    this.pendingVerifier = PKCEHelper.generateCodeVerifier();
    this.pendingState = util.generateRandomUUID(true);
    const challenge = await PKCEHelper.generateCodeChallenge(this.pendingVerifier);
    const query = [
      'response_type=code',
      `client_id=${encodeURIComponent(OAuthConfig.clientID)}`,
      `redirect_uri=${encodeURIComponent(OAuthConfig.redirectURI)}`,
      `scope=${encodeURIComponent(Scopes.scopeString(withOffline))}`,
      `state=${encodeURIComponent(this.pendingState)}`,
      `code_challenge=${encodeURIComponent(challenge)}`,
      'code_challenge_method=S256',
    ].join('&');
    return `${OAuthConfig.authorizationURL}?${query}`;
  }

  /// 首次登录：拉起系统浏览器。scopes 可由权限选择 UI 定制，默认仍全量。
  async login(context: common.UIAbilityContext, scopes: string[] = Scopes.defaultScopes): Promise<void> {
    this.error = '';
    const authURL = await this.buildAuthorizeURL(scopes);
    this.status = 'authorizing';
    try {
      const options: OpenLinkOptions = { appLinkingOnly: false };
      await context.openLink(authURL, options);
    } catch (e) {
      this.status = 'loggedOut';
      this.error = '无法打开浏览器进行授权';
      hilog.error(DOMAIN, TAG, 'openLink failed: %{public}s', JSON.stringify(e));
    }
  }

  /// 收到 orangecloud://oauth/callback（deep link 或无痕 Web 拦截）后调用。
  /// 有进行中的重授权（reauthSessionId 非空）时走原地替换分支，不新建身份。
  async handleOAuthCallback(uri: string): Promise<void> {
    const wasLoggedIn = this.sessions.length > 0;
    const reauthTarget = this.reauthSessionId;
    const queryIndex = uri.indexOf('?');
    const params = new url.URLParams(queryIndex >= 0 ? uri.substring(queryIndex + 1) : '');
    const callbackError = params.get('error');
    if (callbackError) {
      if (reauthTarget !== '') {
        this.failReauth(callbackError);
      } else {
        this.finishAuth(wasLoggedIn, callbackError);
      }
      return;
    }
    const code = params.get('code');
    const state = params.get('state');
    if (!code || !state) {
      if (reauthTarget !== '') {
        this.failReauth('授权响应缺少必要参数，请重试');
      } else {
        this.finishAuth(wasLoggedIn, '授权响应缺少必要参数，请重试');
      }
      return;
    }
    if (this.pendingState === '' || state !== this.pendingState) {
      if (reauthTarget !== '') {
        this.failReauth('state 校验失败，请重试');
      } else {
        this.finishAuth(wasLoggedIn, 'state 校验失败，请重试');
      }
      return;
    }
    if (reauthTarget !== '') {
      try {
        await this.completeReauth(reauthTarget, code);
      } finally {
        this.pendingVerifier = '';
        this.pendingState = '';
      }
      return;
    }
    if (!wasLoggedIn) {
      this.status = 'exchanging';
    }
    try {
      const response = await this.requestToken({
        'grant_type': 'authorization_code',
        'client_id': OAuthConfig.clientID,
        'code': code,
        'redirect_uri': OAuthConfig.redirectURI,
        'code_verifier': this.pendingVerifier,
      } as Record<string, string>);
      const sessionId = util.generateRandomUUID(true);
      const stored: StoredToken = {
        accessToken: response.access_token,
        refreshToken: response.refresh_token,
        expiresAtMs: Date.now() + response.expires_in * 1000,
        scope: response.scope ?? '',
      };
      const label = await this.fetchUserLabel(stored.accessToken);
      await TokenStore.save(sessionId, stored);
      this.tokens.set(sessionId, stored);
      const meta: AuthSessionMeta = {
        id: sessionId,
        label: label,
        createdAtMs: Date.now(),
        scope: stored.scope,
      };
      this.sessions = this.sessions.concat([meta]);
      this.currentSessionId = sessionId;
      await this.persistSessions();
      this.status = 'loggedIn';
      this.isAddingAccount = false;
      this.error = '';
      // 登录交换后即检查：端点没发 refresh token 就立刻标记，Dashboard 可第一时间挂横幅
      if (!stored.refreshToken) {
        this.markNeedsReauth(sessionId);
        hilog.error(DOMAIN, TAG, 'token exchange returned no refresh token. session=%{public}s', sessionId);
      }
    } catch (e) {
      this.finishAuth(wasLoggedIn, (e as Error).message ?? '登录失败，请重试');
      hilog.error(DOMAIN, TAG, 'token exchange failed: %{public}s', JSON.stringify(e));
    } finally {
      this.pendingVerifier = '';
      this.pendingState = '';
    }
  }

  private finishAuth(wasLoggedIn: boolean, errorMessage: string): void {
    this.error = errorMessage;
    this.isAddingAccount = false;
    if (!wasLoggedIn) {
      this.status = 'loggedOut';
    }
  }

  /// 浏览器授权中途返回 App，允许用户重置回登录页
  cancelAuthorizing(): void {
    if (this.status === 'authorizing') {
      this.status = 'loggedOut';
    }
  }

  // MARK: - 重新授权（re-auth，原地替换同一身份的 token）

  /// 对已存在的身份重新走授权流：union(该身份原 scope, additionalScopes)，
  /// offline_access 由 buildAuthorizeURL 咽喉点无条件追加。
  /// 交换成功后沿用同一身份 UUID 原地替换 token（不新建账号、不改 currentSessionId）；
  /// 交换前用 userinfo 邮箱与原身份比对，串号即中止。
  /// 用途：① 缺 refresh token 的会话补授权（ReauthBanner）；② 身份详情「补齐授权」。
  async reauthorize(context: common.UIAbilityContext, sessionId: string,
    additionalScopes: string[] = []): Promise<void> {
    const meta = this.sessions.find((s: AuthSessionMeta) => s.id === sessionId);
    if (!meta) {
      return;
    }
    this.reauthError = '';
    const merged: string[] = meta.scope.split(' ').filter((s: string) => s !== '');
    for (const scope of additionalScopes) {
      if (!merged.includes(scope)) {
        merged.push(scope);
      }
    }
    // 原 scope 记录为空（极端兜底）时退回全量，避免发出空 scope 请求
    const authURL = await this.buildAuthorizeURL(merged.length > 0 ? merged : Scopes.defaultScopes);
    this.reauthSessionId = sessionId;
    hilog.info(DOMAIN, TAG, 'reauthorize start session=%{public}s scopeCount=%{public}d',
      sessionId, merged.length);
    try {
      const options: OpenLinkOptions = { appLinkingOnly: false };
      await context.openLink(authURL, options);
    } catch (e) {
      this.reauthSessionId = '';
      this.reauthError = '无法打开浏览器进行授权';
      hilog.error(DOMAIN, TAG, 'reauthorize openLink failed: %{public}s', JSON.stringify(e));
    }
  }

  private failReauth(message: string): void {
    this.reauthError = message;
    this.reauthSessionId = '';
  }

  /// 重授权的 code 交换与原地落盘（handleOAuthCallback 的 reauth 分支）。
  /// 全程不动 status / currentSessionId——App 保持 loggedIn，不触发任何页面重建。
  private async completeReauth(sessionId: string, code: string): Promise<void> {
    const meta = this.sessions.find((s: AuthSessionMeta) => s.id === sessionId);
    if (!meta) {
      this.reauthSessionId = '';
      return;
    }
    try {
      const response = await this.requestToken({
        'grant_type': 'authorization_code',
        'client_id': OAuthConfig.clientID,
        'code': code,
        'redirect_uri': OAuthConfig.redirectURI,
        'code_verifier': this.pendingVerifier,
      } as Record<string, string>);
      const stored: StoredToken = {
        accessToken: response.access_token,
        refreshToken: response.refresh_token,
        expiresAtMs: Date.now() + response.expires_in * 1000,
        scope: response.scope ?? '',
      };
      // 防串号：能取到邮箱、两边都是邮箱且不一致 → 中止，不写入 token
      const newLabel = await this.fetchUserLabel(stored.accessToken);
      if (meta.label.includes('@') && newLabel.includes('@') && newLabel !== meta.label) {
        hilog.error(DOMAIN, TAG, 'reauthorize identity mismatch, aborted');
        this.reauthError = `重新授权返回了不同的账号（${newLabel}），已取消以保护当前身份。请先在浏览器退出其它 Cloudflare 账号，再用原账号登录重试。`;
        return;
      }
      await TokenStore.save(sessionId, stored);
      this.tokens.set(sessionId, stored);
      this.sessions = this.sessions.map((s: AuthSessionMeta) => {
        if (s.id === sessionId) {
          const updated: AuthSessionMeta = {
            id: s.id,
            label: s.label,
            createdAtMs: s.createdAtMs,
            scope: stored.scope,
          };
          return updated;
        }
        return s;
      });
      await this.persistSessions();
      if (stored.refreshToken) {
        this.clearNeedsReauth(sessionId);
      } else {
        this.markNeedsReauth(sessionId);
      }
      this.reauthError = '';
      hilog.info(DOMAIN, TAG, 'reauthorize stored session=%{public}s', sessionId);
    } catch (e) {
      this.reauthError = (e as Error).message ?? '重新授权失败，请重试';
      hilog.error(DOMAIN, TAG, 'reauthorize exchange failed: %{public}s', JSON.stringify(e));
    } finally {
      this.reauthSessionId = '';
    }
  }

  /// 切换当前身份
  async switchSession(sessionId: string): Promise<void> {
    if (this.sessions.some((s: AuthSessionMeta) => s.id === sessionId)) {
      this.currentSessionId = sessionId;
      await AppPrefs.putString(KEY_CURRENT, sessionId);
    }
  }

  /// 重命名身份标签
  async renameSession(sessionId: string, label: string): Promise<void> {
    this.sessions = this.sessions.map((s: AuthSessionMeta) => {
      if (s.id === sessionId) {
        const renamed: AuthSessionMeta = {
          id: s.id,
          label: label,
          createdAtMs: s.createdAtMs,
          scope: s.scope,
        };
        return renamed;
      }
      return s;
    });
    await this.persistSessions();
  }

  /// 返回当前身份的有效 access_token（临期 2 分钟内静默刷新，并发去重）
  async ensureAccessToken(): Promise<string> {
    const sessionId = this.currentSessionId;
    let current = this.tokens.get(sessionId);
    if (!current) {
      throw new Error('未登录');
    }
    if (current.expiresAtMs - Date.now() < 120000) {
      let inflight = this.refreshing.get(sessionId);
      if (!inflight) {
        inflight = this.refreshAccessToken(sessionId).finally(() => {
          this.refreshing.delete(sessionId);
        });
        this.refreshing.set(sessionId, inflight);
      }
      await inflight;
      current = this.tokens.get(sessionId);
      if (!current) {
        throw new Error('登录已过期，请重新登录');
      }
    }
    return current.accessToken;
  }

  /// 刷新 access_token：委托给进程无关的 TokenRefresher（跨进程 RefreshGate 锁），
  /// 前台与后台 WorkScheduler 共用同一条闸门路径，避免并发消费已轮换的 refresh_token。
  /// 本方法在其上保留内存态同步（this.tokens）与登出判定。
  private async refreshAccessToken(sessionId: string): Promise<void> {
    const current = this.tokens.get(sessionId);
    if (!current) {
      await this.removeSession(sessionId, false);
      throw new Error('登录已过期，请重新登录');
    }
    if (!current.refreshToken) {
      // 缺 refresh token 无从续期，但**不清会话**：标记需重授权，由 ReauthBanner 引导
      // 用户原地重授权修复（对齐 iOS token-no-refresh 处置；清会话会误伤多身份场景）。
      this.markNeedsReauth(sessionId);
      if (current.expiresAtMs > Date.now()) {
        return; // 旧 token 尚未真正过期，先沿用
      }
      throw new Error('登录授权已失效，请重新授权');
    }
    const context = GlobalContext.getBase();
    // TokenRefresher 已在锁内完成「重读最新 token → 刷新 → 落盘 / 4xx 清空」。
    // 它不抛错：refreshed=false 可能是「他人已刷新」「网络错误保持原状」或「4xx 已判死」。
    await TokenRefresher.refreshSessionIfNeeded(context, sessionId);
    // 从持久层同步最新态到内存
    const latest = await TokenStore.load(sessionId);
    if (latest) {
      this.tokens.set(sessionId, latest);
      // 仍临期（网络错误未刷成）则报网络错误，让调用方沿用旧 token 重试
      if (latest.expiresAtMs - Date.now() < 120000) {
        throw new Error('网络错误，请稍后重试');
      }
      // 刷新链路健康（拿到了新 token 且带 refresh token）→ 摘除陈旧的重授权标记
      if (latest.refreshToken) {
        this.clearNeedsReauth(sessionId);
      }
      return;
    }
    // TokenStore 被清空 = 4xx 判死，会话结束
    await this.removeSession(sessionId, false);
    throw new Error('登录已过期，请重新登录');
  }

  /// 退出单个身份：尽力撤销 token（失败不阻塞），清空本地；退出全部则回登录页
  async removeSession(sessionId: string, revoke: boolean = true): Promise<void> {
    const token = this.tokens.get(sessionId);
    if (revoke && token) {
      try {
        await this.postForm(OAuthConfig.revokeURL, {
          'client_id': OAuthConfig.clientID,
          'token': token.refreshToken ?? token.accessToken,
        } as Record<string, string>);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'revoke failed (ignored)');
      }
    }
    await TokenStore.clear(sessionId);
    this.tokens.delete(sessionId);
    this.clearNeedsReauth(sessionId);
    if (this.reauthSessionId === sessionId) {
      this.reauthSessionId = '';
    }
    this.sessions = this.sessions.filter((s: AuthSessionMeta) => s.id !== sessionId);
    if (this.currentSessionId === sessionId) {
      this.currentSessionId = this.sessions.length > 0 ? this.sessions[0].id : '';
    }
    await this.persistSessions();
    if (this.sessions.length === 0) {
      this.status = 'loggedOut';
    }
  }

  async logoutAll(): Promise<void> {
    const ids = this.sessions.map((s: AuthSessionMeta) => s.id);
    for (const id of ids) {
      await this.removeSession(id);
    }
  }

  private async persistSessions(): Promise<void> {
    await AppPrefs.putString(KEY_SESSIONS, JSON.stringify(this.sessions));
    await AppPrefs.putString(KEY_CURRENT, this.currentSessionId);
  }

  // MARK: - HTTP

  private async requestToken(params: Record<string, string>): Promise<TokenResponse> {
    const text = await this.postForm(OAuthConfig.tokenURL, params);
    return JSON.parse(text) as TokenResponse;
  }

  private async postForm(endpoint: string, params: Record<string, string>): Promise<string> {
    const session = http.createHttp();
    try {
      const response = await session.request(endpoint, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/x-www-form-urlencoded' } as Record<string, string>,
        extraData: formEncode(params),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 30000,
      });
      const body = response.result as string;
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`HTTP ${response.responseCode} ${body}`);
      }
      return body;
    } finally {
      session.destroy();
    }
  }

  /// 取 userinfo 的 email/name 作为账号标签（失败不阻塞登录）
  private async fetchUserLabel(accessToken: string): Promise<string> {
    const session = http.createHttp();
    try {
      const response = await session.request(OAuthConfig.userInfoURL, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': `Bearer ${accessToken}` } as Record<string, string>,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 30000,
      });
      if (response.responseCode !== 200) {
        return 'Cloudflare 账号';
      }
      const info = JSON.parse(response.result as string) as UserInfo;
      return info.email ?? info.name ?? 'Cloudflare 账号';
    } catch (e) {
      return 'Cloudflare 账号';
    } finally {
      session.destroy();
    }
  }
}

/// 全局单例：EntryAbility（回调分发）与各 View/ViewModel 共用
export const authManager = new AuthManager();
