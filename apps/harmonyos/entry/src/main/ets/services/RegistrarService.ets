// Cloudflare Registrar（registrar-domains.read / .admin）。
//
// ⚠️ 用新版 /accounts/{id}/registrar/registrations —— 旧的 /registrar/domains
// 于 2026-06-29 弃用、**2026-09-27 停用**。
//
// 两个接口边界：PATCH 只支持 auto_renew（locked 转移锁只读）；PATCH 返回异步 workflow 状态，
// 写入后需回读列表。
import { CFApiClient, apiClient } from '../core/network/CFApiClient';

export interface DomainRegistration {
  domain_name: string;
  expires_at?: string;
  created_at?: string;
  auto_renew?: boolean;
  locked?: boolean;          // 只读
  privacy_mode?: string;
  status?: string;           // active / registration_pending / expired / suspended / redemption_period
}

interface AutoRenewUpdate {
  auto_renew: boolean;
}

/// 域名搜索 / 实时检查的价格（金额是字符串，原样展示）
export interface DomainPricing {
  currency?: string;
  registration_cost?: string;
  renewal_cost?: string;
}

/// 域名搜索 / 实时检查结果项。reason 见 domainReasonLabel；tier 为 standard / premium
export interface DomainAvailability {
  name: string;
  registrable?: boolean;
  tier?: string;
  reason?: string;
  pricing?: DomainPricing;
}

interface DomainSearchResult {
  domains?: DomainAvailability[];
}

interface DomainCheckBody {
  domains: string[];
}

export class RegistrarService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  /// 该端点是游标分页，但 getList 已封装分页细节，这里取首屏 50 条足够移动端展示
  registrations(accountId: string): Promise<DomainRegistration[]> {
    return this.client.getList<DomainRegistration>(`/accounts/${accountId}/registrar/registrations`, {
      'per_page': '50',
    } as Record<string, string>);
  }

  /// 搜索可注册的新域名（结果可能有延迟，点开后再用 check 实时确认）。registrar-domains.read
  async search(accountId: string, query: string): Promise<DomainAvailability[]> {
    const result = await this.client.getObject<DomainSearchResult>(
      `/accounts/${accountId}/registrar/domain-search`, {
        'q': query,
        'limit': '20',
      } as Record<string, string>);
    return result.domains ?? [];
  }

  /// 实时向注册局确认（单次最多 20 个）
  async check(accountId: string, names: string[]): Promise<DomainAvailability[]> {
    const body: DomainCheckBody = { domains: names };
    const result = await this.client.postObject<DomainSearchResult>(
      `/accounts/${accountId}/registrar/domain-check`, body);
    return result.domains ?? [];
  }

  /// 设置自动续费。返回异步 workflow 状态，调用方成功后应回读列表。
  setAutoRenew(accountId: string, domainName: string, enabled: boolean): Promise<object> {
    const body: AutoRenewUpdate = { auto_renew: enabled };
    return this.client.patchObject<object>(`/accounts/${accountId}/registrar/registrations/${domainName}`, body);
  }
}
