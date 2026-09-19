// 账号用量：账号级 GraphQL 各产品数据集 → 归一化聚合（对齐 iOS Services/AnalyticsService 用量部分）。
// Workers 是账户级 analytics 代表：命中 authz = 整账号无账户级数据权限（CF 的 authz 账号级、
// 各产品数据集同进同退）→ 抛 AccountAnalyticsUnauthorizedError，调用方降级停发其余查询。
// R2/D1/KV 各自独立 best-effort 合并：账号未启用某产品 / 无对应数据集权限时该产品静默省略。
import {
  AccountUsage,
  AccountUsageResponse,
  D1Usage,
  D1UsageResponse,
  D1UsageGroup,
  isAuthzError,
  KVUsage,
  KVUsageResponse,
  KVOpsGroup,
  KVStorageGroup,
  R2OperationClass,
  R2OpsGroup,
  R2StorageGroup,
  R2UsageResponse,
  UsageGQLError,
  WorkersCpuGroup,
  WorkersCpuResponse,
  WorkersUsageGroup,
} from '../models/UsageModels';
import { AppPrefs } from '../core/system/AppPrefs';
import { apiClient, CFApiClient } from '../core/network/CFApiClient';

/// 账户级数据集未授权（免费账号常态）——与普通失败区分，让 UI 走中性「不可用」卡片而非重试。
export class AccountAnalyticsUnauthorizedError extends Error {
  constructor(message: string = 'account-level analytics not authorized') {
    super(message);
  }
}

interface UsageVariables {
  accountTag: string;
  monthStart: string;
  todayStart: string;
  now: string;
}

interface DateVariables {
  accountTag: string;
  periodStart: string;
  todayStart: string;
  until: string;
}

interface TwoWindow {
  month: number;
  today: number;
}

interface R2Totals {
  classA: number;
  classB: number;
  storageBytes: number;
  objectCount: number;
}

interface ReadWrite {
  read: number;
  written: number;
}

interface ReadsWrites {
  reads: number;
  writes: number;
}

function isoSeconds(date: Date): string {
  return `${date.toISOString().substring(0, 19)}Z`;
}

function isoDate(date: Date): string {
  return date.toISOString().substring(0, 10);
}

// UTC 当月 1 号 00:00
function monthStartUTC(now: Date): Date {
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1, 0, 0, 0));
}

// UTC 当日 00:00
function todayStartUTC(now: Date): Date {
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), 0, 0, 0));
}

/// 本机时区当日 00:00（设置页「今日按=本地时间」时用它做统计窗口起点）。
/// 只改 App 的统计窗口，不改变 Cloudflare 免费额度按 UTC 重置这一事实。
function todayStartLocal(now: Date): Date {
  return new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0);
}

// MARK: - 查询串（对齐 iOS AccountUsageModels 各 query 文本）

// Workers 调用（月/今日两窗口）——账户级 analytics 代表查询。
const WORKERS_QUERY = `query ($accountTag: string!, $monthStart: Time!, $todayStart: Time!, $now: Time!) {
  viewer { accounts(filter: { accountTag: $accountTag }) {
    month: workersInvocationsAdaptive(limit: 10000, filter: { datetime_geq: $monthStart, datetime_leq: $now }) {
      sum { requests errors subrequests }
    }
    today: workersInvocationsAdaptive(limit: 10000, filter: { datetime_geq: $todayStart, datetime_leq: $now }) {
      sum { requests errors subrequests }
    }
  } } }`;

// Workers CPU 总耗时（较新 schema 字段，独立查询，不支持时回退）
const WORKERS_CPU_QUERY = `query ($accountTag: string!, $monthStart: Time!, $todayStart: Time!, $now: Time!) {
  viewer { accounts(filter: { accountTag: $accountTag }) {
    month: workersInvocationsAdaptive(limit: 10000, filter: { datetime_geq: $monthStart, datetime_leq: $now }) {
      sum { cpuTimeUs }
    }
    today: workersInvocationsAdaptive(limit: 10000, filter: { datetime_geq: $todayStart, datetime_leq: $now }) {
      sum { cpuTimeUs }
    }
  } } }`;

