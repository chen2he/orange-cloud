import { HdsNavDestination } from '@kit.UIDesignKit';
// Cloudflare 官方状态页（cloudflarestatus.com 公开 API）：总体状态 → 进行中的事件 →
// 计划维护 → 产品服务 → 边缘网络（按大区汇总）→ 最近事件历史。事件点按看更新时间线（sheet）。
import {
  IncidentUpdate,
  StatusComponent,
  StatusIncident,
  StatusSummary,
} from '../../models/AccountModels';
import { AccountModuleService } from '../../services/AccountModuleService';
import { formatTimeAgo } from '../../core/util/Format';
import { OCError, OCLoading, SectionHeader } from '../common/Components';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';

const CF_SERVICE_GROUP = 'Cloudflare Sites and Services';

// ---- 颜色 ----
function overallColor(indicator: string): string {
  switch (indicator) {
    case 'none':
      return '#22C55E';
    case 'minor':
      return '#EAB308';
    case 'major':
      return '#F5A623';
    case 'critical':
      return '#DC2626';
    case 'maintenance':
      return '#3B82F6';
    default:
      return '#22C55E';
  }
}

function overallText(indicator: string, description: string): string {
  switch (indicator) {
    case 'none':
      return '所有系统正常运行';
    case 'minor':
      return '部分服务轻微异常';
    case 'major':
      return '部分服务严重异常';
    case 'critical':
      return '重大服务中断';
    case 'maintenance':
      return '维护进行中';
    default:
      return description !== '' ? description : '未知';
  }
}

function componentColor(status: string): string {
  switch (status) {
    case 'operational':
      return '#22C55E';
    case 'degraded_performance':
    case 'under_maintenance':
      return '#F5A623';
    case 'partial_outage':
      return '#F5A623';
    case 'major_outage':
      return '#DC2626';
    default:
      return '#9CA3AF';
  }
}

function componentText(status: string): string {
  switch (status) {
    case 'operational':
      return '运行正常';
    case 'degraded_performance':
      return '性能下降';
    case 'partial_outage':
      return '部分中断';
    case 'major_outage':
      return '严重中断';
    case 'under_maintenance':
      return '维护中';
    default:
      return status;
  }
}

function incidentStatusText(status: string): string {
  switch (status) {
    case 'investigating':
      return '调查中';
    case 'identified':
      return '已定位';
    case 'monitoring':
      return '监控中';
    case 'resolved':
      return '已解决';
    case 'postmortem':
      return '事后分析';
    case 'scheduled':
      return '已排期';
    case 'in_progress':
      return '进行中';
    case 'verifying':
      return '验证中';
    case 'completed':
      return '已完成';
    default:
      return status;
  }
}

function impactColor(impact: string): string {
  switch (impact) {
    case 'critical':
      return '#DC2626';
    case 'major':
      return '#F5A623';
    case 'minor':
      return '#EAB308';
    case 'maintenance':
      return '#3B82F6';
    default:
      return '#9CA3AF';
  }
}

interface StatusRegion {
  id: string;
  name: string;
  impacted: number;
}

function regionLocalizedName(name: string): string {
  switch (name) {
    case 'Africa':
      return '非洲';
    case 'Asia':
      return '亚洲';
    case 'Europe':
      return '欧洲';
    case 'Latin America & the Caribbean':
      return '拉丁美洲和加勒比';
    case 'Middle East':
      return '中东';
    case 'North America':
      return '北美';
    case 'Oceania':
      return '大洋洲';
    default:
      return name;
  }
}

@ObservedV2
class StatusVM {
  @Trace overallIndicator: string = '';
  @Trace overallDescription: string = '';
  @Trace activeIncidents: StatusIncident[] = [];
  @Trace maintenances: StatusIncident[] = [];
  @Trace affectedProducts: StatusComponent[] = [];
  @Trace productTotal: number = 0;
  @Trace regions: StatusRegion[] = [];
  @Trace recentIncidents: StatusIncident[] = [];
  @Trace hasSummary: boolean = false;
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  private service: AccountModuleService = new AccountModuleService();

  async load(): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      const summary: StatusSummary = await this.service.statusSummary();
      this.overallIndicator = summary.status?.indicator ?? summary.status?.status ?? '';
      this.overallDescription = summary.status?.description ?? '';
      this.activeIncidents = summary.incidents ?? [];
      this.maintenances = summary.scheduled_maintenances ?? [];
      this.splitComponents(summary.components ?? []);
      this.hasSummary = true;

