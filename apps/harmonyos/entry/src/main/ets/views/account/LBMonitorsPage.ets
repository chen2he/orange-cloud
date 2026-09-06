// 负载均衡·健康监测（account 级）：列表 + 新建 / 编辑（类型 http/https/tcp、路径、方法、期望码、
// 间隔 / 超时 / 重试、跟随重定向、允许不安全证书）+ 长按删除。对齐 iOS MonitorListView；LB_POOLS_WRITE 门控。
import { LBMonitor, LBMonitorPayload, LoadBalancerService } from '../../services/LoadBalancerService';
import { accountStore } from '../../core/store/AccountStore';
import { authManager } from '../../core/auth/AuthManager';
import { Scopes } from '../../core/auth/Scopes';
import { BRAND_ORANGE, OCEmpty, OCError, OCLoading, SectionHeader, ToggleRow } from '../common/Components';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';

const MONITOR_TYPES: string[] = ['http', 'https', 'tcp'];
const MONITOR_METHODS: string[] = ['GET', 'HEAD'];

function isHTTPType(type: string): boolean {
  return type === 'http' || type === 'https';
}

/// 列表主标题：HTTP 类显示 方法+路径，其它显示 类型/端口
function monitorTitle(monitor: LBMonitor): string {
  if (isHTTPType(monitor.type ?? '')) {
    return `${monitor.method ?? 'GET'} ${monitor.path ?? '/'}`;
  }
  if (monitor.port !== undefined) {
    return `端口 ${monitor.port}`;
  }
  return (monitor.type ?? '').toUpperCase();
}

@ObservedV2
class LBMonitorsVM {
  @Trace monitors: LBMonitor[] = [];
  @Trace isLoading: boolean = false;
  @Trace isSaving: boolean = false;
  @Trace error: string = '';
  @Trace saveError: string = '';
  private service: LoadBalancerService = new LoadBalancerService();

