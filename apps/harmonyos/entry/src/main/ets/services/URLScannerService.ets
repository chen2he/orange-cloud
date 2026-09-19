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

  /// 提交扫描，返回 uuid。
  /// ⚠️ v2 全部端点都**不走 CF 标准信封**：POST /scan 2xx 直接回 { uuid, api, result(报告网址), … }，
  /// GET /result/{id} 2xx 直接回报告对象；按信封解，提交这一步就必失败（iOS/Android 同款问题已修）。
  /// 撞上近期已扫过的主机名回 409，未就绪回 404（ApiError.code 为 HTTP 状态码）。
  async submit(accountId: string, url: string): Promise<string> {
    const body: SubmitBody = { url: url };
    const res = await this.client.postBare<AcceptedResponse>(`/accounts/${accountId}/urlscanner/v2/scan`, body);
    return res.uuid ?? '';
  }

  /// 取报告。未就绪时接口 404，调用方按「继续轮询」处理。
  result(accountId: string, scanId: string): Promise<URLScanResult> {
    return this.client.getBare<URLScanResult>(`/accounts/${accountId}/urlscanner/v2/result/${scanId}`);
  }
}
