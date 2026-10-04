// 安全洞察（Security Center Insights）：全套餐可用，按需扫描域名的配置风险。
// 权限沿用 zone-settings.read / .write（Zone Settings Read / Write）。
//   - GET  /zones/{id}/security-center/insights?dismissed=false&page=&per_page=
//          → result { count, page, per_page, issues[] }（result 是对象，不是数组）
//   - POST /zones/{id}/security-center/insights/scans，体 {} = 全部扫描 → result { scan_id }
//          每个账户 24 小时最多 5 次（账户内共享），超限时直接透出 API 的错误消息
//   - PUT  /zones/{id}/security-center/insights/{issue_id}/dismiss，体 { dismiss: true }
// 响应里 severity 是首字母大写（Low / Moderate / Critical），比较一律转小写；未知枚举值不崩。
import { CFApiClient, apiClient } from '../core/network/CFApiClient';

export interface SecurityInsightPayload {
  detection_method?: string;
  zone_tag?: string;
}

export interface SecurityInsight {
  id: string;
  issue_type?: string;
  issue_class?: string;
  severity?: string;
  subject?: string;
  since?: string;
  timestamp?: string;
  status?: string;
  dismissed?: boolean;
  resolve_link?: string;
  resolve_text?: string;
  payload?: SecurityInsightPayload;
}

interface SecurityInsightsResult {
  count?: number;
  page?: number;
  per_page?: number;
  issues?: SecurityInsight[];
}

interface ScanResult {
  scan_id?: string;
}

interface DismissBody {
  dismiss: boolean;
}

/// 「扫描全部」的空请求体：序列化后就是 {}
class ScanAllBody {
}

const PAGE_SIZE = 50;

export class SecurityInsightsService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  /// 未忽略的洞察全量（按 count 翻页，最多 10 页兜底防死循环）
  async list(zoneId: string): Promise<SecurityInsight[]> {
    const all: SecurityInsight[] = [];
    for (let page = 1; page <= 10; page++) {
      const query: Record<string, string> = {
        'dismissed': 'false',
        'page': String(page),
        'per_page': String(PAGE_SIZE),
      };
      const result = await this.client.getObject<SecurityInsightsResult>(
        `/zones/${zoneId}/security-center/insights`, query);
      const issues = result.issues ?? [];
      for (const issue of issues) {
        all.push(issue);
      }
      const total = result.count ?? 0;
      if (issues.length < PAGE_SIZE || all.length >= total) {
        break;
      }
    }
    return all;
  }

  /// 发起一次全量扫描，返回 scan_id（可能为空串）
  async scan(zoneId: string): Promise<string> {
    const result = await this.client.postObject<ScanResult>(
      `/zones/${zoneId}/security-center/insights/scans`, new ScanAllBody());
    return result.scan_id ?? '';
  }

  /// 忽略一条洞察。成功回包不保证带 result，只校验信封 success。
  async dismiss(zoneId: string, issueId: string): Promise<void> {
    const body: DismissBody = { dismiss: true };
    await this.client.putRaw(`/zones/${zoneId}/security-center/insights/${issueId}/dismiss`,
      JSON.stringify(body), 'application/json');
  }
}
