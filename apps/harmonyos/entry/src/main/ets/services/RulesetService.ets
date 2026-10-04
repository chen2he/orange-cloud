// Rulesets entrypoint 通用 Service（WAF / Cache Rules / Rate Limiting / Transform 共用）。
// phase 还没有规则集时 entrypoint 返回 404/业务错误 → 返回 null，由首条规则 PUT 创建。
import {
  PageRule,
  PageRuleStatusUpdate,
  Ruleset,
  RulesetRuleCreate,
  UrlNormalizationSetting,
} from '../models/RulesetModels';
import { CFApiClient, apiClient } from '../core/network/CFApiClient';

interface RuleToggle {
  enabled: boolean;
}

interface EntrypointUpdate {
  rules: RulesetRuleCreate[];
}

export class RulesetService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  /// 取某 phase 的 entrypoint ruleset；无规则集时返回 null
  async entrypoint(zoneId: string, phase: string): Promise<Ruleset | null> {
    try {
      return await this.client.getObject<Ruleset>(`/zones/${zoneId}/rulesets/phases/${phase}/entrypoint`);
    } catch (e) {
      return null;
    }
  }

  toggleRule(zoneId: string, rulesetId: string, ruleId: string, enabled: boolean): Promise<Ruleset> {
    const body: RuleToggle = { enabled: enabled };
    return this.client.patchObject<Ruleset>(`/zones/${zoneId}/rulesets/${rulesetId}/rules/${ruleId}`, body);
  }

  createRule(zoneId: string, rulesetId: string, rule: RulesetRuleCreate): Promise<Ruleset> {
    return this.client.postObject<Ruleset>(`/zones/${zoneId}/rulesets/${rulesetId}/rules`, rule);
  }

  updateRule(zoneId: string, rulesetId: string, ruleId: string, rule: RulesetRuleCreate): Promise<Ruleset> {
    return this.client.patchObject<Ruleset>(`/zones/${zoneId}/rulesets/${rulesetId}/rules/${ruleId}`, rule);
  }

  /// phase 还没有规则集时，用首条规则创建 entrypoint
  createEntrypoint(zoneId: string, phase: string, rule: RulesetRuleCreate): Promise<Ruleset> {
    const body: EntrypointUpdate = { rules: [rule] };
    return this.client.putObject<Ruleset>(`/zones/${zoneId}/rulesets/phases/${phase}/entrypoint`, body);
  }

  deleteRule(zoneId: string, rulesetId: string, ruleId: string): Promise<void> {
    return this.client.delete(`/zones/${zoneId}/rulesets/${rulesetId}/rules/${ruleId}`);
  }

  /// 规则校验（?dry_run=true）：发与保存完全相同的请求，只校验不落库，成功时 result 为 null。
  /// 编辑 → PATCH 规则；新建 → POST 到规则集；还没有规则集 → PUT entrypoint
  async validateRule(zoneId: string, phase: string, rulesetId: string, ruleId: string,
    rule: RulesetRuleCreate): Promise<void> {
    if (ruleId !== '' && rulesetId !== '') {
      await this.client.patchVoid(`/zones/${zoneId}/rulesets/${rulesetId}/rules/${ruleId}?dry_run=true`, rule);
    } else if (rulesetId !== '') {
      await this.client.postVoid(`/zones/${zoneId}/rulesets/${rulesetId}/rules?dry_run=true`, rule);
    } else {
      const body: EntrypointUpdate = { rules: [rule] };
      await this.client.putRaw(`/zones/${zoneId}/rulesets/phases/${phase}/entrypoint?dry_run=true`,
        JSON.stringify(body), 'application/json');
    }
  }

  // —— Page Rules（传统 REST，仅列表 / 启停 / 删除）——

  listPageRules(zoneId: string): Promise<PageRule[]> {
    return this.client.getList<PageRule>(`/zones/${zoneId}/pagerules`);
  }

  setPageRuleStatus(zoneId: string, ruleId: string, active: boolean): Promise<PageRule> {
    const body: PageRuleStatusUpdate = { status: active ? 'active' : 'disabled' };
    return this.client.patchObject<PageRule>(`/zones/${zoneId}/pagerules/${ruleId}`, body);
  }

  deletePageRule(zoneId: string, ruleId: string): Promise<void> {
    return this.client.delete(`/zones/${zoneId}/pagerules/${ruleId}`);
  }

  // —— URL Normalization（单一设置对象 GET 与 PUT）——

  getUrlNormalization(zoneId: string): Promise<UrlNormalizationSetting> {
    return this.client.getObject<UrlNormalizationSetting>(`/zones/${zoneId}/url_normalization`);
  }

  setUrlNormalization(zoneId: string, value: UrlNormalizationSetting): Promise<UrlNormalizationSetting> {
    return this.client.putObject<UrlNormalizationSetting>(`/zones/${zoneId}/url_normalization`, value);
  }
}

/// 通用 ViewModel 基座：各 phase 页面复用列表 + 启停 + 删除逻辑
@ObservedV2
export class RulesetVM {
  @Trace ruleset: Ruleset | null = null;
  @Trace isLoading: boolean = false;
  @Trace isSaving: boolean = false;
  @Trace error: string = '';
  @Trace saveError: string = '';
  @Trace isValidating: boolean = false;

  private service: RulesetService = new RulesetService();
  private phase: string;

  constructor(phase: string) {
    this.phase = phase;
  }

  async load(zoneId: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.ruleset = await this.service.entrypoint(zoneId, this.phase);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async toggle(zoneId: string, ruleId: string, enabled: boolean): Promise<string> {
    const rulesetId = this.ruleset?.id ?? '';
    if (rulesetId === '') {
      return '规则集不存在';
    }
    try {
      this.ruleset = await this.service.toggleRule(zoneId, rulesetId, ruleId, enabled);
      return '';
    } catch (e) {
      return (e as Error).message ?? '操作失败';
    }
  }

  /// 新建或更新（ruleId 空 = 新建；无规则集时首条走 PUT entrypoint）
  async save(zoneId: string, ruleId: string, rule: RulesetRuleCreate): Promise<boolean> {
    this.isSaving = true;
    this.saveError = '';
    try {
      const rulesetId = this.ruleset?.id ?? '';
      if (ruleId !== '' && rulesetId !== '') {
        this.ruleset = await this.service.updateRule(zoneId, rulesetId, ruleId, rule);
      } else if (rulesetId !== '') {
        this.ruleset = await this.service.createRule(zoneId, rulesetId, rule);
      } else {
        this.ruleset = await this.service.createEntrypoint(zoneId, this.phase, rule);
      }
      return true;
    } catch (e) {
      this.saveError = (e as Error).message ?? '保存失败';
      return false;
    } finally {
      this.isSaving = false;
    }
  }

  /// 校验（dry_run）：返回 '' = 通过，否则为 API 错误消息。不改动列表与保存流程
  async validate(zoneId: string, ruleId: string, rule: RulesetRuleCreate): Promise<string> {
    this.isValidating = true;
    try {
      await this.service.validateRule(zoneId, this.phase, this.ruleset?.id ?? '', ruleId, rule);
      return '';
    } catch (e) {
      return (e as Error).message ?? '校验失败';
    } finally {
      this.isValidating = false;
    }
  }

  async remove(zoneId: string, ruleId: string): Promise<string> {
    const rulesetId = this.ruleset?.id ?? '';
    if (rulesetId === '') {
      return '规则集不存在';
    }
    try {
      await this.service.deleteRule(zoneId, rulesetId, ruleId);
      await this.load(zoneId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}
