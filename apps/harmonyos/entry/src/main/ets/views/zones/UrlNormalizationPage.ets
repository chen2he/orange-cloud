import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// URL 规范化（对照 iOS URLNormalizationView）：GET 与 PUT /zones/{id}/url_normalization。
// 规范化类型 cloudflare/rfc3986 单选 + 作用范围 incoming/both（含 none 只读兜底），改动即时 PUT。
import { UrlNormalizationSetting } from '../../models/RulesetModels';
import { ZoneRouteParam } from '../../models/Routes';
import { RulesetService } from '../../services/RulesetService';
import { authManager } from '../../core/auth/AuthManager';
import { BRAND_ORANGE, OCError, OCLoading } from '../common/Components';
import { GlassIsland, OCLayout } from '../common/Daybreak';
import { OCSkyBackground } from '../common/OCSky';

const CONFIG_SETTINGS_WRITE = 'config-settings.write';

interface NormalizationOption {
  value: string;
  label: string;
  note: string;
}

const TYPE_OPTIONS: NormalizationOption[] = [
  { value: 'cloudflare', label: 'Cloudflare', note: '在 RFC 3986 基础上额外合并斜杠等（推荐）' },
  { value: 'rfc3986', label: 'RFC 3986', note: '仅按 RFC 3986 标准做百分号编码规范化' },
];

const SCOPE_OPTIONS: NormalizationOption[] = [
  { value: 'incoming', label: '仅入站 URL', note: '只规范化到达 Cloudflare 的请求 URL' },
  { value: 'both', label: '入站与规则匹配', note: '规则表达式匹配时也使用规范化后的 URL' },
  { value: 'none', label: '不规范化', note: '关闭 URL 规范化' },
];

@ObservedV2
class UrlNormalizationVM {
  @Trace value: UrlNormalizationSetting | null = null;
  @Trace isLoading: boolean = false;
  @Trace isMutating: boolean = false;
  @Trace error: string = '';

  private service: RulesetService = new RulesetService();

  async load(zoneId: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.value = await this.service.getUrlNormalization(zoneId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async update(zoneId: string, type: string, scope: string): Promise<string> {
    this.isMutating = true;
    try {
      const body: UrlNormalizationSetting = { type: type, scope: scope };
      this.value = await this.service.setUrlNormalization(zoneId, body);
      return '';
    } catch (e) {
      return (e as Error).message ?? '设置失败';
    } finally {
      this.isMutating = false;
    }
  }
}

@ComponentV2
export struct UrlNormalizationPage {
  @Local vm: UrlNormalizationVM = new UrlNormalizationVM();
  @Local zoneId: string = '';
  @Local zoneName: string = '';

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  private apply(type: string, scopeValue: string): void {
    if (!authManager.hasScope(CONFIG_SETTINGS_WRITE)) {
      this.toast(`当前授权未包含编辑权限（${CONFIG_SETTINGS_WRITE}）`);
      return;
    }
    if (this.vm.isMutating) {
      return;
    }
    this.vm.update(this.zoneId, type, scopeValue).then((err: string) => {
      this.toast(err === '' ? '已更新' : err);
    });
  }

  // @Builder 按值传参不具备响应性：选中态一律直接引用 this.vm.value 内联判断。

  @Builder
  typeIsland() {
    GlassIsland() {
      Column({ space: 2 }) {
        Text('规范化类型')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
        ForEach(TYPE_OPTIONS, (option: NormalizationOption) => {
          Row({ space: 10 }) {
            Column({ space: 2 }) {
              Text(option.label)
                .fontSize(14)
                .fontWeight(this.vm.value?.type === option.value ? FontWeight.Medium : FontWeight.Normal)
                .fontColor($r('sys.color.font_primary'))
              Text(option.note)
                .fontSize(11)
                .fontColor($r('sys.color.font_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (this.vm.value?.type === option.value) {
              SymbolGlyph($r('sys.symbol.checkmark_circle'))
                .fontSize(20)
                .fontColor([$r('app.color.oc_brand_text')])
            }
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
          .onClick(() => {
            this.apply(option.value, this.vm.value?.scope ?? 'incoming');
          })
        }, (option: NormalizationOption) => option.value)
      }
      .width('100%')
    }
  }

  @Builder
  scopeIsland() {
    GlassIsland() {
      Column({ space: 2 }) {
        Text('作用范围')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
        ForEach(SCOPE_OPTIONS, (option: NormalizationOption) => {
          Row({ space: 10 }) {
            Column({ space: 2 }) {
              Text(option.label)
                .fontSize(14)
                .fontWeight(this.vm.value?.scope === option.value ? FontWeight.Medium : FontWeight.Normal)
                .fontColor($r('sys.color.font_primary'))
              Text(option.note)
                .fontSize(11)
                .fontColor($r('sys.color.font_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (this.vm.value?.scope === option.value) {
              SymbolGlyph($r('sys.symbol.checkmark_circle'))
                .fontSize(20)
                .fontColor([$r('app.color.oc_brand_text')])
            }
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
          .onClick(() => {
            this.apply(this.vm.value?.type ?? 'cloudflare', option.value);
          })
        }, (option: NormalizationOption) => option.value)
      }
      .width('100%')
    }
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载 URL 规范化设置…' })
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
        } else if (this.vm.value !== null) {
          Scroll() {
            Column({ space: OCLayout.islandGap }) {
              this.typeIsland()
              this.scopeIsland()
              Text('URL 规范化影响所有规则的表达式匹配方式，修改立即生效。')
                .fontSize(11)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
                .padding({ left: 4, right: 4 })
            }
            .width('100%')
            .padding(OCLayout.pagePadding)
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
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: `${this.zoneName} · URL 规范化` } } })
    .backgroundColor($r('sys.color.background_secondary'))
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
