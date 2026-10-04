import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// 安全洞察（Security Center Insights，全套餐可用）：按严重度分组列出域名的配置风险，
// 支持「立即扫描」「去处理」（打开控制台修复页）与逐条「忽略」。
// 读写走 zone-settings.read / .write；扫描每账户 24 小时最多 5 次，超限时透出 API 原文。
import { ZoneRouteParam } from '../../models/Routes';
import { SecurityInsight, SecurityInsightsService } from '../../services/SecurityInsightsService';
import { Scopes } from '../../core/auth/Scopes';
import { authManager } from '../../core/auth/AuthManager';
import { GlobalContext } from '../../core/system/GlobalContext';
import { OCEmpty, OCError, OCLoading, SectionHeader } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';

/// 严重度分组（顺序即展示顺序：严重 > 中等 > 低 > 未知）
interface SeverityGroup {
  key: string;
  title: string;
  color: string;
  items: SecurityInsight[];
}

const SEVERITY_ORDER: string[] = ['critical', 'moderate', 'low'];

function severityKey(raw: string | undefined): string {
  const key = (raw ?? '').toLowerCase();
  return SEVERITY_ORDER.includes(key) ? key : 'other';
}

function severityTitle(key: string): string {
  if (key === 'critical') {
    return '严重';
  }
  if (key === 'moderate') {
    return '中等';
  }
  if (key === 'low') {
    return '低';
  }
  return '其他';
}

function severityColor(key: string): string {
  if (key === 'critical') {
    return '#DC2626';
  }
  if (key === 'moderate') {
    return '#EA580C';
  }
  if (key === 'low') {
    return '#2563EB';
  }
  return '#757575';
}

/// issue_type → 中文类型名；未知类型退回 issue_class / 原值
function insightTypeLabel(insight: SecurityInsight): string {
  const type = insight.issue_type ?? '';
  if (type === 'compliance_violation') {
    return '合规问题';
  }
  if (type === 'email_security') {
    return '邮件安全';
  }
  if (type === 'exposed_infrastructure') {
    return '暴露的基础设施';
  }
  if (type === 'insecure_configuration') {
    return '不安全的配置';
  }
  if (type === 'weak_authentication') {
    return '弱身份验证';
  }
  if (type === 'configuration_suggestion') {
    return '配置建议';
  }
  const fallback = insight.issue_class ?? type;
  return fallback !== '' ? fallback : '安全问题';
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

/// since（date-time）→ yyyy-MM-dd；解析不了原样返回
function sinceText(since: string | undefined): string {
  const raw = since ?? '';
  if (raw === '') {
    return '';
  }
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) {
    return raw;
  }
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}`;
}

/// resolve_link 可能是控制台相对路径（/...），补全为 dash 地址
function resolveUrl(link: string): string {
  if (link.startsWith('/')) {
    return `https://dash.cloudflare.com${link}`;
  }
  return link;
}

/// 「去处理」按钮文案：优先用 API 给的 resolve_text
function resolveLabel(insight: SecurityInsight): string {
  const text = insight.resolve_text ?? '';
  return text !== '' ? text : '去处理';
}

@ObservedV2
class SecurityInsightsVM {
  @Trace groups: SeverityGroup[] = [];
  @Trace total: number = 0;
  @Trace isLoading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace error: string = '';
  @Trace isScanning: boolean = false;
  @Trace dismissingId: string = '';
  private service: SecurityInsightsService = new SecurityInsightsService();

