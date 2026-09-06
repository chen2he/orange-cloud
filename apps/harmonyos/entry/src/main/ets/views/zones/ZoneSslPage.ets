import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// SSL/TLS：加密模式（off/flexible/full/strict）+ HTTPS 开关 + 最低 TLS + TLS 1.3
// + 边缘证书入口（对齐 Android ZoneSslScreens）。
import { Routes, ZoneRouteParam } from '../../models/Routes';
import { ZoneSettingsService } from '../../services/ZoneSettingsService';
import { BRAND_ORANGE, NavRow, OCLoading, SectionHeader, ToggleRow } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';

interface SslModeSpec {
  raw: string;
  title: string;
  blurb: string;
}

const SSL_MODES: SslModeSpec[] = [
  { raw: 'off', title: '关闭', blurb: '全程 HTTP（不推荐）' },
  { raw: 'flexible', title: '灵活', blurb: '访客到 CF 加密，CF 到源站 HTTP' },
  { raw: 'full', title: '完全', blurb: '全程加密，源站证书可自签' },
  { raw: 'strict', title: '完全（严格）', blurb: '全程加密并校验源站证书' },
];

const MIN_TLS_VALUES: string[] = ['1.0', '1.1', '1.2', '1.3'];

@ObservedV2
class SslVM {
  @Trace sslMode: string = '';
  @Trace alwaysUseHttps: boolean = false;
  @Trace autoHttpsRewrites: boolean = false;
  @Trace minTls: string = '1.0';
  @Trace tls13: boolean = false;
  @Trace isLoading: boolean = false;
  @Trace isSaving: boolean = false;

  private service: ZoneSettingsService = new ZoneSettingsService();

  async load(zoneId: string): Promise<void> {
    this.isLoading = true;
    try {
      try {
        this.sslMode = await this.service.getSetting(zoneId, 'ssl');
      } catch (e) {
      }
      try {
        this.alwaysUseHttps = (await this.service.getSetting(zoneId, 'always_use_https')) === 'on';
      } catch (e) {
      }
      try {
        this.autoHttpsRewrites = (await this.service.getSetting(zoneId, 'automatic_https_rewrites')) === 'on';
      } catch (e) {
      }
      try {
        this.minTls = await this.service.getSetting(zoneId, 'min_tls_version');
      } catch (e) {
      }
      try {
        const v = await this.service.getSetting(zoneId, 'tls_1_3');
        this.tls13 = v === 'on' || v === 'zrt';
      } catch (e) {
      }
    } finally {
      this.isLoading = false;
    }
  }

  async set(zoneId: string, id: string, value: string): Promise<string> {
    this.isSaving = true;
    try {
      const applied = await this.service.setSetting(zoneId, id, value);
      if (id === 'ssl') {
        this.sslMode = applied;
      } else if (id === 'always_use_https') {
        this.alwaysUseHttps = applied === 'on';
      } else if (id === 'automatic_https_rewrites') {
        this.autoHttpsRewrites = applied === 'on';
      } else if (id === 'min_tls_version') {
        this.minTls = applied;
      } else if (id === 'tls_1_3') {
        this.tls13 = applied === 'on' || applied === 'zrt';
      }
      return '';
    } catch (e) {
      return (e as Error).message ?? '设置失败';
    } finally {
      this.isSaving = false;
    }
  }
}

