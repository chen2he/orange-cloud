// Workers / DevPlatform / Pages 数据模型（对齐 Android 各 model）。

export interface WorkerScript {
  id: string;
  created_on?: string;
  modified_on?: string;
  /// 以下为列表端点返回的元信息（详情页「信息」分组用，对齐 iOS CachedWorkerScript）
  usage_model?: string;
  handlers?: string[];
  logpush?: boolean;
  compatibility_date?: string;
}

export interface WorkerSecret {
  name: string;
  type?: string;
}

export interface WorkerRoute {
  id: string;
  pattern: string;
  script?: string;
}

export interface WorkerSchedule {
  cron: string;
}

export interface WorkerCustomDomain {
  id: string;
  hostname?: string;
  service?: string;
  zone_name?: string;
}

export interface WorkerSubdomain {
  enabled?: boolean;
}

/// 一次部署（deployments 端点 result.deployments 元素；首项为当前活跃部署，CF 拒绝删除活跃部署）
export interface WorkerDeployment {
  id: string;
  created_on?: string;
  source?: string;
  author_email?: string;
  annotations?: Record<string, string>;
}

export interface WorkerDeploymentsResult {
  deployments?: WorkerDeployment[];
}

/// settings 端点里的一条绑定（更新代码时按名转 inherit 回传，密钥值读不到也能保住）
export interface WorkerBindingInfo {
  name?: string;
  type?: string;
  /// plain_text 变量的值；其余类型不返回
  text?: string;
}

/// 脚本设置（绑定 + 兼容性日期/标志），更新代码时沿用旧值
export interface WorkerSettingsInfo {
  bindings?: WorkerBindingInfo[];
  compatibility_date?: string;
  compatibility_flags?: string[];
  usage_model?: string;
  logpush?: boolean;
}

/// PATCH settings / 上传时的单条绑定（对齐 iOS WorkerBindingInput）。
/// inherit 只发 { type, name } 按名保留；plain_text 发 text；
/// kv_namespace 发 namespace_id；d1 发 id；r2_bucket 发 bucket_name（**按桶名不是 ID**）。
export interface WorkerBindingInput {
  type: string;
  name: string;
  text?: string;
  namespace_id?: string;
  id?: string;
  bucket_name?: string;
}

export function bindingIsSecret(binding: WorkerBindingInfo): boolean {
  const type = binding.type ?? '';
  return type === 'secret_text' || type === 'secrets_store_secret';
}

export function bindingIsPlainText(binding: WorkerBindingInfo): boolean {
  return (binding.type ?? '') === 'plain_text';
}

/// 本客户端可原地增删的资源绑定（D1 / KV / R2）——其余类型只读展示
export function bindingIsQuickManaged(binding: WorkerBindingInfo): boolean {
  const type = binding.type ?? '';
  return type === 'kv_namespace' || type === 'd1' || type === 'r2_bucket';
}

/// 绑定类型 → 人类可读标签（对齐 iOS WorkerBinding.typeLabel）
export function bindingTypeLabel(type: string): string {
  switch (type) {
    case 'plain_text':
      return '变量';
    case 'secret_text':
    case 'secrets_store_secret':
      return '密钥';
    case 'kv_namespace':
      return 'KV';
    case 'd1':
      return 'D1';
    case 'r2_bucket':
      return 'R2';
    case 'queue':
      return '队列';
    case 'durable_object_namespace':
      return 'Durable Object';
    case 'service':
      return 'Service 绑定';
    case 'ai':
      return 'Workers AI';
    case 'vectorize':
      return 'Vectorize';
    case 'analytics_engine':
      return 'Analytics Engine';
    case 'browser':
      return '浏览器渲染';
    default:
      return type;
  }
}

/// 整组绑定转 inherit（可排除一个名字，用于「改这一项、其余原样保留」）
export function inheritedBindings(settings: WorkerSettingsInfo, excludingName: string = ''): WorkerBindingInput[] {
  const out: WorkerBindingInput[] = [];
  for (const binding of settings.bindings ?? []) {
    const name = binding.name ?? '';
    if (name === '' || name === excludingName) {
      continue;
    }
    out.push({ type: 'inherit', name: name });
  }
  return out;
}

/// 解析后的脚本源码（content 端点：模块脚本 multipart、service worker 裸 JS）。
/// 仅单模块可安全往返编辑；多模块（构建产物）只读。
export interface WorkerScriptContent {
  body: string;
  moduleName: string;
  contentType: string;
  isModule: boolean;
  editable: boolean;
  moduleCount: number;
}

/// tail 预签名会话
export interface TailSession {
  id: string;
  url: string;
  expires_at?: string;
}

