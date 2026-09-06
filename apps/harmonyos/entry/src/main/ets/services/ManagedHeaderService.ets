// 托管请求/响应头（Managed Transforms）。GET/PATCH /zones/{zone_id}/managed_headers
// managed-headers.read / .write
//
// 由 Cloudflare 维护的一组开关式头部改写，无需自己写 Transform 规则。
// PATCH 是分区合并：只发要改的那一节、节内按 id 匹配。
import { CFApiClient, apiClient } from '../core/network/CFApiClient';

export interface ManagedTransform {
  id: string;
  enabled?: boolean;
  conflicts_with?: string[];   // 只读；开启前提示互斥
}

export interface ManagedTransforms {
  managed_request_headers?: ManagedTransform[];
  managed_response_headers?: ManagedTransform[];
}

interface ToggleItem {
  id: string;
  enabled: boolean;
}

interface PatchBody {
  managed_request_headers?: ToggleItem[];
  managed_response_headers?: ToggleItem[];
}

/// 接口给的是 add_security_headers 这类蛇形 id，直接展示不友好
export function managedHeaderLabel(id: string): string {
  return id.split('_').map((w: string) => w.length > 0 ? w[0].toUpperCase() + w.slice(1) : w).join(' ');
}

export class ManagedHeaderService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  transforms(zoneId: string): Promise<ManagedTransforms> {
    return this.client.getObject<ManagedTransforms>(`/zones/${zoneId}/managed_headers`);
  }

  /// isRequest 决定改哪一节——两节的 id 空间独立
  setEnabled(zoneId: string, id: string, enabled: boolean, isRequest: boolean): Promise<ManagedTransforms> {
    const item: ToggleItem = { id: id, enabled: enabled };
    const body: PatchBody = isRequest
      ? { managed_request_headers: [item] } as PatchBody
      : { managed_response_headers: [item] } as PatchBody;
    return this.client.patchObject<ManagedTransforms>(`/zones/${zoneId}/managed_headers`, body);
  }
}
