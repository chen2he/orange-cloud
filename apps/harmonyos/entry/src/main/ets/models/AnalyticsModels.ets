// GraphQL Analytics 模型（对齐 Android AnalyticsModels）。
// 数据集：httpRequests1hGroups（24h，Time 标量）/ httpRequests1dGroups（7d·30d，Date 标量）。

export type AnalyticsRange = '24h' | '7d' | '30d';

/// 按国家/地区聚合的子项（httpRequests1hGroups/1dGroups 的 sum.countryMap 数组元素）。
/// Cloudflare 的国家维度不作为顶层 dimension，而是每个时间桶 sum 内携带一个 countryMap 数组，
/// 端上需跨时间桶按国家码合并求和（对齐 iOS AnalyticsModels.swift 的 CountryMapEntry）。
export interface CountryMapEntry {
  clientCountryName?: string;
  requests?: number;
  threats?: number;
  bytes?: number;
}

export interface GQLSum {
  requests?: number;
  bytes?: number;
  threats?: number;
  pageViews?: number;
  cachedRequests?: number;
  cachedBytes?: number;
  errors?: number;
  subrequests?: number;
  cpuTimeUs?: number;
  countryMap?: CountryMapEntry[];
}

/// workersInvocationsAdaptive 的分位数（CPU 单次耗时，微秒）
export interface GQLQuantiles {
  cpuTimeP50?: number;
  cpuTimeP99?: number;
}

export interface GQLUniq {
  uniques?: number;
}

export interface GQLDimensions {
  datetime?: string;
  date?: string;
  datetimeHour?: string;
  clientCountryName?: string;
  status?: string;
}

export interface GQLGroup {
  dimensions?: GQLDimensions;
  sum?: GQLSum;
  uniq?: GQLUniq;
  quantiles?: GQLQuantiles;
}

export interface GQLZoneNode {
  httpRequests1hGroups?: GQLGroup[];
  httpRequests1dGroups?: GQLGroup[];
}

export interface GQLAccountNode {
  summary?: GQLGroup[];
  series?: GQLGroup[];
  byStatus?: GQLGroup[];
}

export interface GQLViewer {
  zones?: GQLZoneNode[];
  accounts?: GQLAccountNode[];
}

export interface GQLData {
  viewer?: GQLViewer;
}

/// GraphQL 错误的扩展段：Cloudflare 用 code='authz' 表示该账号无账户级数据权限
export interface GQLErrorExtensions {
  code?: string;
}

export interface GQLError {
  message: string;
  extensions?: GQLErrorExtensions;
}

/// 账户级数据集未授权（免费账号常态），与普通查询失败区分
export function isAccountAuthzError(err: GQLError): boolean {
  return err.extensions?.code === 'authz' || err.message === 'not authorized for that account';
}

export interface GQLResponse {
  data?: GQLData;
  errors?: GQLError[];
}

/// 归一化后的时间序列点
export interface TrafficDataPoint {
  label: string;
  requests: number;
  bytes: number;
  threats: number;
  pageViews: number;
  uniques: number;
  cachedRequests: number;
}

export interface CountryTraffic {
  country: string;
  requests: number;
}

/// 调用状态分解的一项（workersInvocationsAdaptive 的 status 维度）
export interface WorkerStatusItem {
  status: string;
  requests: number;
}

/// Worker 指标摘要（对齐 iOS WorkerMetrics）。
/// CPU 相关字段来自较新的 GraphQL 字段，取不到时为 -1（调用方按「不展示」处理）。
export interface WorkerMetrics {
  requests: number;
  errors: number;
  subrequests: number;
  /// CPU 单次耗时分位（微秒），-1 = 不可用
  cpuP50Us: number;
  cpuP99Us: number;
  /// CPU 合计耗时（微秒），-1 = 不可用
  cpuTotalUs: number;
  statusBreakdown: WorkerStatusItem[];
}

