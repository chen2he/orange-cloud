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

  /// 设置自动续费。返回异步 workflow 状态，调用方成功后应回读列表。
  setAutoRenew(accountId: string, domainName: string, enabled: boolean): Promise<object> {
    const body: AutoRenewUpdate = { auto_renew: enabled };
    return this.client.patchObject<object>(`/accounts/${accountId}/registrar/registrations/${domainName}`, body);
  }
}