/// trace-v1 帧（camelCase，勿映射 snake_case）
export interface TailLog {
  message?: string[];
  level?: string;
  timestamp?: number;
}

export interface TailException {
  name?: string;
  message?: string;
}

export interface TailEventRequest {
  url?: string;
  method?: string;
}

export interface TailEvent {
  request?: TailEventRequest;
}

export interface TailTraceItem {
  outcome?: string;
  scriptName?: string;
  eventTimestamp?: number;
  logs?: TailLog[];
  exceptions?: TailException[];
  event?: TailEvent;
}

// ---- DevPlatform ----

/// 队列生产者 / 消费者端点（script 或 type 二选一）
export interface QueueEndpoint {
  script?: string;
  type?: string;
}

/// 消费者批处理参数 + 死信队列
export interface QueueConsumerSettings {
  batch_size?: number;
  max_retries?: number;
  max_concurrency?: number;
}

export interface QueueConsumer {
  script?: string;
  type?: string;
  settings?: QueueConsumerSettings;
  dead_letter_queue?: string;
}

export interface QueueSettings {
  delivery_paused?: boolean;
  message_retention_period?: number;
  delivery_delay?: number;
}

export interface CFQueue {
  queue_id?: string;
  queue_name?: string;
  created_on?: string;
  producers_total_count?: number;
  consumers_total_count?: number;
  producers?: QueueEndpoint[];
  consumers?: QueueConsumer[];
  settings?: QueueSettings;
}

export interface AIGateway {
  id: string;
  name?: string;
  created_on?: string;
  modified_on?: string;
  cache_ttl?: number;
  collect_logs?: boolean;
  rate_limiting_interval?: number;
  rate_limiting_limit?: number;
  cache_invalidate_on_update?: boolean;
}

/// 命名空间下的一个对象实例（只读）
export interface DurableObjectInstance {
  id: string;
  hasStoredData?: boolean;
}

/// 对象实例的一页（游标为空表示已到末页）
export interface DurableObjectPage {
  items: DurableObjectInstance[];
  cursor: string;
}

export interface DurableObjectNamespace {
  id: string;
  name?: string;
  class?: string;
  script?: string;
}

export interface HyperdriveOrigin {
  scheme?: string;
  host?: string;
  port?: number;
  database?: string;
  user?: string;
}

export interface HyperdriveCaching {
  disabled?: boolean;
  max_age?: number;
  stale_while_revalidate?: number;
}

export interface HyperdriveConfig {
  id: string;
  name?: string;
  origin?: HyperdriveOrigin;
  caching?: HyperdriveCaching;
  origin_connection_limit?: number;
}

export interface AIModel {
  id?: string;
  name: string;
  description?: string;
  task?: AIModelTask;
}

export interface AIModelTask {
  name?: string;
}

// ---- Pages ----

export interface PagesDeploymentStage {
  name?: string;
  status?: string;
}

export interface PagesLatestStage {
  name?: string;
  status?: string;
}

export interface PagesDeployment {
  id: string;
  short_id?: string;
  environment?: string;
  created_on?: string;
  modified_on?: string;
  latest_stage?: PagesLatestStage;
  url?: string;
}

export interface PagesSource {
  type?: string;
}

export interface PagesBuildConfig {
  build_command?: string;
  destination_dir?: string;
}

export interface PagesProject {
  name: string;
  subdomain?: string;
  domains?: string[];
  production_branch?: string;
  created_on?: string;
  /// 列表端点随项目返回的最近一次部署（排序「最近更新」取它的时间）
  latest_deployment?: PagesDeployment;
  source?: PagesSource;
}

/// 直接上传部署的一个待上传文件
export interface PagesDeployFile {
  /// 站点内路径，以 / 开头
  path: string;
  /// 文件内容
  data: ArrayBuffer;
  contentType: string;
}

/// 上传资源的元数据
export interface PagesAssetMetadata {
  contentType: string;
}

/// /pages/assets/upload 的单条负载（value 为 base64 文本）
export interface PagesAssetUpload {
  key: string;
  value: string;
  metadata: PagesAssetMetadata;
  base64: boolean;
}

/// 域名归属验证（zone 不在 Cloudflare 时 CF 会给一条 TXT 记录让你自证）
export interface PagesDomainValidation {
  method?: string;
  status?: string;
  txt_name?: string;
  txt_value?: string;
  error_message?: string;
}

/// 证书签发 / 校验状态
export interface PagesDomainVerification {
  status?: string;
  error_message?: string;
}

export interface PagesDomain {
  id: string;
  name: string;
  status?: string;
  /// 域名所在 zone（不在本账号时缺省，此时只能去域名服务商处配 CNAME）
  zone_tag?: string;
  validation_data?: PagesDomainValidation;
  verification_data?: PagesDomainVerification;
}
