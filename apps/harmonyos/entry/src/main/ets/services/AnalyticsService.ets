// Zone 流量分析：GraphQL Analytics API → 归一化数据点（对齐 Android AnalyticsRepository）。
// 24h 走 httpRequests1hGroups（Time 标量），7d/30d 走 httpRequests1dGroups（Date 标量）。
import {
  AccessDetails,
  AdaptiveGroup,
  AdaptiveResponse,
  AdaptiveWindow,
  AdaptiveZoneNode,
  AnalyticsRange,
  CountryTraffic,
  DatasetSetting,
  GQLGroup,
  GQLResponse,
  SecurityEvents,
  TopItem,
  ZoneDatasetSettings,
  TrafficDataPoint,
  WorkerMetrics,
  WorkerSeriesPoint,
  WorkerStatusItem,
  isAccountAuthzError,
} from '../models/AnalyticsModels';
import { AccountAnalyticsUnauthorizedError } from './UsageService';
import { CFApiClient, apiClient, ApiError } from '../core/network/CFApiClient';

export interface RangeWindow {
  since: string;
  until: string;
  hourly: boolean;
}

function isoSeconds(date: Date): string {
  return `${date.toISOString().substring(0, 19)}Z`;
}

function isoDate(date: Date): string {
  return date.toISOString().substring(0, 10);
}

/// 上一周期窗口（等长、紧邻当前窗口之前）——趋势徽章的对比基准，对齐 iOS previousSinceUntil
export function previousRangeWindow(range: AnalyticsRange): RangeWindow {
  const now = new Date();
  if (range === '24h') {
    const until = new Date(now.getTime() - 24 * 3600 * 1000);
    const since = new Date(now.getTime() - 48 * 3600 * 1000);
    return { since: isoSeconds(since), until: isoSeconds(until), hourly: true };
  }
  const days = range === '7d' ? 7 : 30;
  const until = new Date(now.getTime() - days * 24 * 3600 * 1000);
  const since = new Date(now.getTime() - 2 * days * 24 * 3600 * 1000);
  return { since: isoDate(since), until: isoDate(until), hourly: false };
}

export function rangeWindow(range: AnalyticsRange): RangeWindow {
  const now = new Date();
  if (range === '24h') {
    const since = new Date(now.getTime() - 24 * 3600 * 1000);
    return { since: isoSeconds(since), until: isoSeconds(now), hourly: true };
  }
  const days = range === '7d' ? 6 : 29;
  const since = new Date(now.getTime() - days * 24 * 3600 * 1000);
  return { since: isoDate(since), until: isoDate(now), hourly: false };
}

interface GQLVariables {
  zoneTag: string;
  since: string;
  until: string;
}

const ZONE_HOURLY_QUERY = `query ($zoneTag: string!, $since: Time!, $until: Time!) {
  viewer { zones(filter: { zoneTag: $zoneTag }) {
    httpRequests1hGroups(limit: 500, filter: { datetime_geq: $since, datetime_leq: $until }, orderBy: [datetime_ASC]) {
      dimensions { datetime }
      sum { requests bytes threats pageViews cachedRequests cachedBytes }
      uniq { uniques }
    } } } }`;

const ZONE_DAILY_QUERY = `query ($zoneTag: string!, $since: Date!, $until: Date!) {
  viewer { zones(filter: { zoneTag: $zoneTag }) {
    httpRequests1dGroups(limit: 100, filter: { date_geq: $since, date_leq: $until }, orderBy: [date_ASC]) {
      dimensions { date }
      sum { requests bytes threats pageViews cachedRequests cachedBytes }
      uniq { uniques }
    } } } }`;

// 国家/地区聚合：Cloudflare 不把 clientCountryName 作为顶层 dimension，
// 而是每个时间桶的 sum 内携带一个 countryMap 数组（对齐 iOS AnalyticsQueries.zoneCountryHourly/Daily）。
// 端上跨时间桶按国家码合并求和。用 dimensions { clientCountryName } 分组会返回空国家名 → 空数据。
const COUNTRY_HOURLY_QUERY = `query ($zoneTag: string!, $since: Time!, $until: Time!) {
  viewer { zones(filter: { zoneTag: $zoneTag }) {
    httpRequests1hGroups(limit: 1000, filter: { datetime_geq: $since, datetime_leq: $until }) {
      sum { countryMap { clientCountryName requests threats bytes } }
    } } } }`;

