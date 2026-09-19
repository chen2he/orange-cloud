// 概览页「跨类型资源」的统一视图模型（对齐 iOS Core/Dashboard/DashboardResource + DashboardAlerts）：
// 把域名 / Workers / R2 / D1 / KV / Tunnel 归一成同一种可搜索、可固定、可跳转的条目，
// 供命令搜索面板、置顶区与告警中心共用。纯映射 / 纯函数，不发任何请求。
import { Zone, zoneDisplayStatus } from '../../models/Models';
import { WorkerScript } from '../../models/WorkerModels';
import { D1Database, KVNamespace, R2Bucket } from '../../models/StorageModels';
import { Tunnel } from '../../models/AccountModels';

/// 可固定 / 可搜索的资源类型（字符串进持久化，勿改）
export class ResKind {
  static readonly ZONE = 'zone';
  static readonly WORKER = 'worker';
  static readonly R2 = 'r2';
  static readonly D1 = 'd1';
  static readonly KV = 'kv';
  static readonly TUNNEL = 'tunnel';
}

/// 归一化的资源条目：搜索面板与置顶区共用一行的数据
export interface ResourceItem {
  kind: string;
  /// 资源在其类型内的稳定标识：zoneId / 脚本名 / 桶名 / d1 uuid / kv namespace id / tunnel id
  id: string;
  title: string;
  subtitle: string;
}

/// 告警严重度：数值越小越靠前
export class AlertLevel {
  static readonly CRITICAL = 0;
  static readonly WARN = 1;
  static readonly INFO = 2;
  static readonly OK = 3;
}

/// 一条告警。kind 为空表示无处可跳（如「还没有部署 Worker」）
export interface DashAlert {
  id: string;
  level: number;
  title: string;
  detail: string;
  kind: string;
  resourceId: string;
}

export function resKindLabel(kind: string): string {
  if (kind === ResKind.WORKER) {
    return 'Workers';
  }
  if (kind === ResKind.R2) {
    return 'R2';
  }
  if (kind === ResKind.D1) {
    return 'D1';
  }
  if (kind === ResKind.KV) {
    return 'KV';
  }
  if (kind === ResKind.TUNNEL) {
    return 'Tunnel';
  }
  return '域名';
}

export function resKindSymbol(kind: string): Resource {
  if (kind === ResKind.WORKER) {
    return $r('sys.symbol.bolt');
  }
  if (kind === ResKind.R2) {
    return $r('sys.symbol.archivebox');
  }
  if (kind === ResKind.D1) {
    return $r('sys.symbol.externaldrive');
  }
  if (kind === ResKind.KV) {
    return $r('sys.symbol.key');
  }
  if (kind === ResKind.TUNNEL) {
    return $r('sys.symbol.wifi_router');
  }
  return $r('sys.symbol.discover');
}

export function tunnelStatusText(status: string): string {
  if (status === 'healthy') {
    return '运行中';
  }
  if (status === 'degraded') {
    return '降级';
  }
  if (status === 'down') {
    return '已断开';
  }
  return '未连接';
}

function zoneStatusText(status: string): string {
  if (status === 'active') {
    return '已启用';
  }
  if (status === 'pending' || status === 'initializing') {
    return '待激活';
  }
  return '已暂停';
}

/// 套餐取首词（"Free Website" → "Free"），与域名卡口径一致
function planShort(planName: string): string {
  const parts = planName.split(' ');
  return parts.length > 0 && parts[0] !== '' ? parts[0] : planName;
}

