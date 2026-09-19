// 进程无关的 OAuth token 刷新（前台 AuthManager 与后台 WorkScheduler 共用同一条闸门路径）。
// 安全铁律（Cloudflare 每次刷新轮换 refresh_token）：
//   1. 拿到 RefreshGate 跨进程锁后，**重新从 TokenStore 读一次最新 token**——
//      另一进程可能刚刷新过，若读到的 token 已远离过期则直接跳过（避免消费到已轮换的旧 refresh_token）。
//   2. 只有 token 端点明确拒绝该 refresh_token 才判死（清空该身份 token）：400–403 **且**响应体是
//      OAuth 错误 JSON（{"error":"invalid_grant",…}）。WAF 挑战页（403 HTML）、429 限流、公共 Wi-Fi
//      登录页、5xx、断网都只是瞬时问题，保持原状、绝不误登出（对齐 iOS 2.1.3）。
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { OAuthConfig } from './OAuthConfig';
import { StoredToken, TokenStore } from './TokenStore';
import { RefreshGate } from './RefreshGate';

const DOMAIN = 0x0001;
const TAG = 'TokenRefresher';
/// 距过期这么久内才考虑刷新（后台阈值放宽到 5 分钟，早于前台 2 分钟，保活更从容）
const REFRESH_THRESHOLD_MS = 300000;

interface TokenResponse {
  access_token: string;
  expires_in: number;
  refresh_token?: string;
  scope?: string;
}

function formEncode(params: Record<string, string>): string {
  const parts: string[] = [];
  for (const key of Object.keys(params)) {
    parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(params[key])}`);
  }
  return parts.join('&');
}

/// token 端点非 2xx：保留状态码与原始响应体，交给 isRefreshTokenRejected 判定
class TokenEndpointError extends Error {
  status: number;
  body: string;

  constructor(status: number, body: string) {
    super(`HTTP ${status}`);
    this.status = status;
    this.body = body;
  }
}

interface OAuthErrorBody {
  error?: string;
}

/// 服务端明确拒绝了这个 refresh_token：400–403 且响应体是带 error 字段的 OAuth JSON。
/// 403 的 WAF 挑战页是 HTML，解析失败即不算；429 / 5xx 不在区间内。
function isRefreshTokenRejected(e: TokenEndpointError): boolean {
  if (e.status < 400 || e.status > 403) {
    return false;
  }
  try {
    const body = JSON.parse(e.body) as OAuthErrorBody;
    return typeof body.error === 'string' && body.error.length > 0;
  } catch (err) {
    return false;
  }
}

/// POST token 端点；非 2xx 抛 TokenEndpointError（由 isRefreshTokenRejected 决定是否判死）
async function postForm(endpoint: string, params: Record<string, string>): Promise<string> {
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
      throw new TokenEndpointError(response.responseCode, body ?? '');
    }
    return body;
  } finally {
    session.destroy();
  }
}

export class TokenRefresher {
  /// 若临期则刷新指定身份的 token（跨进程锁保护），返回是否发生了刷新。
  /// 进程无关：只经 TokenStore 读写，不依赖 AuthManager 内存状态。
  static async refreshSessionIfNeeded(context: common.Context, sessionId: string): Promise<boolean> {
    const current = await TokenStore.load(sessionId);
    if (!current) {
      return false; // 无此身份 token，交由上层处理
    }
    if (current.expiresAtMs - Date.now() >= REFRESH_THRESHOLD_MS) {
      return false; // 尚未临期
    }
    const key = `refresh_${sessionId}.lock`;
    const result = await RefreshGate.runExclusive<boolean>(context, key, async (): Promise<boolean> => {
      // 拿锁后重读最新 token——另一进程可能刚刷新过
      const latest = await TokenStore.load(sessionId);
      if (!latest) {
        return false;
      }
      if (latest.expiresAtMs - Date.now() >= REFRESH_THRESHOLD_MS) {
        return false; // 已被他人刷新，跳过
      }
      if (!latest.refreshToken) {
        // 无 refresh_token：会话已被 stranded，判死清空（对齐既有语义）
        await TokenStore.clear(sessionId);
        return false;
      }
      try {
        const text = await postForm(OAuthConfig.tokenURL, {
          'grant_type': 'refresh_token',
          'client_id': OAuthConfig.clientID,
          'refresh_token': latest.refreshToken,
        } as Record<string, string>);
        const parsed = JSON.parse(text) as TokenResponse;
        const renewed: StoredToken = {
          accessToken: parsed.access_token,
          refreshToken: parsed.refresh_token ?? latest.refreshToken,
          expiresAtMs: Date.now() + parsed.expires_in * 1000,
          scope: parsed.scope ?? latest.scope,
        };
        await TokenStore.save(sessionId, renewed);
        return true;
      } catch (e) {
        const message = (e as Error).message ?? '';
        if (e instanceof TokenEndpointError && isRefreshTokenRejected(e as TokenEndpointError)) {
          await TokenStore.clear(sessionId);
          hilog.warn(DOMAIN, TAG, 'session %{public}s refresh token rejected (%{public}s), cleared',
            sessionId, message);
        } else {
          // WAF 挑战页 / 限流 / 5xx / 断网：瞬时问题，保留会话
          hilog.warn(DOMAIN, TAG, 'refresh transient error (kept): %{public}s', message);
        }
        return false;
      }
    });
    return result === true;
  }
}
