import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { HdsNavDestination } from '@kit.UIDesignKit';
// 指南正文（对齐 iOS GuideArticleView）：官网 feed 的结构化块原生渲染。
// 块类型：heading / paragraph / note / list / code / quote / figure / table；
// 行内为极小 markdown 子集（GuideInline 解析），链接点按交给系统浏览器。
// 内联 SVG 示意图渲染不了，feed 给的是它的 aria-label，按图注展示。
import { GuideArticle, GuideBlock, GuideService } from '../../services/GuideService';
import { GuideParam } from '../../models/Routes';
import { GlobalContext } from '../../core/system/GlobalContext';
import { InlineSegment, parseInline } from './GuideInline';
import { OCError, OCLoading } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';

/// base = 文章网页地址：页内锚点（#delegation）App 里无法定位，交给浏览器打开原文对应段落
function openExternal(url: string, base: string = ''): void {
  let target = url;
  if (target.startsWith('#')) {
    const page = base.split('#')[0];
    if (page === '') {
      return;
    }
    target = `${page}${target}`;
  }
  if (target.startsWith('/')) {
    target = `https://o-c.do${target}`;
  }
  if (!target.startsWith('http://') && !target.startsWith('https://')) {
    return;
  }
  GlobalContext.get().openLink(target).catch(() => {
  });
}

@ComponentV2
struct InlineText {
  @Param md: string = '';
  @Param base: string = '';
  @Param fs: number = 15;
  @Param lineHeight: number = 24;
  @Param color: ResourceColor = $r('sys.color.font_primary');

  build() {
    Text() {
      ForEach(parseInline(this.md), (s: InlineSegment) => {
        if (s.code) {
          Span(s.text)
            .fontFamily('monospace')
            .fontSize(this.fs - 1)
            .fontColor($r('app.color.oc_brand_text'))
        } else if (s.link !== '') {
          Span(s.text)
            .fontColor($r('app.color.oc_brand_text'))
            .fontWeight(s.bold ? FontWeight.Bold : FontWeight.Normal)
            .decoration({ type: TextDecorationType.Underline, color: $r('app.color.oc_brand_text') })
            .onClick(() => {
              openExternal(s.link, this.base);
            })
        } else {
          Span(s.text)
            .fontWeight(s.bold ? FontWeight.Bold : FontWeight.Normal)
            .fontStyle(s.italic ? FontStyle.Italic : FontStyle.Normal)
        }
      }, (s: InlineSegment, i: number) => `${i}`)
    }
    .fontSize(this.fs)
    .lineHeight(this.lineHeight)
    .fontColor(this.color)
    .width('100%')
  }
}

@ComponentV2
export struct GuideArticlePage {
  @Local article: GuideArticle | null = null;
  @Local isLoading: boolean = false;
  @Local error: string = '';
  @Local param: GuideParam = { locale: 'zh-Hans', slug: '', title: '', url: '' };
  private service: GuideService = new GuideService();

  private pageUrl(): string {
    const url = this.article !== null && this.article!.url !== '' ? this.article!.url : this.param.url;
    return url.startsWith('/') ? `https://o-c.do${url}` : url;
  }

  private load(): void {
    this.isLoading = true;
    this.error = '';
    this.service.article(this.param.locale, this.param.slug).then((a: GuideArticle) => {
      this.article = a;
      this.isLoading = false;
    }).catch((e: Error) => {
      // 已有缓存垫底时不打断阅读，只在完全没内容时报错
      if (this.article === null) {
        this.error = e.message ?? '加载失败';
      }
      this.isLoading = false;
    });
  }

