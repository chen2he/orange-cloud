// 独立健康检查（healthcheck.read / .write）。/zones/{zone_id}/healthchecks
// 免费套餐不可用（0 个）；Pro 10 / Business 50 / Enterprise 1000。
import { CFApiClient, apiClient } from '../core/network/CFApiClient';

export interface HealthCheck {
  id: string;
  name: string;
  address?: string;
  description?: string;
  type?: string;            // HTTP / HTTPS / TCP
  status?: string;          // healthy / unhealthy / unknown
  failure_reason?: string;
  suspended?: boolean;      // 暂停后不再向源站发送检查
  interval?: number;
  timeout?: number;
  retries?: number;
  consecutive_fails?: number;
  consecutive_successes?: number;
  check_regions?: string[];
}

interface SuspendBody {
  suspended: boolean;
}

export class HealthCheckService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  list(zoneId: string): Promise<HealthCheck[]> {
    return this.client.getList<HealthCheck>(`/zones/${zoneId}/healthchecks`, {
      'per_page': '50',
    } as Record<string, string>);
  }

  /// 暂停 / 恢复。暂停后 CF 不再向源站发送检查。
  setSuspended(zoneId: string, checkId: string, suspended: boolean): Promise<HealthCheck> {
    const body: SuspendBody = { suspended: suspended };
    return this.client.patchObject<HealthCheck>(`/zones/${zoneId}/healthchecks/${checkId}`, body);
  }

  remove(zoneId: string, checkId: string): Promise<void> {
    return this.client.delete(`/zones/${zoneId}/healthchecks/${checkId}`);
  }
}
