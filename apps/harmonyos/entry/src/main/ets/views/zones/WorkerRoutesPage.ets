import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// Worker 路由（zone 级）：pattern → script 映射，列表 + 新建 + 删除（对齐 Android Worker 路由管理）。
import { WorkerRoute } from '../../models/WorkerModels';
import { ZoneRouteParam } from '../../models/Routes';
import { WorkerService } from '../../services/WorkerService';
import { BRAND_ORANGE, OCEmpty, OCError, OCLoading } from '../common/Components';
import { GlassIsland } from '../common/Daybreak';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';

@ObservedV2
class RoutesVM {
  @Trace routes: WorkerRoute[] = [];
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  @Trace isCreating: boolean = false;
  @Trace createError: string = '';
  private service: WorkerService = new WorkerService();

  async load(zoneId: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.routes = await this.service.routes(zoneId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async create(zoneId: string, pattern: string, script: string): Promise<boolean> {
    this.isCreating = true;
    this.createError = '';
    try {
      await this.service.createRoute(zoneId, pattern, script);
      await this.load(zoneId);
      return true;
    } catch (e) {
      this.createError = (e as Error).message ?? '创建失败';
      return false;
    } finally {
      this.isCreating = false;
    }
  }

  async remove(zoneId: string, routeId: string): Promise<string> {
    try {
      await this.service.deleteRoute(zoneId, routeId);
      this.routes = this.routes.filter((r: WorkerRoute) => r.id !== routeId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}

@ComponentV2
export struct WorkerRoutesPage {
  @Local vm: RoutesVM = new RoutesVM();
  @Local zoneId: string = '';
  @Local zoneName: string = '';
  @Local showCreate: boolean = false;
  @Local fPattern: string = '';
  @Local fScript: string = '';

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  @Builder
  createSheet() {
    Column({ space: 12 }) {
      Text('新建 Worker 路由')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      TextInput({ text: this.fPattern, placeholder: `路由匹配，如 ${this.zoneName}/api/*` })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fPattern = value;
        })
      TextInput({ text: this.fScript, placeholder: 'Worker 脚本名' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fScript = value;
        })
      if (this.vm.createError !== '') {
        Text(this.vm.createError)
          .fontSize(13)
          .fontColor('#DC2626')
          .width('100%')
      }
      Button(this.vm.isCreating ? '正在创建…' : '创建')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm.isCreating && this.fPattern.trim() !== '' && this.fScript.trim() !== '')
        .onClick(() => {
          this.vm.create(this.zoneId, this.fPattern.trim(), this.fScript.trim()).then((ok: boolean) => {
            if (ok) {
              this.showCreate = false;
              this.fPattern = '';
              this.fScript = '';
            }
          });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载路由…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '') {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load(this.zoneId).catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.routes.length === 0) {
          Column() {
            OCEmpty({ symbol: $r('sys.symbol.link'), title: '暂无 Worker 路由', subtitle: '点右下角 + 创建；长按删除' })
          }
          .width('100%')
          .height('100%')
        } else {
          List() {
            ForEach(this.vm.routes, (route: WorkerRoute) => {
              ListItem() {
                GlassIsland({ pad: 14 }) {
                  Column({ space: 4 }) {
                    Text(route.pattern)
                      .fontSize(14)
                      .fontFamily('monospace')
                      .fontColor($r('sys.color.font_primary'))
                      .width('100%')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`→ ${route.script ?? '（无脚本）'}`)
                      .fontSize(12)
                      .fontColor($r('app.color.oc_brand_text'))
                  }
                  .alignItems(HorizontalAlign.Start)
                  .width('100%')
                  .gesture(LongPressGesture().onAction(() => {
                    this.vm.remove(this.zoneId, route.id).then((err: string) => {
                      this.toast(err === '' ? '已删除' : err);
                    });
                  }))
                }
              }
              .margin({ left: 16, right: 16, top: 5, bottom: 5 })
            }, (route: WorkerRoute) => route.id)
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
        }

        Button('+')
          .width(52)
          .height(52)
          .fontSize(26)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.oc_brand_cta'))
          .borderRadius(26)
          .margin({ right: 20, bottom: 28 })
          .onClick(() => {
            this.showCreate = true;
          })
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: `${this.zoneName} · Worker 路由` } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.showCreate, this.createSheet(), ocSheet(() => {
      this.showCreate = false;
    }))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as ZoneRouteParam;
      this.zoneId = param.zoneId;
      this.zoneName = param.zoneName;
      this.vm.load(param.zoneId).catch(() => {
      });
    })
  }
}
