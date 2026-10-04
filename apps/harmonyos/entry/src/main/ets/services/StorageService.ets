// R2 / D1 / KV Service（对齐 Android StorageRepository）。
// KV value / R2 object 正文是裸字节走 getRaw；KV 写值是 multipart（value + metadata 两 part）。
// R2 区域限制桶（EU / US / FedRAMP）：桶级的每个请求（桶本身、objects、cors、domains/*）都要带
// cf-r2-jurisdiction 头，所以桶级方法一律显式收 jurisdiction（'' / default = 不带头）。
import {
  D1Database,
  D1QueryResult,
  KVKey,
  KVNamespace,
  R2Bucket,
  R2BucketList,
  R2CorsPolicy,
  R2CustomDomain,
  R2CustomDomainCreate,
  R2CustomDomainList,
  R2ListResultInfo,
  R2ManagedDomain,
  R2ManagedDomainUpdate,
  R2Object,
  R2ObjectPage,
  mimeOf,
  r2JurisdictionHeader,
} from '../models/StorageModels';
import { CFApiClient, MultipartPart, apiClient, ApiError } from '../core/network/CFApiClient';
import { http } from '@kit.NetworkKit';
import { authManager } from '../core/auth/AuthManager';

const R2_BASE_URL = 'https://api.cloudflare.com/client/v4';
const R2_JURISDICTION_HEADER = 'cf-r2-jurisdiction';
/// 无头列表是否包含区域桶官方没说清，额外按这两个区域各列一次再合并（FedRAMP 仅政府账号，不探测）
const R2_PROBE_JURISDICTIONS: string[] = ['eu', 'us'];

export interface CursorPage<T> {
  items: T[];
  cursor: string;
}

interface KVKeysResultInfo {
  cursor?: string;
}

/// KV keys 端点的 result_info 带游标（区别于普通分页）
interface KVKeysEnvelope {
  success: boolean;
  result?: KVKey[];
  result_info?: KVKeysResultInfo;
}

interface D1QueryBody {
  sql: string;
  params?: string[];
}

/// D1 免费套餐每日行数上限（2026-09-01 起 REST query 也强制）命中时的说明
const D1_DAILY_LIMIT_HINT =
  '已超过 D1 免费套餐的每日读取/写入行数上限，额度在 UTC 0 点重置；升级到 Workers 付费计划可提高上限。';

/// 错误消息是否在说每日额度（同时含 daily 与 limit，或提到 free tier，不区分大小写）
export function isD1DailyLimitMessage(message: string): boolean {
  const m = message.toLowerCase();
  return (m.includes('daily') && m.includes('limit')) || m.includes('free tier');
}

/// 存储 key 含特殊字符需编码，且 % 不能被二次编码
function encodeStorageKey(key: string): string {
  return encodeURIComponent(key);
}