@ComponentV2
export struct ZoneSslPage {
  @Local vm: SslVM = new SslVM();
  @Local zoneId: string = '';
  @Local zoneName: string = '';
  private pathStack: NavPathStack | null = null;

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  @Builder
  modeRow(mode: SslModeSpec) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(mode.title)
          .fontSize(15)
          .fontWeight(this.vm.sslMode === mode.raw ? FontWeight.Medium : FontWeight.Normal)
          .fontColor($r('sys.color.font_primary'))
        Text(mode.blurb)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Radio({ value: mode.raw, group: 'sslMode' })
        .checked(this.vm.sslMode === mode.raw)
        .radioStyle({ checkedBackgroundColor: BRAND_ORANGE })
        .onChange((checked: boolean) => {
          if (checked && this.vm.sslMode !== mode.raw) {
            this.vm.set(this.zoneId, 'ssl', mode.raw).then((err: string) => {
              this.toast(err);
            });
          }
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载 SSL 设置…' })
          }
          .width('100%')
          .height('100%')
        } else {
          Scroll() {
            Column({ space: 4 }) {
              Column() {
                SectionHeader({ title: '加密模式' })
                Column() {
                  ForEach(SSL_MODES, (mode: SslModeSpec) => {
                    this.modeRow(mode)
                  }, (mode: SslModeSpec) => mode.raw)
                }
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(14)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .clip(true)
                .margin({ left: 16, right: 16 })
              }
              .width('100%')

              Column() {
                SectionHeader({ title: 'HTTPS 行为' })
                Column() {
                  ToggleRow({
                    title: '始终使用 HTTPS',
                    subtitle: 'HTTP 请求 301 到 HTTPS',
                    isOn: this.vm.alwaysUseHttps,
                    isEnabled: !this.vm.isSaving,
                    onToggle: (on: boolean) => {
                      this.vm.set(this.zoneId, 'always_use_https', on ? 'on' : 'off').then((err: string) => {
                        this.toast(err);
                      });
                    },
                  })
                  ToggleRow({
                    title: '自动 HTTPS 重写',
                    subtitle: '把页面内 http:// 资源改写为 https://',
                    isOn: this.vm.autoHttpsRewrites,
                    isEnabled: !this.vm.isSaving,
                    onToggle: (on: boolean) => {
                      this.vm.set(this.zoneId, 'automatic_https_rewrites', on ? 'on' : 'off').then((err: string) => {
                        this.toast(err);
                      });
                    },
                  })
                  ToggleRow({
                    title: 'TLS 1.3',
                    subtitle: '启用最新版 TLS',
                    isOn: this.vm.tls13,
                    isEnabled: !this.vm.isSaving,
                    onToggle: (on: boolean) => {
                      this.vm.set(this.zoneId, 'tls_1_3', on ? 'on' : 'off').then((err: string) => {
                        this.toast(err);
                      });
                    },
                  })
                  Row({ space: 12 }) {
                    Text('最低 TLS 版本')
                      .fontSize(15)
                      .fontColor($r('sys.color.font_primary'))
                    Blank()
                    Select(MIN_TLS_VALUES.map((v: string): SelectOption => ({ value: `TLS ${v}` })))
                      .selected(MIN_TLS_VALUES.indexOf(this.vm.minTls))
                      .value(`TLS ${this.vm.minTls}`)
                      .font({ size: 14 })
                      .onSelect((index: number) => {
                        this.vm.set(this.zoneId, 'min_tls_version', MIN_TLS_VALUES[index]).then((err: string) => {
                          this.toast(err);
                        });
                      })
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 6, bottom: 10 })
                }
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(14)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .clip(true)
                .margin({ left: 16, right: 16 })
              }
              .width('100%')

              Column() {
                SectionHeader({ title: '证书' })
                Column() {
                  NavRow({
                    symbol: $r('sys.symbol.doc_plaintext'),
                    title: '边缘证书',
                    subtitle: '证书包列表 / Universal SSL 开关',
                    onNav: () => {
                      const param: ZoneRouteParam = { zoneId: this.zoneId, zoneName: this.zoneName };
                      this.pathStack?.pushPathByName(Routes.SSL_CERTS, param);
                    },
                  })
                }
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(14)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .clip(true)
                .margin({ left: 16, right: 16 })
              }
              .width('100%')
              .margin({ bottom: 24 })
            }
            .width('100%')
          }
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .width('100%')
          .height('100%')
        }
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({ content: { title: { mainTitle: `${this.zoneName} · SSL/TLS` } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as ZoneRouteParam;
      this.zoneId = param.zoneId;
      this.zoneName = param.zoneName;
      this.vm.load(param.zoneId).catch(() => {
      });
    })
  }
}