  async load(accountId: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.monitors = await this.service.listMonitors(accountId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async save(accountId: string, monitorId: string, body: LBMonitorPayload): Promise<boolean> {
    this.isSaving = true;
    this.saveError = '';
    try {
      if (monitorId === '') {
        await this.service.createMonitor(accountId, body);
      } else {
        await this.service.updateMonitor(accountId, monitorId, body);
      }
      await this.load(accountId);
      return true;
    } catch (e) {
      this.saveError = (e as Error).message ?? '保存失败';
      return false;
    } finally {
      this.isSaving = false;
    }
  }

  async remove(accountId: string, monitorId: string): Promise<string> {
    try {
      await this.service.deleteMonitor(accountId, monitorId);
      this.monitors = this.monitors.filter((m: LBMonitor) => m.id !== monitorId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}

@ComponentV2
export struct LBMonitorsPage {
  @Local vm: LBMonitorsVM = new LBMonitorsVM();
  @Local editorVisible: boolean = false;
  @Local editingId: string = '';
  @Local fType: string = 'https';
  @Local fMethod: string = 'GET';
  @Local fPath: string = '/';
  @Local fExpectedCodes: string = '200';
  @Local fInterval: string = '60';
  @Local fTimeout: string = '5';
  @Local fRetries: string = '2';
  @Local fFollowRedirects: boolean = false;
  @Local fAllowInsecure: boolean = false;

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  private canWrite(): boolean {
    return authManager.hasScope(Scopes.LB_POOLS_WRITE);
  }

  private openEditor(monitor: LBMonitor | null): void {
    if (!this.canWrite()) {
      this.toast('当前授权缺少健康监测写权限');
      return;
    }
    this.vm.saveError = '';
    if (monitor) {
      this.editingId = monitor.id;
      this.fType = MONITOR_TYPES.includes(monitor.type ?? '') ? (monitor.type ?? 'https') : 'https';
      this.fMethod = monitor.method ?? 'GET';
      this.fPath = monitor.path ?? '/';
      this.fExpectedCodes = monitor.expected_codes ?? '200';
      this.fInterval = `${monitor.interval ?? 60}`;
      this.fTimeout = `${monitor.timeout ?? 5}`;
      this.fRetries = `${monitor.retries ?? 2}`;
      this.fFollowRedirects = monitor.follow_redirects === true;
      this.fAllowInsecure = monitor.allow_insecure === true;
    } else {
      this.editingId = '';
      this.fType = 'https';
      this.fMethod = 'GET';
      this.fPath = '/';
      this.fExpectedCodes = '200';
      this.fInterval = '60';
      this.fTimeout = '5';
      this.fRetries = '2';
      this.fFollowRedirects = false;
      this.fAllowInsecure = false;
    }
    this.editorVisible = true;
  }

  private buildPayload(): LBMonitorPayload {
    const interval = Number.parseInt(this.fInterval.trim());
    const timeoutValue = Number.parseInt(this.fTimeout.trim());
    const retries = Number.parseInt(this.fRetries.trim());
    const payload: LBMonitorPayload = {
      type: this.fType,
      interval: !Number.isNaN(interval) && interval > 0 ? interval : 60,
      timeout: !Number.isNaN(timeoutValue) && timeoutValue > 0 ? timeoutValue : 5,
      retries: !Number.isNaN(retries) && retries >= 0 ? retries : 2,
    };
    if (isHTTPType(this.fType)) {
      payload.method = this.fMethod;
      payload.path = this.fPath.trim() === '' ? '/' : this.fPath.trim();
      payload.expected_codes = this.fExpectedCodes.trim() === '' ? '200' : this.fExpectedCodes.trim();
      payload.follow_redirects = this.fFollowRedirects;
      payload.allow_insecure = this.fAllowInsecure;
    }
    return payload;
  }

  private confirmDelete(monitor: LBMonitor): void {
    if (!this.canWrite()) {
      this.toast('当前授权缺少健康监测写权限');
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '删除健康监测',
      message: `确定删除「${monitorTitle(monitor)}」？挂载它的源站池会停止探测。`,
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '删除',
        fontColor: '#DC2626',
        action: () => {
          this.vm.remove(accountStore.selectedId, monitor.id).then((err: string) => {
            this.toast(err === '' ? '已删除' : err);
          });
        },
      },
    });
  }

  @Builder
  monitorRow(monitor: LBMonitor) {
    Row({ space: 10 }) {
      Text((monitor.type ?? '').toUpperCase())
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.oc_brand_text'))
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .backgroundColor('#1AF48120')
        .borderRadius(4)
      Column({ space: 2 }) {
        Text(monitorTitle(monitor))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`每 ${monitor.interval ?? 60} 秒 · 超时 ${monitor.timeout ?? 5} 秒 · 重试 ${monitor.retries ?? 2} 次`)
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(16)
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .shadow({ radius: 10, color: '#12000000', offsetY: 4 })
    .margin({ left: 16, right: 16, top: 5, bottom: 5 })
    .onClick(() => {
      this.openEditor(monitor);
    })
    .gesture(LongPressGesture().onAction(() => {
      this.confirmDelete(monitor);
    }))
  }

  @Builder
  editorSheet() {
    Scroll() {
      Column({ space: 12 }) {
        Text(this.editingId === '' ? '新建健康监测' : '编辑健康监测')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .margin({ top: 8 })

        Row({ space: 12 }) {
          Text('类型')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Blank()
          Select(MONITOR_TYPES.map((t: string): SelectOption => ({ value: t.toUpperCase() })))
            .selected(MONITOR_TYPES.indexOf(this.fType))
            .value(this.fType.toUpperCase())
            .font({ size: 14 })
            .onSelect((index: number) => {
              this.fType = MONITOR_TYPES[index];
            })
        }
        .width('100%')

        if (isHTTPType(this.fType)) {
          Row({ space: 12 }) {
            Text('方法')
              .fontSize(14)
              .fontColor($r('sys.color.font_primary'))
            Blank()
            Select(MONITOR_METHODS.map((m: string): SelectOption => ({ value: m })))
              .selected(MONITOR_METHODS.indexOf(this.fMethod))
              .value(this.fMethod)
              .font({ size: 14 })
              .onSelect((index: number) => {
                this.fMethod = MONITOR_METHODS[index];
              })
          }
          .width('100%')

          TextInput({ text: this.fPath, placeholder: '探测路径，如 /health' })
            .fontSize(14)
            .width('100%')
            .onChange((value: string) => {
              this.fPath = value;
            })

          TextInput({ text: this.fExpectedCodes, placeholder: '期望状态码，如 200 或 2xx' })
            .fontSize(14)
            .width('100%')
            .onChange((value: string) => {
              this.fExpectedCodes = value;
            })
        }

        Row({ space: 12 }) {
          Text('探测间隔（秒）')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Blank()
          TextInput({ text: this.fInterval })
            .fontSize(13)
            .width(72)
            .type(InputType.Number)
            .onChange((value: string) => {
              this.fInterval = value;
            })
        }
        .width('100%')

        Row({ space: 12 }) {
          Text('超时（秒）')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Blank()
          TextInput({ text: this.fTimeout })
            .fontSize(13)
            .width(72)
            .type(InputType.Number)
            .onChange((value: string) => {
              this.fTimeout = value;
            })
        }
        .width('100%')

        Row({ space: 12 }) {
          Text('重试次数')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Blank()
          TextInput({ text: this.fRetries })
            .fontSize(13)
            .width(72)
            .type(InputType.Number)
            .onChange((value: string) => {
              this.fRetries = value;
            })
        }
        .width('100%')

        if (isHTTPType(this.fType)) {
          Column({ space: 2 }) {
            ToggleRow({
              title: '跟随重定向',
              isOn: this.fFollowRedirects,
              onToggle: (isOn: boolean) => {
                this.fFollowRedirects = isOn;
              },
            })
            ToggleRow({
              title: '允许不安全证书',
              subtitle: '跳过源站 TLS 证书校验',
              isOn: this.fAllowInsecure,
              onToggle: (isOn: boolean) => {
                this.fAllowInsecure = isOn;
              },
            })
          }
          .backgroundColor($r('sys.color.comp_background_list_card'))
          .borderRadius(14)
          .border({ width: 0.5, color: $r('sys.color.comp_divider') })
          .clip(true)
        }

        if (this.vm.saveError !== '') {
          Text(this.vm.saveError)
            .fontSize(13)
            .fontColor('#DC2626')
            .width('100%')
        }

        Button(this.vm.isSaving ? '正在保存…' : (this.editingId === '' ? '创建' : '保存'))
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor(BRAND_ORANGE)
          .enabled(!this.vm.isSaving)
          .onClick(() => {
            this.vm.save(accountStore.selectedId, this.editingId, this.buildPayload()).then((ok: boolean) => {
              if (ok) {
                this.editorVisible = false;
                this.toast(this.editingId === '' ? '已创建' : '已保存');
              }
            });
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 24 })
    }
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .width('100%')
    .height('100%')
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载健康监测…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '') {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load(accountStore.selectedId).catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.monitors.length === 0) {
          Column() {
            OCEmpty({
              symbol: $r('sys.symbol.checkmark_circle'),
              title: '暂无健康监测',
              subtitle: this.canWrite() ? '点右下角 + 创建；长按监测可删除' : '当前授权无监测写权限',
            })
          }
          .width('100%')
          .height('100%')
        } else {
          List() {
            ListItem() {
              SectionHeader({ title: `健康监测（${this.vm.monitors.length}）` })
            }
            ForEach(this.vm.monitors, (monitor: LBMonitor) => {
              ListItem() {
                this.monitorRow(monitor)
              }
            }, (monitor: LBMonitor) => monitor.id)
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
        }

        if (this.canWrite()) {
          Button('+')
            .width(52)
            .height(52)
            .fontSize(26)
            .fontColor(Color.White)
            .backgroundColor(BRAND_ORANGE)
            .borderRadius(26)
            .shadow({ radius: 12, color: '#40000000', offsetY: 4 })
            .margin({ right: 20, bottom: 28 })
            .onClick(() => {
              this.openEditor(null);
            })
        }
      }
      .width('100%')
      .height('100%')
    }
    .title('健康监测')
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.editorVisible, this.editorSheet(), ocSheet(() => {
      this.editorVisible = false;
    }))
    .onReady(() => {
      this.vm.load(accountStore.selectedId).catch(() => {
      });
    })
  }
}
