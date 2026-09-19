import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// Worker 的 CI 构建记录：状态、分支/commit、日志、取消。
import { IdNameParam } from '../../models/Routes';
import {
  BuildLogLine, buildStateColor, buildStateLabel, isBuildRunning, WorkerBuild, WorkerBuildService,
} from '../../services/WorkerBuildService';
import { accountStore } from '../../core/store/AccountStore';
import { Scopes } from '../../core/auth/Scopes';
import { authManager } from '../../core/auth/AuthManager';
import { OCLoading, SectionHeader } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';
import { promptAction } from '@kit.ArkUI';

@ObservedV2
class BuildsVM {
  @Trace builds: WorkerBuild[] = [];
  @Trace logs: BuildLogLine[] = [];
  @Trace logsOpen: boolean = false;
  @Trace isLoading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace isSaving: boolean = false;
  private service: WorkerBuildService = new WorkerBuildService();

  async load(scriptId: string): Promise<void> {
    this.isLoading = true;
    try {
      this.builds = await this.service.builds(accountStore.selectedId, scriptId);
    } catch (e) {
      // 未接 CI 的 Worker 会 404 —— 视为「没有构建」，不当错误弹
      this.builds = [];
    } finally {
      this.loaded = true;
      this.isLoading = false;
    }
  }

  async openLogs(build: WorkerBuild): Promise<void> {
    this.logs = [];
    this.logsOpen = true;
    try {
      this.logs = await this.service.logs(accountStore.selectedId, build.build_uuid);
    } catch (e) {
    }
  }

  async cancel(scriptId: string, build: WorkerBuild): Promise<string> {
    this.isSaving = true;
    try {
      await this.service.cancel(accountStore.selectedId, build.build_uuid);
      await this.load(scriptId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '取消失败';
    } finally {
      this.isSaving = false;
    }
  }
}

@ComponentV2
export struct WorkerBuildsPage {
  @Local scriptId: string = '';
  @Local vm: BuildsVM = new BuildsVM();
  private canWrite: boolean = authManager.hasScope(Scopes.WORKERS_CI_WRITE);

  private toast(msg: string): void {
    if (msg !== '') {
      ocSnack(this.getUIContext(), msg);
    }
  }

  @Builder
  logsSheet() {
    Column({ space: 8 }) {
      Text('构建日志')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .margin({ top: 16 })
      Scroll() {
        Column({ space: 2 }) {
          if (this.vm.logs.length === 0) {
            Text('没有日志输出。')
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
          } else {
            ForEach(this.vm.logs, (l: BuildLogLine, index: number) => {
              Text(l.line ?? '')
                .fontSize(11)
                .fontColor($r('sys.color.font_primary'))
                .width('100%')
            }, (l: BuildLogLine, index: number) => `${index}`)
          }
        }
        .width('100%')
        .padding(16)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_secondary'))
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading && !this.vm.loaded) {
          Column() {
            OCLoading({ text: '正在加载构建记录…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.builds.length === 0) {
          Column() {
            Text('这个 Worker 还没有构建记录。接上 Git 仓库后，每次推送都会在这里出现。')
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .padding(32)
        } else {
          Scroll() {
            Column() {
              SectionHeader({ title: '构建记录' })
              Column({ space: 10 }) {
                ForEach(this.vm.builds, (b: WorkerBuild) => {
                  Column({ space: 4 }) {
                    Row({ space: 8 }) {
                      Text('●')
                        .fontSize(12)
                        .fontColor(buildStateColor(b))
                      Text(buildStateLabel(b))
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('sys.color.font_primary'))
                        .layoutWeight(1)
                    }
                    .width('100%')

                    if (b.build_trigger_metadata !== undefined) {
                      Text(`${b.build_trigger_metadata?.branch ?? ''} ${(b.build_trigger_metadata?.commit_hash ?? '').substring(0, 7)}`)
                        .fontSize(12)
                        .fontColor($r('sys.color.font_secondary'))
                        .width('100%')
                      if ((b.build_trigger_metadata?.author ?? '') !== '') {
                        Text(b.build_trigger_metadata?.author)
                          .fontSize(11)
                          .fontColor($r('sys.color.font_secondary'))
                          .width('100%')
                      }
                    }

                    Row({ space: 14 }) {
                      Text('构建日志')
                        .fontSize(13)
                        .fontColor($r('sys.color.font_secondary'))
                        .onClick(() => {
                          this.vm.openLogs(b).catch(() => {
                          });
                        })
                      // 只有进行中的构建才谈得上取消
                      if (this.canWrite && isBuildRunning(b)) {
                        Text('取消构建')
                          .fontSize(13)
                          .fontColor('#C62828')
                          .onClick(() => {
                            if (this.vm.isSaving) {
                              return;
                            }
                            this.vm.cancel(this.scriptId, b).then((err: string) => this.toast(err));
                          })
                      }
                    }
                    .width('100%')
                    .margin({ top: 2 })
                  }
                  .width('100%')
                  .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                }, (b: WorkerBuild) => b.build_uuid)
              }
              .backgroundColor($r('sys.color.comp_background_list_card'))
              .borderRadius(14)
              .clip(true)
              .margin({ left: 16, right: 16 })
            }
            .width('100%')
            .padding({ top: 8, bottom: 24 })
          }
          .width('100%')
          .height('100%')
        }
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: '构建' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.vm.logsOpen, this.logsSheet(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      onDisappear: () => {
        this.vm.logsOpen = false;
      },
    })
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as IdNameParam;
      this.scriptId = param.id;
      this.vm.load(param.id).catch(() => {
      });
    })
  }
}
