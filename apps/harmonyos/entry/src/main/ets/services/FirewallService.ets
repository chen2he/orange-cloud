// IP 访问规则（legacy firewall access rules）。
// configuration（target+value）创建后不可改，编辑仅改 mode + notes（对齐 Android FirewallRepository）。
import { CFApiClient, apiClient } from '../core/network/CFApiClient';

export interface AccessRuleConfig {
  target?: string; // ip | ip_range | country | asn
  value?: string;
}

export interface FirewallAccessRule {
  id: string;
  mode?: string; // block | challenge | whitelist | js_challenge | managed_challenge
  configuration?: AccessRuleConfig;
  notes?: string;
}

interface AccessRuleConfigInput {
  target: string;
  value: string;
}

interface AccessRuleCreate {
  mode: string;
  configuration: AccessRuleConfigInput;
  notes?: string;
}

interface AccessRuleUpdate {
  mode: string;
  notes?: string;
}

export class FirewallService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  list(zoneId: string): Promise<FirewallAccessRule[]> {
    return this.client.getList<FirewallAccessRule>(`/zones/${zoneId}/firewall/access_rules/rules`, {
      'per_page': '100',
    } as Record<string, string>);
  }

  create(zoneId: string, mode: string, target: string, value: string, notes: string): Promise<FirewallAccessRule> {
    const body: AccessRuleCreate = {
      mode: mode,
      configuration: { target: target, value: value } as AccessRuleConfigInput,
      notes: notes === '' ? undefined : notes,
    };
    return this.client.postObject<FirewallAccessRule>(`/zones/${zoneId}/firewall/access_rules/rules`, body);
  }

  update(zoneId: string, ruleId: string, mode: string, notes: string): Promise<FirewallAccessRule> {
    const body: AccessRuleUpdate = { mode: mode, notes: notes === '' ? undefined : notes };
    return this.client.patchObject<FirewallAccessRule>(`/zones/${zoneId}/firewall/access_rules/rules/${ruleId}`, body);
  }

  remove(zoneId: string, ruleId: string): Promise<void> {
    return this.client.delete(`/zones/${zoneId}/firewall/access_rules/rules/${ruleId}`);
  }
}
