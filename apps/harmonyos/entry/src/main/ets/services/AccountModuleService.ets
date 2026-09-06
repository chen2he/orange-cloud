// 账号级模块 Service（Tunnel / ZeroTrust / 审计 / 告警 / LB / Bulk Redirects / 状态页）。
// 对齐 Android 各 repository；只做查看 + 关键写操作（启停/删除/新建），复杂配置留到后续。
import { http } from '@kit.NetworkKit';
import {
  AccessApp,
  AlertPolicy,
  AuditLogEntry,
  GatewayRule,
  LoadBalancer,
  Pool,
  RedirectList,
  RedirectListItem,
  StatusIncident,
  StatusSummary,
  Tunnel,
  TunnelClient,
  TunnelConnection,
  WebhookDestination,
} from '../models/AccountModels';
import { CFError } from '../models/Models';
import { CFApiClient, apiClient } from '../core/network/CFApiClient';

interface CreateTunnelBody {
  name: string;
  config_src: string;
}

// ---- Tunnel 配置（公共主机名 ingress，对齐 iOS TunnelModels）----
/// 单条 ingress 规则。catch-all（末尾兜底）只有 service、无 hostname。
/// originRequest 原样透传（JSON.parse 出的运行时对象保留全部键），整组回写不丢高级配置。
export interface TunnelIngressRule {
  hostname?: string;
  service: string;
  path?: string;
  originRequest?: object;
}

/// 隧道配置。整组 PUT；未建模字段（warp-routing / 全局 originRequest 等）留在
/// JSON.parse 出的原对象上，随 JSON.stringify 原样回写。
export interface TunnelConfigData {
  ingress?: TunnelIngressRule[];
}

interface TunnelConfigResultShell {
  tunnel_id?: string;
  config?: TunnelConfigData;
}

interface TunnelConfigEnvelope {
  success: boolean;
  errors?: CFError[];
  result?: TunnelConfigResultShell;
}

interface TunnelConfigUpdateBody {
  config: TunnelConfigData;
}

// ---- Access 应用编辑 ----
interface AccessDestinationRaw {
  type?: string;
  uri?: string;
}

interface AccessPolicyRef {
  id?: string;
}

/// PUT 前先取详情用的原始形态（比 AccountModels.AccessApp 多 destinations，
/// PUT 是全量替换，漏传 destinations 会把多主机名应用删到只剩 domain 单值）。
interface AccessAppDetailRaw {
  id: string;
  name?: string;
  domain?: string;
  type?: string;
  session_duration?: string;
  destinations?: AccessDestinationRaw[];
  policies?: AccessPolicyRef[];
}

interface AccessAppUpdateBody {
  name: string;
  domain: string;
  type: string;
  session_duration: string;
  policies: string[];
  destinations?: AccessDestinationRaw[];
}

// ---- 审计日志（游标分页，对齐 iOS AuditLogService）----
interface AuditResultInfo {
  cursor?: string;
  // 仅资源变更历史返回：exact / approximate / unavailable。
  // approximate = 没拿到资源 URI、靠其它字段近似匹配，结果可能混入无关条目，必须如实告诉用户。
  history_status?: string;
}

interface AuditEnvelope {
  success: boolean;
  errors?: CFError[];
  result?: AuditLogEntry[];
  result_info?: AuditResultInfo;
}

export interface AuditLogPageResult {
  entries: AuditLogEntry[];
  cursor: string;
  historyStatus?: string;
}

function firstEnvelopeError(errors?: CFError[]): Error {
  if (errors && errors.length > 0) {
    return new Error(errors[0].message);
  }
  return new Error('未知错误');
}

interface WebhookCreate {
  name: string;
  url: string;
}

interface RedirectListCreate {
  name: string;
  kind: string;
  description?: string;
}

