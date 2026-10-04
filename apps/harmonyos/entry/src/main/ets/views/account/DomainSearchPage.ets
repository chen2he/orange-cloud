import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// 搜索新域名（Registrar domain-search / domain-check，registrar-domains.read，免费）。
// 搜索结果来自缓存可能有延迟；点开某个域名时实时向注册局确认，可注册就给「在 Cloudflare 控制台注册」。
// App 内不做任何购买：注册是花钱操作，一律跳控制台完成。
import { DomainAvailability, RegistrarService } from '../../services/RegistrarService';
import { accountStore } from '../../core/store/AccountStore';
import { GlobalContext } from '../../core/system/GlobalContext';
import { OCEmpty, OCError, OCLoading } from '../common/Components';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';

const REGISTER_URL = 'https://dash.cloudflare.com/?to=/:account/registrar/register';
const PREMIUM_COLOR = '#B45309';

/// reason → 中文说明；未知原因原样显示
function domainReasonLabel(reason: string): string {
  if (reason === 'extension_not_supported_via_api') {
    return '该后缀暂不支持通过 API 注册';
  }
  if (reason === 'extension_not_supported') {
    return 'Cloudflare 不支持该后缀';
  }
  if (reason === 'extension_disallows_registration') {
    return '该后缀不开放注册';
  }
  if (reason === 'domain_premium') {
    return '溢价域名';
  }
  if (reason === 'domain_unavailable') {
    return '已被注册';
  }
  return reason;
}

/// 「可注册」/「不可注册（原因）」
function availabilityText(item: DomainAvailability): string {
  if (item.registrable === true) {
    return '可注册';
  }
  const reason = item.reason ?? '';
  return reason !== '' ? `不可注册（${domainReasonLabel(reason)}）` : '不可注册';
}

/// 价格行：「首年 {registration_cost} {currency} · 续费 {renewal_cost}/年」；无价格返回空串
function priceText(item: DomainAvailability): string {
  const p = item.pricing;
  if (p === undefined || p === null) {
    return '';
  }
  const reg = p.registration_cost ?? '';
  const renew = p.renewal_cost ?? '';
  if (reg === '' && renew === '') {
    return '';
  }
  return `首年 ${reg} ${p.currency ?? ''} · 续费 ${renew}/年`;
}

function isPremium(item: DomainAvailability): boolean {
  return item.tier === 'premium';
}

@ObservedV2
class DomainSearchVM {
  @Trace results: DomainAvailability[] = [];
  @Trace searched: boolean = false;
  @Trace isSearching: boolean = false;
  @Trace error: string = '';
  // 实时检查
  @Trace checkingName: string = '';
  @Trace checked: DomainAvailability | null = null;
  @Trace checkError: string = '';
  private service: RegistrarService = new RegistrarService();
  private generation: number = 0;

  async search(query: string): Promise<void> {
    this.generation++;
    const gen = this.generation;
    this.isSearching = true;
    this.error = '';
    try {
      await accountStore.loadIfNeeded();
      const results = await this.service.search(accountStore.selectedId, query);
      if (gen !== this.generation) {
        return;
      }
      this.results = results;
      this.searched = true;
    } catch (e) {
      if (gen === this.generation) {
        this.error = (e as Error).message ?? '搜索失败';
      }
    } finally {
      if (gen === this.generation) {
        this.isSearching = false;
      }
    }
  }

  async check(name: string): Promise<void> {
    this.checkingName = name;
    this.checked = null;
    this.checkError = '';
    try {
      const results = await this.service.check(accountStore.selectedId, [name]);
      if (this.checkingName !== name) {
        return;
      }
      const match = results.find((d: DomainAvailability) => d.name === name);
      this.checked = match ?? (results.length > 0 ? results[0] : null);
      if (this.checked === null) {
        this.checkError = '没有拿到该域名的实时结果';
      }
    } catch (e) {
      if (this.checkingName === name) {
        this.checkError = (e as Error).message ?? '查询失败';
      }
    }
  }
}

@ComponentV2
export struct DomainSearchPage {
  @Local vm: DomainSearchVM = new DomainSearchVM();
  @Local query: string = '';
  @Local sheetVisible: boolean = false;
  /// 点开的那一行（实时结果回来前先展示搜索结果里的信息）
  @Local picked: DomainAvailability | null = null;

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  private submit(value: string): void {
    const q = value.trim();
    if (q === '') {
      return;
    }
    this.query = q;
    this.vm.search(q).catch(() => {
    });
  }

