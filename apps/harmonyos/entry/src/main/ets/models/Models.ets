// Cloudflare API 数据模型。
// 与 iOS Models/ 对齐；ArkTS 直接以 API 原始 snake_case 字段名建接口（无 CodingKeys 一说）。

export interface CFError {
  code: number;
  message: string;
}

export interface ResultInfo {
  /// 游标分页端点（如 Durable Objects 对象列表）用它翻页，空/缺省表示已到末页
  cursor?: string;
  page?: number;
  per_page?: number;
  total_pages?: number;
  count?: number;
  total_count?: number;
}

/// 通用响应包装 { result, success, errors }（列表型）
export interface CFListEnvelope<T> {
  success: boolean;
  result?: T[];
  errors?: CFError[];
  result_info?: ResultInfo;
}

/// 通用响应包装（单对象型，POST/PUT/DELETE 返回）
export interface CFObjectEnvelope<T> {
  success: boolean;
  result?: T;
  errors?: CFError[];
}

export interface Account {
  id: string;
  name: string;
  type?: string;
}

export interface ZonePlan {
  name?: string;
}

export interface Zone {
  id: string;
  name: string;
  status: string; // "active" | "pending" | "initializing" | "moved" 等
  /// 是否暂停 Cloudflare 代理（Dashboard 的「Pause Cloudflare on Site」）。
  /// 与 status 正交：暂停时 status 多半仍是 active，展示态用 zoneDisplayStatus()。
  paused?: boolean;
  plan?: ZonePlan;
  name_servers?: string[];
}

/// 对外展示用状态：暂停优先于 status
export function zoneDisplayStatus(zone: Zone): string {
  return zone.paused === true ? 'paused' : zone.status;
}

export interface DNSRecord {
  id: string;
  type: string; // A, AAAA, CNAME, TXT, MX 等
  name: string;
  content: string;
  proxied?: boolean;
  ttl: number;
  priority?: number;
  comment?: string;
}

/// DNS 记录创建/更新请求体（POST/PUT /zones/{id}/dns_records）
export interface DNSRecordPayload {
  type: string;
  name: string;
  content: string;
  ttl: number;
  proxied?: boolean;
  priority?: number;
  comment?: string;
}