/// 错误率（百分比）；无请求时返回 -1
export function workerErrorRate(metrics: WorkerMetrics): number {
  if (metrics.requests <= 0) {
    return -1;
  }
  return metrics.errors / metrics.requests * 100;
}

/// Worker 指标时间序列的一个点（24h 按小时，7d/30d 按天）
export interface WorkerSeriesPoint {
  label: string;
  requests: number;
  errors: number;
}

/// 调用状态 → 中文展示名（对齐 iOS WorkerInvocationStatus.label）
export function workerStatusLabel(status: string): string {
  switch (status) {
    case 'success':
      return '成功';
    case 'scriptThrewException':
      return '脚本异常';
    case 'exceededCpu':
      return '超出 CPU 限制';
    case 'exceededMemory':
      return '超出内存限制';
    case 'clientDisconnected':
      return '客户端断开';
    case 'canceled':
      return '已取消';
    case 'responseStreamDisconnected':
      return '响应流断开';
    default:
      return status;
  }
}

/// 调用状态 → 状态点颜色：健康绿 / 中性灰 / 异常红（对齐 iOS statusColor）
export function workerStatusColor(status: string): string {
  if (status === 'success') {
    return '#22C55E';
  }
  if (status === 'clientDisconnected' || status === 'canceled' || status === 'responseStreamDisconnected') {
    return '#9CA3AF';
  }
  return '#DC2626';
}

// ---- 访问明细 / 安全事件（adaptive 数据集，2026-10-02 起 Free/Pro 保留 ≥31 天、可查 30 天）----

/// adaptive 分组的维度（各别名按需取一个）
export interface AdaptiveDimensions {
  clientCountryName?: string;
  edgeResponseStatus?: number;
  clientRequestPath?: string;
  clientRequestHTTPHost?: string;
  action?: string;
  source?: string;
}

export interface AdaptiveGroup {
  count?: number;
  dimensions?: AdaptiveDimensions;
}

/// firewallEventsAdaptive 单条事件
export interface FirewallEventRow {
  datetime?: string;
  action?: string;
  source?: string;
  clientIP?: string;
  clientCountryName?: string;
  clientRequestPath?: string;
  clientRequestHTTPHost?: string;
  rayName?: string;
}

/// 数据集可用性与查询上限（maxDuration / notOlderThan 单位秒）
export interface DatasetSetting {
  enabled?: boolean;
  maxDuration?: number;
  notOlderThan?: number;
}

export interface ZoneDatasetSettings {
  httpRequestsAdaptiveGroups?: DatasetSetting;
  firewallEventsAdaptive?: DatasetSetting;
}

export interface AdaptiveZoneNode {
  settings?: ZoneDatasetSettings;
  byCountry?: AdaptiveGroup[];
  byStatus?: AdaptiveGroup[];
  byPath?: AdaptiveGroup[];
  byHost?: AdaptiveGroup[];
  byAction?: AdaptiveGroup[];
  bySource?: AdaptiveGroup[];
  recent?: FirewallEventRow[];
}

export interface AdaptiveViewer {
  zones?: AdaptiveZoneNode[];
}

export interface AdaptiveData {
  viewer?: AdaptiveViewer;
}

export interface AdaptiveResponse {
  data?: AdaptiveData;
  errors?: GQLError[];
}

/// Top N 的一项（标签 + 次数）
export interface TopItem {
  label: string;
  count: number;
}

/// 访问明细：四个维度各自 Top 10
export interface AccessDetails {
  country: TopItem[];
  status: TopItem[];
  path: TopItem[];
  host: TopItem[];
}

/// 安全事件：按处置方式 / 按来源计数 + 最近 20 条
export interface SecurityEvents {
  byAction: TopItem[];
  bySource: TopItem[];
  recent: FirewallEventRow[];
}

/// 按数据集上限裁剪后的查询窗口
export interface AdaptiveWindow {
  since: string;
  until: string;
  /// 数据集停用（enabled=false）
  unavailable: boolean;
  /// 被裁剪后的实际秒数；0 = 未裁剪
  clampedSeconds: number;
}
