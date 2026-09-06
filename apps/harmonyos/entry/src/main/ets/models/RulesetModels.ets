// Rulesets API 模型（WAF 自定义规则 / Cache Rules / Rate Limiting / Transform 共用）。
// 动作差异全在 action_parameters / ratelimit。

export interface UriRewriteValue {
  value?: string;
}

export interface UriRewrite {
  path?: UriRewriteValue;
  query?: UriRewriteValue;
}

export interface HeaderTransform {
  operation?: string; // set | remove
  value?: string;
}

export interface EdgeTTL {
  mode?: string; // override_origin | respect_origin | bypass_by_default
  default?: number;
  /// 按状态码的 TTL：App 不提供编辑，但编辑时原样保留，避免整量回写丢配置
  status_code_ttl?: object[];
}

/// 浏览器缓存 TTL（与边缘 TTL 同枚举）
export interface BrowserTTL {
  mode?: string;
  default?: number;
}

/// 重新验证时提供陈旧内容
export interface ServeStale {
  disable_stale_while_updating?: boolean;
}

/// 单条重定向 target_url：静态 value 与动态 expression 二选一
export interface RedirectTargetUrl {
  value?: string;
  expression?: string;
}

export interface RedirectFromValue {
  target_url?: RedirectTargetUrl;
  status_code?: number;
  preserve_query_string?: boolean;
}

/// 批量列表形态（from_list）的重定向规则只读，不在 App 内编辑
export interface RedirectFromList {
  key?: string;
  name?: string;
}

/// 源站规则 origin 覆写
export interface OriginOverride {
  host?: string;
  port?: number;
}

export interface SniOverride {
  value?: string;
}

/// 压缩规则算法项
export interface CompressionAlgorithm {
  name?: string;
}

export interface RuleActionParameters {
  uri?: UriRewrite;
  headers?: Record<string, HeaderTransform>;
  cache?: boolean;
  edge_ttl?: EdgeTTL;
  browser_ttl?: BrowserTTL;
  serve_stale?: ServeStale;
  respect_strong_etags?: boolean;
  origin_error_page_passthru?: boolean;
  // —— 仅用于「是否含高级设置」探测：App 不开放编辑，含这些设置的规则只读，
  // 免得整量回写把用户在控制台配的缓存键 / Cache Reserve / Vary 多版本缓存丢掉 ——
  cache_key?: object;
  cache_reserve?: object;
  read_timeout?: number;
  origin_cache_control?: boolean;
  additional_cacheable_ports?: number[];
  /// 2026-07-02 新增：按 Vary 响应头缓存多版本
  vary?: object;
  // —— 单条重定向（http_request_dynamic_redirect）——
  from_value?: RedirectFromValue;
  from_list?: RedirectFromList;
  // —— 源站规则（http_request_origin）——
  host_header?: string;
  origin?: OriginOverride;
  sni?: SniOverride;
  // —— 压缩规则（http_response_compression）——
  algorithms?: CompressionAlgorithm[];
  // —— 自定义错误（http_custom_errors）——
  content?: string;
  content_type?: string;
  status_code?: number;
  asset_name?: string;
  // —— 配置规则（http_config_settings）常用项，未建模字段编辑时以原对象为底保留 ——
  automatic_https_rewrites?: boolean;
  bic?: boolean;
  email_obfuscation?: boolean;
  rocket_loader?: boolean;
  opportunistic_encryption?: boolean;
  security_level?: string;
  ssl?: string;
  polish?: string;
}

export interface RateLimitConfig {
  characteristics?: string[];
  period?: number;
  requests_per_period?: number;
  mitigation_timeout?: number;
}

export interface RulesetRule {
  id: string;
  action?: string;
  expression?: string;
  description?: string;
  enabled?: boolean;
  last_updated?: string;
  action_parameters?: RuleActionParameters;
  ratelimit?: RateLimitConfig;
}

export interface Ruleset {
  id: string;
  name?: string;
  phase?: string;
  rules?: RulesetRule[];
}

