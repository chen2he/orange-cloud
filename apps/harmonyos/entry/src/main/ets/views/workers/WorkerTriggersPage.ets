import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// Worker 定时触发器（对照 iOS WorkerTriggersView）：Cron 查看 + 增删。
// Cron 走 UTC，5 字段标准表达式；端点是**整组 PUT**，加/删都要回写全集。
import { NameParam } from '../../models/Routes';
import { WorkerSchedule } from '../../models/WorkerModels';
import { WorkerService } from '../../services/WorkerService';
import { accountStore } from '../../core/store/AccountStore';
import { authManager } from '../../core/auth/AuthManager';
import { Scopes } from '../../core/auth/Scopes';
import { BRAND_ORANGE, DANGER_RED, OCEmpty, OCLoading } from '../common/Components';
import { ocSheetCompact } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';
import { OCLayout } from '../common/Daybreak';

@ObservedV2
class TriggersVM {
  @Trace schedules: WorkerSchedule[] = [];
  @Trace isLoading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace isSaving: boolean = false;
  @Trace error: string = '';

  private service: WorkerService = new WorkerService();

  async load(accountId: string, scriptName: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.schedules = await this.service.schedules(accountId, scriptName);
      this.loaded = true;
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  /// 整组回写：现有 cron + 新增（去重）
  async add(accountId: string, scriptName: string, cron: string): Promise<string> {
    if (this.schedules.some((s: WorkerSchedule) => s.cron === cron)) {
      return '该 Cron 已存在';
    }
    this.isSaving = true;
    try {
      const crons = this.schedules.map((s: WorkerSchedule) => s.cron);
      crons.push(cron);
      await this.service.putSchedules(accountId, scriptName, crons);
      this.schedules = await this.service.schedules(accountId, scriptName);
      return '';
    } catch (e) {
      return (e as Error).message ?? '添加失败';
    } finally {
      this.isSaving = false;
    }
  }

  /// 整组回写：剔除目标 cron
  async remove(accountId: string, scriptName: string, cron: string): Promise<string> {
    this.isSaving = true;
    try {
      const crons = this.schedules.map((s: WorkerSchedule) => s.cron).filter((c: string) => c !== cron);
      await this.service.putSchedules(accountId, scriptName, crons);
      this.schedules = this.schedules.filter((s: WorkerSchedule) => s.cron !== cron);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    } finally {
      this.isSaving = false;
    }
  }
}

@ComponentV2
export struct WorkerTriggersPage {
  @Local vm: TriggersVM = new TriggersVM();
  @Local scriptName: string = '';
  @Local sheetVisible: boolean = false;
  @Local fCron: string = '0 * * * *';
  @Local refreshing: boolean = false;

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  private canWrite(): boolean {
    if (!authManager.hasScope(Scopes.WORKERS_WRITE)) {
      this.toast('当前授权未包含 Workers 写权限（workers-scripts.write）');
      return false;
    }
    return true;
  }

  @Builder
  cronSheet() {
    Column({ space: 14 }) {
      Text('添加定时触发器')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
      Text('Cron 表达式（分 时 日 月 周），按 UTC 时间执行。每小时：0 * * * *')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({ placeholder: '0 * * * *', text: this.fCron })
        .onChange((value: string) => {
          this.fCron = value;
        })
      Button(this.vm.isSaving ? '正在保存…' : '添加')
        .width('100%')
        .height(46)
        .backgroundColor($r('app.color.oc_brand'))
        .enabled(!this.vm.isSaving && this.fCron.trim() !== '')
        .onClick(() => {
          this.vm.add(accountStore.selectedId, this.scriptName, this.fCron.trim()).then((err: string) => {
            if (err === '') {
              this.sheetVisible = false;
              this.toast('已添加');
            } else {
              this.toast(err);
            }
          });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  @Builder
  cronRow(schedule: WorkerSchedule) {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.clock'))
        .fontSize(18)
        .fontColor([$r('app.color.oc_brand_text')])
      Text(schedule.cron)
        .fontSize(15)
        .fontFamily('monospace')
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 13, bottom: 13 })
    .gesture(LongPressGesture().onAction(() => {
      if (!this.canWrite()) {
        return;
      }
      this.getUIContext().showAlertDialog({
        title: '删除触发器',
        message: `将删除 ${schedule.cron}，该定时任务不再执行。`,
        primaryButton: { value: '取消', action: () => {
        } },
        secondaryButton: {
          value: '删除',
          fontColor: DANGER_RED,
          action: () => {
            this.vm.remove(accountStore.selectedId, this.scriptName, schedule.cron).then((err: string) => {
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
            OCLoading({ text: '正在加载触发器…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.schedules.length === 0) {
          Column() {
            OCEmpty({
              symbol: $r('sys.symbol.clock'),
              title: '尚无定时触发器',
              subtitle: '用 Cron 表达式让脚本定时执行，按 UTC 时间',
            })
          }
          .width('100%')
          .height('100%')
        } else {
          Refresh({ refreshing: this.refreshing }) {
            Scroll() {
              Column({ space: 8 }) {
                Text(`共 ${this.vm.schedules.length} 条 · 长按删除`)
                  .fontSize(13)
                  .fontColor($r('sys.color.font_secondary'))
                  .width('100%')
                  .padding({ left: 4 })
                Column() {
                  ForEach(this.vm.schedules, (schedule: WorkerSchedule, index: number) => {
                    this.cronRow(schedule)
                    if (index < this.vm.schedules.length - 1) {
                      Divider()
                        .strokeWidth(0.5)
                        .color($r('sys.color.comp_divider'))
                        .margin({ left: 14 })
                    }
                  }, (schedule: WorkerSchedule) => schedule.cron)
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
    .titleBar({ content: { title: { mainTitle: '触发器' }, menu: { value: [{ content: { icon: $r('sys.symbol.plus'), label: '添加', action: () => { if (this.canWrite()) { this.fCron = '0 * * * *'; this.sheetVisible = true; } } } }] } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.sheetVisible, this.cronSheet(), ocSheetCompact(() => {
      this.sheetVisible = false;
    }))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as NameParam;
      this.scriptName = param.name;
      this.vm.load(accountStore.selectedId, param.name).catch(() => {
      });
    })
  }
}
