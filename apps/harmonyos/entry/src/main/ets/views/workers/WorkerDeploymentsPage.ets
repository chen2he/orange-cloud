import { HdsNavDestination } from '@kit.UIDesignKit';
// Worker 部署历史（对照 iOS WorkerDeploymentsView）：列表 + 删除。
// 列表首项为当前活跃部署，Cloudflare 拒绝删除活跃部署，故活跃项不给删除入口。
import { NameParam } from '../../models/Routes';
import { WorkerDeployment } from '../../models/WorkerModels';
import { WorkerService } from '../../services/WorkerService';
import { accountStore } from '../../core/store/AccountStore';
import { authManager } from '../../core/auth/AuthManager';
import { Scopes } from '../../core/auth/Scopes';
import { formatTimeAgo } from '../../core/util/Format';
import { BRAND_ORANGE, BRAND_ORANGE_BG, DANGER_RED, OCEmpty, OCLoading } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';
import { OCLayout } from '../common/Daybreak';

@ObservedV2
class DeploymentsVM {
  @Trace deployments: WorkerDeployment[] = [];
  @Trace isLoading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace error: string = '';

  private service: WorkerService = new WorkerService();

  async load(accountId: string, scriptName: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.deployments = await this.service.listDeployments(accountId, scriptName);
      this.loaded = true;
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async remove(accountId: string, scriptName: string, deploymentId: string): Promise<string> {
    try {
      await this.service.deleteDeployment(accountId, scriptName, deploymentId);
      this.deployments = this.deployments.filter((d: WorkerDeployment) => d.id !== deploymentId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}

@ComponentV2
export struct WorkerDeploymentsPage {
  @Local vm: DeploymentsVM = new DeploymentsVM();
  @Local scriptName: string = '';
  @Local refreshing: boolean = false;

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  /// 部署标题：优先用部署留言，没有就用短 ID
  private title(deployment: WorkerDeployment): string {
    if (deployment.annotations !== undefined) {
      const message = deployment.annotations['workers/message'] ?? '';
      if (message !== '') {
        return message;
      }
    }
    return `部署 ${deployment.id.substring(0, 8)}`;
  }

  private subtitle(deployment: WorkerDeployment): string {
    const parts: string[] = [];
    if ((deployment.source ?? '') !== '') {
      parts.push(deployment.source ?? '');
    }
    if ((deployment.author_email ?? '') !== '') {
      parts.push(deployment.author_email ?? '');
    }
    if ((deployment.created_on ?? '') !== '') {
      parts.push(formatTimeAgo(deployment.created_on ?? ''));
    }
    return parts.join(' · ');
  }

  @Builder
  deploymentRow(deployment: WorkerDeployment, isActive: boolean) {
    Row({ space: 8 }) {
      Column({ space: 3 }) {
        Row({ space: 6 }) {
          Text(this.title(deployment))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (isActive) {
            Text('活跃')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.oc_brand_text'))
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .backgroundColor($r('app.color.oc_brand_bg'))
              .borderRadius(8)
          }
        }
        .width('100%')
        Text(this.subtitle(deployment))
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .gesture(LongPressGesture().onAction(() => {
      if (isActive) {
        // Cloudflare 会拒绝删除活跃部署，提前说清楚而不是让用户吃一个服务端报错
        this.toast('当前活跃部署不可删除');
        return;
      }
      if (!authManager.hasScope(Scopes.WORKERS_WRITE)) {
        this.toast('当前授权未包含 Workers 写权限（workers-scripts.write）');
        return;
      }
      this.getUIContext().showAlertDialog({
        title: '删除部署',
        message: `将删除 ${this.title(deployment)}，历史记录不可恢复。`,
        primaryButton: { value: '取消', action: () => {
        } },
        secondaryButton: {
          value: '删除',
          fontColor: DANGER_RED,
          action: () => {
            this.vm.remove(accountStore.selectedId, this.scriptName, deployment.id).then((err: string) => {
              this.toast(err === '' ? '已删除' : err);
            });
          },
        },
      });
    }))
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading && !this.vm.loaded) {
          Column() {
            OCLoading({ text: '正在加载部署历史…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.deployments.length === 0) {
          Column() {
            OCEmpty({
              symbol: $r('sys.symbol.clock_arrow_2_circlepath'),
              title: '尚无部署记录',
              subtitle: this.vm.error !== '' ? this.vm.error : '每次更新代码都会生成一条部署记录',
            })
          }
          .width('100%')
          .height('100%')
        } else {
          Refresh({ refreshing: this.refreshing }) {
            Scroll() {
              Column({ space: 8 }) {
                Text(`共 ${this.vm.deployments.length} 次 · 长按删除（活跃部署除外）`)
                  .fontSize(13)
                  .fontColor($r('sys.color.font_secondary'))
                  .width('100%')
                  .padding({ left: 4 })
                Column() {
                  ForEach(this.vm.deployments, (deployment: WorkerDeployment, index: number) => {
                    this.deploymentRow(deployment, index === 0)
                    if (index < this.vm.deployments.length - 1) {
                      Divider()
                        .strokeWidth(0.5)
                        .color($r('sys.color.comp_divider'))
                        .margin({ left: 14 })
                    }
                  }, (deployment: WorkerDeployment) => deployment.id)
                }
                .width('100%')
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(OCLayout.chipRadius)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
                .clip(true)
              }
              .width('100%')
              .padding(OCLayout.pagePadding)
            }
            .align(Alignment.Top)
            .scrollBar(BarState.Off)
            .width('100%')
            .height('100%')
          }
          .onRefreshing(() => {
            this.refreshing = true;
            this.vm.load(accountStore.selectedId, this.scriptName).then(() => {
              this.refreshing = false;
            }).catch(() => {
              this.refreshing = false;
            });
          })
        }
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({ content: { title: { mainTitle: '部署历史' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as NameParam;
      this.scriptName = param.name;
      this.vm.load(accountStore.selectedId, param.name).catch(() => {
      });
    })
  }
}
