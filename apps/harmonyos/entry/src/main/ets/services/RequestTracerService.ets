// Cloudflare Trace —— 模拟一条请求打过 Cloudflare，看它走了哪些规则、被谁拦的。
// POST /accounts/{account_id}/request-tracer/trace（request-tracer.read）
// 全套餐可用，但要求 Administrator / Super Administrator 角色。
import { CFApiClient, apiClient } from '../core/network/CFApiClient';

/// 单个求值步骤。**递归结构**：ruleset 步骤的 trace 里装着它的各条 rule。
export interface TraceStep {
  type?: string;
  step_name?: string;
  action?: string;
  description?: string;
  expression?: string;
  kind?: string;
  name?: string;
  matched?: boolean;      // 该步骤是否真的影响了请求
  trace?: TraceStep[];
}

export interface TraceResult {
  status_code?: number;
  trace?: TraceStep[];
}

interface TraceBody {
  method: string;
  url: string;
  protocol: string;
}

/// 摊平后的行，depth 用于缩进
export interface FlatTraceStep {
  step: TraceStep;
  depth: number;
}

export function flattenTrace(steps: TraceStep[], depth: number = 0): FlatTraceStep[] {
  const out: FlatTraceStep[] = [];
  steps.forEach((s: TraceStep) => {
    out.push({ step: s, depth: depth });
    if (s.trace !== undefined && s.trace.length > 0) {
      flattenTrace(s.trace, depth + 1).forEach((x: FlatTraceStep) => out.push(x));
    }
  });
  return out;
}

/// 展示名：ruleset 用 name，rule 用 description，都没有才退回 step_name
export function stepTitle(s: TraceStep): string {
  if ((s.name ?? '') !== '') {
    return s.name as string;
  }
  if ((s.description ?? '') !== '') {
    return s.description as string;
  }
  return s.step_name ?? '未命名步骤';
}

export class RequestTracerService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  trace(accountId: string, method: string, url: string): Promise<TraceResult> {
    const body: TraceBody = { method: method, url: url, protocol: 'HTTP/1.1' };
    return this.client.postObject<TraceResult>(`/accounts/${accountId}/request-tracer/trace`, body);
  }
}
