// 开发者平台：Queues / AI Gateway / Durable Objects / Hyperdrive / Workers AI（对齐 Android DeveloperPlatformRepository）。
import { util } from '@kit.ArkTS';
import {
  AIGateway,
  AIModel,
  CFQueue,
  DurableObjectInstance,
  DurableObjectNamespace,
  DurableObjectPage,
  HyperdriveConfig,
} from '../models/WorkerModels';
import { ApiError, CFApiClient, apiClient } from '../core/network/CFApiClient';

/// 文生图信封形态（少数模型走这条：v4 信封 + base64 图片）
interface AIImageResult {
  image?: string;
}

interface AIImageEnvelope {
  result?: AIImageResult;
}

/// 按魔数判断是否图片（PNG / JPEG / GIF / WEBP），对齐 iOS looksLikeImage
function looksLikeImage(buffer: ArrayBuffer): boolean {
  if (buffer.byteLength <= 12) {
    return false;
  }
  const head = new Uint8Array(buffer, 0, 12);
  if (head[0] === 0x89 && head[1] === 0x50 && head[2] === 0x4E && head[3] === 0x47) {
    return true; // PNG
  }
  if (head[0] === 0xFF && head[1] === 0xD8 && head[2] === 0xFF) {
    return true; // JPEG
  }
  if (head[0] === 0x47 && head[1] === 0x49 && head[2] === 0x46) {
    return true; // GIF
  }
  if (head[0] === 0x52 && head[1] === 0x49 && head[2] === 0x46 && head[3] === 0x46 &&
    head[8] === 0x57 && head[9] === 0x45 && head[10] === 0x42 && head[11] === 0x50) {
    return true; // WEBP
  }
  return false;
}

interface AIChatMessage {
  role: string;
  content: string;
}

interface AITextGenBody {
  messages: AIChatMessage[];
}

interface AITextGenResult {
  response?: string;
}

/// PUT queues/{id} 的 settings 局部体（全字段可选，omit 即不改，对齐 iOS CFQueueSettingsPatch）
interface QueueSettingsPatchBody {
  delivery_delay?: number;
  delivery_paused?: boolean;
  message_retention_period?: number;
}

/// PUT queues/{id} 请求体（重命名 / 改投递设置，对齐 iOS CFQueueUpdate）
interface QueueUpdateBody {
  queue_name?: string;
  settings?: QueueSettingsPatchBody;
}

interface QueuePurgeBody {
  delete_messages_permanently: boolean;
}

interface HyperdriveRenameBody {
  name: string;
}

/// PATCH origin 时 CF 要求整组连接字段（含密码）一起提交
interface HyperdriveOriginInput {
  scheme: string;
  host: string;
  port: number;
  database: string;
  user: string;
  password: string;
}

interface HyperdriveOriginPatchBody {
  origin: HyperdriveOriginInput;
}

// —— Durable Objects 内存分位数（GraphQL durableObjectsPeriodicGroups）——
// REST 没有这项。口径是 V8 isolate 的内存而非单个对象：一个 isolate 可能同时承载同类的
// 多个对象与外围 Worker 代码，每个 isolate 上限 128 MB。
const DO_MEMORY_QUERY: string = `
query DOMemory($accountTag: String!, $namespaceId: String!, $since: Time!, $until: Time!) {
  viewer {
    accounts(filter: { accountTag: $accountTag }) {
      durableObjectsPeriodicGroups(
        limit: 1
        filter: { datetime_geq: $since, datetime_leq: $until, namespaceId: $namespaceId }
      ) {
        quantiles {
          memoryUsageBytesP50
          memoryUsageBytesP90
          memoryUsageBytesP99
          memoryUsageBytesP999
        }
      }
    }
  }
}`;

interface DOMemoryVariables {
  accountTag: string;
  namespaceId: string;
  since: string;
  until: string;
}

interface DOMemoryQuantiles {
  memoryUsageBytesP50?: number;
  memoryUsageBytesP90?: number;
  memoryUsageBytesP99?: number;
  memoryUsageBytesP999?: number;
}

interface DOMemoryGroup {
  quantiles?: DOMemoryQuantiles;
}

