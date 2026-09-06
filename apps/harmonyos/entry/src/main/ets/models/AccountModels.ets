// 账号级模块数据模型（Tunnel / ZeroTrust / 审计 / 告警 / LB / Bulk Redirects / 状态页）。

// ---- Tunnel ----
export interface TunnelConnection {
  id?: string;
  colo_name?: string;
  origin_ip?: string;
  opened_at?: string;
  client_version?: string;
  // 仅专用端点返回；旧的内嵌数组没有这两个字段
  client_id?: string;
  uuid?: string;
}

/**
 * GET /accounts/{id}/cfd_tunnel/{id}/connections 的 result 元素。
 * 一个 client 即一个 cloudflared 进程，其 conns 是它维持的各条连接。
 */
export interface TunnelClient {
  id?: string;
  arch?: string;
  version?: string;
  run_at?: string;
  config_version?: number;
  features?: string[];
  conns?: TunnelConnection[];
}

export interface Tunnel {
  id: string;
  name: string;
  status?: string; // inactive | degraded | healthy | down
  created_at?: string;
  conns_active_at?: string;
  /**
   * 过渡期字段：CF 将于 **2026-10-05** 从 list/get 响应移除（2026-07-09 公告）。
   * 只用来在详情页首帧占位，真实数据以 AccountModuleService.tunnelConnections() 为准。
   */
  connections?: TunnelConnection[];
}

// ---- ZeroTrust ----
export interface AccessPolicySummary {
  id?: string;
  name?: string;
  decision?: string;
}

export interface AccessApp {
  id: string;
  name?: string;
  domain?: string;
  type?: string;
  aud?: string;
  session_duration?: string;
  auto_redirect_to_identity?: boolean;
  allowed_idps?: string[];
  policies?: AccessPolicySummary[];
  created_at?: string;
  updated_at?: string;
}

export interface GatewayRule {
  id: string;
  name?: string;
  action?: string;
  enabled?: boolean;
  description?: string;
}

// ---- 审计日志 ----
export interface AuditActor {
  email?: string;
  type?: string;
}

export interface AuditAction {
  type?: string;
  result?: string;
}

export interface AuditResource {
  type?: string;
}

export interface AuditLogEntry {
  id?: string;
  when?: string;
  actor?: AuditActor;
  action?: AuditAction;
  resource?: AuditResource;
}

// ---- 告警 ----
export interface AlertPolicy {
  id: string;
  name?: string;
  alert_type?: string;
  enabled?: boolean;
}

export interface WebhookDestination {
  id: string;
  name?: string;
  url?: string;
}

// ---- Load Balancer ----
export interface LoadBalancer {
  id: string;
  name?: string;
  enabled?: boolean;
  default_pools?: string[];
  proxied?: boolean;
  steering_policy?: string;
  session_affinity?: string;
  fallback_pool?: string;
  ttl?: number;
}

export interface PoolOrigin {
  name?: string;
  address?: string;
  enabled?: boolean;
  weight?: number;
}

export interface Pool {
  id: string;
  name?: string;
  enabled?: boolean;
  healthy?: boolean;
  monitor?: string;
  origins?: PoolOrigin[];
}

// ---- Bulk Redirects ----
export interface RedirectList {
  id: string;
  name: string;
  kind?: string;
  num_items?: number;
  description?: string;
}

export interface RedirectItemRedirect {
  source_url?: string;
  target_url?: string;
  status_code?: number;
}

export interface RedirectListItem {
  id?: string;
  redirect?: RedirectItemRedirect;
}

// ---- 状态页（cloudflarestatus.com，非 CF 信封） ----
export interface StatusIndicator {
  status?: string;      // 兼容旧字段
  indicator?: string;   // none | minor | major | critical | maintenance
  description?: string;
}

export interface StatusComponent {
  id: string;
  name: string;
  status: string;       // operational | degraded_performance | partial_outage | major_outage | under_maintenance
  group?: boolean;      // true = 分组容器（如各大洲 PoP 分组）
  group_id?: string;
}

export interface IncidentUpdate {
  status?: string;
  body?: string;
  display_at?: string;
}

export interface StatusIncident {
  id?: string;
  name?: string;
  status?: string;
  impact?: string;
  shortlink?: string;
  updated_at?: string;
  created_at?: string;
  scheduled_for?: string;
  incident_updates?: IncidentUpdate[];
}

export interface StatusSummary {
  status?: StatusIndicator;
  components?: StatusComponent[];
  incidents?: StatusIncident[];
  scheduled_maintenances?: StatusIncident[];
}

export interface StatusIncidentList {
  incidents?: StatusIncident[];
}