// R2 操作分类（月）+ 当前存储
const R2_QUERY = `query ($accountTag: string!, $monthStart: Time!, $todayStart: Time!, $now: Time!) {
  viewer { accounts(filter: { accountTag: $accountTag }) {
    r2Ops: r2OperationsAdaptiveGroups(limit: 10000, filter: { datetime_geq: $monthStart, datetime_leq: $now }) {
      dimensions { actionType bucketName }
      sum { requests }
    }
    r2Storage: r2StorageAdaptiveGroups(limit: 1000, filter: { datetime_geq: $todayStart, datetime_leq: $now }) {
      dimensions { bucketName }
      max { payloadSize metadataSize objectCount }
    }
  } } }`;

// D1 行读写（Date 标量过滤，周期 + 今日）
const D1_QUERY = `query ($accountTag: string!, $periodStart: Date!, $todayStart: Date!, $until: Date!) {
  viewer { accounts(filter: { accountTag: $accountTag }) {
    period: d1AnalyticsAdaptiveGroups(limit: 10000, filter: { date_geq: $periodStart, date_leq: $until }) {
      sum { rowsRead rowsWritten readQueries writeQueries }
    }
    today: d1AnalyticsAdaptiveGroups(limit: 10000, filter: { date_geq: $todayStart, date_leq: $until }) {
      sum { rowsRead rowsWritten readQueries writeQueries }
    }
  } } }`;

// KV 操作（按 actionType，Date 标量，周期 + 今日）
const KV_OPS_QUERY = `query ($accountTag: string!, $periodStart: Date!, $todayStart: Date!, $until: Date!) {
  viewer { accounts(filter: { accountTag: $accountTag }) {
    period: kvOperationsAdaptiveGroups(limit: 10000, filter: { date_geq: $periodStart, date_leq: $until }) {
      dimensions { actionType }
      sum { requests }
    }
    today: kvOperationsAdaptiveGroups(limit: 10000, filter: { date_geq: $todayStart, date_leq: $until }) {
      dimensions { actionType }
      sum { requests }
    }
  } } }`;

// KV 存储（各 namespace 当日 max byteCount）
const KV_STORAGE_QUERY = `query ($accountTag: string!, $periodStart: Date!, $todayStart: Date!, $until: Date!) {
  viewer { accounts(filter: { accountTag: $accountTag }) {
    storage: kvStorageAdaptiveGroups(limit: 1000, filter: { date_geq: $todayStart, date_leq: $until }) {
      dimensions { namespaceId }
      max { byteCount keyCount }
    }
  } } }`;