interface DOMemoryAccount {
  durableObjectsPeriodicGroups?: DOMemoryGroup[];
}

interface DOMemoryViewer {
  accounts?: DOMemoryAccount[];
}

interface DOMemoryData {
  viewer?: DOMemoryViewer;
}

interface DOMemoryError {
  message: string;
}

interface DOMemoryResponse {
  data?: DOMemoryData;
  errors?: DOMemoryError[];
}

export interface DurableObjectMemory {
  p50: number;
  p90: number;
  p99: number;
  p999: number;
}

export class DevPlatformService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  listQueues(accountId: string): Promise<CFQueue[]> {
    return this.client.getList<CFQueue>(`/accounts/${accountId}/queues`);
  }

  /// 单队列详情（含 producers / consumers / settings，列表端点只给计数）
  getQueue(accountId: string, queueId: string): Promise<CFQueue> {
    return this.client.getObject<CFQueue>(`/accounts/${accountId}/queues/${queueId}`);
  }

  createQueue(accountId: string, name: string): Promise<CFQueue> {
    interface QueueCreate {
      queue_name: string;
    }
    const body: QueueCreate = { queue_name: name };
    return this.client.postObject<CFQueue>(`/accounts/${accountId}/queues`, body);
  }

  deleteQueue(accountId: string, queueId: string): Promise<void> {
    return this.client.delete(`/accounts/${accountId}/queues/${queueId}`);
  }

  /// 重命名队列（PUT 全字段可选，只发 queue_name 即只改名，对齐 iOS QueueService.update）
  renameQueue(accountId: string, queueId: string, name: string): Promise<CFQueue> {
    const body: QueueUpdateBody = { queue_name: name };
    return this.client.putObject<CFQueue>(`/accounts/${accountId}/queues/${queueId}`, body);
  }

  /// 改投递设置（投递延迟 / 消息保留期，单位秒）
  updateQueueSettings(accountId: string, queueId: string, deliveryDelay: number,
    retentionPeriod: number): Promise<CFQueue> {
    const patch: QueueSettingsPatchBody = {
      delivery_delay: deliveryDelay,
      message_retention_period: retentionPeriod,
    };
    const body: QueueUpdateBody = { settings: patch };
    return this.client.putObject<CFQueue>(`/accounts/${accountId}/queues/${queueId}`, body);
  }

  /// 暂停 / 恢复投递（settings.delivery_paused）
  setQueuePaused(accountId: string, queueId: string, paused: boolean): Promise<CFQueue> {
    const patch: QueueSettingsPatchBody = { delivery_paused: paused };
    const body: QueueUpdateBody = { settings: patch };
    return this.client.putObject<CFQueue>(`/accounts/${accountId}/queues/${queueId}`, body);
  }

  /// 清空队列全部消息（不可撤销，对齐 iOS QueueService.purge）
  async purgeQueue(accountId: string, queueId: string): Promise<void> {
    const body: QueuePurgeBody = { delete_messages_permanently: true };
    await this.client.postObject<object>(`/accounts/${accountId}/queues/${queueId}/purge`, body);
  }

  listGateways(accountId: string): Promise<AIGateway[]> {
    return this.client.getList<AIGateway>(`/accounts/${accountId}/ai-gateway/gateways`);
  }

  /// 单网关详情（含 cache_ttl / collect_logs / 限流 / 时间等）
  getGateway(accountId: string, gatewayId: string): Promise<AIGateway> {
    return this.client.getObject<AIGateway>(`/accounts/${accountId}/ai-gateway/gateways/${gatewayId}`);
  }

  /// 新建网关。CF 要求 6 个字段全传，缺 rate_limiting_* 两个整数会被服务端解析成 NaN 报错。
  createGateway(accountId: string, name: string, cacheTtl: number = 0, collectLogs: boolean = true,
    rateLimit: number = 0, rateInterval: number = 60): Promise<AIGateway> {
    interface GatewayCreate {
      id: string;
      cache_ttl: number;
      cache_invalidate_on_update: boolean;
      collect_logs: boolean;
      rate_limiting_interval: number;
      rate_limiting_limit: number;
    }
    const body: GatewayCreate = {
      id: name,
      cache_ttl: cacheTtl,
      cache_invalidate_on_update: false,
      collect_logs: collectLogs,
      rate_limiting_interval: rateInterval,
      rate_limiting_limit: rateLimit,
    };
    return this.client.postObject<AIGateway>(`/accounts/${accountId}/ai-gateway/gateways`, body);
  }

  deleteGateway(accountId: string, gatewayId: string): Promise<void> {
    return this.client.delete(`/accounts/${accountId}/ai-gateway/gateways/${gatewayId}`);
  }

  // namespace 最近 24h 的内存分位数。免费账号的账户级 GraphQL 会被 authz 挡，
  // 这里统一返回 undefined 交给 UI 说「无数据」，不弹错误。
  async durableObjectMemory(accountId: string, namespaceId: string): Promise<DurableObjectMemory | undefined> {
    const until = new Date();
    const since = new Date(until.getTime() - 24 * 3600 * 1000);
    const vars: DOMemoryVariables = {
      accountTag: accountId,
      namespaceId: namespaceId,
      since: since.toISOString(),
      until: until.toISOString(),
    };
    try {
      const text = await this.client.graphql(DO_MEMORY_QUERY, vars);
      const response = JSON.parse(text) as DOMemoryResponse;
      if (response.errors && response.errors.length > 0) {
        return undefined;
      }
      const accounts = response.data?.viewer?.accounts ?? [];
      if (accounts.length === 0) {
        return undefined;
      }
      const groups = accounts[0].durableObjectsPeriodicGroups ?? [];
      if (groups.length === 0) {
        return undefined;
      }
      const q = groups[0].quantiles;
      if (!q || q.memoryUsageBytesP50 === undefined) {
        return undefined;
      }
      const memory: DurableObjectMemory = {
        p50: q.memoryUsageBytesP50,
        p90: q.memoryUsageBytesP90 ?? 0,
        p99: q.memoryUsageBytesP99 ?? 0,
        p999: q.memoryUsageBytesP999 ?? 0,
      };
      return memory;
    } catch (e) {
      return undefined;
    }
  }

  /// 端点默认 per_page=20（上限 1000）：不翻页第 21 个命名空间起就看不见
  listDurableObjectNamespaces(accountId: string): Promise<DurableObjectNamespace[]> {
    return this.client.getAllPages<DurableObjectNamespace>(
      `/accounts/${accountId}/workers/durable_objects/namespaces`, 1000);
  }

  /// 命名空间下的对象实例（只读，游标分页）。对象在首次被访问时才由运行时创建，
  /// 所以空列表是正常状态而不是错误。
  async listDurableObjects(accountId: string, namespaceId: string,
    cursor: string = ''): Promise<DurableObjectPage> {
    const query: Record<string, string> = { 'limit': '50' };
    if (cursor !== '') {
      query['cursor'] = cursor;
    }
    const envelope = await this.client.getListEnvelope<DurableObjectInstance>(
      `/accounts/${accountId}/workers/durable_objects/namespaces/${namespaceId}/objects`, query);
    return {
      items: envelope.result ?? [],
      cursor: envelope.result_info?.cursor ?? '',
    };
  }

  /// 端点默认 per_page=20（上限 100）：不翻页第 21 个配置起就看不见
  listHyperdrive(accountId: string): Promise<HyperdriveConfig[]> {
    return this.client.getAllPages<HyperdriveConfig>(`/accounts/${accountId}/hyperdrive/configs`, 100);
  }

  /// 创建 Hyperdrive（PostgreSQL 源连接）
  createHyperdrive(accountId: string, name: string, host: string, port: number,
    database: string, user: string, password: string,
    scheme: string = 'postgres'): Promise<HyperdriveConfig> {
    interface HyperdriveOrigin {
      host: string;
      port: number;
      database: string;
      user: string;
      password: string;
      scheme: string;
    }
    interface HyperdriveCreate {
      name: string;
      origin: HyperdriveOrigin;
    }
    const body: HyperdriveCreate = {
      name: name,
      origin: {
        host: host, port: port, database: database, user: user, password: password, scheme: scheme,
      } as HyperdriveOrigin,
    };
    return this.client.postObject<HyperdriveConfig>(`/accounts/${accountId}/hyperdrive/configs`, body);
  }

  /// 编辑 Hyperdrive 缓存与连接上限（PATCH 局部更新，对齐 iOS HyperdrivePatch）
  updateHyperdrive(accountId: string, configId: string, disabled: boolean, maxAge: number,
    staleWhileRevalidate: number, connLimit: number): Promise<HyperdriveConfig> {
    interface CachingPatch {
      disabled: boolean;
      max_age?: number;
      stale_while_revalidate?: number;
    }
    interface HyperdrivePatchBody {
      caching: CachingPatch;
      origin_connection_limit?: number;
    }
    const caching: CachingPatch = disabled
      ? { disabled: true }
      : { disabled: false, max_age: maxAge, stale_while_revalidate: staleWhileRevalidate };
    const body: HyperdrivePatchBody = {
      caching: caching,
      origin_connection_limit: connLimit > 0 ? connLimit : undefined,
    };
    return this.client.patchObject<HyperdriveConfig>(`/accounts/${accountId}/hyperdrive/configs/${configId}`, body);
  }

  /// 重命名 Hyperdrive 配置（PATCH 只发 name 即只改名，对齐 iOS HyperdrivePatch）
  renameHyperdrive(accountId: string, configId: string, name: string): Promise<HyperdriveConfig> {
    const body: HyperdriveRenameBody = { name: name };
    return this.client.patchObject<HyperdriveConfig>(`/accounts/${accountId}/hyperdrive/configs/${configId}`, body);
  }

  /// 编辑源库连接（PATCH origin 需整组字段含密码一起提交）
  updateHyperdriveOrigin(accountId: string, configId: string, scheme: string, host: string, port: number,
    database: string, user: string, password: string): Promise<HyperdriveConfig> {
    const origin: HyperdriveOriginInput = {
      scheme: scheme,
      host: host,
      port: port,
      database: database,
      user: user,
      password: password,
    };
    const body: HyperdriveOriginPatchBody = { origin: origin };
    return this.client.patchObject<HyperdriveConfig>(`/accounts/${accountId}/hyperdrive/configs/${configId}`, body);
  }

  deleteHyperdrive(accountId: string, configId: string): Promise<void> {
    return this.client.delete(`/accounts/${accountId}/hyperdrive/configs/${configId}`);
  }

  listAIModels(accountId: string): Promise<AIModel[]> {
    return this.client.getList<AIModel>(`/accounts/${accountId}/ai/models/search`, {
      'per_page': '100',
    } as Record<string, string>);
  }

  /// Workers AI 文本生成试运行
  async runTextGeneration(accountId: string, model: string, prompt: string): Promise<string> {
    const body: AITextGenBody = {
      messages: [{ role: 'user', content: prompt } as AIChatMessage],
    };
    const result = await this.client.postObject<AITextGenResult>(`/accounts/${accountId}/ai/run/${model}`, body);
    return result.response ?? '（无返回）';
  }

  /// Workers AI 文生图试运行。返回体两种形态：多数模型直接回图片二进制（PNG/JPEG/GIF/WEBP），
  /// 少数回 v4 信封 + base64 `image`。两种都不匹配就明确报错，不静默返回空图（对齐 iOS）。
  async runTextToImage(accountId: string, model: string, prompt: string): Promise<ArrayBuffer> {
    interface ImageGenBody {
      prompt: string;
    }
    const body: ImageGenBody = { prompt: prompt };
    const raw = await this.client.postForBytes(`/accounts/${accountId}/ai/run/${model}`, body);
    if (looksLikeImage(raw)) {
      return raw;
    }
    // 信封 + base64 形态
    try {
      const text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(raw));
      const envelope = JSON.parse(text) as AIImageEnvelope;
      const base64 = envelope.result?.image ?? '';
      if (base64 !== '') {
        const decoded = new util.Base64Helper().decodeSync(base64, util.Type.BASIC);
        const buffer = decoded.buffer as ArrayBuffer;
        if (looksLikeImage(buffer)) {
          return buffer;
        }
      }
    } catch (e) {
      // 不是 JSON，落到下面统一报错
    }
    throw new ApiError('该模型返回的不是图片数据，暂不支持在 App 内试运行');
  }
}