export class AccountModuleService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  // ---- Tunnel ----
  listTunnels(accountId: string): Promise<Tunnel[]> {
    return this.client.getList<Tunnel>(`/accounts/${accountId}/cfd_tunnel`, {
      'is_deleted': 'false',
      'per_page': '100',
    } as Record<string, string>);
  }

  getTunnel(accountId: string, tunnelId: string): Promise<Tunnel> {
    return this.client.getObject<Tunnel>(`/accounts/${accountId}/cfd_tunnel/${tunnelId}`);
  }

  /**
   * 隧道的活跃连接（专用端点）。
   *
   * 取代 list/get 响应里内嵌的 connections 数组（CF 将于 2026-10-05 移除该字段）。
   * result 是 Client 数组（一个 cloudflared 进程一项），此处摊平为连接列表供 UI 直接消费；
   * client_version 在 conns 里可能缺省，回退用 client 自身的 version 补齐。
   */
  async tunnelConnections(accountId: string, tunnelId: string): Promise<TunnelConnection[]> {
    const clients =
      await this.client.getList<TunnelClient>(`/accounts/${accountId}/cfd_tunnel/${tunnelId}/connections`);
    const flattened: TunnelConnection[] = [];
    clients.forEach((c: TunnelClient) => {
      (c.conns ?? []).forEach((conn: TunnelConnection) => {
        flattened.push({
          id: conn.id,
          colo_name: conn.colo_name,
          origin_ip: conn.origin_ip,
          opened_at: conn.opened_at,
          client_version: conn.client_version ?? c.version,
          client_id: conn.client_id ?? c.id,
          uuid: conn.uuid,
        } as TunnelConnection);
      });
    });
    return flattened;
  }

  createTunnel(accountId: string, name: string): Promise<Tunnel> {
    const body: CreateTunnelBody = { name: name, config_src: 'cloudflare' };
    return this.client.postObject<Tunnel>(`/accounts/${accountId}/cfd_tunnel`, body);
  }

  deleteTunnel(accountId: string, tunnelId: string): Promise<void> {
    return this.client.delete(`/accounts/${accountId}/cfd_tunnel/${tunnelId}`);
  }

  /// 隧道配置（公共主机名 ingress）。远程托管（config_src=cloudflare）才有；
  /// 新建后尚无配置时 result.config 为空，这里统一返回空对象。
  async getTunnelConfig(accountId: string, tunnelId: string): Promise<TunnelConfigData> {
    const raw = await this.client.getRaw(`/accounts/${accountId}/cfd_tunnel/${tunnelId}/configurations`);
    const envelope = JSON.parse(raw) as TunnelConfigEnvelope;
    if (!envelope.success) {
      throw firstEnvelopeError(envelope.errors);
    }
    return envelope.result?.config ?? ({} as TunnelConfigData);
  }

  /// 整组回写隧道配置（末条 catch-all 由调用方保证），返回更新后的配置。
  async updateTunnelConfig(accountId: string, tunnelId: string,
    config: TunnelConfigData): Promise<TunnelConfigData> {
    const body: TunnelConfigUpdateBody = { config: config };
    const result = await this.client.putObject<TunnelConfigResultShell>(
      `/accounts/${accountId}/cfd_tunnel/${tunnelId}/configurations`, body);
    return result.config ?? config;
  }

  /// 隧道连接令牌（result 是裸 base64 字符串；argotunnel.write 才可读），
  /// 用于 `cloudflared service install <token>` 安装命令。
  getTunnelToken(accountId: string, tunnelId: string): Promise<string> {
    return this.client.getObject<string>(`/accounts/${accountId}/cfd_tunnel/${tunnelId}/token`);
  }

  /// 清理失活连接（活跃的 cloudflared 仍会自动重连）
  deleteTunnelConnections(accountId: string, tunnelId: string): Promise<void> {
    return this.client.delete(`/accounts/${accountId}/cfd_tunnel/${tunnelId}/connections`);
  }

  // ---- ZeroTrust ----
  accessApps(accountId: string): Promise<AccessApp[]> {
    return this.client.getList<AccessApp>(`/accounts/${accountId}/access/apps`);
  }

  /// 单 Access 应用详情（列表只给概要，详情含 session_duration / aud / policies 等）
  accessApp(accountId: string, appId: string): Promise<AccessApp> {
    return this.client.getObject<AccessApp>(`/accounts/${accountId}/access/apps/${appId}`);
  }

  gatewayRules(accountId: string): Promise<GatewayRule[]> {
    return this.client.getList<GatewayRule>(`/accounts/${accountId}/gateway/rules`);
  }

  deleteAccessApp(accountId: string, appId: string): Promise<void> {
    return this.client.delete(`/accounts/${accountId}/access/apps/${appId}`);
  }

  /// 新建 Access 应用：先建可复用策略（decision + include），再建应用引用它。
  /// includeType: everyone / email_domain（value 为域名）。对齐 Android createOrUpdateApp。
  async createAccessApp(accountId: string, name: string, domain: string, includeType: string,
    includeValue: string): Promise<AccessApp> {
    // 1) 建策略
    interface EmptyRule {
    }
    interface EmailDomainRule {
      domain: string;
    }
    interface IncludeEveryone {
      everyone: EmptyRule;
    }
    interface IncludeEmailDomain {
      email_domain: EmailDomainRule;
    }
    interface PolicyInput {
      name: string;
      decision: string;
      include: Object[];
    }
    interface PolicyResult {
      id: string;
    }
    const include: Object[] = includeType === 'email_domain' && includeValue !== ''
      ? [{ email_domain: { domain: includeValue } as EmailDomainRule } as IncludeEmailDomain]
      : [{ everyone: {} as EmptyRule } as IncludeEveryone];
    const policyBody: PolicyInput = { name: `${name} policy`, decision: 'allow', include: include };
    const policy = await this.client.postObject<PolicyResult>(`/accounts/${accountId}/access/policies`, policyBody);

    // 2) 建应用引用策略
    interface AppInput {
      name: string;
      domain: string;
      type: string;
      session_duration: string;
      policies: string[];
    }
    const appBody: AppInput = {
      name: name,
      domain: domain,
      type: 'self_hosted',
      session_duration: '24h',
      policies: [policy.id],
    };
    return this.client.postObject<AccessApp>(`/accounts/${accountId}/access/apps`, appBody);
  }

  /// 编辑 Access 应用（名称/域名/会话时长）。PUT 是全量替换：先取详情，
  /// 把既有 policies（转成 ID 列表）与 destinations 一并回写，避免被清空；
  /// 域名变更时同步替换 destinations 里与旧 domain 匹配的那条。
  async updateAccessApp(accountId: string, appId: string, name: string, domain: string,
    sessionDuration: string): Promise<AccessApp> {
    const detail = await this.client.getObject<AccessAppDetailRaw>(
      `/accounts/${accountId}/access/apps/${appId}`);
    const policyIds: string[] = [];
    for (const p of detail.policies ?? []) {
      if (p.id !== undefined && p.id !== '') {
        policyIds.push(p.id);
      }
    }
    let destinations: AccessDestinationRaw[] | undefined = undefined;
    if (detail.destinations !== undefined && detail.destinations.length > 0) {
      destinations = detail.destinations.map((d: AccessDestinationRaw): AccessDestinationRaw => {
        if (d.uri !== undefined && d.uri === detail.domain && domain !== detail.domain) {
          return { type: d.type ?? 'public', uri: domain } as AccessDestinationRaw;
        }
        return d;
      });
    }
    const body: AccessAppUpdateBody = {
      name: name,
      domain: domain,
      type: detail.type ?? 'self_hosted',
      session_duration: sessionDuration,
      policies: policyIds,
      destinations: destinations,
    };
    return this.client.putObject<AccessApp>(`/accounts/${accountId}/access/apps/${appId}`, body);
  }

  /// 新建 Gateway 规则（DNS/L4/HTTP 过滤，action=block/allow 等 + traffic 表达式）
  createGatewayRule(accountId: string, name: string, action: string, traffic: string): Promise<GatewayRule> {
    interface GatewayRuleCreate {
      name: string;
      action: string;
      enabled: boolean;
      filters: string[];
      traffic: string;
    }
    const body: GatewayRuleCreate = {
      name: name,
      action: action,
      enabled: true,
      filters: ['dns'],
      traffic: traffic,
    };
    return this.client.postObject<GatewayRule>(`/accounts/${accountId}/gateway/rules`, body);
  }

  deleteGatewayRule(accountId: string, ruleId: string): Promise<void> {
    return this.client.delete(`/accounts/${accountId}/gateway/rules/${ruleId}`);
  }

  // CF 审计端点要求 since/before 为完整 ISO8601，且 before 必填、外加 limit/direction；
  // 只传 YYYY-MM-DD 的 since、缺 before 会被拒（表现为空错误「未知错误」）。
  // 游标分页（对齐 iOS AuditLogService）：cursor 为空取首页，非空续接下一页；
  // 续页必须复用首页固定的 since/before 时间窗（查询参数一致游标才有效）。
  async auditLogsPage(accountId: string, sinceIso: string, beforeIso: string,
    cursor: string): Promise<AuditLogPageResult> {
    const query: Record<string, string> = {
      'since': sinceIso,
      'before': beforeIso,
      'limit': '50',
      'direction': 'desc',
    };
    if (cursor !== '') {
      query['cursor'] = cursor;
    }
    const raw = await this.client.getRaw(`/accounts/${accountId}/logs/audit`, query);
    const envelope = JSON.parse(raw) as AuditEnvelope;
    if (!envelope.success) {
      throw firstEnvelopeError(envelope.errors);
    }
    const page: AuditLogPageResult = {
      entries: envelope.result ?? [],
      cursor: envelope.result_info?.cursor ?? '',
    };
    return page;
  }

  // 某条审计日志所对应资源的完整变更序列（2026-07-27 上线）。
  // 接口先用 id + action_time 定位源日志、从中推出资源标识，再回查同一资源的其它日志，
  // 所以 actionTime 必填（用于收窄查找窗口），缺了就定位不到。
  async auditResourceHistory(accountId: string, entryId: string, actionTimeIso: string,
    sinceIso: string, beforeIso: string): Promise<AuditLogPageResult> {
    const query: Record<string, string> = {
      'action_time': actionTimeIso,
      'since': sinceIso,
      'before': beforeIso,
      'limit': '50',
      'direction': 'desc',
    };
    const raw = await this.client.getRaw(`/accounts/${accountId}/logs/audit/${entryId}/history`, query);
    const envelope = JSON.parse(raw) as AuditEnvelope;
    if (!envelope.success) {
      throw firstEnvelopeError(envelope.errors);
    }
    const page: AuditLogPageResult = {
      entries: envelope.result ?? [],
      cursor: envelope.result_info?.cursor ?? '',
      historyStatus: envelope.result_info?.history_status ?? '',
    };
    return page;
  }

  // ---- 告警 ----
  alertPolicies(accountId: string): Promise<AlertPolicy[]> {
    return this.client.getList<AlertPolicy>(`/accounts/${accountId}/alerting/v3/policies`);
  }

  webhooks(accountId: string): Promise<WebhookDestination[]> {
    return this.client.getList<WebhookDestination>(`/accounts/${accountId}/alerting/v3/destinations/webhooks`);
  }

  createWebhook(accountId: string, name: string, url: string): Promise<WebhookDestination> {
    const body: WebhookCreate = { name: name, url: url };
    return this.client.postObject<WebhookDestination>(
      `/accounts/${accountId}/alerting/v3/destinations/webhooks`, body);
  }

  deleteWebhook(accountId: string, webhookId: string): Promise<void> {
    return this.client.delete(`/accounts/${accountId}/alerting/v3/destinations/webhooks/${webhookId}`);
  }

  /// 新建告警策略（绑定一个 webhook 目标）
  createPolicy(accountId: string, name: string, alertType: string, webhookId: string): Promise<AlertPolicy> {
    interface PolicyMechanisms {
      webhooks: WebhookRef[];
    }
    interface WebhookRef {
      id: string;
    }
    interface PolicyCreate {
      name: string;
      alert_type: string;
      enabled: boolean;
      mechanisms: PolicyMechanisms;
    }
    const body: PolicyCreate = {
      name: name,
      alert_type: alertType,
      enabled: true,
      mechanisms: { webhooks: [{ id: webhookId } as WebhookRef] } as PolicyMechanisms,
    };
    return this.client.postObject<AlertPolicy>(`/accounts/${accountId}/alerting/v3/policies`, body);
  }

  deletePolicy(accountId: string, policyId: string): Promise<void> {
    return this.client.delete(`/accounts/${accountId}/alerting/v3/policies/${policyId}`);
  }

  // ---- Load Balancer ----
  loadBalancers(zoneId: string): Promise<LoadBalancer[]> {
    return this.client.getList<LoadBalancer>(`/zones/${zoneId}/load_balancers`);
  }

  async setLoadBalancerEnabled(zoneId: string, lbId: string, enabled: boolean): Promise<void> {
    interface LBToggle {
      enabled: boolean;
    }
    const body: LBToggle = { enabled: enabled };
    await this.client.patchObject<object>(`/zones/${zoneId}/load_balancers/${lbId}`, body);
  }

  loadBalancer(zoneId: string, lbId: string): Promise<LoadBalancer> {
    return this.client.getObject<LoadBalancer>(`/zones/${zoneId}/load_balancers/${lbId}`);
  }

  pools(accountId: string): Promise<Pool[]> {
    return this.client.getList<Pool>(`/accounts/${accountId}/load_balancers/pools`);
  }

  // ---- Bulk Redirects ----
  async redirectLists(accountId: string): Promise<RedirectList[]> {
    const lists = await this.client.getList<RedirectList>(`/accounts/${accountId}/rules/lists`);
    return lists.filter((l: RedirectList) => l.kind === 'redirect');
  }

  createRedirectList(accountId: string, name: string, description: string): Promise<RedirectList> {
    const body: RedirectListCreate = {
      name: name,
      kind: 'redirect',
      description: description === '' ? undefined : description,
    };
    return this.client.postObject<RedirectList>(`/accounts/${accountId}/rules/lists`, body);
  }

  deleteRedirectList(accountId: string, listId: string): Promise<void> {
    return this.client.delete(`/accounts/${accountId}/rules/lists/${listId}`);
  }

  listItems(accountId: string, listId: string): Promise<RedirectListItem[]> {
    return this.client.getList<RedirectListItem>(`/accounts/${accountId}/rules/lists/${listId}/items`);
  }

  /// 追加重定向条目（异步 bulk operation，POST 返回 operation_id，这里不等完成）
  async addItem(accountId: string, listId: string, sourceUrl: string, targetUrl: string,
    statusCode: number): Promise<void> {
    interface ItemRedirect {
      source_url: string;
      target_url: string;
      status_code: number;
    }
    interface ItemInput {
      redirect: ItemRedirect;
    }
    const body: ItemInput[] = [{
      redirect: { source_url: sourceUrl, target_url: targetUrl, status_code: statusCode } as ItemRedirect,
    }];
    await this.client.postForList<object>(`/accounts/${accountId}/rules/lists/${listId}/items`, body);
  }

  /// 删除条目（整表 PUT 覆盖：传剩余条目；此处用 DELETE 带 items）
  async deleteItem(accountId: string, listId: string, itemId: string): Promise<void> {
    interface ItemRef {
      id: string;
    }
    interface DeleteBody {
      items: ItemRef[];
    }
    const body: DeleteBody = { items: [{ id: itemId } as ItemRef] };
    await this.client.delete(`/accounts/${accountId}/rules/lists/${listId}/items`, body);
  }

  // ---- 状态页（公开 API，无鉴权、非 CF 信封）----
  async statusSummary(): Promise<StatusSummary> {
    const text = await this.publicGet('https://www.cloudflarestatus.com/api/v2/summary.json');
    return JSON.parse(text) as StatusSummary;
  }

  async statusIncidents(): Promise<StatusIncident[]> {
    const text = await this.publicGet('https://www.cloudflarestatus.com/api/v2/incidents.json');
    interface IncidentsResponse {
      incidents?: StatusIncident[];
    }
    const parsed = JSON.parse(text) as IncidentsResponse;
    return parsed.incidents ?? [];
  }

  private async publicGet(url: string): Promise<string> {
    const session = http.createHttp();
    try {
      const response = await session.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 30000,
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`HTTP ${response.responseCode}`);
      }
      return response.result as string;
    } finally {
      session.destroy();
    }
  }
}
