// Workers 问题（Workers Observability Issues，2026-09-30 起公开测试）。
// Cloudflare 自动把未捕获异常、5xx 响应与错误日志归类成「问题」。
//   - GET   /accounts/{id}/workers/observability/issues?status=&service=&page=&perPage=&orderBy=&order=
//           result[] + result_info { page, per_page, count, total_count, total_pages }
//           注意列表的分页参数是 camelCase 的 perPage（≤100），occurrences 却是 per_page
//   - GET   …/issues/summary?service= → result { activeIssues, activeOccurrences, resolvedIssues, lastIssue }
//   - GET   …/issues/{issueId}        → result.issue
//   - PATCH …/issues/{issueId}        体 { status }（需 workers-observability.write）
//   - GET   …/issues/{issueId}/occurrences?per_page=&cursor= → result[]，游标在 result_info.cursors.after
// 读权限 workers-observability.read。时间戳都是数字，按毫秒处理；小于 1e12 的按秒换算。
// 字段类型与文档常有出入（测试期接口），时间戳 / 次数一律按 Object 收再容错取值。
import { CFApiClient, apiClient, ApiError } from '../core/network/CFApiClient';
import { CFError } from '../models/Models';

/// 问题状态：active / resolved / ignored（未知值原样保留，界面兜底显示原文）
export interface WorkerIssue {
  id: string;
  title?: string;
  service?: string;
  status?: string;
  count?: Object;
  firstObserved?: Object;
  lastObserved?: Object;
  statusUpdated?: Object;
  created?: Object;
  updated?: Object;
  type?: string;
  fingerprint?: string;
}

export interface WorkerIssueSummary {
  activeIssues?: Object;
  activeOccurrences?: Object;
  resolvedIssues?: Object;
  lastIssue?: Object | null;
}

export interface WorkerIssuePage {
  issues: WorkerIssue[];
  page: number;
  totalPages: number;
}

interface IssueDetailResult {
  issue?: WorkerIssue;
}

interface IssueStatusBody {
  status: string;
}

export interface IssueOccurrenceError {
  name?: string;
  message?: string;
  stack?: string;
  handled?: boolean;
}

export interface IssueOccurrenceInvocation {
  method?: string;
  path?: string;
  url?: string;
  statusCode?: Object;
  rayId?: string;
  cron?: string;
  queue?: string;
  type?: string;
}

export interface IssueOccurrenceTrail {
  level?: string;
  message?: string;
  timestamp?: Object;
}

export interface IssueOccurrence {
  id?: string;
  timestamp?: Object;
  error?: IssueOccurrenceError;
  invocation?: IssueOccurrenceInvocation;
  trail?: IssueOccurrenceTrail[];
}

export interface IssueOccurrencePage {
  occurrences: IssueOccurrence[];
  cursor: string;
}

interface OccurrenceCursors {
  after?: string;
}

interface OccurrenceResultInfo {
  cursors?: OccurrenceCursors;
}

interface OccurrencesEnvelope {
  success: boolean;
  result?: IssueOccurrence[];
  errors?: CFError[];
  result_info?: OccurrenceResultInfo;
}

/// 数字或数字字符串 → number；取不到返回 fallback
export function issueNumber(v: Object | null | undefined, fallback: number = 0): number {
  if (typeof v === 'number') {
    return v as number;
  }
  if (typeof v === 'string') {
    const n = Number(v as string);
    return isNaN(n) ? fallback : n;
  }
  return fallback;
}

/// 时间戳 → epoch 毫秒：数字按毫秒，小于 1e12 视为秒；ISO 字符串也兜底解析。0 = 无
export function issueEpochMs(v: Object | null | undefined): number {
  if (typeof v === 'string') {
    const text = v as string;
    const n = Number(text);
    if (!isNaN(n) && text.trim() !== '') {
      return n < 1e12 ? n * 1000 : n;
    }
    const parsed = new Date(text).getTime();
    return isNaN(parsed) ? 0 : parsed;
  }
  const n = issueNumber(v, 0);
  if (n <= 0) {
    return 0;
  }
  return n < 1e12 ? n * 1000 : n;
}

export class WorkerIssuesService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  private base(accountId: string): string {
    return `/accounts/${accountId}/workers/observability/issues`;
  }

  /// 按状态分页列问题，最近发生的在前。service 为空 = 账号下全部 Worker
  async list(accountId: string, status: string, service: string, page: number,
    perPage: number = 50): Promise<WorkerIssuePage> {
    const query: Record<string, string> = {
      'status': status,
      'page': String(page),
      'perPage': String(perPage),
      'orderBy': 'lastObserved',
      'order': 'desc',
    };
    if (service !== '') {
      query['service'] = service;
    }
    const envelope = await this.client.getListEnvelope<WorkerIssue>(this.base(accountId), query);
    return {
      issues: envelope.result ?? [],
      page: envelope.result_info?.page ?? page,
      totalPages: envelope.result_info?.total_pages ?? 1,
    };
  }

  /// 汇总（活跃问题数 / 活跃发生次数 / 已解决数）；service 为空 = 全账号
  summary(accountId: string, service: string): Promise<WorkerIssueSummary> {
    const query: Record<string, string> = {};
    if (service !== '') {
      query['service'] = service;
    }
    return this.client.getObject<WorkerIssueSummary>(`${this.base(accountId)}/summary`, query);
  }

  async detail(accountId: string, issueId: string): Promise<WorkerIssue> {
    const result = await this.client.getObject<IssueDetailResult>(
      `${this.base(accountId)}/${encodeURIComponent(issueId)}`);
    if (result.issue === undefined || result.issue === null) {
      throw new ApiError('问题不存在或已被删除');
    }
    return result.issue;
  }

  /// 改状态：resolved / ignored / active（重新打开）。回包形态不定，调用方随后重新拉详情
  async setStatus(accountId: string, issueId: string, status: string): Promise<void> {
    const body: IssueStatusBody = { status: status };
    await this.client.patchVoid(`${this.base(accountId)}/${encodeURIComponent(issueId)}`, body);
  }

  /// 最近发生（游标分页）。cursor 为空取首页
  async occurrences(accountId: string, issueId: string, cursor: string,
    perPage: number = 20): Promise<IssueOccurrencePage> {
    const query: Record<string, string> = { 'per_page': String(perPage) };
    if (cursor !== '') {
      query['cursor'] = cursor;
    }
    const raw = await this.client.getRaw(
      `${this.base(accountId)}/${encodeURIComponent(issueId)}/occurrences`, query);
    const envelope = JSON.parse(raw) as OccurrencesEnvelope;
    if (!envelope.success) {
      const first = envelope.errors && envelope.errors.length > 0 ? envelope.errors[0] : undefined;
      throw new ApiError(first?.message ?? '加载失败', first?.code ?? 0, first?.documentation_url ?? '');
    }
    return {
      occurrences: envelope.result ?? [],
      cursor: envelope.result_info?.cursors?.after ?? '',
    };
  }
}
