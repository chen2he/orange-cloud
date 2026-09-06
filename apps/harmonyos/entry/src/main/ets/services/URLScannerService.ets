// Cloudflare URL Scanner（**v2**，别用 v1）。url-scanner.read / .write
// 扫描是异步的：提交后返回 uuid，结果需轮询，未就绪时接口 404。
import { CFApiClient, apiClient } from '../core/network/CFApiClient';

export interface URLScanCategory {
  id?: number;
  name?: string;
}

export interface URLScanVerdict {
  malicious?: boolean;
  categories?: URLScanCategory[];
}

export interface URLScanVerdicts {
  overall?: URLScanVerdict;
}

export interface URLScanPage {
  url?: string;
  domain?: string;
  ip?: string;
  country?: string;
  asn?: string;
  asnname?: string;
  server?: string;
  statusCode?: number;
}

export interface URLScanTask {
  uuid?: string;
  url?: string;
  effectiveUrl?: string;
  status?: string;
}

export interface URLScanResult {
  task?: URLScanTask;
  page?: URLScanPage;
  verdicts?: URLScanVerdicts;
}

interface SubmitBody {
  url: string;
}

interface AcceptedResponse {
  uuid?: string;
  result?: string;
}

export class URLScannerService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  /// 提交扫描，返回 uuid（不同版本可能落在 uuid 或 result 字段）
  async submit(accountId: string, url: string): Promise<string> {
    const body: SubmitBody = { url: url };
    const res = await this.client.postObject<AcceptedResponse>(`/accounts/${accountId}/urlscanner/v2/scan`, body);
    return res.uuid ?? res.result ?? '';
  }

  /// 取报告。未就绪时接口 404，调用方按「继续轮询」处理。
  result(accountId: string, scanId: string): Promise<URLScanResult> {
    return this.client.getObject<URLScanResult>(`/accounts/${accountId}/urlscanner/v2/result/${scanId}`);
  }
}
