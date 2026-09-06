import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// 托管请求/响应头：Cloudflare 维护的开关式头部改写，不用自己写 Transform 规则。
import { ZoneRouteParam } from '../../models/Routes';
import {
  ManagedHeaderService, ManagedTransform, ManagedTransforms, managedHeaderLabel,
} from '../../services/ManagedHeaderService';
import { Scopes } from '../../core/auth/Scopes';
import { authManager } from '../../core/auth/AuthManager';
import { OCLoading, SectionHeader, ToggleRow } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';
import { promptAction } from '@kit.ArkUI';

@ObservedV2
class ManagedHeadersVM {
  @Trace requestHeaders: ManagedTransform[] = [];
  @Trace responseHeaders: ManagedTransform[] = [];
  @Trace isLoading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace isSaving: boolean = false;
  private service: ManagedHeaderService = new ManagedHeaderService();

  /// 接口不保证顺序，按 id 排一下，避免每次刷新行位置跳动
  private apply(t: ManagedTransforms): void {
    this.requestHeaders = (t.managed_request_headers ?? [])
      .sort((a: ManagedTransform, b: ManagedTransform) => a.id.localeCompare(b.id));
    this.responseHeaders = (t.managed_response_headers ?? [])
      .sort((a: ManagedTransform, b: ManagedTransform) => a.id.localeCompare(b.id));
    this.loaded = true;
  }

  async load(zoneId: string): Promise<void> {
    this.isLoading = true;
    try {
      this.apply(await this.service.transforms(zoneId));
    } catch (e) {
    } finally {
      this.isLoading = false;
    }
  }

  async setEnabled(zoneId: string, item: ManagedTransform, on: boolean, isRequest: boolean): Promise<string> {
    this.isSaving = true;
    try {
      this.apply(await this.service.setEnabled(zoneId, item.id, on, isRequest));
      return '';
    } catch (e) {
      await this.load(zoneId);
      return (e as Error).message ?? '设置失败';
    } finally {
      this.isSaving = false;
    }
  }
}

@ComponentV2
export struct ManagedHeadersPage {
  @Local zoneId: string = '';
  @Local vm: ManagedHeadersVM = new ManagedHeadersVM();
  private canWrite: boolean = authManager.hasScope(Scopes.MANAGED_HEADERS_WRITE);

  private toast(msg: string): void {
    if (msg !== '') {
      ocSnack(this.getUIContext(), msg);
    }
  }

  @Builder
  headerGroup(title: string, items: ManagedTransform[], isRequest: boolean) {
    Column() {
      SectionHeader({ title: title })
      Column() {
        if (items.length === 0) {
          Text('此域名没有可用的托管头。')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
            .padding(14)
        } else {
          ForEach(items, (item: ManagedTransform) => {
            ToggleRow({
              title: managedHeaderLabel(item.id),
              // 互斥关系由接口给出，开之前让用户知道会顶掉谁
              subtitle: (item.conflicts_with ?? []).length > 0
                ? `与 ${(item.conflicts_with ?? []).join('、')} 互斥` : '',
              isOn: item.enabled === true,
              isEnabled: this.canWrite && !this.vm.isSaving,
              onToggle: (on: boolean) => {
                this.vm.setEnabled(this.zoneId, item, on, isRequest).then((err: string) => this.toast(err));
              },
            })
          }, (item: ManagedTransform) => item.id)
        }
      }
      .backgroundColor($r('sys.color.comp_background_list_card'))
      .borderRadius(14)
      .border({ width: 0.5, color: $r('sys.color.comp_divider') })
      .clip(true)
      .margin({ left: 16, right: 16 })
    }
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading && !this.vm.loaded) {
          Column() {
            OCLoading({ text: '正在加载托管头…' })
          }
          .width('100%')
          .height('100%')
        } else {
          Scroll() {
            Column({ space: 4 }) {
              this.headerGroup('请求头', this.vm.requestHeaders, true)
              this.headerGroup('响应头', this.vm.responseHeaders, false)
              Text('由 Cloudflare 维护的头部改写，开关即生效，无需自己写 Transform 规则。')
                .fontSize(12)
                .fontColor($r('sys.color.font_secondary'))
                .padding({ left: 20, right: 20, top: 12, bottom: 24 })
            }
            .width('100%')
            .padding({ top: 8 })
          }
          .width('100%')
          .height('100%')
        }
      }
    }
    .titleBar({ content: { title: { mainTitle: '托管头' } } })
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as ZoneRouteParam;
      this.zoneId = param.zoneId;
      this.vm.load(param.zoneId).catch(() => {
      });
    })
  }
}
