// 边缘证书查询 + Universal SSL 开关 + 删除证书包（对齐 Android SslRepository）。
// SSL/TLS 加密设置（ssl 模式 / min_tls 等）走 ZoneSettingsService（scope zone-settings）。
import { CFApiClient, apiClient } from '../core/network/CFApiClient';

export interface SslCertificate {
  issuer?: string;
  expires_on?: string;
}

export interface SslCertificatePack {
  id: string;
  type?: string;
  status?: string;
  hosts?: string[];
  certificates?: SslCertificate[];
  certificate_authority?: string;
}

interface UniversalSslSettings {
  enabled?: boolean;
}

export class SSLService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  /// 列出证书包（含未激活，status=all）
  certificatePacks(zoneId: string): Promise<SslCertificatePack[]> {
    return this.client.getList<SslCertificatePack>(`/zones/${zoneId}/ssl/certificate_packs`, {
      'status': 'all',
    } as Record<string, string>);
  }

  async universalEnabled(zoneId: string): Promise<boolean> {
    const settings = await this.client.getObject<UniversalSslSettings>(`/zones/${zoneId}/ssl/universal/settings`);
    return settings.enabled ?? false;
  }

  async setUniversal(zoneId: string, enabled: boolean): Promise<boolean> {
    const body: UniversalSslSettings = { enabled: enabled };
    const settings = await this.client.patchObject<UniversalSslSettings>(
      `/zones/${zoneId}/ssl/universal/settings`, body);
    return settings.enabled ?? enabled;
  }

  /// 删除证书包（仅高级/自定义包；Universal 不可删）
  deletePack(zoneId: string, packId: string): Promise<void> {
    return this.client.delete(`/zones/${zoneId}/ssl/certificate_packs/${packId}`);
  }
}