const COUNTRY_DAILY_QUERY = `query ($zoneTag: string!, $since: Date!, $until: Date!) {
  viewer { zones(filter: { zoneTag: $zoneTag }) {
    httpRequests1dGroups(limit: 1000, filter: { date_geq: $since, date_leq: $until }) {
      sum { countryMap { clientCountryName requests threats bytes } }
    } } } }`;

// ---- 访问明细 / 安全事件（adaptive 数据集，Time 标量，datetime_geq / datetime_lt）----

const ADAPTIVE_SETTINGS_QUERY = `query ($zoneTag: string!) {
  viewer { zones(filter: { zoneTag: $zoneTag }) {
    settings {
      httpRequestsAdaptiveGroups { enabled maxDuration notOlderThan }
      firewallEventsAdaptive { enabled maxDuration notOlderThan }
    } } } }`;

const ACCESS_DETAILS_QUERY = `query ($zoneTag: string!, $since: Time!, $until: Time!) {
  viewer { zones(filter: { zoneTag: $zoneTag }) {
    byCountry: httpRequestsAdaptiveGroups(limit: 10, filter: { datetime_geq: $since, datetime_lt: $until }, orderBy: [count_DESC]) {
      count dimensions { clientCountryName } }
    byStatus: httpRequestsAdaptiveGroups(limit: 10, filter: { datetime_geq: $since, datetime_lt: $until }, orderBy: [count_DESC]) {
      count dimensions { edgeResponseStatus } }
    byPath: httpRequestsAdaptiveGroups(limit: 10, filter: { datetime_geq: $since, datetime_lt: $until }, orderBy: [count_DESC]) {
      count dimensions { clientRequestPath } }
    byHost: httpRequestsAdaptiveGroups(limit: 10, filter: { datetime_geq: $since, datetime_lt: $until }, orderBy: [count_DESC]) {
      count dimensions { clientRequestHTTPHost } }
  } } }`;

const SECURITY_EVENTS_QUERY = `query ($zoneTag: string!, $since: Time!, $until: Time!) {
  viewer { zones(filter: { zoneTag: $zoneTag }) {
    byAction: firewallEventsAdaptiveGroups(limit: 20, filter: { datetime_geq: $since, datetime_lt: $until }, orderBy: [count_DESC]) {
      count dimensions { action } }
    bySource: firewallEventsAdaptiveGroups(limit: 20, filter: { datetime_geq: $since, datetime_lt: $until }, orderBy: [count_DESC]) {
      count dimensions { source } }
    recent: firewallEventsAdaptive(limit: 20, filter: { datetime_geq: $since, datetime_lt: $until }, orderBy: [datetime_DESC]) {
      datetime action source clientIP clientCountryName clientRequestPath clientRequestHTTPHost rayName }
  } } }`;

interface ZoneTagVariables {
  zoneTag: string;
}

/// 时间窗对应秒数（24h / 7d / 30d）
function rangeSeconds(range: AnalyticsRange): number {
  if (range === '24h') {
    return 24 * 3600;
  }
  return (range === '7d' ? 7 : 30) * 24 * 3600;
}

/// 按数据集上限裁剪窗口：超过 maxDuration / notOlderThan 就缩短到上限（取最近这一段）
export function adaptiveWindow(range: AnalyticsRange, setting: DatasetSetting | undefined): AdaptiveWindow {
  const now = new Date();
  let seconds = rangeSeconds(range);
  let clamped = 0;
  const maxDuration = setting?.maxDuration ?? 0;
  if (maxDuration > 0 && seconds > maxDuration) {
    seconds = maxDuration;
    clamped = seconds;
  }
  const notOlderThan = setting?.notOlderThan ?? 0;
  if (notOlderThan > 0 && seconds > notOlderThan) {
    seconds = notOlderThan;
    clamped = seconds;
  }
  const since = new Date(now.getTime() - seconds * 1000);
  return {
    since: isoSeconds(since),
    until: isoSeconds(now),
    unavailable: setting?.enabled === false,
    clampedSeconds: clamped,
  };
}

function topItems(groups: AdaptiveGroup[] | undefined, pick: (g: AdaptiveGroup) => string): TopItem[] {
  const out: TopItem[] = [];
  for (const g of groups ?? []) {
    const label = pick(g);
    out.push({ label: label !== '' ? label : '（空）', count: g.count ?? 0 });
  }
  return out;
}