      try {
        const history = await this.service.statusIncidents();
        const activeIds = new Set(this.activeIncidents.map((i: StatusIncident) => i.id ?? ''));
        this.recentIncidents = history
          .filter((i: StatusIncident) => !activeIds.has(i.id ?? ''))
          .slice(0, 10);
      } catch (e) {
        this.recentIncidents = [];
      }
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  /// 组件拆成「产品服务」与「边缘网络大区」；找不到服务分组时兜底列异常叶子。
  private splitComponents(components: StatusComponent[]): void {
    const serviceGroup = components.find(
      (c: StatusComponent) => c.group === true && c.name === CF_SERVICE_GROUP);
    if (serviceGroup === undefined) {
      const leaves = components.filter((c: StatusComponent) => c.group !== true);
      this.productTotal = leaves.length;
      this.affectedProducts = leaves.filter((c: StatusComponent) => c.status !== 'operational');
      this.regions = [];
      return;
    }
    const products = components.filter((c: StatusComponent) => c.group_id === serviceGroup.id);
    this.productTotal = products.length;
    this.affectedProducts = products.filter((c: StatusComponent) => c.status !== 'operational');
    this.regions = components
      .filter((c: StatusComponent) => c.group === true && c.id !== serviceGroup.id)
      .map((group: StatusComponent): StatusRegion => {
        const nodes = components.filter((c: StatusComponent) => c.group_id === group.id);
        const impacted = nodes.filter((c: StatusComponent) => c.status !== 'operational').length;
        return { id: group.id, name: group.name, impacted: impacted };
      });
  }
}

@ComponentV2
export struct StatusPage {
  @Local vm: StatusVM = new StatusVM();
  @Local detailVisible: boolean = false;
  @Local detailIncident: StatusIncident | null = null;

  private openDetail(incident: StatusIncident): void {
    this.detailIncident = incident;
    this.detailVisible = true;
  }

