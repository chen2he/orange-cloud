// Zone DNS 设置（/zones/{id}/dns_settings，zone-dns-settings.*）与 DNSSEC（/zones/{id}/dnssec，dns.*）。
//
// 注意历史弃用：cname_flattening 与账户级 default_nameservers 都已迁到 DNS Settings API；
// foundation_dns（sunset 2026-11-23）由 nameservers.type = 'cloudflare.advanced' 取代——只用后者。
import { CFApiClient, apiClient } from '../core/network/CFApiClient';

export interface ZoneNameservers {
  type?: string;      // cloudflare.standard / cloudflare.advanced / custom.*
  ns_set?: number;
}

export interface ZoneDnsSettings {
  flatten_all_cnames?: boolean;
  multi_provider?: boolean;
  secondary_overrides?: boolean;
  ns_ttl?: number;
  zone_mode?: string;   // standard / cdn_only / dns_only
  nameservers?: ZoneNameservers;
}

export interface ZoneDnssec {
  status?: string;      // active / pending / disabled / pending-disabled / error
  ds?: string;          // 完整 DS 记录，用户要粘到域名注册商处
  digest?: string;
  algorithm?: string;
}

interface DnssecUpdate {
  status: string;
}

export class DnsSettingsService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  settings(zoneId: string): Promise<ZoneDnsSettings> {
    return this.client.getObject<ZoneDnsSettings>(`/zones/${zoneId}/dns_settings`);
  }

  /// 合并语义：body 只带要改的字段
  updateSettings(zoneId: string, body: ZoneDnsSettings): Promise<ZoneDnsSettings> {
    return this.client.patchObject<ZoneDnsSettings>(`/zones/${zoneId}/dns_settings`, body);
  }

  dnssec(zoneId: string): Promise<ZoneDnssec> {
    return this.client.getObject<ZoneDnssec>(`/zones/${zoneId}/dnssec`);
  }

  /// 启用传 active，停用传 disabled。启用后先是 pending，需用户去注册商加 DS 记录才转 active。
  setDnssec(zoneId: string, enabled: boolean): Promise<ZoneDnssec> {
    const body: DnssecUpdate = { status: enabled ? 'active' : 'disabled' };
    return this.client.patchObject<ZoneDnssec>(`/zones/${zoneId}/dnssec`, body);
  }
}
