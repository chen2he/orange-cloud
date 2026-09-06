// Turnstile 人机验证组件（账号级 /accounts/{id}/challenges/widgets，
// OAuth scope challenge-widgets.read / .write）。对齐 iOS TurnstileService。
//
// 端点与字段以 api-schemas OpenAPI 为准（2026-08 核对）：
// · widget 主键是 sitekey；secret 仅 list/get/create/rotate 响应携带
// · mode 枚举：managed / non-interactive / invisible
// · domains 最多 10 条（主机名或 IP，含子域生效）；空数组 = 允许任意主机名
// · region（world / china）创建后不可改；offlabel / ephemeral_id 是 ENT 专属，
//   只透传显示、不提供编辑（免费/付费账号写它必 403）
import { CFApiClient, apiClient } from '../core/network/CFApiClient';

export interface TurnstileWidget {
  sitekey: string;
  name: string;
  mode: string;
  domains?: string[];
  /// 服务端校验用密钥。出于最小暴露，详情页默认遮蔽、点按显示/复制。
  secret?: string;
  bot_fight_mode?: boolean;
  clearance_level?: string;
  region?: string;
  offlabel?: boolean;
  ephemeral_id?: boolean;
  created_on?: string;
  modified_on?: string;
}

/// 创建 / 更新载荷（PUT 必填 name + mode + domains；bot_fight_mode / clearance_level
/// 显式带上，避免整量 PUT 丢配置）
export interface TurnstileWidgetInput {
  name: string;
  mode: string;
  domains: string[];
  bot_fight_mode?: boolean;
  /// 仅创建时有效（world / china），创建后不可改
  region?: string;
  clearance_level?: string;
}

interface RotateBody {
  invalidate_immediately: boolean;
}

/// 模式清障强度递增：invisible（无感）→ non-interactive（可见不点选）→ managed（必要时勾选）
export const TURNSTILE_MODES: string[] = ['managed', 'non-interactive', 'invisible'];

export function turnstileModeLabel(mode: string): string {
  if (mode === 'non-interactive') {
    return '非交互';
  }
  if (mode === 'invisible') {
    return '隐形';
  }
  return '托管（推荐）';
}

export function turnstileModeDetail(mode: string): string {
  if (mode === 'non-interactive') {
    return '显示验证进度但不需要访客操作';
  }
  if (mode === 'invisible') {
    return '完全不可见，静默完成验证';
  }
  return '由 Cloudflare 判断是否要求访客勾选复选框';
}

export class TurnstileService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  /// 账号下全部 widget（页码分页，最多兜 10 页防跑飞）
  async list(accountId: string): Promise<TurnstileWidget[]> {
    let widgets: TurnstileWidget[] = [];
    let page = 1;
    while (page <= 10) {
      const envelope = await this.client.getListEnvelope<TurnstileWidget>(
        `/accounts/${accountId}/challenges/widgets`,
        { 'page': `${page}`, 'per_page': '50' } as Record<string, string>);
      widgets = widgets.concat(envelope.result ?? []);
      const totalPages = envelope.result_info?.total_pages ?? 1;
      if (page >= totalPages) {
        break;
      }
      page += 1;
    }
    return widgets;
  }

  /// 单个 widget 详情（响应含 secret）
  detail(accountId: string, sitekey: string): Promise<TurnstileWidget> {
    return this.client.getObject<TurnstileWidget>(`/accounts/${accountId}/challenges/widgets/${sitekey}`);
  }

  /// 新建（响应含 sitekey + secret）
  create(accountId: string, input: TurnstileWidgetInput): Promise<TurnstileWidget> {
    return this.client.postObject<TurnstileWidget>(`/accounts/${accountId}/challenges/widgets`, input);
  }

  /// 更新（PUT 全量：name / mode / domains 必填）
  update(accountId: string, sitekey: string, input: TurnstileWidgetInput): Promise<TurnstileWidget> {
    return this.client.putObject<TurnstileWidget>(
      `/accounts/${accountId}/challenges/widgets/${sitekey}`, input);
  }

  remove(accountId: string, sitekey: string): Promise<void> {
    return this.client.delete(`/accounts/${accountId}/challenges/widgets/${sitekey}`);
  }

  /// 轮换服务端密钥。immediately = false 时旧密钥保留 2 小时宽限期。
  rotateSecret(accountId: string, sitekey: string, immediately: boolean): Promise<TurnstileWidget> {
    const body: RotateBody = { invalidate_immediately: immediately };
    return this.client.postObject<TurnstileWidget>(
      `/accounts/${accountId}/challenges/widgets/${sitekey}/rotate_secret`, body);
  }
}