export interface RulesetRuleCreate {
  action: string;
  expression: string;
  description?: string;
  enabled: boolean;
  action_parameters?: RuleActionParameters;
  ratelimit?: RateLimitConfig;
}

/// 含 App 未开放的高级设置 → 编辑器只读（status_code_ttl 不计入，编辑时原样保留）
export function cacheRuleHasAdvanced(params: RuleActionParameters | undefined): boolean {
  if (params === undefined) {
    return false;
  }
  return params.cache_key !== undefined || params.cache_reserve !== undefined
    || params.read_timeout !== undefined || params.origin_cache_control !== undefined
    || (params.additional_cacheable_ports !== undefined && params.additional_cacheable_ports.length > 0)
    || params.vary !== undefined;
}

/// Rulesets 各 phase 常量
export class RulesetPhases {
  static readonly WAF_CUSTOM = 'http_request_firewall_custom';
  static readonly CACHE_SETTINGS = 'http_request_cache_settings';
  static readonly RATE_LIMIT = 'http_ratelimit';
  static readonly TRANSFORM_URL = 'http_request_transform';
  static readonly TRANSFORM_REQ_HEADER = 'http_request_late_transform';
  static readonly TRANSFORM_RESP_HEADER = 'http_response_headers_transform';
  // 规则中心新增五个 phase（对照 iOS ZoneRulePhase）
  static readonly SINGLE_REDIRECT = 'http_request_dynamic_redirect';
  static readonly ORIGIN = 'http_request_origin';
  static readonly CONFIG = 'http_config_settings';
  static readonly COMPRESSION = 'http_response_compression';
  static readonly CUSTOM_ERRORS = 'http_custom_errors';
}

/// 规则中心 phase 元信息：固定 action 名 + OAuth scope（ID 对照 iOS ZoneRuleModels，已按 OpenAPI 核实）
export interface PhaseMeta {
  phase: string;
  title: string;
  action: string;
  readScope: string;
  writeScope: string;
}

const PHASE_METAS: PhaseMeta[] = [
  {
    phase: RulesetPhases.SINGLE_REDIRECT,
    title: '单条重定向',
    action: 'redirect',
    readScope: 'dynamic-redirect.read',
    writeScope: 'dynamic-redirect.write',
  },
  {
    phase: RulesetPhases.ORIGIN,
    title: '源站规则',
    action: 'route',
    readScope: 'origin.read',
    writeScope: 'origin.write',
  },
  {
    phase: RulesetPhases.CONFIG,
    title: '配置规则',
    action: 'set_config',
    readScope: 'config-settings.read',
    writeScope: 'config-settings.write',
  },
  {
    phase: RulesetPhases.COMPRESSION,
    title: '压缩规则',
    action: 'compress_response',
    readScope: 'response-compression.read',
    writeScope: 'response-compression.write',
  },
  {
    phase: RulesetPhases.CUSTOM_ERRORS,
    title: '自定义错误',
    action: 'serve_error',
    readScope: 'custom-errors.read',
    writeScope: 'custom-errors.write',
  },
];

export function phaseMeta(phase: string): PhaseMeta {
  for (const meta of PHASE_METAS) {
    if (meta.phase === phase) {
      return meta;
    }
  }
  return {
    phase: phase,
    title: '规则',
    action: '',
    readScope: '',
    writeScope: '',
  };
}

// —— Page Rules（传统 REST）——

export interface PageRuleConstraint {
  operator?: string;
  value?: string;
}

export interface PageRuleTarget {
  target?: string;
  constraint?: PageRuleConstraint;
}

/// 动作 value 形态繁杂且仅作摘要展示，只取 id
export interface PageRuleAction {
  id: string;
}

export interface PageRule {
  id: string;
  targets?: PageRuleTarget[];
  actions?: PageRuleAction[];
  priority?: number;
  status?: string; // active 或 disabled
}

export interface PageRuleStatusUpdate {
  status: string;
}

// —— URL Normalization ——

export interface UrlNormalizationSetting {
  type: string; // cloudflare 或 rfc3986
  scope: string; // incoming 或 both 或 none
}