  @Builder
  incidentRow(incident: StatusIncident) {
    Column({ space: 3 }) {
      Text(incident.name ?? '')
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row({ space: 6 }) {
        Text(incidentStatusText(incident.status ?? ''))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(impactColor(incident.impact ?? ''))
        Text(formatTimeAgo(incident.updated_at ?? incident.created_at ?? ''))
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .onClick(() => {
      this.openDetail(incident);
    })
  }

  @Builder
  detailSheet() {
    Scroll() {
      Column({ space: 4 }) {
        Text(this.detailIncident?.name ?? '')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .padding({ left: 20, right: 20, top: 8 })
        Row({ space: 8 }) {
          Circle({ width: 8, height: 8 })
            .fill(impactColor(this.detailIncident?.impact ?? ''))
          Text(incidentStatusText(this.detailIncident?.status ?? ''))
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 8 })

        SectionHeader({ title: '更新记录' })
        Column() {
          ForEach(this.detailIncident?.incident_updates ?? [], (update: IncidentUpdate) => {
            Column({ space: 4 }) {
              Row() {
                Text(incidentStatusText(update.status ?? ''))
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.oc_brand_text'))
                Blank()
                Text(formatTimeAgo(update.display_at ?? ''))
                  .fontSize(11)
                  .fontColor($r('sys.color.font_secondary'))
              }
              .width('100%')
              Text(update.body ?? '')
                .fontSize(13)
                .fontColor($r('sys.color.font_primary'))
                .width('100%')
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          }, (update: IncidentUpdate, index: number) => `${index}`)
        }
        .backgroundColor($r('sys.color.comp_background_list_card'))
        .borderRadius(14)
        .border({ width: 0.5, color: $r('sys.color.comp_divider') })
        .clip(true)
        .margin({ left: 16, right: 16 })
      }
      .width('100%')
      .padding({ bottom: 24 })
    }
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .width('100%')
    .height('100%')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading && !this.vm.hasSummary) {
          Column() {
            OCLoading({ text: '正在查询 Cloudflare 状态…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '' && !this.vm.hasSummary) {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load().catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else {
          Scroll() {
            Column({ space: 4 }) {
              // ── 总体状态 ──
              Row({ space: 12 }) {
                Circle({ width: 14, height: 14 })
                  .fill(overallColor(this.vm.overallIndicator))
                Text(overallText(this.vm.overallIndicator, this.vm.overallDescription))
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
              }
              .width('100%')
              .padding(16)
              .backgroundColor($r('sys.color.comp_background_list_card'))
              .borderRadius(14)
              .border({ width: 0.5, color: $r('sys.color.comp_divider') })
              .margin({ left: 16, right: 16, top: 12 })

              // ── 进行中的事件 ──
              if (this.vm.activeIncidents.length > 0) {
                SectionHeader({ title: '进行中的事件' })
                Column() {
                  ForEach(this.vm.activeIncidents, (incident: StatusIncident) => {
                    this.incidentRow(incident)
                  }, (incident: StatusIncident, index: number) => incident.id ?? `${index}`)
                }
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(14)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .clip(true)
                .margin({ left: 16, right: 16 })
              }

              // ── 计划维护 ──
              if (this.vm.maintenances.length > 0) {
                SectionHeader({ title: '计划维护' })
                Column() {
                  ForEach(this.vm.maintenances, (incident: StatusIncident) => {
                    this.incidentRow(incident)
                  }, (incident: StatusIncident, index: number) => incident.id ?? `${index}`)
                }
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(14)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .clip(true)
                .margin({ left: 16, right: 16 })
              }

              // ── 产品服务 ──
              SectionHeader({ title: '产品服务' })
              Column() {
                if (this.vm.affectedProducts.length === 0) {
                  Row({ space: 12 }) {
                    Circle({ width: 8, height: 8 })
                      .fill('#22C55E')
                    Text(`${this.vm.productTotal} 项全部正常`)
                      .fontSize(13)
                      .fontColor($r('sys.color.font_secondary'))
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                } else {
                  ForEach(this.vm.affectedProducts, (component: StatusComponent) => {
                    Row({ space: 10 }) {
                      Circle({ width: 8, height: 8 })
                        .fill(componentColor(component.status))
                      Text(component.name)
                        .fontSize(13)
                        .fontColor($r('sys.color.font_primary'))
                        .layoutWeight(1)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(componentText(component.status))
                        .fontSize(11)
                        .fontColor($r('sys.color.font_secondary'))
                    }
                    .width('100%')
                    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                  }, (component: StatusComponent) => component.id)
                }
              }
              .backgroundColor($r('sys.color.comp_background_list_card'))
              .borderRadius(14)
              .border({ width: 0.5, color: $r('sys.color.comp_divider') })
              .clip(true)
              .margin({ left: 16, right: 16 })

              // ── 边缘网络 ──
              if (this.vm.regions.length > 0) {
                SectionHeader({ title: '边缘网络' })
                Column() {
                  ForEach(this.vm.regions, (region: StatusRegion) => {
                    Row({ space: 10 }) {
                      Circle({ width: 8, height: 8 })
                        .fill(region.impacted === 0 ? '#22C55E' : '#F5A623')
                      Text(regionLocalizedName(region.name))
                        .fontSize(13)
                        .fontColor($r('sys.color.font_primary'))
                        .layoutWeight(1)
                      Text(region.impacted === 0 ? '全部正常' : `${region.impacted} 个节点异常`)
                        .fontSize(11)
                        .fontColor(region.impacted === 0 ? $r('sys.color.font_secondary') : '#F5A623')
                    }
                    .width('100%')
                    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                  }, (region: StatusRegion) => region.id)
                }
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(14)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .clip(true)
                .margin({ left: 16, right: 16 })
              }

              // ── 最近事件 ──
              if (this.vm.recentIncidents.length > 0) {
                SectionHeader({ title: '最近事件' })
                Column() {
                  ForEach(this.vm.recentIncidents, (incident: StatusIncident) => {
                    this.incidentRow(incident)
                  }, (incident: StatusIncident, index: number) => incident.id ?? `${index}`)
                }
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(14)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .clip(true)
                .margin({ left: 16, right: 16, bottom: 24 })
              } else {
                Text('近期无事件报告')
                  .fontSize(13)
                  .fontColor($r('sys.color.font_secondary'))
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding({ top: 16, bottom: 24 })
              }
            }
            .width('100%')
          }
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
          .width('100%')
          .height('100%')
        }
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({ content: { title: { mainTitle: 'Cloudflare 状态' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.detailVisible, this.detailSheet(), ocSheet(() => {
      this.detailVisible = false;
    }))
    .onReady(() => {
      this.vm.load().catch(() => {
      });
    })
  }
}
