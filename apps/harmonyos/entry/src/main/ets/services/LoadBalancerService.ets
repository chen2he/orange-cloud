// 负载均衡 CRUD（对齐 iOS LoadBalancerService.swift，端点核对自 cloudflare-python SDK）：
// LB 为 zone 级（zones/{zone}/load_balancers），池与健康监测为 account 级（accounts/{acct}/load_balancers/pools|monitors）。
// 更新一律走 PATCH 顶层合并：载荷只带表单开放的字段，未开放的高级配置（region_pools / load_shedding 等）自动保留。
// 注意：Pool 的 origins 是整组字段，编辑时必须把现有 origin 完整回写（含 port / header / vnet），漏传即删。
import { CFApiClient, apiClient } from '../core/network/CFApiClient';
import { LoadBalancer } from '../models/AccountModels';

/// 源站（比 AccountModels.PoolOrigin 多 port / header / virtual_network_id，编辑回写时保留）
export interface LBOrigin {
  name?: string;
  address?: string;
  enabled?: boolean;
  weight?: number;
  port?: number;
  header?: Record<string, string[]>;
  virtual_network_id?: string;
}

/// 源站池（account 级；比 AccountModels.Pool 多 minimum_origins / description，供编辑表单用）
export interface LBPool {
  id: string;
  name?: string;
  enabled?: boolean;
  healthy?: boolean;
  monitor?: string;
  description?: string;
  minimum_origins?: number;
  origins?: LBOrigin[];
}

/// 健康监测（account 级）
export interface LBMonitor {
  id: string;
  type?: string;
  method?: string;
  path?: string;
  expected_codes?: string;
  expected_body?: string;
  interval?: number;
  timeout?: number;
  retries?: number;
  port?: number;
  follow_redirects?: boolean;
  allow_insecure?: boolean;
  description?: string;
}

/// LB 创建 / 编辑载荷（可选字段省略即不改）
export interface LoadBalancerPayload {
  name?: string;
  default_pools?: string[];
  fallback_pool?: string;
  steering_policy?: string;
  session_affinity?: string;
  proxied?: boolean;
  ttl?: number;
}

/// 池创建 / 编辑载荷（origins 整组提交）
export interface LBPoolPayload {
  name?: string;
  origins?: LBOrigin[];
  minimum_origins?: number;
  monitor?: string;
}

/// 监测创建 / 编辑载荷（tcp 类型不带 method / path / expected_codes）
export interface LBMonitorPayload {
  type?: string;
  method?: string;
  path?: string;
  expected_codes?: string;
  interval?: number;
  timeout?: number;
  retries?: number;
  follow_redirects?: boolean;
  allow_insecure?: boolean;
}

export class LoadBalancerService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  // ---- Load Balancer（zone 级）----

  listLoadBalancers(zoneId: string): Promise<LoadBalancer[]> {
    return this.client.getList<LoadBalancer>(`/zones/${zoneId}/load_balancers`);
  }

  createLoadBalancer(zoneId: string, body: LoadBalancerPayload): Promise<LoadBalancer> {
    return this.client.postObject<LoadBalancer>(`/zones/${zoneId}/load_balancers`, body);
  }

  updateLoadBalancer(zoneId: string, lbId: string, body: LoadBalancerPayload): Promise<LoadBalancer> {
    return this.client.patchObject<LoadBalancer>(`/zones/${zoneId}/load_balancers/${lbId}`, body);
  }

  deleteLoadBalancer(zoneId: string, lbId: string): Promise<void> {
    return this.client.delete(`/zones/${zoneId}/load_balancers/${lbId}`);
  }

  // ---- 源站池 Pool（account 级）----

  listPools(accountId: string): Promise<LBPool[]> {
    return this.client.getList<LBPool>(`/accounts/${accountId}/load_balancers/pools`);
  }

  createPool(accountId: string, body: LBPoolPayload): Promise<LBPool> {
    return this.client.postObject<LBPool>(`/accounts/${accountId}/load_balancers/pools`, body);
  }

  updatePool(accountId: string, poolId: string, body: LBPoolPayload): Promise<LBPool> {
    return this.client.patchObject<LBPool>(`/accounts/${accountId}/load_balancers/pools/${poolId}`, body);
  }

  deletePool(accountId: string, poolId: string): Promise<void> {
    return this.client.delete(`/accounts/${accountId}/load_balancers/pools/${poolId}`);
  }

  // ---- 健康监测 Monitor（account 级）----

  listMonitors(accountId: string): Promise<LBMonitor[]> {
    return this.client.getList<LBMonitor>(`/accounts/${accountId}/load_balancers/monitors`);
  }

  createMonitor(accountId: string, body: LBMonitorPayload): Promise<LBMonitor> {
    return this.client.postObject<LBMonitor>(`/accounts/${accountId}/load_balancers/monitors`, body);
  }

  updateMonitor(accountId: string, monitorId: string, body: LBMonitorPayload): Promise<LBMonitor> {
    return this.client.patchObject<LBMonitor>(`/accounts/${accountId}/load_balancers/monitors/${monitorId}`, body);
  }

  deleteMonitor(accountId: string, monitorId: string): Promise<void> {
    return this.client.delete(`/accounts/${accountId}/load_balancers/monitors/${monitorId}`);
  }
}
