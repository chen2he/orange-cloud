// 「书写规则」可视化表达式构建器（生成 Cloudflare Rules 表达式）。
// 逐行移植自 iOS Models/WAFModels.swift（WAFExpressionCatalog / WAFOperator / WAFExpressionBuilder）
// 与 Core/Intelligence/WAFIntelligence.swift 的 WAFExpressionLint。纯函数，无副作用。

export enum RuleValueType {
  string,
  ip,
  number,
  country,
  // 布尔字段（如 cf.bot_management.verified_bot）：值裸写 true/false，不加引号
  bool,
}

export interface RuleField {
  key: string;
  label: string;
  type: RuleValueType;
}

// curated 常用字段集（key 为表达式字段名）
export const RULE_FIELDS: RuleField[] = [
  { key: 'http.host', label: '主机名', type: RuleValueType.string },
  { key: 'http.request.uri.path', label: 'URI 路径', type: RuleValueType.string },
  { key: 'http.request.uri.query', label: '查询字符串', type: RuleValueType.string },
  { key: 'http.request.full_uri', label: '完整 URL', type: RuleValueType.string },
  { key: 'http.request.method', label: '请求方法', type: RuleValueType.string },
  { key: 'http.user_agent', label: 'User-Agent', type: RuleValueType.string },
  { key: 'http.referer', label: 'Referer', type: RuleValueType.string },
  { key: 'http.cookie', label: 'Cookie', type: RuleValueType.string },
  { key: 'http.request.version', label: 'HTTP 版本', type: RuleValueType.string },
  { key: 'ip.src', label: '来源 IP', type: RuleValueType.ip },
  { key: 'ip.src.country', label: '来源国家', type: RuleValueType.country },
  { key: 'ip.src.asnum', label: 'ASN', type: RuleValueType.number },
  { key: 'cf.threat_score', label: '威胁分数', type: RuleValueType.number },
  { key: 'cf.bot_management.score', label: 'Bot 分数', type: RuleValueType.number },
  { key: 'cf.bot_management.verified_bot', label: '已验证机器人', type: RuleValueType.bool },
  // 2026-08 起缓存规则等 phase 也支持按 TLS 指纹匹配（需 Bot Management 订阅）
  { key: 'cf.bot_management.ja3_hash', label: 'JA3 指纹', type: RuleValueType.string },
  { key: 'cf.bot_management.ja4', label: 'JA4 指纹', type: RuleValueType.string },
];

export interface RuleOperator {
  token: string;
  label: string;
}

// token 为 CF 表达式里的实际运算符（in 是关键字）
export function ruleOperators(type: RuleValueType): RuleOperator[] {
  switch (type) {
    case RuleValueType.string:
      return [
        { token: 'eq', label: '等于' },
        { token: 'ne', label: '不等于' },
        { token: 'contains', label: '包含' },
        { token: 'matches', label: '匹配正则' },
        { token: 'in', label: '属于集合' },
      ];
    case RuleValueType.ip:
      return [
        { token: 'eq', label: '等于' },
        { token: 'ne', label: '不等于' },
        { token: 'in', label: '属于集合' },
      ];
    case RuleValueType.number:
      return [
        { token: 'eq', label: '等于' },
        { token: 'ne', label: '不等于' },
        { token: 'gt', label: '大于' },
        { token: 'ge', label: '大于等于' },
        { token: 'lt', label: '小于' },
        { token: 'le', label: '小于等于' },
      ];
    case RuleValueType.country:
      return [
        { token: 'eq', label: '等于' },
        { token: 'ne', label: '不等于' },
        { token: 'in', label: '属于集合' },
      ];
    case RuleValueType.bool:
      return [
        { token: 'eq', label: '等于' },
        { token: 'ne', label: '不等于' },
      ];
    default:
      return [];
  }
}

export interface RuleCondition {
  fieldKey: string;
  opToken: string;
  value: string;
}

function fieldType(key: string): RuleValueType {
  for (let i = 0; i < RULE_FIELDS.length; i++) {
    if (RULE_FIELDS[i].key === key) {
      return RULE_FIELDS[i].type;
    }
  }
  return RuleValueType.string;
}

// 字符串/国家码加双引号并转义内部引号；IP/数值裸写。
function quote(value: string, type: RuleValueType): string {
  if (type === RuleValueType.ip || type === RuleValueType.number) {
    return value;
  }
  // 布尔只认裸 true/false，其余输入归一到 false，避免写出 `... eq "yes"` 这种 CF 会拒的表达式
  if (type === RuleValueType.bool) {
    return value.trim().toLowerCase() === 'true' ? 'true' : 'false';
  }
  const escaped = value.replace(/"/g, '\\"');
  return `"${escaped}"`;
}

// 单条件 → 表达式片段；值为空返回空串（忽略未填完的行）。
export function compileCondition(c: RuleCondition): string {
  const trimmed = c.value.trim();
  if (trimmed === '') {
    return '';
  }
  const type = fieldType(c.fieldKey);

  if (c.opToken === 'in') {
    const items = trimmed
      .split(/[\s,\n]+/)
      .map((s: string): string => s.trim())
      .filter((s: string): boolean => s !== '');
    if (items.length === 0) {
      return '';
    }
    const set = items.map((s: string): string => quote(s, type)).join(' ');
    return `${c.fieldKey} in {${set}}`;
  }
  return `${c.fieldKey} ${c.opToken} ${quote(trimmed, type)}`;
}

// 多条件按逻辑（'and'|'or'）连接；两条以上时每条加括号，避免优先级歧义。
export function compileExpression(logic: string, conds: RuleCondition[]): string {
  const parts = conds
    .map((c: RuleCondition): string => compileCondition(c))
    .filter((s: string): boolean => s !== '');
  if (parts.length === 0) {
    return '';
  }
  if (parts.length === 1) {
    return parts[0];
  }
  const joiner = logic === 'or' ? ' or ' : ' and ';
  return parts.map((p: string): string => `(${p})`).join(joiner);
}

// 结构 lint：括号 / 双引号是否配平（字符串感知：引号内不计括号，\" 不切换引号态）。
// 空表达式允许（返回空串）。返回本地化错误或空串。
export function lintExpression(expr: string): string {
  const trimmed = expr.trim();
  if (trimmed === '') {
    return '';
  }
  let inString = false;
  let escaped = false;
  let depth = 0;
  for (let i = 0; i < trimmed.length; i++) {
    const ch = trimmed.charAt(i);
    if (escaped) {
      escaped = false;
      continue;
    }
    if (ch === '\\') {
      escaped = true;
      continue;
    }
    if (ch === '"') {
      inString = !inString;
      continue;
    }
    if (inString) {
      continue;
    }
    if (ch === '(') {
      depth += 1;
    }
    if (ch === ')') {
      depth -= 1;
      if (depth < 0) {
        return '括号不匹配';
      }
    }
  }
  if (inString) {
    return '引号不匹配';
  }
  if (depth !== 0) {
    return '括号不匹配';
  }
  return '';
}
