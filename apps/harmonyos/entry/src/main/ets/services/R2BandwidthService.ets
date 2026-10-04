// R2 带宽（GraphQL r2BandwidthUsageAdaptiveGroups，account-analytics.read）。
// 最长查 31 天，这里取近 30 天；小于 100 KiB 的传输不计入（数据集口径）。
// 区域限制桶在该数据集里的 bucketName 带区域前缀：`eu_bucket-name`（R2 文档原文格式）。
// 账户级数据集未授权 / 账号没开 R2 时调用方整块隐藏，不报错。
import { CFApiClient, apiClient, ApiError } from '../core/network/CFApiClient';
import { r2JurisdictionHeader } from '../models/StorageModels';

export interface R2Bandwidth {
  uploadBytes: number;
  downloadBytes: number;
}

interface BandwidthSum {
  bytesUpload?: number;
  bytesDownload?: number;
}

interface BandwidthGroup {
  sum?: BandwidthSum;
}

interface BandwidthAccountNode {
  bandwidth?: BandwidthGroup[];
}

interface BandwidthViewer {
  accounts?: BandwidthAccountNode[];
}

interface BandwidthData {
  viewer?: BandwidthViewer;
}

interface BandwidthGQLError {
  message: string;
}

interface BandwidthResponse {
  data?: BandwidthData;
  errors?: BandwidthGQLError[];
}

interface AccountVariables {
  accountTag: string;
  since: string;
  until: string;
}

interface BucketVariables {
  accountTag: string;
  since: string;
  until: string;
  bucketName: string;
}

const ACCOUNT_QUERY = `query ($accountTag: string!, $since: Time!, $until: Time!) {
  viewer { accounts(filter: { accountTag: $accountTag }) {
    bandwidth: r2BandwidthUsageAdaptiveGroups(limit: 100,
      filter: { datetime_geq: $since, datetime_lt: $until }) {
      sum { bytesUpload bytesDownload }
      dimensions { date }
    } } } }`;

const BUCKET_QUERY = `query ($accountTag: string!, $since: Time!, $until: Time!, $bucketName: string!) {
  viewer { accounts(filter: { accountTag: $accountTag }) {
    bandwidth: r2BandwidthUsageAdaptiveGroups(limit: 100,
      filter: { datetime_geq: $since, datetime_lt: $until, bucketName: $bucketName }) {
      sum { bytesUpload bytesDownload }
      dimensions { date }
    } } } }`;

const WINDOW_DAYS = 30;

function isoSeconds(date: Date): string {
  return `${date.toISOString().substring(0, 19)}Z`;
}

/// 数据集里的桶名：区域桶加 `区域_` 前缀
export function r2AnalyticsBucketName(name: string, jurisdiction: string): string {
  const j = r2JurisdictionHeader(jurisdiction);
  return j === '' ? name : `${j}_${name}`;
}

export class R2BandwidthService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  /// 近 30 天上传 / 下载合计。bucketName 为空 = 全账号
  async last30Days(accountId: string, bucketName: string, jurisdiction: string): Promise<R2Bandwidth> {
    const until = new Date();
    const since = new Date(until.getTime() - WINDOW_DAYS * 24 * 3600 * 1000);
    let text = '';
    if (bucketName === '') {
      const variables: AccountVariables = { accountTag: accountId, since: isoSeconds(since), until: isoSeconds(until) };
      text = await this.client.graphql(ACCOUNT_QUERY, variables);
    } else {
      const variables: BucketVariables = {
        accountTag: accountId,
        since: isoSeconds(since),
        until: isoSeconds(until),
        bucketName: r2AnalyticsBucketName(bucketName, jurisdiction),
      };
      text = await this.client.graphql(BUCKET_QUERY, variables);
    }
    const response = JSON.parse(text) as BandwidthResponse;
    const accounts = response.data?.viewer?.accounts ?? [];
    let upload = 0;
    let download = 0;
    let groups = 0;
    for (const node of accounts) {
      for (const group of node.bandwidth ?? []) {
        groups++;
        upload += group.sum?.bytesUpload ?? 0;
        download += group.sum?.bytesDownload ?? 0;
      }
    }
    // 有错误且一行数据都没有（authz / 数据集不可用）→ 抛给调用方隐藏；没错误的空结果就是 0 流量
    if (groups === 0 && response.errors && response.errors.length > 0) {
      throw new ApiError(response.errors[0].message);
    }
    return { uploadBytes: upload, downloadBytes: download };
  }
}