  async load(zoneId: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      const issues = await this.service.list(zoneId);
      this.applyIssues(issues.filter((i: SecurityInsight) => i.dismissed !== true));
      this.loaded = true;
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  private applyIssues(issues: SecurityInsight[]): void {
    const groups: SeverityGroup[] = [];
    const keys: string[] = SEVERITY_ORDER.concat(['other']);
    for (const key of keys) {
      const items = issues.filter((i: SecurityInsight) => severityKey(i.severity) === key);
      if (items.length > 0) {
        groups.push({ key: key, title: severityTitle(key), color: severityColor(key), items: items });
      }
    }
    this.groups = groups;
    this.total = issues.length;
  }

  private allIssues(): SecurityInsight[] {
    const all: SecurityInsight[] = [];
    for (const g of this.groups) {
      for (const i of g.items) {
        all.push(i);
      }
    }
    return all;
  }

  /// 返回 '' 表示已发起；否则为错误消息（含 24 小时 5 次的限流提示原文）
  async scan(zoneId: string): Promise<string> {
    this.isScanning = true;
    try {
      await this.service.scan(zoneId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '扫描失败';
    } finally {
      this.isScanning = false;
    }
  }

  async dismiss(zoneId: string, insight: SecurityInsight): Promise<string> {
    this.dismissingId = insight.id;
    try {
      await this.service.dismiss(zoneId, insight.id);
      this.applyIssues(this.allIssues().filter((i: SecurityInsight) => i.id !== insight.id));
      return '';
    } catch (e) {
      return (e as Error).message ?? '操作失败';
    } finally {
      this.dismissingId = '';
    }
  }
}

@ComponentV2
export struct SecurityInsightsPage {
  @Local zoneId: string = '';
  @Local zoneName: string = '';
  @Local vm: SecurityInsightsVM = new SecurityInsightsVM();
  @Local refreshing: boolean = false;

  private toast(msg: string): void {
    if (msg !== '') {
      ocSnack(this.getUIContext(), msg);
    }
  }

  private canWrite(): boolean {
    if (!authManager.hasScope(Scopes.ZONE_SETTINGS_WRITE)) {
      this.toast(`当前授权未包含域名设置写入权限（${Scopes.ZONE_SETTINGS_WRITE}），可在「设置 → 身份」中升级授权`);
      return false;
    }
    return true;
  }

  private startScan(): void {
    if (this.vm.isScanning || !this.canWrite()) {
      return;
    }
    this.vm.scan(this.zoneId).then((err: string) => {
      this.toast(err === '' ? '已发起扫描，结果稍后更新' : err);
    });
  }

  private dismiss(insight: SecurityInsight): void {
    if (this.vm.dismissingId !== '' || !this.canWrite()) {
      return;
    }
    this.vm.dismiss(this.zoneId, insight).then((err: string) => {
      this.toast(err === '' ? '已忽略' : err);
    });
  }

  private openResolve(insight: SecurityInsight): void {
    const link = insight.resolve_link ?? '';
    if (link === '') {
      return;
    }
    try {
      GlobalContext.get().openLink(resolveUrl(link)).catch(() => {
      });
    } catch (e) {
    }
  }

  @Builder
  insightRow(insight: SecurityInsight, color: string) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(insightTypeLabel(insight))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(color)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(`#1A${color.replace('#', '')}`)
          .borderRadius(4)
        Blank()
        if (sinceText(insight.since) !== '') {
          Text(sinceText(insight.since))
            .fontSize(11)
            .fontColor($r('sys.color.font_tertiary'))
        }
      }
      .width('100%')

      Text(insight.subject ?? '')
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')

      Row({ space: 16 }) {
        if ((insight.resolve_link ?? '') !== '') {
          Text(resolveLabel(insight))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.oc_brand_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
            .onClick(() => {
              this.openResolve(insight);
            })
        }
        Blank()
        Text(this.vm.dismissingId === insight.id ? '正在忽略…' : '忽略')
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .onClick(() => {
            this.dismiss(insight);
          })
      }
      .width('100%')
      .margin({ top: 2 })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        Column() {
          if (this.vm.isLoading && !this.vm.loaded) {
            OCLoading({ text: '正在加载安全洞察…' })
          } else if (this.vm.error !== '' && !this.vm.loaded) {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load(this.zoneId).catch(() => {
                });
              },
            })
          } else {
            Refresh({ refreshing: this.refreshing }) {
              Scroll() {
                Column({ space: 4 }) {
                  if (this.vm.total === 0) {
                    Column({ space: 8 }) {
                      OCEmpty({ symbol: $r('sys.symbol.checkmark_shield'), title: '未发现安全问题' })
                    }
                    .width('100%')
                    .height(320)
                  } else {
                    ForEach(this.vm.groups, (group: SeverityGroup) => {
                      Column() {
                        SectionHeader({ title: `${group.title} · ${group.items.length}` })
                        Column() {
                          ForEach(group.items, (insight: SecurityInsight, index: number) => {
                            this.insightRow(insight, group.color)
                            if (index < group.items.length - 1) {
                              Divider()
                                .strokeWidth(0.5)
                                .color($r('sys.color.comp_divider'))
                                .margin({ left: 14 })
                            }
                          }, (insight: SecurityInsight) => insight.id)
                        }
                        .backgroundColor($r('sys.color.comp_background_list_card'))
                        .borderRadius(14)
                        .clip(true)
                        .margin({ left: 16, right: 16 })
                      }
                      .width('100%')
                    }, (group: SeverityGroup) => `${group.key}-${group.items.length}`)
                  }

                  Text('每个账户每 24 小时最多扫描 5 次')
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                    .width('100%')
                    .padding({ left: 20, right: 20, top: 12 })
                }
                .width('100%')
                .padding({ top: 8, bottom: 24 })
              }
              .align(Alignment.Top)
              .scrollBar(BarState.Off)
              .width('100%')
              .height('100%')
            }
            .onRefreshing(() => {
              this.refreshing = true;
              this.vm.load(this.zoneId).then(() => {
                this.refreshing = false;
              }).catch(() => {
                this.refreshing = false;
              });
            })
            .layoutWeight(1)
          }
        }
        .width('100%')
        .height('100%')
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
    }
    .titleBar({
      style: { systemMaterialEffect: systemMaterial() },
      content: {
        title: { mainTitle: '安全洞察', subTitle: this.zoneName },
        menu: {
          value: [{
            content: {
              icon: $r('sys.symbol.arrow_2_circlepath'),
              label: this.vm.isScanning ? '正在扫描…' : '立即扫描',
              action: () => {
                this.startScan();
              },
            },
          }],
        },
      },
    })
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as ZoneRouteParam;
      this.zoneId = param.zoneId;
      this.zoneName = param.zoneName;
      this.vm.load(param.zoneId).catch(() => {
      });
    })
  }
}