function hourLabel(datetime: string): string {
  // "2026-07-06T13:00:00Z" → 本地 "HH:00"
  const date = new Date(datetime);
  if (Number.isNaN(date.getTime())) {
    return datetime;
  }
  const h = date.getHours();
  return `${h < 10 ? '0' : ''}${h}:00`;
}

function dayLabel(dateStr: string): string {
  // "2026-07-06" → "07-06"
  return dateStr.length >= 10 ? dateStr.substring(5, 10) : dateStr;
}

export class AnalyticsService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  private async run(query: string, variables: GQLVariables): Promise<GQLResponse> {
    const text = await this.client.graphql(query, variables);
    const response = JSON.parse(text) as GQLResponse;
    if (response.errors && response.errors.length > 0) {
      const first = response.errors[0];
      // 免费账号没有账户级数据权限：抛专用错误让 UI 走中性提示而非「重试」
      if (isAccountAuthzError(first)) {
        throw new AccountAnalyticsUnauthorizedError(first.message);
      }
      throw new ApiError(first.message);
    }
    return response;
  }

  async zoneTraffic(zoneId: string, range: AnalyticsRange): Promise<TrafficDataPoint[]> {
    return this.zoneTrafficWindow(zoneId, rangeWindow(range));
  }

  /// 上一周期同长窗口（趋势徽章用；失败由调用方吞掉，不挡主数据）
  async zoneTrafficPrevious(zoneId: string, range: AnalyticsRange): Promise<TrafficDataPoint[]> {
    return this.zoneTrafficWindow(zoneId, previousRangeWindow(range));
  }

  private async zoneTrafficWindow(zoneId: string, win: RangeWindow): Promise<TrafficDataPoint[]> {
    const query = win.hourly ? ZONE_HOURLY_QUERY : ZONE_DAILY_QUERY;
    const variables: GQLVariables = { zoneTag: zoneId, since: win.since, until: win.until };
    const response = await this.run(query, variables);
    const zones = response.data?.viewer?.zones ?? [];
    if (zones.length === 0) {
      return [];
    }
    const groups: GQLGroup[] = (win.hourly ? zones[0].httpRequests1hGroups : zones[0].httpRequests1dGroups) ?? [];
    const points: TrafficDataPoint[] = [];
    for (const g of groups) {
      const label = win.hourly
        ? hourLabel(g.dimensions?.datetime ?? '')
        : dayLabel(g.dimensions?.date ?? '');
      points.push({
        label: label,
        requests: g.sum?.requests ?? 0,
        bytes: g.sum?.bytes ?? 0,
        threats: g.sum?.threats ?? 0,
        pageViews: g.sum?.pageViews ?? 0,
        uniques: g.uniq?.uniques ?? 0,
        cachedRequests: g.sum?.cachedRequests ?? 0,
      });
    }
    return points;
  }

  /// 按国家/地区聚合请求量，降序
  async zoneCountryTraffic(zoneId: string, range: AnalyticsRange): Promise<CountryTraffic[]> {
    const win = rangeWindow(range);
    const query = win.hourly ? COUNTRY_HOURLY_QUERY : COUNTRY_DAILY_QUERY;
    const variables: GQLVariables = { zoneTag: zoneId, since: win.since, until: win.until };
    const response = await this.run(query, variables);
    const zones = response.data?.viewer?.zones ?? [];
    if (zones.length === 0) {
      return [];
    }
    const groups: GQLGroup[] = (win.hourly ? zones[0].httpRequests1hGroups : zones[0].httpRequests1dGroups) ?? [];
    const byCountry: Map<string, number> = new Map();
    for (const g of groups) {
      const countryMap = g.sum?.countryMap ?? [];
      for (const entry of countryMap) {
        const country = entry.clientCountryName ?? '';
        if (country === '') {
          continue;
        }
        byCountry.set(country, (byCountry.get(country) ?? 0) + (entry.requests ?? 0));
      }
    }
    const result: CountryTraffic[] = [];
    byCountry.forEach((requests: number, country: string) => {
      if (requests > 0) {
        result.push({ country: country, requests: requests });
      }
    });
    result.sort((a: CountryTraffic, b: CountryTraffic) => b.requests - a.requests);
    return result;
  }

  /// adaptive 查询：有错误且对应别名一个都没回数据才算失败（部分 authz 时照用已有字段）
  private async runAdaptive(query: string, variables: object, aliases: string[]): Promise<AdaptiveZoneNode> {
    const text = await this.client.graphql(query, variables);
    const response = JSON.parse(text) as AdaptiveResponse;
    const zones = response.data?.viewer?.zones ?? [];
    const node: AdaptiveZoneNode = zones.length > 0 ? zones[0] : {};
    if (response.errors && response.errors.length > 0) {
      const record = JSON.parse(JSON.stringify(node)) as Record<string, Object>;
      const hasAny = aliases.some((alias: string) => record[alias] !== undefined && record[alias] !== null);
      if (!hasAny) {
        throw new ApiError(response.errors[0].message);
      }
    }
    return node;
  }

  /// 数据集可用性与查询上限；字段不可用时返回 null，由调用方直接按原窗口查询
  async adaptiveSettings(zoneId: string): Promise<ZoneDatasetSettings | null> {
    const variables: ZoneTagVariables = { zoneTag: zoneId };
    const node = await this.runAdaptive(ADAPTIVE_SETTINGS_QUERY, variables, ['settings']);
    return node.settings ?? null;
  }

  /// 访问明细：国家/地区、状态码、路径、主机名各 Top 10（按请求数）
  async accessDetails(zoneId: string, win: AdaptiveWindow): Promise<AccessDetails> {
    const variables: GQLVariables = { zoneTag: zoneId, since: win.since, until: win.until };
    const node = await this.runAdaptive(ACCESS_DETAILS_QUERY, variables, ['byCountry', 'byStatus', 'byPath', 'byHost']);
    return {
      country: topItems(node.byCountry, (g: AdaptiveGroup) => g.dimensions?.clientCountryName ?? ''),
      status: topItems(node.byStatus, (g: AdaptiveGroup) => {
        const code = g.dimensions?.edgeResponseStatus;
        return code !== undefined && code !== null ? String(code) : '';
      }),
      path: topItems(node.byPath, (g: AdaptiveGroup) => g.dimensions?.clientRequestPath ?? ''),
      host: topItems(node.byHost, (g: AdaptiveGroup) => g.dimensions?.clientRequestHTTPHost ?? ''),
    };
  }

  /// 安全事件：按处置方式 / 按来源计数 + 最近 20 条
  async securityEvents(zoneId: string, win: AdaptiveWindow): Promise<SecurityEvents> {
    const variables: GQLVariables = { zoneTag: zoneId, since: win.since, until: win.until };
    const node = await this.runAdaptive(SECURITY_EVENTS_QUERY, variables, ['byAction', 'bySource', 'recent']);
    return {
      byAction: topItems(node.byAction, (g: AdaptiveGroup) => g.dimensions?.action ?? ''),
      bySource: topItems(node.bySource, (g: AdaptiveGroup) => g.dimensions?.source ?? ''),
      recent: node.recent ?? [],
    };
  }

  /// Worker 指标摘要（Worker 详情页用）
  /// Worker 指标摘要 + 按调用状态分解（对齐 iOS WorkerMetricsQueries.summary）。
  /// CPU 合计与时间序列是另外两个查询（workerCpuTotal / workerSeries）——
  /// 较新字段不可用时不能把摘要一起拖垮，故拆开发。
  async workerMetrics(accountId: string, scriptName: string,
    range: AnalyticsRange = '24h'): Promise<WorkerMetrics> {
    const win = rangeWindow(range);
    const query = `query ($accountTag: string!, $scriptName: string!, $since: Time!, $until: Time!) {
      viewer { accounts(filter: { accountTag: $accountTag }) {
        summary: workersInvocationsAdaptive(limit: 10000,
          filter: { scriptName: $scriptName, datetime_geq: $since, datetime_leq: $until }) {
          sum { requests errors subrequests }
          quantiles { cpuTimeP50 cpuTimeP99 }
        }
        byStatus: workersInvocationsAdaptive(limit: 100,
          filter: { scriptName: $scriptName, datetime_geq: $since, datetime_leq: $until }) {
          dimensions { status }
          sum { requests }
        } } } }`;
    const response = await this.runWorker(query, accountId, scriptName, win.since, win.until);
    const accounts = response.data?.viewer?.accounts ?? [];
    const node = accounts.length > 0 ? accounts[0] : null;
    const summary: GQLGroup[] = node?.summary ?? [];
    let requests = 0;
    let errors = 0;
    let subrequests = 0;
    let cpuP50 = -1;
    let cpuP99 = -1;
    for (const g of summary) {
      requests += g.sum?.requests ?? 0;
      errors += g.sum?.errors ?? 0;
      subrequests += g.sum?.subrequests ?? 0;
      // 分位数不可相加，取首个非空桶即可（limit 足够大时只有一个聚合桶）
      if (cpuP50 < 0 && g.quantiles?.cpuTimeP50 !== undefined) {
        cpuP50 = g.quantiles!.cpuTimeP50!;
        cpuP99 = g.quantiles?.cpuTimeP99 ?? -1;
      }
    }
    const breakdown: WorkerStatusItem[] = [];
    for (const g of node?.byStatus ?? []) {
      const status = g.dimensions?.status ?? '';
      if (status === '') {
        continue;
      }
      breakdown.push({ status: status, requests: g.sum?.requests ?? 0 });
    }
    breakdown.sort((a: WorkerStatusItem, b: WorkerStatusItem) => b.requests - a.requests);
    return {
      requests: requests,
      errors: errors,
      subrequests: subrequests,
      cpuP50Us: cpuP50,
      cpuP99Us: cpuP99,
      cpuTotalUs: -1,
      statusBreakdown: breakdown,
    };
  }

  /// CPU 合计耗时（微秒）。较新字段，单独一个查询，失败返回 -1 不影响摘要。
  async workerCpuTotal(accountId: string, scriptName: string,
    range: AnalyticsRange = '24h'): Promise<number> {
    const win = rangeWindow(range);
    const query = `query ($accountTag: string!, $scriptName: string!, $since: Time!, $until: Time!) {
      viewer { accounts(filter: { accountTag: $accountTag }) {
        summary: workersInvocationsAdaptive(limit: 10000,
          filter: { scriptName: $scriptName, datetime_geq: $since, datetime_leq: $until }) {
          sum { cpuTimeUs }
        } } } }`;
    const response = await this.runWorker(query, accountId, scriptName, win.since, win.until);
    const accounts = response.data?.viewer?.accounts ?? [];
    const summary: GQLGroup[] = (accounts.length > 0 ? accounts[0].summary : []) ?? [];
    let total = -1;
    for (const g of summary) {
      const value = g.sum?.cpuTimeUs;
      if (value !== undefined) {
        total = (total < 0 ? 0 : total) + value;
      }
    }
    return total;
  }

  /// 请求 / 错误时间序列：24h 按小时（datetimeHour），7d·30d 按天（date）
  async workerSeries(accountId: string, scriptName: string,
    range: AnalyticsRange = '24h'): Promise<WorkerSeriesPoint[]> {
    const win = rangeWindow(range);
    const dimension = win.hourly ? 'datetimeHour' : 'date';
    const query = `query ($accountTag: string!, $scriptName: string!, $since: Time!, $until: Time!) {
      viewer { accounts(filter: { accountTag: $accountTag }) {
        series: workersInvocationsAdaptive(limit: 1000, orderBy: [${dimension}_ASC],
          filter: { scriptName: $scriptName, datetime_geq: $since, datetime_leq: $until }) {
          dimensions { ${dimension} }
          sum { requests errors }
        } } } }`;
    const response = await this.runWorker(query, accountId, scriptName, win.since, win.until);
    const accounts = response.data?.viewer?.accounts ?? [];
    const groups: GQLGroup[] = (accounts.length > 0 ? accounts[0].series : []) ?? [];
    const points: WorkerSeriesPoint[] = [];
    for (const g of groups) {
      const raw = win.hourly ? (g.dimensions?.datetimeHour ?? '') : (g.dimensions?.date ?? '');
      points.push({
        label: raw,
        requests: g.sum?.requests ?? 0,
        errors: g.sum?.errors ?? 0,
      });
    }
    return points;
  }

  /// Worker 三个查询共用的发送 + 错误检查
  private async runWorker(query: string, accountId: string, scriptName: string,
    since: string, until: string): Promise<GQLResponse> {
    interface WorkerVariables {
      accountTag: string;
      scriptName: string;
      since: string;
      until: string;
    }
    const variables: WorkerVariables = {
      accountTag: accountId,
      scriptName: scriptName,
      since: since,
      until: until,
    };
    const text = await this.client.graphql(query, variables);
    const response = JSON.parse(text) as GQLResponse;
    if (response.errors && response.errors.length > 0) {
      throw new ApiError(response.errors[0].message);
    }
    return response;
  }
}