/// 由各数据源拼出统一条目列表（纯映射，无网络）
export function buildResourceItems(zones: Zone[], workers: WorkerScript[], buckets: R2Bucket[],
  databases: D1Database[], namespaces: KVNamespace[], tunnels: Tunnel[]): ResourceItem[] {
  const items: ResourceItem[] = [];
  for (const zone of zones) {
    items.push({
      kind: ResKind.ZONE, id: zone.id, title: zone.name,
      subtitle: `${planShort(zone.plan?.name ?? '')} · ${zoneStatusText(zoneDisplayStatus(zone))}`,
    });
  }
  for (const script of workers) {
    items.push({
      kind: ResKind.WORKER, id: script.id, title: script.id,
      subtitle: (script.handlers ?? []).length > 0 ? (script.handlers ?? []).join(' · ') : 'Workers 脚本',
    });
  }
  for (const bucket of buckets) {
    items.push({
      kind: ResKind.R2, id: bucket.name, title: bucket.name,
      subtitle: bucket.location ?? 'R2 存储桶',
    });
  }
  for (const db of databases) {
    items.push({
      kind: ResKind.D1, id: db.uuid, title: db.name,
      subtitle: db.num_tables !== undefined ? `${db.num_tables} 张表` : 'D1 数据库',
    });
  }
  for (const ns of namespaces) {
    items.push({ kind: ResKind.KV, id: ns.id, title: ns.title, subtitle: ns.id });
  }
  for (const tunnel of tunnels) {
    items.push({
      kind: ResKind.TUNNEL, id: tunnel.id, title: tunnel.name,
      subtitle: tunnelStatusText(tunnel.status ?? ''),
    });
  }
  return items;
}

/// 大小写不敏感匹配标题或副标题
export function resourceMatches(item: ResourceItem, query: string): boolean {
  if (query === '') {
    return true;
  }
  const q = query.toLowerCase();
  return item.title.toLowerCase().includes(q) || item.subtitle.toLowerCase().includes(q);
}

/// 告警规则集：只用已经在手上的数据推导（域名 / Tunnel / Workers 计数），不额外发请求。
/// workerCount < 0 表示未知（无权限或仍在加载），此时不下「一个 Worker 都没有」的结论。
export function buildAlerts(zones: Zone[], tunnels: Tunnel[], workerCount: number,
  limit: number = 5): DashAlert[] {
  const alerts: DashAlert[] = [];
  // ① 未激活 / 已暂停的域名
  for (const zone of zones) {
    const display = zoneDisplayStatus(zone);
    if (display === 'active') {
      continue;
    }
    const pendingLike = zone.status === 'pending' || zone.status === 'initializing';
    let detail = `域名未处于启用状态（${zone.status}）`;
    if (zone.paused === true) {
      detail = '已暂停 Cloudflare，流量当前不经过代理';
    } else if (pendingLike) {
      detail = '域名待激活，检查域名服务器是否已指向 Cloudflare';
    }
    alerts.push({
      id: `zone|${zone.id}`,
      level: pendingLike ? AlertLevel.WARN : AlertLevel.CRITICAL,
      title: zone.name, detail: detail, kind: ResKind.ZONE, resourceId: zone.id,
    });
  }
  // ② 非 healthy 的 Tunnel
  for (const tunnel of tunnels) {
    const status = tunnel.status ?? '';
    if (status === 'healthy') {
      continue;
    }
    let level = AlertLevel.INFO;
    if (status === 'down') {
      level = AlertLevel.CRITICAL;
    } else if (status === 'degraded') {
      level = AlertLevel.WARN;
    }
    alerts.push({
      id: `tunnel|${tunnel.id}`, level: level, title: tunnel.name,
      detail: `隧道状态：${tunnelStatusText(status)}`, kind: ResKind.TUNNEL, resourceId: tunnel.id,
    });
  }
  // ③ 一个 Worker 都没有（有权限读到结果时才提示）
  if (workerCount === 0) {
    alerts.push({
      id: 'workers|empty', level: AlertLevel.INFO, title: '还没有部署 Worker',
      detail: '当前账号下没有 Workers 脚本', kind: '', resourceId: '',
    });
  }
  // 稳定排序：同级保持输入顺序
  const indexed = alerts.map((a: DashAlert, i: number): DashAlert => a);
  indexed.sort((a: DashAlert, b: DashAlert) => a.level - b.level);
  return indexed.slice(0, limit);
}

export function alertColor(level: number): string {
  if (level === AlertLevel.CRITICAL) {
    return '#DC2626';
  }
  if (level === AlertLevel.WARN) {
    return '#EA580C';
  }
  if (level === AlertLevel.INFO) {
    return '#2563EB';
  }
  return '#22C55E';
}
