import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { HdsNavDestination } from '@kit.UIDesignKit';
// 指南清单（对齐 iOS GuidesListView）：官网 /guides 的 Cloudflare 排障与科普长文，免登录可读。
// 两语各写各的、互不翻译；鸿蒙版界面为简体中文，默认选简中，可切到英文看更多篇目。
import { GuideCollection, GuideIndex, GuideService, GuideSummary } from '../../services/GuideService';
import { GuideParam, Routes } from '../../models/Routes';
import { OCEmpty, OCError, OCLoading } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';

function localeName(locale: string): string {
  if (locale === 'zh-Hans') {
    return '简体中文';
  }
  if (locale === 'en') {
    return 'English';
  }
  return locale;
}

@ObservedV2
class GuidesVM {
  @Trace collections: Record<string, GuideCollection> = {};
  @Trace locales: string[] = [];
  @Trace selectedLocale: string = 'zh-Hans';
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  private service: GuideService = new GuideService();
  private loaded: boolean = false;

  guides(): GuideSummary[] {
    const c = this.collections[this.selectedLocale];
    return c ? c.guides : [];
  }

  async load(): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      const index: GuideIndex = await this.service.index();
      const keys = Object.keys(index.locales);
      const ordered = ['zh-Hans', 'en'].filter((l: string) => keys.includes(l));
      this.collections = index.locales;
      this.locales = ordered.concat(keys.filter((l: string) => !ordered.includes(l)).sort());
      if (!this.loaded || !this.locales.includes(this.selectedLocale)) {
        this.selectedLocale = this.locales.length > 0 ? this.locales[0] : 'zh-Hans';
      }
      this.loaded = true;
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }
}

@ComponentV2
export struct GuidesListPage {
  @Local vm: GuidesVM = new GuidesVM();
  @Local refreshing: boolean = false;
  private pathStack: NavPathStack | null = null;

  private open(g: GuideSummary): void {
    const param: GuideParam = { locale: this.vm.selectedLocale, slug: g.slug, title: g.title, url: g.url };
    this.pathStack?.pushPathByName(Routes.GUIDE_ARTICLE, param);
  }

  @Builder
  localeBar() {
    Row({ space: 6 }) {
      ForEach(this.vm.locales, (l: string) => {
        Text(localeName(l))
          .fontSize(13)
          .fontWeight(this.vm.selectedLocale === l ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.vm.selectedLocale === l ? $r('app.color.oc_brand_text') : $r('sys.color.font_secondary'))
          .padding({ left: 14, right: 14 })
          .height(32)
          .borderRadius(16)
          .backgroundColor(this.vm.selectedLocale === l ? $r('app.color.oc_brand_bg') : $r('sys.color.comp_background_list_card'))
          .onClick(() => {
            this.vm.selectedLocale = l;
          })
      }, (l: string) => l)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  @Builder
  guideCard(g: GuideSummary) {
    Column({ space: 6 }) {
      Text(g.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
      Text(g.blurb !== '' ? g.blurb : g.description)
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (g.readingTime !== '' || g.updated !== '') {
        Text([g.readingTime, g.updated].filter((s: string) => s !== '').join(' · '))
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(16)
    .onClick(() => {
      this.open(g);
    })
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading && this.vm.locales.length === 0) {
          Column() {
            OCLoading({ text: '正在加载指南…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '' && this.vm.locales.length === 0) {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load().catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else {
          Column() {
            if (this.vm.locales.length > 1) {
              this.localeBar()
            }
            Refresh({ refreshing: this.refreshing }) {
              List({ space: 10 }) {
                if (this.vm.guides().length === 0) {
                  ListItem() {
                    OCEmpty({ symbol: $r('sys.symbol.doc_text'), title: '暂无指南', subtitle: '' })
                  }
                }
                ForEach(this.vm.guides(), (g: GuideSummary) => {
                  ListItem() {
                    this.guideCard(g)
                  }
                }, (g: GuideSummary) => `${this.vm.selectedLocale}_${g.slug}`)
              }
              .width('100%')
              .height('100%')
              .padding({ left: 16, right: 16, bottom: 16 })
              .scrollBar(BarState.Off)
            }
            .layoutWeight(1)
            .onRefreshing(() => {
              this.refreshing = true;
              this.vm.load().then(() => {
                this.refreshing = false;
              }).catch(() => {
                this.refreshing = false;
              });
            })
          }
          .width('100%')
          .height('100%')
        }
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: '指南' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.vm.load().catch(() => {
      });
    })
  }
}