export class UsageService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  /// 「今日」窗口起点：'local' 用本机零点，其余（默认 'utc'）用 UTC 零点。
  /// D1 / KV 的接口按 UTC 天聚合，那两个查询始终走 UTC（见 dateVariables）。
  private todayStart(now: Date, boundary: string): Date {
    return boundary === 'local' ? todayStartLocal(now) : todayStartUTC(now);
  }

  private timeVariables(accountId: string, now: Date, boundary: string): UsageVariables {
    return {
      accountTag: accountId,
      monthStart: isoSeconds(monthStartUTC(now)),
      todayStart: isoSeconds(this.todayStart(now, boundary)),
      now: isoSeconds(now),
    };
  }

  private dateVariables(accountId: string, now: Date): DateVariables {
    return {
      accountTag: accountId,
      periodStart: isoDate(monthStartUTC(now)),
      todayStart: isoDate(todayStartUTC(now)),
      until: isoDate(now),
    };
  }

  /// 账号用量：先跑 Workers（代表查询）——authz 抛 AccountAnalyticsUnauthorizedError；
  /// 成功后 best-effort 合并 R2/D1/KV，各产品单独失败静默省略。
  async loadAccountUsage(accountId: string): Promise<AccountUsage> {
    const now = new Date();
    // 日界口径偏好（设置页）：只影响按时间戳过滤的 Workers / R2 窗口
    let boundary = 'utc';
    try {
      boundary = await AppPrefs.getDayBoundary();
    } catch (e) {
      // 读偏好失败按 UTC 处理
    }
    const timeVars = this.timeVariables(accountId, now, boundary);
    const dateVars = this.dateVariables(accountId, now);

    // Workers 主查询——authz 会往上抛，调用方据此整体降级。
    const workers = await this.loadWorkers(timeVars);

    const usage: AccountUsage = {
      workersRequestsToday: workers.today,
      workersRequestsMonth: workers.month,
      r2ClassAMonth: 0,
      r2ClassBMonth: 0,
      r2StorageBytes: 0,
      r2ObjectCount: 0,
    };

    // CPU 总耗时（较新字段，不支持则保持省略）
    const cpu: TwoWindow | undefined = await this.loadCpu(timeVars);
    if (cpu !== undefined) {
      usage.cpuTimeMonthUs = cpu.month;
      usage.cpuTimeTodayUs = cpu.today;
    }

    // R2 操作分类 + 存储
    const r2: R2Totals | undefined = await this.loadR2(timeVars);
    if (r2 !== undefined) {
      usage.r2ClassAMonth = r2.classA;
      usage.r2ClassBMonth = r2.classB;
      usage.r2StorageBytes = r2.storageBytes;
      usage.r2ObjectCount = r2.objectCount;
    }

    // D1 行读写
    const d1 = await this.loadD1(dateVars);
    if (d1 !== undefined) {
      usage.d1Usage = d1;
    }

    // KV 操作 + 存储
    const kv = await this.loadKV(dateVars);
    if (kv !== undefined) {
      usage.kvUsage = kv;
    }
    const kvBytes = await this.loadKVStorage(dateVars);
    if (kvBytes !== undefined) {
      usage.kvStorageBytes = kvBytes;
    }

    return usage;
  }

  /// 解析 GraphQL 错误：authz → 抛 AccountAnalyticsUnauthorizedError；其余 → 普通 Error。
  private throwForErrors(errors: UsageGQLError[]): never {
    for (const e of errors) {
      if (isAuthzError(e)) {
        throw new AccountAnalyticsUnauthorizedError();
      }
    }
    throw new Error(errors[0].message);
  }

  private async loadWorkers(vars: UsageVariables): Promise<TwoWindow> {
    const text = await this.client.graphql(WORKERS_QUERY, vars);
    const response = JSON.parse(text) as AccountUsageResponse;
    if (response.errors && response.errors.length > 0) {
      this.throwForErrors(response.errors);
    }
    const accounts = response.data?.viewer?.accounts ?? [];
    if (accounts.length === 0) {
      return { month: 0, today: 0 };
    }
    const node = accounts[0];
    const sumReq = (groups?: WorkersUsageGroup[]): number => {
      let total = 0;
      for (const g of groups ?? []) {
        total += g.sum?.requests ?? 0;
      }
      return total;
    };
    return { month: sumReq(node.month), today: sumReq(node.today) };
  }

  private async loadCpu(vars: UsageVariables): Promise<TwoWindow | undefined> {
    try {
      const text = await this.client.graphql(WORKERS_CPU_QUERY, vars);
      const response = JSON.parse(text) as WorkersCpuResponse;
      if (response.errors && response.errors.length > 0) {
        return undefined;
      }
      const accounts = response.data?.viewer?.accounts ?? [];
      if (accounts.length === 0) {
        return undefined;
      }
      const node = accounts[0];
      const sumCpu = (groups?: WorkersCpuGroup[]): number => {
        let total = 0;
        for (const g of groups ?? []) {
          total += g.sum?.cpuTimeUs ?? 0;
        }
        return total;
      };
      return { month: sumCpu(node.month), today: sumCpu(node.today) };
    } catch (e) {
      return undefined;
    }
  }

  private async loadR2(vars: UsageVariables): Promise<R2Totals | undefined> {
    try {
      const text = await this.client.graphql(R2_QUERY, vars);
      const response = JSON.parse(text) as R2UsageResponse;
      if (response.errors && response.errors.length > 0) {
        return undefined;
      }
      const accounts = response.data?.viewer?.accounts ?? [];
      if (accounts.length === 0) {
        return undefined;
      }
      const node = accounts[0];
      let classA = 0;
      let classB = 0;
      for (const g of node.r2Ops ?? []) {
        const action = g.dimensions?.actionType ?? '';
        const count = g.sum?.requests ?? 0;
        if (R2OperationClass.classA.includes(action)) {
          classA += count;
        } else if (R2OperationClass.classB.includes(action)) {
          classB += count;
        }
      }
      let storageBytes = 0;
      let objectCount = 0;
      for (const g of node.r2Storage ?? []) {
        storageBytes += (g.max?.payloadSize ?? 0) + (g.max?.metadataSize ?? 0);
        objectCount += g.max?.objectCount ?? 0;
      }
      return { classA: classA, classB: classB, storageBytes: storageBytes, objectCount: objectCount };
    } catch (e) {
      return undefined;
    }
  }

  private async loadD1(vars: DateVariables): Promise<D1Usage | undefined> {
    try {
      const text = await this.client.graphql(D1_QUERY, vars);
      const response = JSON.parse(text) as D1UsageResponse;
      if (response.errors && response.errors.length > 0) {
        return undefined;
      }
      const accounts = response.data?.viewer?.accounts ?? [];
      if (accounts.length === 0) {
        return undefined;
      }
      const node = accounts[0];
      const totals = (groups?: D1UsageGroup[]): ReadWrite => {
        let read = 0;
        let written = 0;
        for (const g of groups ?? []) {
          read += g.sum?.rowsRead ?? 0;
          written += g.sum?.rowsWritten ?? 0;
        }
        return { read: read, written: written };
      };
      const period: ReadWrite = totals(node.period);
      const today: ReadWrite = totals(node.today);
      return {
        rowsReadToday: today.read,
        rowsWrittenToday: today.written,
        rowsReadPeriod: period.read,
        rowsWrittenPeriod: period.written,
      };
    } catch (e) {
      return undefined;
    }
  }

  private async loadKV(vars: DateVariables): Promise<KVUsage | undefined> {
    try {
      const text = await this.client.graphql(KV_OPS_QUERY, vars);
      const response = JSON.parse(text) as KVUsageResponse;
      if (response.errors && response.errors.length > 0) {
        return undefined;
      }
      const accounts = response.data?.viewer?.accounts ?? [];
      if (accounts.length === 0) {
        return undefined;
      }
      const node = accounts[0];
      const totals = (groups?: KVOpsGroup[]): ReadsWrites => {
        let reads = 0;
        let writes = 0;
        for (const g of groups ?? []) {
          const count = g.sum?.requests ?? 0;
          const action = g.dimensions?.actionType ?? '';
          if (action === 'read') {
            reads += count;
          } else if (action === 'write') {
            writes += count;
          }
        }
        return { reads: reads, writes: writes };
      };
      const period: ReadsWrites = totals(node.period);
      const today: ReadsWrites = totals(node.today);
      return {
        readsToday: today.reads,
        writesToday: today.writes,
        readsPeriod: period.reads,
        writesPeriod: period.writes,
      };
    } catch (e) {
      return undefined;
    }
  }

  private async loadKVStorage(vars: DateVariables): Promise<number | undefined> {
    try {
      const text = await this.client.graphql(KV_STORAGE_QUERY, vars);
      const response = JSON.parse(text) as KVUsageResponse;
      if (response.errors && response.errors.length > 0) {
        return undefined;
      }
      const accounts = response.data?.viewer?.accounts ?? [];
      if (accounts.length === 0) {
        return undefined;
      }
      let total = 0;
      for (const g of accounts[0].storage ?? []) {
        total += g.max?.byteCount ?? 0;
      }
      return total;
    } catch (e) {
      return undefined;
    }
  }
}
