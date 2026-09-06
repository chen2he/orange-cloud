import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// Pages 部署详情：概览 + 构建阶段时间线 + 操作（重试 / 回滚 / 删除，对齐 iOS PagesDeploymentDetailView）。
// 路由参数 PagesDeploymentParam；写操作按 page.write 门控，均先确认弹窗再执行。
import { PagesDeploymentParam } from '../../models/Routes';
import { PagesDeploymentDetail, PagesService, PagesStage } from '../../services/PagesService';
import { accountStore } from '../../core/store/AccountStore';
import { authManager } from '../../core/auth/AuthManager';
import { Scopes } from '../../core/auth/Scopes';
import { formatDateTime } from '../../core/util/Format';
import { BRAND_ORANGE, DANGER_RED, InfoRow, OCError, OCLoading, SectionHeader } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';

function deployStatusColor(status: string): string {
  if (status === 'success') {
    return '#22C55E';
  }
  if (status === 'failure' || status === 'canceled') {
    return DANGER_RED;
  }
  if (status === 'active' || status === 'building') {
    return '#EAB308';
  }
  return '#9CA3AF';
}

function deployStatusLabel(status: string): string {
  if (status === 'success') {
    return '成功';
  }
  if (status === 'idle') {
    return '排队中';
  }
  if (status === 'active' || status === 'building') {
    return '进行中';
  }
  if (status === 'failure') {
    return '失败';
  }
  if (status === 'canceled') {
    return '已取消';
  }
  return status === '' ? '未知' : status;
}

function stageLabel(name: string): string {
  if (name === 'queued') {
    return '排队';
  }
  if (name === 'initialize') {
    return '初始化';
  }
  if (name === 'clone_repo') {
    return '拉取代码';
  }
  if (name === 'build') {
    return '构建';
  }
  if (name === 'deploy') {
    return '部署';
  }
  return name === '' ? '阶段' : name;
}

/// 阶段耗时（started_on 到 ended_on），缺一头或未结束时返回空串
function stageDuration(stage: PagesStage): string {
  const startISO = stage.started_on ?? '';
  const endISO = stage.ended_on ?? '';
  if (startISO === '' || endISO === '') {
    return '';
  }
  const start = new Date(startISO).getTime();
  const end = new Date(endISO).getTime();
  if (Number.isNaN(start) || Number.isNaN(end) || end < start) {
    return '';
  }
  const seconds = Math.round((end - start) / 1000);
  if (seconds < 60) {
    return `${seconds} 秒`;
  }
  const minutes = Math.floor(seconds / 60);
  const rest = seconds % 60;
  return rest === 0 ? `${minutes} 分钟` : `${minutes} 分 ${rest} 秒`;
}

@ObservedV2
class PagesDeploymentVM {
  @Trace deployment: PagesDeploymentDetail | null = null;
  @Trace isLoading: boolean = false;
  @Trace isMutating: boolean = false;
  @Trace error: string = '';
  private service: PagesService = new PagesService();

