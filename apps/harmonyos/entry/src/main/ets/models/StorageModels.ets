// R2 / D1 / KV 数据模型（对齐 Android StorageModels）。

export interface R2Bucket {
  name: string;
  creation_date?: string;
  location?: string;
}

/// R2 buckets 端点 result 是 { buckets: [...] } 包裹对象（不是数组），单独解包。
export interface R2BucketList {
  buckets?: R2Bucket[];
}

/// R2 对象 HTTP 元数据（camelCase，区别于信封字段的 snake_case）
export interface R2HttpMetadata {
  contentType?: string;
}

export interface R2Object {
  key: string;
  size?: number;
  uploaded?: string;
  etag?: string;
  last_modified?: string;
  http_metadata?: R2HttpMetadata;
  storage_class?: string;
}

/// R2 list 端点在传 delimiter=/ 时，result_info 里带游标 cursor + 折叠子前缀 delimited（即「文件夹」）。
export interface R2ListResultInfo {
  cursor?: string;
  is_truncated?: boolean;
  delimited?: string[];
}

/// 一页对象浏览结果：当前前缀下的对象 + 子文件夹前缀 + 下一页游标。
export interface R2ObjectPage {
  objects: R2Object[];
  folders: string[];
  cursor: string;
}

// ---- R2 桶设置（公开访问 r2.dev / 自定义域 / CORS；字段为 camelCase，对齐 iOS R2Service）----

/// 托管公开访问域（r2.dev）。GET/PUT domains/managed
export interface R2ManagedDomain {
  bucketId?: string;
  domain?: string;
  enabled?: boolean;
}

export interface R2ManagedDomainUpdate {
  enabled: boolean;
}

/// 自定义域列表。GET domains/custom 的 result 是 { domains: [...] } 包裹对象。
export interface R2CustomDomainList {
  domains?: R2CustomDomain[];
}

export interface R2CustomDomainStatus {
  ownership?: string;
  ssl?: string;
}

export interface R2CustomDomain {
  domain: string;
  enabled?: boolean;
  status?: R2CustomDomainStatus;
  minTLS?: string;
}

/// POST domains/custom 请求体（zoneId 必填，须为同账号下已接入 Cloudflare 的 zone）
export interface R2CustomDomainCreate {
  domain: string;
  zoneId: string;
  enabled: boolean;
}

/// 桶 CORS 策略。GET/PUT/DELETE cors；规则是整组替换（PUT 覆盖全集）。
export interface R2CorsAllowed {
  methods?: string[];
  origins?: string[];
  headers?: string[];
}

export interface R2CorsRule {
  id?: string;
  allowed?: R2CorsAllowed;
  exposeHeaders?: string[];
  maxAgeSeconds?: number;
}

export interface R2CorsPolicy {
  rules?: R2CorsRule[];
}

export interface D1Database {
  uuid: string;
  name: string;
  version?: string;
  num_tables?: number;
  file_size?: number;
}

export interface D1QueryMeta {
  duration?: number;
  rows_read?: number;
  rows_written?: number;
}

/// D1 query 返回 result 是数组，每项含 results（行数组）+ meta
export interface D1QueryResult {
  results?: Record<string, string>[];
  success?: boolean;
  meta?: D1QueryMeta;
}

export interface KVNamespace {
  id: string;
  title: string;
}

export interface KVKey {
  name: string;
  expiration?: number;
}

// ---- R2 对象预览类型判定（Preview Kit / 系统预览）----

/// 可交给系统 Preview Kit 打开的对象类别；纯文本仍走 App 内文本查看器。
export enum R2PreviewKind {
  TEXT = 0,   // 文本/JSON 等 → 保留 App 内文本查看
  MEDIA = 1,  // 图片/音视频/PDF/常见文档 → 下载到临时文件后系统预览
}

interface MimeEntry {
  ext: string;
  mime: string;
}

/// 常见可预览扩展名 → mimeType（Preview Kit 的 PreviewInfo.mimeType 必填）
const PREVIEWABLE_MIMES: MimeEntry[] = [
  { ext: 'jpg', mime: 'image/jpeg' },
  { ext: 'jpeg', mime: 'image/jpeg' },
  { ext: 'png', mime: 'image/png' },
  { ext: 'gif', mime: 'image/gif' },
  { ext: 'webp', mime: 'image/webp' },
  { ext: 'bmp', mime: 'image/bmp' },
  { ext: 'heic', mime: 'image/heic' },
  { ext: 'svg', mime: 'image/svg+xml' },
  { ext: 'pdf', mime: 'application/pdf' },
  { ext: 'mp4', mime: 'video/mp4' },
  { ext: 'mov', mime: 'video/quicktime' },
  { ext: 'm4v', mime: 'video/mp4' },
  { ext: 'mp3', mime: 'audio/mpeg' },
  { ext: 'wav', mime: 'audio/wav' },
  { ext: 'm4a', mime: 'audio/mp4' },
  { ext: 'aac', mime: 'audio/aac' },
  { ext: 'flac', mime: 'audio/flac' },
  { ext: 'ogg', mime: 'audio/ogg' },
  { ext: 'doc', mime: 'application/msword' },
  { ext: 'docx', mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' },
  { ext: 'xls', mime: 'application/vnd.ms-excel' },
  { ext: 'xlsx', mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' },
  { ext: 'ppt', mime: 'application/vnd.ms-powerpoint' },
  { ext: 'pptx', mime: 'application/vnd.openxmlformats-officedocument.presentationml.presentation' },
  { ext: 'txt', mime: 'text/plain' },
];

/// 视作文本、保留 App 内查看器的扩展名（不下载走系统预览）
const TEXT_EXTS: string[] = [
  'txt', 'json', 'js', 'ts', 'css', 'html', 'htm', 'xml', 'yaml', 'yml',
  'md', 'log', 'csv', 'ini', 'toml', 'sh', 'sql', 'env',
];

/// 从对象 key 取小写扩展名（无扩展返回 ''）
export function extOf(key: string): string {
  const slash = key.lastIndexOf('/');
  const leaf = slash >= 0 ? key.substring(slash + 1) : key;
  const dot = leaf.lastIndexOf('.');
  if (dot <= 0 || dot === leaf.length - 1) {
    return '';
  }
  return leaf.substring(dot + 1).toLowerCase();
}

/// 判定对象走哪种查看方式：文本类留 App 内，其余可预览类型交系统 Preview Kit。
export function previewKindOf(key: string): R2PreviewKind {
  const ext = extOf(key);
  if (ext === '' || TEXT_EXTS.includes(ext)) {
    return R2PreviewKind.TEXT;
  }
  for (const e of PREVIEWABLE_MIMES) {
    if (e.ext === ext) {
      return R2PreviewKind.MEDIA;
    }
  }
  // 未识别扩展：默认按文本尝试（getObjectText 已容错）
  return R2PreviewKind.TEXT;
}

/// 对象 key 对应的 mimeType（供 Preview Kit PreviewInfo）；未知回退 octet-stream。
export function mimeOf(key: string): string {
  const ext = extOf(key);
  for (const e of PREVIEWABLE_MIMES) {
    if (e.ext === ext) {
      return e.mime;
    }
  }
  return 'application/octet-stream';
}