  private open(item: DomainAvailability): void {
    this.picked = item;
    this.sheetVisible = true;
    this.vm.check(item.name).catch(() => {
    });
  }

  private openRegister(): void {
    try {
      GlobalContext.get().openLink(REGISTER_URL).catch(() => {
        this.toast('无法打开浏览器');
      });
    } catch (e) {
    }
  }

  @Builder
  premiumBadge() {
    Text('溢价')
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor(PREMIUM_COLOR)
      .padding({ left: 6, right: 6, top: 1, bottom: 1 })
      .backgroundColor('#1AB45309')
      .borderRadius(4)
  }

  @Builder
  resultRow(item: DomainAvailability) {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        Text(item.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)
        if (isPremium(item)) {
          this.premiumBadge()
        }
        Blank()
        Text(item.registrable === true ? '可注册' : '不可注册')
          .fontSize(12)
          .fontColor(item.registrable === true ? '#22C55E' : $r('sys.color.font_tertiary'))
      }
      .width('100%')
      if (item.registrable !== true && (item.reason ?? '') !== '') {
        Text(domainReasonLabel(item.reason ?? ''))
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
      }
      if (priceText(item) !== '') {
        Text(priceText(item))
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(14)
    .onClick(() => {
      this.open(item);
    })
  }

  /// 实时确认 sheet：结果回来前显示加载；可注册才给控制台注册入口
  @Builder
  checkSheet() {
    Column({ space: 12 }) {
      Row({ space: 6 }) {
        Text(this.picked?.name ?? '')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)
        if (this.vm.checked !== null && isPremium(this.vm.checked!)) {
          this.premiumBadge()
        }
      }
      .width('100%')
      .margin({ top: 8 })

      if (this.vm.checked === null && this.vm.checkError === '') {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(18)
            .height(18)
          Text('正在向注册局实时确认…')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
      } else if (this.vm.checked === null) {
        Text(this.vm.checkError)
          .fontSize(13)
          .fontColor('#DC2626')
          .width('100%')
      } else {
        Text(availabilityText(this.vm.checked!))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.vm.checked!.registrable === true ? '#22C55E' : $r('sys.color.font_secondary'))
          .width('100%')
        if (priceText(this.vm.checked!) !== '') {
          Text(priceText(this.vm.checked!))
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
        }
        if (this.vm.checked!.registrable === true) {
          Button('在 Cloudflare 控制台注册')
            .width('100%')
            .height(44)
            .fontSize(15)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.oc_brand_cta'))
            .onClick(() => {
              this.openRegister();
            })
        }
      }
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        Column() {
          Search({ value: this.query, placeholder: '输入想注册的域名或关键词' })
            .textFont({ size: 14 })
            .height(40)
            .margin({ left: 16, right: 16, top: 8 })
            .onChange((value: string) => {
              this.query = value;
            })
            .onSubmit((value: string) => {
              this.submit(value);
            })
          Text('搜索结果可能有延迟，点开后会实时确认')
            .fontSize(11)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
            .padding({ left: 20, right: 20, top: 6, bottom: 6 })

          if (this.vm.isSearching && this.vm.results.length === 0) {
            Column() {
              OCLoading({ text: '正在搜索…' })
            }
            .width('100%')
            .layoutWeight(1)
          } else if (this.vm.error !== '') {
            Column() {
              OCError({
                message: this.vm.error,
                onRetry: () => {
                  this.submit(this.query);
                },
              })
            }
            .width('100%')
            .layoutWeight(1)
          } else if (!this.vm.searched) {
            Column() {
              OCEmpty({ symbol: $r('sys.symbol.magnifyingglass'), title: '搜索新域名', subtitle: '查看能否在 Cloudflare 注册以及价格' })
            }
            .width('100%')
            .layoutWeight(1)
          } else if (this.vm.results.length === 0) {
            Column() {
              OCEmpty({ symbol: $r('sys.symbol.magnifyingglass'), title: '没有找到相关域名' })
            }
            .width('100%')
            .layoutWeight(1)
          } else {
            List({ space: 8 }) {
              ForEach(this.vm.results, (item: DomainAvailability) => {
                ListItem() {
                  this.resultRow(item)
                }
              }, (item: DomainAvailability) => item.name)
            }
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 16, right: 16, bottom: 24 })
            .scrollBar(BarState.Off)
          }
        }
        .width('100%')
        .height('100%')
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: '搜索新域名' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.sheetVisible, this.checkSheet(), ocSheet(() => {
      this.sheetVisible = false;
    }))
  }
}
