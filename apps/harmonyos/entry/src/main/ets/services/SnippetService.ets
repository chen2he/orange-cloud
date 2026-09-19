// Snippets（zone 级边缘 JS）：列表 / 正文 / 上传（multipart）/ 删除 / 规则整组 PUT。
// 规则响应 result 形态不固定（裸数组 / {rules:[…]} / {}），容错解码（对齐 iOS SnippetRulesResult）。
import { CFApiClient, MultipartPart, apiClient } from '../core/network/CFApiClient';

export interface Snippet {
  snippet_name: string;
  created_on?: string;
  modified_on?: string;
}

export interface SnippetRule {
  expression: string;
  snippet_name: string;
  enabled?: boolean;
  description?: string;
}

interface SnippetRulesWrapped {
  rules?: SnippetRule[];
}

interface SnippetRulesEnvelope {
  success?: boolean;
  result?: object;
}

interface SnippetRulesPut {
  rules: SnippetRule[];
}

interface SnippetMetadata {
  main_module: string;
}

export class SnippetService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  list(zoneId: string): Promise<Snippet[]> {
    return this.client.getList<Snippet>(`/zones/${zoneId}/snippets`);
  }

  content(zoneId: string, name: string): Promise<string> {
    return this.client.getRaw(`/zones/${zoneId}/snippets/${name}/content`);
  }

  /// 创建/更新：metadata main_module + JS 模块 part（application/javascript+module）
  async upload(zoneId: string, name: string, code: string): Promise<void> {
    const parts: MultipartPart[] = [
      {
        name: 'files',
        filename: 'main.js',
        contentType: 'application/javascript+module',
        data: code,
      },
      {
        name: 'metadata',
        contentType: 'application/json',
        data: JSON.stringify({ main_module: 'main.js' } as SnippetMetadata),
      },
    ];
    await this.client.putMultipartObject<object>(`/zones/${zoneId}/snippets/${name}`, parts);
  }

  remove(zoneId: string, name: string): Promise<void> {
    return this.client.delete(`/zones/${zoneId}/snippets/${name}`);
  }

  /// 规则列表（容错三种 result 形态）
  async rules(zoneId: string): Promise<SnippetRule[]> {
    try {
      const raw = await this.client.getRaw(`/zones/${zoneId}/snippets/snippet_rules`);
      const envelope = JSON.parse(raw) as SnippetRulesEnvelope;
      const result = envelope.result;
      if (result === undefined || result === null) {
        return [];
      }
      if (Array.isArray(result)) {
        return result as SnippetRule[];
      }
      const wrapped = result as SnippetRulesWrapped;
      return wrapped.rules ?? [];
    } catch (e) {
      return [];
    }
  }

  /// 规则是整组 PUT：改任一条都要回写全集（漏传即删）
  async putRules(zoneId: string, rules: SnippetRule[]): Promise<void> {
    const body: SnippetRulesPut = { rules: rules };
    await this.client.putObject<object>(`/zones/${zoneId}/snippets/snippet_rules`, body);
  }
}
