import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// 独立健康检查：源站是否在线（/zones/{id}/healthchecks，healthcheck.read/.write）。
// 与负载均衡的监控器不同源——LB monitor 只在负载均衡语境生效，这里独立监控单个源站。
// 移动端定位是「看状态 + 临时干预」，创建检查字段多、属桌面场景，暂不提供。
import { ZoneRouteParam } from '../../models/Routes';
import { HealthCheck, HealthCheckService } from '../../services/HealthCheckService';
import { Scopes } from '../../core/auth/Scopes';
import { authManager } from '../../core/auth/AuthManager';
import { OCLoading, SectionHeader } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';
import { promptAction } from '@kit.ArkUI';

function statusLabel(status: string): string {
  if (status === 'healthy') {
    return '正常';
  }
  if (status === 'unhealthy') {
    return '异常';
  }
  if (status === 'suspended') {
    return '已暂停';
  }
  return '未知';
}

function statusColor(status: string): string {
  if (status === 'healthy') {
    return '#2E7D32';
  }
  if (status === 'unhealthy') {
    return '#C62828';
  }
  if (status === 'suspended') {
    return '#757575';
  }
  return '#EF6C00';
}

@ObservedV2
class HealthCheckVM {
  @Trace checks: HealthCheck[] = [];
  @Trace isLoading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace isMutating: boolean = false;
  private service: HealthCheckService = new HealthCheckService();

  /// 异常的排在前面——进页第一眼就该看到出问题的源站
  private sorted(items: HealthCheck[]): HealthCheck[] {
    const rank = (c: HealthCheck): number => {
      const s = displayStatus(c);
      if (s === 'unhealthy') {
        return 0;
      }
      if (s === 'unknown') {
        return 1;
      }
      if (s === 'healthy') {
        return 2;
      }
      return 3;
    };
    return items.sort((a: HealthCheck, b: HealthCheck) => rank(a) - rank(b));
  }

  async load(zoneId: string): Promise<void> {
    this.isLoading = true;
    try {
      this.checks = this.sorted(await this.service.list(zoneId));
      this.loaded = true;
    } catch (e) {
    } finally {
      this.isLoading = false;
    }
  }

  async setSuspended(zoneId: string, check: HealthCheck, suspended: boolean): Promise<string> {
    this.isMutating = true;
    try {
      await this.service.setSuspended(zoneId, check.id, suspended);
      await this.load(zoneId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '操作失败';
    } finally {
      this.isMutating = false;
    }
  }

  async remove(zoneId: string, check: HealthCheck): Promise<string> {
    this.isMutating = true;
    try {
      await this.service.remove(zoneId, check.id);
      this.checks = this.checks.filter((c: HealthCheck) => c.id !== check.id);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    } finally {
      this.isMutating = false;
    }
  }
}

/// 暂停优先于 status——暂停时 CF 不再探测，status 会停在最后一次结果上，直接显示会误导
export function displayStatus(check: HealthCheck): string {
  if (check.suspended === true) {
    return 'suspended';
  }
  if (check.status === 'healthy') {
    return 'healthy';
  }
  if (check.status === 'unhealthy') {
    return 'unhealthy';
  }
  return 'unknown';
}

@ComponentV2
export struct HealthCheckPage {
  @Local zoneId: string = '';
  @Local zoneName: string = '';
  @Local vm: HealthCheckVM = new HealthCheckVM();
  private pathStack: NavPathStack | null = null;
  private canWrite: boolean = authManager.hasScope(Scopes.HEALTHCHECK_WRITE);

  private toast(msg: string): void {
    if (msg !== '') {
      ocSnack(this.getUIContext(), msg);
    }
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        Column() {
          if (this.vm.isLoading && !this.vm.loaded) {
            OCLoading()
          } else if (this.vm.checks.length === 0) {
            Column({ space: 8 }) {
              Text('此域名暂无健康检查')
                .fontSize(15)
                .fontColor($r('sys.color.font_primary'))
              Text('可在 Cloudflare 控制台创建后回到这里查看与暂停。')
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .padding(32)
          } else {
            Scroll() {
              Column({ space: 4 }) {
                Column() {
                  SectionHeader({ title: `源站监控（${this.zoneName}）` })
                  Column({ space: 10 }) {
                    ForEach(this.vm.checks, (check: HealthCheck) => {
                      Column({ space: 4 }) {
                        Row() {
                          Text(check.name)
                            .fontSize(15)
                            .fontWeight(FontWeight.Medium)
                            .fontColor($r('sys.color.font_primary'))
                            .layoutWeight(1)
                          Text(statusLabel(displayStatus(check)))
                            .fontSize(13)
                            .fontWeight(FontWeight.Medium)
                            .fontColor(statusColor(displayStatus(check)))
                        }
                        .width('100%')

                        if (check.address !== undefined) {
                          Text(check.address)
                            .fontSize(12)
                            .fontColor($r('sys.color.font_secondary'))
                            .width('100%')
                        }
                        // 只在真的异常时显示原因，避免正常态也占一行
                        if (displayStatus(check) === 'unhealthy' && (check.failure_reason ?? '') !== '') {
                          Text(check.failure_reason)
                            .fontSize(12)
                            .fontColor('#C62828')
                            .width('100%')
                        }
                        if (this.canWrite) {
                          Row({ space: 14 }) {
                            Text(check.suspended === true ? '恢复' : '暂停')
                              .fontSize(13)
                              .fontColor($r('sys.color.font_secondary'))
                              .onClick(() => {
                                if (this.vm.isMutating) {
                                  return;
                                }
                                this.vm.setSuspended(this.zoneId, check, check.suspended !== true)
                                  .then((err: string) => this.toast(err));
                              })
                            Text('删除')
                              .fontSize(13)
                              .fontColor('#C62828')
                              .onClick(() => {
                                if (this.vm.isMutating) {
                                  return;
                                }
                                this.confirmDelete(check);
                              })
                          }
                          .width('100%')
                          .margin({ top: 2 })
                        }
                      }
                      .width('100%')
                      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                    }, (check: HealthCheck) => check.id)
                  }
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(14)
                  .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                  .clip(true)
                  .margin({ left: 16, right: 16 })
                }
                .width('100%')
              }
              .width('100%')
              .padding({ top: 8, bottom: 24 })
            }
            .layoutWeight(1)
          }
        }
        .width('100%')
        .height('100%')
      }
    }
    .titleBar({ content: { title: { mainTitle: '健康检查' } } })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as ZoneRouteParam;
      this.zoneId = param.zoneId;
      this.zoneName = param.zoneName;
      this.vm.load(param.zoneId).catch(() => {
      });
    })
  }

  private confirmDelete(check: HealthCheck): void {
    promptAction.showDialog({
      title: '删除健康检查',
      message: `删除「${check.name}」后将不再监控该源站，也不会再收到相关通知。不可撤销。`,
      buttons: [{ text: '取消', color: '#666666' }, { text: '删除', color: '#C62828' }],
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        this.vm.remove(this.zoneId, check).then((err: string) => this.toast(err));
      }
    }).catch(() => {
    });
  }
}