export class StorageService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  // ---- R2 ----

  /// 桶级请求用的客户端：区域桶派生一个带 cf-r2-jurisdiction 头的实例，默认区域用共享实例
  private r2Client(jurisdiction: string): CFApiClient {
    const header = r2JurisdictionHeader(jurisdiction);
    if (header === '') {
      return this.client;
    }
    const headers: Record<string, string> = {};
    headers[R2_JURISDICTION_HEADER] = header;
    return this.client.withHeaders(headers);
  }

  // R2 buckets 端点 result 是对象 { buckets: [...] }，不能走 getList（会把对象当数组返回，ForEach 崩溃）。
  /// 桶列表走游标取全量：单页上限 100，超过 100 个桶以前后面的看不到（iOS 2.1.3 同批修复）。
  /// 最多 50 页兜底，防服务端游标异常死循环。
  /// 先无头列一次（失败照常抛），再带 eu / us 头各列一次（失败忽略），按 (桶名, 区域) 去重合并。
  async listBuckets(accountId: string): Promise<R2Bucket[]> {
    const all: R2Bucket[] = await this.listBucketsIn(accountId, '');
    const seen = new Set<string>(all.map((b: R2Bucket) => `${b.name}|${r2JurisdictionHeader(b.jurisdiction)}`));
    for (const jurisdiction of R2_PROBE_JURISDICTIONS) {
      let extra: R2Bucket[] = [];
      try {
        extra = await this.listBucketsIn(accountId, jurisdiction);
      } catch (e) {
        continue;
      }
      for (const b of extra) {
        const key = `${b.name}|${r2JurisdictionHeader(b.jurisdiction)}`;
        if (!seen.has(key)) {
          seen.add(key);
          all.push(b);
        }
      }
    }
    return all;
  }

  /// 按单个区域分页列桶。带头列出的桶若完全没回 jurisdiction 字段，按请求的区域补上
  ///（显式回了 default 的不改——那说明服务端没按头过滤，不能误标成区域桶）
  private async listBucketsIn(accountId: string, jurisdiction: string): Promise<R2Bucket[]> {
    const client = this.r2Client(jurisdiction);
    const fallback = r2JurisdictionHeader(jurisdiction);
    const all: R2Bucket[] = [];
    let cursor = '';
    for (let i = 0; i < 50; i++) {
      const query: Record<string, string> = { 'per_page': '100' };
      if (cursor !== '') {
        query['cursor'] = cursor;
      }
      const page = await client.getObjectEnvelope<R2BucketList>(`/accounts/${accountId}/r2/buckets`, query);
      const buckets = page.result?.buckets ?? [];
      for (const b of buckets) {
        if (fallback !== '' && (b.jurisdiction ?? '') === '') {
          b.jurisdiction = fallback;
        }
        all.push(b);
      }
      cursor = page.result_info?.cursor ?? '';
      if (cursor === '' || buckets.length === 0) {
        break;
      }
    }
    return all;
  }

  createBucket(accountId: string, name: string): Promise<R2Bucket> {
    interface BucketCreate {
      name: string;
    }
    const body: BucketCreate = { name: name };
    return this.client.postObject<R2Bucket>(`/accounts/${accountId}/r2/buckets`, body);
  }

  deleteBucket(accountId: string, bucket: string, jurisdiction: string): Promise<void> {
    return this.r2Client(jurisdiction).delete(`/accounts/${accountId}/r2/buckets/${bucket}`);
  }

  /// 对象浏览：传 delimiter=/ 让服务端把子前缀折叠成「文件夹」（result_info.delimited），
  /// prefix 为当前所在文件夹。返回当前层对象 + 子文件夹前缀 + 下一页游标。
  async listObjects(accountId: string, bucket: string, prefix: string, cursor: string,
    jurisdiction: string): Promise<R2ObjectPage> {
    const query: Record<string, string> = { 'per_page': '100', 'delimiter': '/' };
    if (prefix !== '') {
      query['prefix'] = prefix;
    }
    if (cursor !== '') {
      query['cursor'] = cursor;
    }
    const envelope = await this.r2Client(jurisdiction).getListEnvelope<R2Object>(
      `/accounts/${accountId}/r2/buckets/${bucket}/objects`, query);
    const info = envelope.result_info as R2ListResultInfo | undefined;
    const truncated = info?.is_truncated ?? false;
    const page: R2ObjectPage = {
      objects: envelope.result ?? [],
      folders: info?.delimited ?? [],
      cursor: truncated ? (info?.cursor ?? '') : '',
    };
    return page;
  }

  getObjectText(accountId: string, bucket: string, key: string, jurisdiction: string): Promise<string> {
    return this.r2Client(jurisdiction).getRaw(
      `/accounts/${accountId}/r2/buckets/${bucket}/objects/${encodeStorageKey(key)}`);
  }

  /// 取对象原始字节（供系统预览下载临时文件 / 保存到设备）。R2 object 正文是裸字节非信封，
  /// CFApiClient 无 ARRAY_BUFFER 型 getter，此处直连 http（镜像 putBytes 反向），返回 ArrayBuffer。
  async getObjectBytes(accountId: string, bucket: string, key: string, jurisdiction: string): Promise<ArrayBuffer> {
    const token = await authManager.ensureAccessToken();
    const url = `${R2_BASE_URL}/accounts/${accountId}/r2/buckets/${bucket}/objects/${encodeStorageKey(key)}`;
    const headers: Record<string, string> = { 'Authorization': `Bearer ${token}` };
    const jurisdictionHeader = r2JurisdictionHeader(jurisdiction);
    if (jurisdictionHeader !== '') {
      headers[R2_JURISDICTION_HEADER] = jurisdictionHeader;
    }
    const session = http.createHttp();
    try {
      const response = await session.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 120000,
      });
      const code = response.responseCode;
      if (code === 401) {
        throw new ApiError('登录已过期，请重新登录', 401);
      }
      if (code < 200 || code >= 300) {
        throw new ApiError(`HTTP ${code}`, code);
      }
      return response.result as ArrayBuffer;
    } finally {
      session.destroy();
    }
  }

  async putObjectText(accountId: string, bucket: string, key: string, text: string, contentType: string,
    jurisdiction: string): Promise<void> {
    await this.r2Client(jurisdiction).putRaw(
      `/accounts/${accountId}/r2/buckets/${bucket}/objects/${encodeStorageKey(key)}`, text, contentType);
  }

  /// 上传二进制文件对象（picker 选文件 → 读字节 → PUT）
  async putObjectBytes(accountId: string, bucket: string, key: string, buffer: ArrayBuffer,
    contentType: string, jurisdiction: string): Promise<void> {
    await this.r2Client(jurisdiction).putBytes(
      `/accounts/${accountId}/r2/buckets/${bucket}/objects/${encodeStorageKey(key)}`, buffer, contentType);
  }

  deleteObject(accountId: string, bucket: string, key: string, jurisdiction: string): Promise<void> {
    return this.r2Client(jurisdiction).delete(
      `/accounts/${accountId}/r2/buckets/${bucket}/objects/${encodeStorageKey(key)}`);
  }

  // ---- R2 对象复制 / 移动（client v4 无服务端 copy，只能下载字节再上传；上限由调用方守卫）----

  /// 复制对象到新 key（同桶）：GET 原始字节 → PUT 到目标 key。contentType 按目标 key 扩展名推断。
  async copyObject(accountId: string, bucket: string, sourceKey: string, destKey: string,
    jurisdiction: string): Promise<void> {
    const buffer = await this.getObjectBytes(accountId, bucket, sourceKey, jurisdiction);
    await this.putObjectBytes(accountId, bucket, destKey, buffer, mimeOf(destKey), jurisdiction);
  }

  /// 精确判断某 key 是否存在（对象端点无 HEAD，用 prefix 列举核对；对齐 iOS objectExists）
  async objectExists(accountId: string, bucket: string, key: string, jurisdiction: string): Promise<boolean> {
    const page = await this.listObjects(accountId, bucket, key, '', jurisdiction);
    for (const obj of page.objects) {
      if (obj.key === key) {
        return true;
      }
    }
    return false;
  }

  // ---- R2 桶设置：公开访问（r2.dev）/ 自定义域 / CORS ----

  /// 托管公开访问域（r2.dev）当前状态
  getManagedDomain(accountId: string, bucket: string, jurisdiction: string): Promise<R2ManagedDomain> {
    return this.r2Client(jurisdiction).getObject<R2ManagedDomain>(
      `/accounts/${accountId}/r2/buckets/${bucket}/domains/managed`);
  }

  /// 启用 / 停用 r2.dev 公开访问
  async setManagedDomainEnabled(accountId: string, bucket: string, enabled: boolean,
    jurisdiction: string): Promise<R2ManagedDomain> {
    const body: R2ManagedDomainUpdate = { enabled: enabled };
    return this.r2Client(jurisdiction).putObject<R2ManagedDomain>(
      `/accounts/${accountId}/r2/buckets/${bucket}/domains/managed`, body);
  }

  /// 已连接的自定义域（result 是 { domains: [...] } 包裹对象）
  async listCustomDomains(accountId: string, bucket: string, jurisdiction: string): Promise<R2CustomDomain[]> {
    const wrap = await this.r2Client(jurisdiction).getObject<R2CustomDomainList>(
      `/accounts/${accountId}/r2/buckets/${bucket}/domains/custom`);
    return wrap.domains ?? [];
  }

  /// 连接一个自定义域（域名须属于同账号下的 zone，zoneId 必填）
  addCustomDomain(accountId: string, bucket: string, domain: string, zoneId: string,
    jurisdiction: string): Promise<R2CustomDomain> {
    const body: R2CustomDomainCreate = { domain: domain, zoneId: zoneId, enabled: true };
    return this.r2Client(jurisdiction).postObject<R2CustomDomain>(
      `/accounts/${accountId}/r2/buckets/${bucket}/domains/custom`, body);
  }

  /// 移除（断开）一个自定义域
  removeCustomDomain(accountId: string, bucket: string, domain: string, jurisdiction: string): Promise<void> {
    return this.r2Client(jurisdiction).delete(
      `/accounts/${accountId}/r2/buckets/${bucket}/domains/custom/${encodeStorageKey(domain)}`);
  }

  /// 当前 CORS 策略（桶从未配置过时端点报错，由调用方按空处理）
  getCorsPolicy(accountId: string, bucket: string, jurisdiction: string): Promise<R2CorsPolicy> {
    return this.r2Client(jurisdiction).getObject<R2CorsPolicy>(`/accounts/${accountId}/r2/buckets/${bucket}/cors`);
  }

  /// 整体写入 CORS 策略（PUT 覆盖；R2 的 CORS 是整组替换，改任一条都要回写全集）。
  /// 该端点成功时 result 可能为空，走 putRaw 只校验信封 success。
  async putCorsPolicy(accountId: string, bucket: string, policy: R2CorsPolicy, jurisdiction: string): Promise<void> {
    await this.r2Client(jurisdiction).putRaw(`/accounts/${accountId}/r2/buckets/${bucket}/cors`,
      JSON.stringify(policy), 'application/json');
  }

  /// 清除全部 CORS 策略
  deleteCorsPolicy(accountId: string, bucket: string, jurisdiction: string): Promise<void> {
    return this.r2Client(jurisdiction).delete(`/accounts/${accountId}/r2/buckets/${bucket}/cors`);
  }

  // ---- D1 ----
  listDatabases(accountId: string): Promise<D1Database[]> {
    return this.client.getList<D1Database>(`/accounts/${accountId}/d1/database`, {
      'per_page': '100',
    } as Record<string, string>);
  }

  // 列表端点不返回真实 num_tables / file_size（常年 0），须逐库调详情端点补全。
  getDatabase(accountId: string, databaseId: string): Promise<D1Database> {
    return this.client.getObject<D1Database>(`/accounts/${accountId}/d1/database/${databaseId}`);
  }

  createDatabase(accountId: string, name: string): Promise<D1Database> {
    interface CreateBody {
      name: string;
    }
    const body: CreateBody = { name: name };
    return this.client.postObject<D1Database>(`/accounts/${accountId}/d1/database`, body);
  }

  deleteDatabase(accountId: string, databaseId: string): Promise<void> {
    return this.client.delete(`/accounts/${accountId}/d1/database/${databaseId}`);
  }

  /// 执行 SQL。params 为参数化占位符（?）绑定值，D1 端点按字符串绑定、依 SQLite 列亲和性转数值。
  /// 命中免费套餐每日行数上限时，在原始报错前补一句中文说明（控制台 / 表浏览 / 行编辑共用）。
  async query(accountId: string, databaseId: string, sql: string, params?: string[]): Promise<D1QueryResult[]> {
    const body: D1QueryBody = { sql: sql };
    if (params !== undefined) {
      body.params = params;
    }
    try {
      return await this.client.postForList<D1QueryResult>(
        `/accounts/${accountId}/d1/database/${databaseId}/query`, body);
    } catch (e) {
      const err = e as Error;
      const raw = err.message ?? '';
      if (isD1DailyLimitMessage(raw)) {
        const code = err instanceof ApiError ? (err as ApiError).code : 0;
        throw new ApiError(`${D1_DAILY_LIMIT_HINT}\n${raw}`, code);
      }
      throw err;
    }
  }

  // ---- KV ----
  listNamespaces(accountId: string): Promise<KVNamespace[]> {
    return this.client.getList<KVNamespace>(`/accounts/${accountId}/storage/kv/namespaces`, {
      'per_page': '100',
    } as Record<string, string>);
  }

  createNamespace(accountId: string, title: string): Promise<KVNamespace> {
    interface NsCreate {
      title: string;
    }
    const body: NsCreate = { title: title };
    return this.client.postObject<KVNamespace>(`/accounts/${accountId}/storage/kv/namespaces`, body);
  }

  deleteNamespace(accountId: string, namespaceId: string): Promise<void> {
    return this.client.delete(`/accounts/${accountId}/storage/kv/namespaces/${namespaceId}`);
  }

  async listKeys(accountId: string, namespaceId: string, cursor: string): Promise<CursorPage<KVKey>> {
    const query: Record<string, string> = { 'limit': '100' };
    if (cursor !== '') {
      query['cursor'] = cursor;
    }
    const raw = await this.client.getRaw(`/accounts/${accountId}/storage/kv/namespaces/${namespaceId}/keys`, query);
    const envelope = JSON.parse(raw) as KVKeysEnvelope;
    return { items: envelope.result ?? [], cursor: envelope.result_info?.cursor ?? '' };
  }

  getValue(accountId: string, namespaceId: string, key: string): Promise<string> {
    return this.client.getRaw(
      `/accounts/${accountId}/storage/kv/namespaces/${namespaceId}/values/${encodeStorageKey(key)}`);
  }

  /// KV 写值：multipart value + metadata 两 part
  async putValue(accountId: string, namespaceId: string, key: string, value: string): Promise<void> {
    const parts: MultipartPart[] = [
      { name: 'value', data: value },
      { name: 'metadata', contentType: 'application/json', data: '{}' },
    ];
    await this.client.putMultipart(
      `/accounts/${accountId}/storage/kv/namespaces/${namespaceId}/values/${encodeStorageKey(key)}`, parts);
  }

  deleteKey(accountId: string, namespaceId: string, key: string): Promise<void> {
    return this.client.delete(
      `/accounts/${accountId}/storage/kv/namespaces/${namespaceId}/values/${encodeStorageKey(key)}`);
  }
}
