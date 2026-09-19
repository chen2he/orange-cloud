// Workers Logs（Observability）历史日志查询（对齐 iOS WorkerLogsService）。
// 端点 POST /accounts/{id}/workers/observability/telemetry/query（scope: workers-observability.read）。
// 与实时日志（tail）互补：tail 只播放连接期间的调用，这里查已落库、可回溯的事件。
//   - view=events 取逐条日志；按脚本名过滤走 $metadata.service eq，级别走 $metadata.level
//   - 全文搜索是 parameters.needle；datasets 留空 = 查全部（不猜数据集名）
//   - 分页：offset 传上一页最后一条的 $metadata.id，配 offsetDirection=next
//   - dry 保持 false（其语义是「执行但不持久化」，官方没承诺 dry 下仍回结果）
//   - 前提：Worker 需开启 observability，否则查出来就是空
import { CFApiClient, apiClient } from '../core/network/CFApiClient';

interface QueryFilter {
  key: string;
  operation: string;
  type: string;
  value: string;
}

interface QueryNeedle {
  value: string;
  matchCase: boolean;
}

interface QueryParameters {
  datasets: string[];
  filters: QueryFilter[];
  needle?: QueryNeedle;
}

interface QueryTimeframe {
  from: number;   // Unix 毫秒
  to: number;
}

interface QueryBody {
  queryId: string;
  timeframe: QueryTimeframe;
  view: string;
  limit: number;
  parameters: QueryParameters;
  dry: boolean;
  offset?: string;
  offsetDirection?: string;
}

/// 原始事件：字段类型与文档常有出入，一律按 Object 收下再逐字段容错取值
interface RawEvent {
  timestamp?: Object;
  $metadata?: Record<string, Object>;
  $workers?: Record<string, Object>;
}

interface RawEventsBlock {
  count?: Object;
  events?: RawEvent[];
}

interface RawQueryResult {
  events?: RawEventsBlock;
}

/// 归一化后的一条日志
export interface WorkerLogEvent {
  id: string;
  timestampMs: number;
  level: string;          // log / debug / info / warn / error / event
  text: string;           // 列表主文：message → error → trigger → url
  message: string;
  error: string;
  trigger: string;
  url: string;
  statusCode: number;     // 0 = 无
  durationMs: number;     // -1 = 无
  requestId: string;
  rayId: string;
  outcome: string;
  eventType: string;
}

export interface WorkerLogsPage {
  events: WorkerLogEvent[];
  total: number;          // -1 = 服务端未给
}

function str(v: Object | undefined): string {
  if (typeof v === 'string') {
    return v as string;
  }
  if (typeof v === 'number') {
    return String(v as number);
  }
  return '';
}

function num(v: Object | undefined, fallback: number): number {
  if (typeof v === 'number') {
    return v as number;
  }
  if (typeof v === 'string') {
    const n = Number(v as string);
    return isNaN(n) ? fallback : n;
  }
  return fallback;
}

let fallbackSeq = 0;

function normalize(raw: RawEvent): WorkerLogEvent {
  const m: Record<string, Object> = raw.$metadata ?? {};
  const w: Record<string, Object> = raw.$workers ?? {};
  const message = str(m['message']);
  const error = str(m['error']);
  const trigger = str(m['trigger']);
  const url = str(m['url']);
  let level = str(m['level']).toLowerCase();
  if (level === '') {
    level = error !== '' ? 'error' : 'event';
  }
  let text = message;
  if (text === '') {
    text = error !== '' ? error : (trigger !== '' ? trigger : (url !== '' ? url : '（无正文）'));
  }
  let id = str(m['id']);
  if (id === '') {
    fallbackSeq += 1;
    id = `local-${Date.now()}-${fallbackSeq}`;
  }
  return {
    id: id,
    timestampMs: num(raw.timestamp, num(m['startTime'], 0)),
    level: level,
    text: text,
    message: message,
    error: error,
    trigger: trigger,
    url: url,
    statusCode: num(m['statusCode'], 0),
    durationMs: num(m['duration'], -1),
    requestId: str(m['requestId']),
    rayId: str(m['rayId']),
    outcome: str(w['outcome']),
    eventType: str(w['eventType']),
  };
}

export class WorkerLogsService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  /// 查一页历史日志。cursor 为空取首页，非空续接更早的一页。
  async events(accountId: string, scriptName: string, sinceMs: number, untilMs: number,
    level: string, search: string, cursor: string, limit: number = 100): Promise<WorkerLogsPage> {
    const filters: QueryFilter[] = [
      { key: '$metadata.service', operation: 'eq', type: 'string', value: scriptName },
    ];
    if (level !== '' && level !== 'all') {
      filters.push({ key: '$metadata.level', operation: 'eq', type: 'string', value: level });
    }
    const parameters: QueryParameters = { datasets: [], filters: filters };
    const needle = search.trim();
    if (needle !== '') {
      parameters.needle = { value: needle, matchCase: false };
    }
    const body: QueryBody = {
      queryId: 'orange-cloud-worker-logs',
      timeframe: { from: Math.floor(sinceMs), to: Math.floor(untilMs) },
      view: 'events',
      limit: limit,
      parameters: parameters,
      dry: false,
    };
    if (cursor !== '') {
      body.offset = cursor;
      body.offsetDirection = 'next';
    }
    const result = await this.client.postObject<RawQueryResult>(
      `/accounts/${accountId}/workers/observability/telemetry/query`, body);
    const raws = result.events?.events ?? [];
    return {
      events: raws.map((r: RawEvent): WorkerLogEvent => normalize(r)),
      total: num(result.events?.count, -1),
    };
  }
}