  async load(projectName: string, deploymentId: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.deployment = await this.service.getDeployment(accountStore.selectedId, projectName, deploymentId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async retry(projectName: string, deploymentId: string): Promise<string> {
    this.isMutating = true;
    try {
      await this.service.retryDeployment(accountStore.selectedId, projectName, deploymentId);
      await this.load(projectName, deploymentId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '重试失败';
    } finally {
      this.isMutating = false;
    }
  }

  async rollback(projectName: string, deploymentId: string): Promise<string> {
    this.isMutating = true;
    try {
      await this.service.rollbackDeployment(accountStore.selectedId, projectName, deploymentId);
      await this.load(projectName, deploymentId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '回滚失败';
    } finally {
      this.isMutating = false;
    }
  }

  async remove(projectName: string, deploymentId: string): Promise<string> {
    this.isMutating = true;
    try {
      await this.service.deleteDeployment(accountStore.selectedId, projectName, deploymentId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    } finally {
      this.isMutating = false;
    }
  }
}

@ComponentV2
export struct PagesDeploymentPage {
  @Local vm: PagesDeploymentVM = new PagesDeploymentVM();
  @Local projectName: string = '';
  @Local deploymentId: string = '';
  @Local isProduction: boolean = false;
  private pathStack: NavPathStack | null = null;

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  private confirmRetry(): void {
    this.getUIContext().showAlertDialog({
      title: '重试此部署？',
      message: '将用相同的源重新构建并部署。',
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '重试',
        fontColor: BRAND_ORANGE,
        action: () => {
          this.vm.retry(this.projectName, this.deploymentId).then((err: string) => {
            this.toast(err === '' ? '已触发重试' : err);
          });
        },
      },
    });
  }

  private confirmRollback(): void {
    this.getUIContext().showAlertDialog({
      title: '回滚到此部署？',
      message: '将使此次部署重新成为生产环境的当前版本。',
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '回滚',
        fontColor: BRAND_ORANGE,
        action: () => {
          this.vm.rollback(this.projectName, this.deploymentId).then((err: string) => {
            this.toast(err === '' ? '已回滚' : err);
          });
        },
      },
    });
  }

  private confirmDelete(): void {
    this.getUIContext().showAlertDialog({
      title: '删除此部署？',
      message: '删除后不可恢复；不能删除当前生效的部署。',
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '删除',
        fontColor: DANGER_RED,
        action: () => {
          this.vm.remove(this.projectName, this.deploymentId).then((err: string) => {
            if (err === '') {
              this.toast('已删除部署');
              this.pathStack?.pop();
            } else {
              this.toast(err);
            }
          });
        },
      },
    });
  }

  @Builder
  actionRow(label: string, color: ResourceColor, onTap: () => void) {
    Row({ space: 10 }) {
      Text(label)
        .fontSize(15)
        .fontColor(color)
      Blank()
      if (this.vm.isMutating) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color($r('sys.color.font_secondary'))
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 13, bottom: 13 })
    .enabled(!this.vm.isMutating)
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  islandDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.comp_divider'))
      .margin({ left: 16 })
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载部署…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '') {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load(this.projectName, this.deploymentId).catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.deployment !== null) {
          Scroll() {
            Column({ space: 4 }) {
              // ---- 概览 ----
              Column() {
                SectionHeader({ title: '部署' })
                Column() {
                  Row({ space: 12 }) {
                    Text('状态')
                      .fontSize(14)
                      .fontColor($r('sys.color.font_secondary'))
                    Blank()
                    Circle({ width: 8, height: 8 })
                      .fill(deployStatusColor(this.vm.deployment?.latest_stage?.status ?? ''))
                    Text(deployStatusLabel(this.vm.deployment?.latest_stage?.status ?? ''))
                      .fontSize(14)
                      .fontColor(deployStatusColor(this.vm.deployment?.latest_stage?.status ?? ''))
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 12, bottom: 12 })

                  InfoRow({
                    label: '环境',
                    value: (this.vm.deployment?.environment ?? (this.isProduction ? 'production' : 'preview')) === 'production'
                      ? '生产' : '预览',
                  })
                  if ((this.vm.deployment?.url ?? '') !== '') {
                    InfoRow({ label: '访问地址', value: this.vm.deployment?.url ?? '' })
                  }
                  if ((this.vm.deployment?.deployment_trigger?.metadata?.branch ?? '') !== '') {
                    InfoRow({ label: '分支', value: this.vm.deployment?.deployment_trigger?.metadata?.branch ?? '' })
                  }
                  if ((this.vm.deployment?.deployment_trigger?.metadata?.commit_hash ?? '') !== '') {
                    InfoRow({
                      label: '提交',
                      value: (this.vm.deployment?.deployment_trigger?.metadata?.commit_hash ?? '').substring(0, 8),
                    })
                  }
                  if ((this.vm.deployment?.deployment_trigger?.metadata?.commit_message ?? '') !== '') {
                    InfoRow({
                      label: '提交信息',
                      value: this.vm.deployment?.deployment_trigger?.metadata?.commit_message ?? '',
                    })
                  }
                  if ((this.vm.deployment?.created_on ?? '') !== '') {
                    InfoRow({ label: '创建于', value: formatDateTime(this.vm.deployment?.created_on ?? '') })
                  }
                  if ((this.vm.deployment?.modified_on ?? '') !== '') {
                    InfoRow({ label: '更新于', value: formatDateTime(this.vm.deployment?.modified_on ?? '') })
                  }
                }
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(14)
                .clip(true)
                .margin({ left: 16, right: 16 })
              }
              .width('100%')

              // ---- 构建阶段时间线 ----
              if ((this.vm.deployment?.stages ?? []).length > 0) {
                Column() {
                  SectionHeader({ title: '构建阶段' })
                  Column() {
                    ForEach(this.vm.deployment?.stages ?? [], (stage: PagesStage, index: number) => {
                      Row({ space: 12 }) {
                        // 时间线轴：节点 + 连线
                        Column() {
                          Divider()
                            .vertical(true)
                            .strokeWidth(1.5)
                            .color(index === 0 ? Color.Transparent : $r('sys.color.comp_divider'))
                            .height(8)
                          Circle({ width: 9, height: 9 })
                            .fill(deployStatusColor(stage.status ?? ''))
                          Divider()
                            .vertical(true)
                            .strokeWidth(1.5)
                            .color(index === (this.vm.deployment?.stages ?? []).length - 1
                              ? Color.Transparent : $r('sys.color.comp_divider'))
                            .layoutWeight(1)
                        }
                        .width(12)
                        .alignItems(HorizontalAlign.Center)

                        Text(stageLabel(stage.name ?? ''))
                          .fontSize(14)
                          .fontColor($r('sys.color.font_primary'))
                        Blank()
                        if (stageDuration(stage) !== '') {
                          Text(stageDuration(stage))
                            .fontSize(12)
                            .fontColor($r('sys.color.font_secondary'))
                        }
                        Text(deployStatusLabel(stage.status ?? ''))
                          .fontSize(13)
                          .fontColor(deployStatusColor(stage.status ?? ''))
                      }
                      .width('100%')
                      .height(44)
                      .padding({ left: 16, right: 16 })
                    }, (stage: PagesStage, index: number) => `${stage.name ?? ''}-${index}`)
                  }
                  .padding({ top: 4, bottom: 4 })
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(14)
                  .clip(true)
                  .margin({ left: 16, right: 16 })
                }
                .width('100%')
              }

              // ---- 操作（page.write 门控）----
              if (authManager.hasScope(Scopes.PAGES_WRITE)) {
                Column() {
                  SectionHeader({ title: '操作' })
                  Column() {
                    this.actionRow('重试部署', BRAND_ORANGE, () => {
                      this.confirmRetry();
                    })
                    this.islandDivider()
                    if (this.isProduction) {
                      this.actionRow('回滚到此部署', '#3B82F6', () => {
                        this.confirmRollback();
                      })
                      this.islandDivider()
                    }
                    this.actionRow('删除部署', DANGER_RED, () => {
                      this.confirmDelete();
                    })
                  }
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(14)
                  .clip(true)
                  .margin({ left: 16, right: 16 })

                  Text('重试会用相同的源重新构建；回滚使此次部署重新生效（仅生产环境）；删除不可撤销，且不能删除当前生效的部署。')
                    .fontSize(12)
                    .fontColor($r('sys.color.font_secondary'))
                    .width('100%')
                    .padding({ left: 20, right: 20, top: 8 })
                }
                .width('100%')
              } else {
                Text('当前授权未包含 Pages 写权限（page.write），仅可查看。')
                  .fontSize(12)
                  .fontColor($r('sys.color.font_secondary'))
                  .width('100%')
                  .padding({ left: 20, right: 20, top: 12 })
              }

              Blank()
                .height(32)
            }
            .width('100%')
          }
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .width('100%')
          .height('100%')
        }
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: this.vm.deployment?.short_id ?? '部署' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as PagesDeploymentParam;
      this.projectName = param.projectName;
      this.deploymentId = param.deploymentId;
      this.isProduction = param.isProduction;
      this.vm.load(param.projectName, param.deploymentId).catch(() => {
      });
    })
  }
}
