// Email Routing：zone 级状态/规则 + 账户级目标地址（对齐 Android EmailRoutingRepository）。
import { ApiError, CFApiClient, apiClient } from '../core/network/CFApiClient';

export interface EmailRoutingStatus {
  enabled?: boolean;
  status?: string;
  name?: string;
}

export interface EmailMatcher {
  type: string; // literal | all
  field?: string;
  value?: string;
}

export interface EmailAction {
  type: string; // forward | drop
  value?: string[];
}

export interface EmailRoutingRule {
  id: string;
  name?: string;
  enabled?: boolean;
  matchers?: EmailMatcher[];
  actions?: EmailAction[];
}

export interface EmailRuleInput {
  name?: string;
  enabled: boolean;
  matchers: EmailMatcher[];
  actions: EmailAction[];
}

export interface EmailDestinationAddress {
  id: string;
  email: string;
  verified?: string;
}

interface EmailDestinationCreate {
  email: string;
}

/**
 * 被抑制的收件地址：硬退信/投诉后 Cloudflare 不再向其转发。
 * 与「路由规则」是两回事——规则决定往哪转，抑制决定不往哪转。
 * 「规则配了却收不到」多半就是命中了这里。
 */
export interface EmailSuppression {
  id: string;
  email?: string;
  reason?: string;        // hard_bounce / soft_bounce / complaint / manual
  created_at?: string;
  expires_at?: string;    // null 表示永久
  zones?: string[];
}

/// GET 抑制列表的顶层结构（非标准信封：无 success / errors）
interface SuppressionPage {
  result?: EmailSuppression[];
  page?: number;
  per_page?: number;
  total?: number;
}

/// POST 抑制地址的顶层结构（只有 result）
interface SuppressionCreated {
  result?: EmailSuppression;
}

interface SuppressionCreate {
  email: string;
}

export function suppressionReasonLabel(reason: string): string {
  if (reason === 'hard_bounce') {
    return '硬退信';
  }
  if (reason === 'soft_bounce') {
    return '软退信';
  }
  if (reason === 'complaint') {
    return '投诉';
  }
  if (reason === 'manual') {
    return '手动添加';
  }
  return '未知';
}

export class EmailRoutingService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  status(zoneId: string): Promise<EmailRoutingStatus> {
    return this.client.getObject<EmailRoutingStatus>(`/zones/${zoneId}/email/routing`);
  }

  async setEnabled(zoneId: string, enabled: boolean): Promise<void> {
    const action = enabled ? 'enable' : 'disable';
    await this.client.postObject<object>(`/zones/${zoneId}/email/routing/${action}`, {} as Record<string, string>);
  }

  /// 路由规则（不含 catch-all）。端点默认 per_page=20（上限 50），不翻页第 21 条起就看不见。
  rules(zoneId: string): Promise<EmailRoutingRule[]> {
    return this.client.getAllPages<EmailRoutingRule>(`/zones/${zoneId}/email/routing/rules`, 50);
  }

  createRule(zoneId: string, input: EmailRuleInput): Promise<EmailRoutingRule> {
    return this.client.postObject<EmailRoutingRule>(`/zones/${zoneId}/email/routing/rules`, input);
  }

  updateRule(zoneId: string, ruleId: string, input: EmailRuleInput): Promise<EmailRoutingRule> {
    return this.client.putObject<EmailRoutingRule>(`/zones/${zoneId}/email/routing/rules/${ruleId}`, input);
  }

  deleteRule(zoneId: string, ruleId: string): Promise<void> {
    return this.client.delete(`/zones/${zoneId}/email/routing/rules/${ruleId}`);
  }

  /// catch-all 兜底规则（matcher 固定 type=all；不在普通 rules 列表里，走独立端点）
  catchAll(zoneId: string): Promise<EmailRoutingRule> {
    return this.client.getObject<EmailRoutingRule>(`/zones/${zoneId}/email/routing/rules/catch_all`);
  }

  /// 更新 catch-all（PUT 需带完整 matchers/actions；启停也走整条回写）
  updateCatchAll(zoneId: string, input: EmailRuleInput): Promise<EmailRoutingRule> {
    return this.client.putObject<EmailRoutingRule>(`/zones/${zoneId}/email/routing/rules/catch_all`, input);
  }

  /// 账号下全部目的地址（含未验证）。
  /// OpenAPI 里 `verified` 查询参数默认 true（只回已验证），而 UI 有「待验证」态，刚添加的地址必须出现——
  /// 所以已验证 / 未验证各拉一遍再按 id 去重合并；分页同 rules（默认 20 条）。
  async addresses(accountId: string): Promise<EmailDestinationAddress[]> {
    const merged: EmailDestinationAddress[] = [];
    const seen = new Set<string>();
    for (const verified of ['true', 'false']) {
      const items = await this.client.getAllPages<EmailDestinationAddress>(
        `/accounts/${accountId}/email/routing/addresses`, 50, { 'verified': verified } as Record<string, string>);
      for (const item of items) {
        if (!seen.has(item.id)) {
          seen.add(item.id);
          merged.push(item);
        }
      }
    }
    return merged;
  }

  createAddress(accountId: string, email: string): Promise<EmailDestinationAddress> {
    const body: EmailDestinationCreate = { email: email };
    return this.client.postObject<EmailDestinationAddress>(`/accounts/${accountId}/email/routing/addresses`, body);
  }

  deleteAddress(accountId: string, addressId: string): Promise<void> {
    return this.client.delete(`/accounts/${accountId}/email/routing/addresses/${addressId}`);
  }
  /// 抑制列表（email-routing-suppression.read / .write）。
  /// ⚠️ 该端点 2xx 不走 CF 标准信封：顶层是 { page, per_page, total, result }，没有 success
  /// （OpenAPI 规范如此，iOS Sentry APPLE-IOS-AB 坐实）；按信封解必然失败。
  async suppressions(zoneId: string): Promise<EmailSuppression[]> {
    const page = await this.client.getBare<SuppressionPage>(`/zones/${zoneId}/email/routing/suppression`, {
      'per_page': '100',
    } as Record<string, string>);
    return page.result ?? [];
  }

  /// 手动抑制一个地址。响应同样无信封，只有 { result }（OpenAPI）。
  async addSuppression(zoneId: string, email: string): Promise<EmailSuppression> {
    const body: SuppressionCreate = { email: email };
    const res = await this.client.postBare<SuppressionCreated>(`/zones/${zoneId}/email/routing/suppression`, body);
    if (!res.result) {
      throw new ApiError('响应缺少结果');
    }
    return res.result;
  }

  /// 解除抑制
  deleteSuppression(zoneId: string, id: string): Promise<void> {
    return this.client.delete(`/zones/${zoneId}/email/routing/suppression/${id}`);
  }

}
