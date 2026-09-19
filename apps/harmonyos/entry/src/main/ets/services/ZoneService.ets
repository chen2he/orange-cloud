// Zone Service：列表 / 新建 / 暂停恢复
import { Zone } from '../models/Models';
import { CFApiClient, apiClient } from '../core/network/CFApiClient';

interface CreateZoneAccount {
  id: string;
}

interface PauseZoneBody {
  paused: boolean;
}

interface CreateZoneBody {
  name: string;
  account: CreateZoneAccount;
  type: string;
}

export class ZoneService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  fetchZones(accountId: string): Promise<Zone[]> {
    return this.client.getList<Zone>('/zones', {
      'account.id': accountId,
      'per_page': '50',
    } as Record<string, string>);
  }

  fetchZone(zoneId: string): Promise<Zone> {
    return this.client.getObject<Zone>(`/zones/${zoneId}`);
  }

  /// 清除全部缓存（POST /zones/{id}/purge_cache）
  async purgeAllCache(zoneId: string): Promise<void> {
    interface PurgeBody {
      purge_everything: boolean;
    }
    const body: PurgeBody = { purge_everything: true };
    await this.client.postObject<object>(`/zones/${zoneId}/purge_cache`, body);
  }

  /// 暂停 / 恢复 Cloudflare 代理（Dashboard 的「Pause Cloudflare on Site」）。
  /// 暂停后 DNS 仍由 Cloudflare 解析，但流量不再经过 Cloudflare——WAF、缓存、
  /// 源站 IP 隐藏一并失效；生效约需 5 分钟。需要 zone.write。
  setPaused(zoneId: string, paused: boolean): Promise<Zone> {
    const body: PauseZoneBody = { paused: paused };
    return this.client.patchObject<Zone>(`/zones/${zoneId}`, body);
  }

  /// 添加域名（full setup，添加后需在注册商改 NS）
  createZone(accountId: string, name: string): Promise<Zone> {
    const body: CreateZoneBody = {
      name: name,
      account: { id: accountId } as CreateZoneAccount,
      type: 'full',
    };
    return this.client.postObject<Zone>('/zones', body);
  }
}
