// R2 SQL：对 R2 Data Catalog（Iceberg）表跑只读分析查询（对齐 iOS R2SQLService）。
//
// 查询端点在独立主机 api.sql.cloudflarestorage.com（**不是** client/v4）：
// POST /api/v1/accounts/{account_id}/r2-sql/query/{bucket_name}  body {"query": "..."}
// 鉴权是 Cloudflare Bearer token（需 r2-catalog-sql.read + r2-catalog.read + workers-r2.read）。
// 该主机对 OAuth token 的接受度官方未明说，401/403 时由页面给出定向指引。
//
// 响应格式官方未列 schema，按宽容策略解析：在常见容器键（result/data/rows…）下
// 找「对象数组」当作行集，列名取全部行键的并集（字母序，稳定可预期）。
// **计费提醒**：按扫描量计费（$0.0025/GB，10GB/月免费，单次查询最少计 10MB），UI 需带提示。
import { CFApiClient, apiClient } from '../core/network/CFApiClient';

const R2_SQL_HOST = 'https://api.sql.cloudflarestorage.com';

/// 展平后的查询结果（值统一字符串化用于展示）
export interface R2SQLResult {
  columns: string[];
  rows: Record<string, string>[];
}

interface QueryBody {
  query: string;
}

/// 宽容解析用的中间形态（各容器键都可能承载行集）
interface LooseEnvelope {
  success?: boolean;
  errors?: LooseError[];
  result?: object;
  data?: object;
  rows?: object;
  results?: object;
  records?: object;
}

interface LooseError {
  code?: number;
  message?: string;
}

export class R2SQLService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  /// 执行一条 R2 SQL 查询，返回展平后的行集
  async query(accountId: string, bucketName: string, sql: string): Promise<R2SQLResult> {
    const body: QueryBody = { query: sql };
    const text = await this.client.postExternalJson(
      `${R2_SQL_HOST}/api/v1/accounts/${accountId}/r2-sql/query/${bucketName}`, body);
    return R2SQLService.parse(text);
  }

  /// 从响应 JSON 里挖出行集：顶层或 result/data/rows/results/records 容器下的第一个「对象数组」
  static parse(text: string): R2SQLResult {
    const trimmed = text.trim();
    if (trimmed === '') {
      return { columns: [], rows: [] };
    }
    const parsed = JSON.parse(trimmed) as object;

    // 顶层直接就是数组
    if (Array.isArray(parsed)) {
      return R2SQLService.flatten(parsed as object[]);
    }

    const envelope = parsed as LooseEnvelope;
    // CF 信封形态：success=false 时抛出首个错误
    if (envelope.success === false) {
      const first = envelope.errors?.[0];
      throw new Error(first?.message ?? '查询失败');
    }

    const candidates: (object | undefined)[] = [
      envelope.result, envelope.data, envelope.rows, envelope.results, envelope.records,
    ];
    // result 再套一层的情形（{result:{rows:[…]}}）
    const inner = envelope.result as LooseEnvelope | undefined;
    if (inner !== undefined && !Array.isArray(inner)) {
      candidates.push(inner.rows, inner.data, inner.results, inner.records);
    }
    for (const candidate of candidates) {
      if (candidate !== undefined && Array.isArray(candidate)) {
        return R2SQLService.flatten(candidate as object[]);
      }
    }
    // 无行集但也没报错：当作执行成功、零行
    return { columns: [], rows: [] };
  }

  /// 对象数组 → 列名（全部行键并集，字母序）+ 字符串化行；缺失键补空
  private static flatten(rows: object[]): R2SQLResult {
    if (rows.length === 0) {
      return { columns: [], rows: [] };
    }
    const columns: string[] = [];
    for (const row of rows) {
      for (const key of Object.keys(row)) {
        if (!columns.includes(key)) {
          columns.push(key);
        }
      }
    }
    columns.sort();
    const out: Record<string, string>[] = [];
    for (const row of rows) {
      const record = row as Record<string, Object>;
      const flat: Record<string, string> = {};
      for (const col of columns) {
        flat[col] = R2SQLService.display(record[col]);
      }
      out.push(flat);
    }
    return { columns: columns, rows: out };
  }

  /// 值 → 展示串：null 显示 NULL，标量直出，嵌套对象/数组压成紧凑 JSON
  private static display(value: Object | undefined): string {
    if (value === undefined || value === null) {
      return 'NULL';
    }
    if (typeof value === 'string') {
      return value as string;
    }
    if (typeof value === 'number' || typeof value === 'boolean') {
      return `${value}`;
    }
    try {
      return JSON.stringify(value);
    } catch (e) {
      return `${value}`;
    }
  }
}