  @Builder
  blockView(b: GuideBlock) {
    if (b.type === 'heading') {
      Text(b.text ?? '')
        .fontSize((b.level ?? 2) <= 2 ? 20 : 17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 10 })
    } else if (b.type === 'paragraph') {
      InlineText({ md: b.md ?? '', base: this.pageUrl() })
    } else if (b.type === 'note') {
      Column({ space: 6 }) {
        ForEach(b.items ?? [], (item: string, i: number) => {
          InlineText({ md: item, base: this.pageUrl(), fs: 14, lineHeight: 22 })
        }, (item: string, i: number) => `${i}`)
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('app.color.oc_brand_bg'))
      .borderRadius(12)
    } else if (b.type === 'list') {
      Column({ space: 6 }) {
        ForEach(b.items ?? [], (item: string, i: number) => {
          Row({ space: 8 }) {
            Text(b.ordered === true ? `${i + 1}.` : '•')
              .fontSize(15)
              .lineHeight(24)
              .fontColor($r('sys.color.font_secondary'))
              .constraintSize({ minWidth: 16 })
            Column() {
              InlineText({ md: item, base: this.pageUrl() })
            }
            .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (item: string, i: number) => `${i}`)
      }
      .width('100%')
    } else if (b.type === 'code') {
      Scroll() {
        Text(b.text ?? '')
          .fontSize(12)
          .lineHeight(18)
          .fontFamily('monospace')
          .fontColor($r('sys.color.font_primary'))
          .textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
          .padding(12)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .borderRadius(10)
    } else if (b.type === 'quote') {
      Row({ space: 10 }) {
        Column()
          .width(3)
          .height('100%')
          .backgroundColor($r('app.color.oc_brand'))
          .borderRadius(2)
        Column() {
          InlineText({ md: b.md ?? '', base: this.pageUrl(), color: $r('sys.color.font_secondary') })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    } else if (b.type === 'figure') {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.picture'))
          .fontSize(16)
          .fontColor([$r('sys.color.font_tertiary')])
        Text(b.alt ?? '')
          .fontSize(13)
          .lineHeight(20)
          .fontColor($r('sys.color.font_secondary'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding(12)
      .alignItems(VerticalAlign.Top)
      .backgroundColor($r('sys.color.comp_background_list_card'))
      .borderRadius(10)
    } else if (b.type === 'table') {
      Scroll() {
        Column() {
          Row() {
            ForEach(b.headers ?? [], (h: string, i: number) => {
              Text(h)
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('sys.color.font_primary'))
                .width(140)
                .padding(8)
            }, (h: string, i: number) => `h${i}`)
          }
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          ForEach(b.rows ?? [], (row: string[], r: number) => {
            Row() {
              ForEach(row, (cell: string, i: number) => {
                Column() {
                  InlineText({ md: cell, base: this.pageUrl(), fs: 12, lineHeight: 18 })
                }
                .width(140)
                .padding(8)
              }, (cell: string, i: number) => `c${r}_${i}`)
            }
            .alignItems(VerticalAlign.Top)
            .border({ width: { top: 0.5 }, color: $r('sys.color.comp_divider') })
          }, (row: string[], r: number) => `r${r}`)
        }
        .alignItems(HorizontalAlign.Start)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_list_card'))
      .borderRadius(10)
    }
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.article === null && this.isLoading) {
          Column() {
            OCLoading({ text: '正在加载正文…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.article === null && this.error !== '') {
          Column() {
            OCError({
              message: this.error,
              onRetry: () => {
                this.load();
              },
            })
          }
          .width('100%')
          .height('100%')
        } else if (this.article !== null) {
          Scroll() {
            Column({ space: 14 }) {
              Text(this.article!.title)
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('sys.color.font_primary'))
                .width('100%')
              if (this.article!.readingTime !== '' || this.article!.updated !== '') {
                Text([this.article!.readingTime, this.article!.updated].filter((s: string) => s !== '').join(' · '))
                  .fontSize(12)
                  .fontColor($r('sys.color.font_tertiary'))
                  .width('100%')
              }
              ForEach(this.article!.blocks, (b: GuideBlock, i: number) => {
                this.blockView(b)
              }, (b: GuideBlock, i: number) => `${this.article!.slug}_${i}`)
              Text('在官网阅读原文')
                .fontSize(13)
                .fontColor($r('app.color.oc_brand_text'))
                .margin({ top: 12 })
                .onClick(() => {
                  openExternal(this.article!.url !== '' ? this.article!.url : this.param.url);
                })
            }
            .padding({ left: 20, right: 20, top: 8, bottom: 32 })
            .width('100%')
          }
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
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: '指南' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      this.param = context.pathInfo.param as GuideParam;
      // 读过的文章先用缓存垫底，打开即有内容，网络结果回来再替换
      this.article = this.service.cachedArticle(this.param.locale, this.param.slug);
      this.load();
    })
  }
}
