// 账号用量（总览页「用量」宫格）模型：账号级 GraphQL 各产品数据集 → 归一化聚合。
// 对齐 iOS Models/AccountUsageModels.swift。数据集走 viewer.accounts 根，
// 按计费周期窗口（今日 + 周期起点→现在）聚合每个产品的关键指标。
//
// 铁律：所有解码 JSON 显式接口（arkts-no-untyped-obj-literals）。

/// GraphQL 错误项（含 authz 判定用的 extensions.code）
export interface UsageGQLExtensions {
  code?: string;
}

export interface UsageGQLError {
  message: string;
  extensions?: UsageGQLExtensions;
}

/// 账户级数据集未授权：CF 用同一 authz 码兼指「token 无权限」与「计划未开通该数据集」
export function isAuthzError(err: UsageGQLError): boolean {
  return err.extensions?.code === 'authz' || err.message === 'not authorized for that account';
}

// MARK: - 通用响应壳

export interface UsageSumRequests {
  requests?: number;
}

// MARK: - Workers 调用（requests / errors + CPU）

export interface WorkersUsageSum {
  requests?: number;
  errors?: number;
  subrequests?: number;
}

export interface WorkersUsageGroup {
  sum?: WorkersUsageSum;
}

export interface WorkersCpuSum {
  cpuTimeUs?: number;
}

export interface WorkersCpuGroup {
  sum?: WorkersCpuSum;
}

export interface AccountUsageNode {
  month?: WorkersUsageGroup[];
  today?: WorkersUsageGroup[];
}

export interface WorkersCpuNode {
  month?: WorkersCpuGroup[];
  today?: WorkersCpuGroup[];
}

export interface WorkersCpuViewer {
  accounts?: WorkersCpuNode[];
}
export interface WorkersCpuDataWrap {
  viewer?: WorkersCpuViewer;
}
export interface WorkersCpuResponse {
  data?: WorkersCpuDataWrap;
  errors?: UsageGQLError[];
}

// MARK: - R2 操作分类 + 存储

export interface R2OpsDimensions {
  actionType?: string;
  bucketName?: string;
}

export interface R2OpsGroup {
  dimensions?: R2OpsDimensions;
  sum?: UsageSumRequests;
}

export interface R2StorageMax {
  payloadSize?: number;
  metadataSize?: number;
  objectCount?: number;
}

export interface R2StorageDimensions {
  bucketName?: string;
}

export interface R2StorageGroup {
  dimensions?: R2StorageDimensions;
  max?: R2StorageMax;
}

export interface R2UsageNode {
  r2Ops?: R2OpsGroup[];
  r2Storage?: R2StorageGroup[];
}

// MARK: - D1 行读写

export interface D1UsageSum {
  rowsRead?: number;
  rowsWritten?: number;
}

export interface D1UsageGroup {
  sum?: D1UsageSum;
}

export interface D1UsageNode {
  period?: D1UsageGroup[];
  today?: D1UsageGroup[];
}

// MARK: - KV 操作 + 存储

export interface KVOpsDimensions {
  actionType?: string; // "read" | "write" | "delete" | "list"
}

export interface KVOpsGroup {
  dimensions?: KVOpsDimensions;
  sum?: UsageSumRequests;
}

export interface KVStorageMax {
  byteCount?: number;
  keyCount?: number;
}

export interface KVStorageGroup {
  max?: KVStorageMax;
}

export interface KVUsageNode {
  period?: KVOpsGroup[];
  today?: KVOpsGroup[];
  storage?: KVStorageGroup[];
}

// MARK: - 各查询的 viewer/data 壳（每种查询独立）

export interface AccountUsageViewer {
  accounts?: AccountUsageNode[];
}
export interface AccountUsageData {
  viewer?: AccountUsageViewer;
}
export interface AccountUsageResponse {
  data?: AccountUsageData;
  errors?: UsageGQLError[];
}

export interface R2UsageViewer {
  accounts?: R2UsageNode[];
}
export interface R2UsageData {
  viewer?: R2UsageViewer;
}
export interface R2UsageResponse {
  data?: R2UsageData;
  errors?: UsageGQLError[];
}

export interface D1UsageViewer {
  accounts?: D1UsageNode[];
}
export interface D1UsageData {
  viewer?: D1UsageViewer;
}
export interface D1UsageResponse {
  data?: D1UsageData;
  errors?: UsageGQLError[];
}

export interface KVUsageViewer {
  accounts?: KVUsageNode[];
}
export interface KVUsageData {
  viewer?: KVUsageViewer;
}
export interface KVUsageResponse {
  data?: KVUsageData;
  errors?: UsageGQLError[];
}

// MARK: - 聚合子结构

export interface D1Usage {
  rowsReadToday: number;
  rowsWrittenToday: number;
  rowsReadPeriod: number;
  rowsWrittenPeriod: number;
}

export interface KVUsage {
  readsToday: number;
  writesToday: number;
  readsPeriod: number;
  writesPeriod: number;
}

/// 账号用量聚合结果（对齐 iOS AccountUsage）。可空字段在对应产品无数据/无权限时省略对应卡片。
export interface AccountUsage {
  workersRequestsToday: number;
  workersRequestsMonth: number;
  cpuTimeMonthUs?: number;
  cpuTimeTodayUs?: number;
  r2ClassAMonth: number;
  r2ClassBMonth: number;
  r2StorageBytes: number;
  r2ObjectCount: number;
  d1Usage?: D1Usage;
  kvUsage?: KVUsage;
  kvStorageBytes?: number;
}

/// R2 操作分类（来自 R2 计价文档）——A/B 类计费，其余（Delete 等）免费不计。
export class R2OperationClass {
  static readonly classA: string[] = [
    'ListBuckets', 'PutBucket', 'ListObjects', 'PutObject', 'CopyObject',
    'CompleteMultipartUpload', 'CreateMultipartUpload', 'UploadPart',
    'UploadPartCopy', 'ListMultipartUploads', 'ListParts',
    'PutBucketEncryption', 'PutBucketCors', 'PutBucketLifecycleConfiguration',
    'LifecycleStorageTierTransition',
  ];

  static readonly classB: string[] = [
    'HeadBucket', 'HeadObject', 'GetObject', 'UsageSummary',
    'GetBucketEncryption', 'GetBucketLocation', 'GetBucketCors',
    'GetBucketLifecycleConfiguration',
  ];
}
