import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// 边缘证书：证书包列表 + Universal SSL 开关 + 删除高级包（对齐 Android SslCerts 屏）。
import { ZoneRouteParam } from '../../models/Routes';
import { SSLService, SslCertificatePack } from '../../services/SSLService';
import { formatDateTime } from '../../core/util/Format';
import { BRAND_ORANGE, OCEmpty, OCError, OCLoading, SectionHeader, ToggleRow } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';

function packStatusColor(status: string): string {
  if (status === 'active') {
    return '#22C55E';
  }
  if (status.includes('pending') || status === 'initializing') {
    return '#EAB308';
  }
  return '#9CA3AF';
}

@ObservedV2
class SslCertsVM {
  @Trace packs: SslCertificatePack[] = [];
  @Trace universal: boolean = false;
  @Trace isLoading: boolean = false;
  @Trace error: string = '';

  private service: SSLService = new SSLService();

  async load(zoneId: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.packs = await this.service.certificatePacks(zoneId);
      try {
        this.universal = await this.service.universalEnabled(zoneId);
      } catch (e) {
      }
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async setUniversal(zoneId: string, on: boolean): Promise<string> {
    try {
      this.universal = await this.service.setUniversal(zoneId, on);
      return '';
    } catch (e) {
      return (e as Error).message ?? '设置失败';
    }
  }

  async deletePack(zoneId: string, packId: string): Promise<string> {
    try {
      await this.service.deletePack(zoneId, packId);
      this.packs = this.packs.filter((p: SslCertificatePack) => p.id !== packId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}

@ComponentV2
export struct SslCertsPage {
  @Local vm: SslCertsVM = new SslCertsVM();
  @Local zoneId: string = '';
  @Local zoneName: string = '';

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  private confirmDelete(pack: SslCertificatePack): void {
    this.getUIContext().showAlertDialog({
      title: '删除证书包',
      message: `确定删除 ${pack.type ?? ''} 证书包？此操作不可撤销。`,
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#DC2626',
        action: () => {
          this.vm.deletePack(this.zoneId, pack.id).then((err: string) => {
            this.toast(err === '' ? '已删除' : err);
          });
        },
      },
    });
  }

  @Builder
  packRow(pack: SslCertificatePack) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(pack.type ?? 'universal')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        Circle({ width: 7, height: 7 })
          .fill(packStatusColor(pack.status ?? ''))
        Text(pack.status ?? '')
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
        Blank()
        if (pack.type !== 'universal') {
          Text('删除')
            .fontSize(12)
            .fontColor('#DC2626')
            .onClick(() => {
              this.confirmDelete(pack);
            })
        }
      }
      .width('100%')

      Text((pack.hosts ?? []).join('，'))
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (pack.certificates && pack.certificates.length > 0 && pack.certificates[0].expires_on) {
        Text(`到期：${formatDateTime(pack.certificates[0].expires_on ?? '')} · ${pack.certificate_authority ?? ''}`)
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载证书…' })
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
        } else {
          Scroll() {
            Column({ space: 4 }) {
              Column() {
                SectionHeader({ title: 'Universal SSL' })
                Column() {
                  ToggleRow({
                    title: 'Universal SSL',
                    subtitle: 'Cloudflare 免费边缘证书',
                    isOn: this.vm.universal,
                    onToggle: (on: boolean) => {
                      this.vm.setUniversal(this.zoneId, on).then((err: string) => {
                        this.toast(err);
                      });
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

              Column() {
                SectionHeader({ title: `证书包（${this.vm.packs.length}）` })
                if (this.vm.packs.length === 0) {
                  Column() {
                    OCEmpty({ symbol: $r('sys.symbol.doc_plaintext'), title: '暂无证书包' })
                  }
                  .height(160)
                } else {
                  Column() {
                    ForEach(this.vm.packs, (pack: SslCertificatePack) => {
                      this.packRow(pack)
                    }, (pack: SslCertificatePack) => pack.id)
                  }
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(14)
                  .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                  .clip(true)
                  .margin({ left: 16, right: 16 })
                }
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
    .titleBar({ content: { title: { mainTitle: `${this.zoneName} · 证书` } } })
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
