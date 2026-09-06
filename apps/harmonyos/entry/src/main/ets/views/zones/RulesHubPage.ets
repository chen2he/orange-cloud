// 「规则中心」聚合入口（对照 iOS ZoneRulesHubView）：把域名详情页平铺的规则类条目
// （Transform / 缓存规则 / Snippets）与五个 Rulesets phase（单条重定向 / 源站 / 配置 /
// 压缩 / 自定义错误）、Page Rules（传统）、URL 规范化收进一个二级页。
// Bulk Redirects 是账号级，挂同一入口方便发现。
import { RulesetPhases, phaseMeta } from '../../models/RulesetModels';
import { PhaseRulesParam, Routes, ZoneRouteParam } from '../../models/Routes';
import { Scopes } from '../../core/auth/Scopes';
import { authManager } from '../../core/auth/AuthManager';
import { NavRow } from '../common/Components';
import { OCLayout, RevealBox } from '../common/Daybreak';
import { OCSkyBackground } from '../common/OCSky';

interface HubEntry {
  symbol: Resource;
  title: string;
  subtitle: string;
  route: string;
  /// 非空 = 走 Routes.PHASE_RULES 泛化列表页
  phase: string;
  /// 非空 = 进入前校验的读 scope
  readScope: string;
}

interface HubSection {
  title: string;
  entries: HubEntry[];
  footer: string;
}

const HUB_SECTIONS: HubSection[] = [
  {
    title: '重定向',
    footer: '',
    entries: [
      {
        symbol: $r('sys.symbol.arrow_right'),
        title: '单条重定向',
        subtitle: '按表达式跳转到目标 URL',
        route: Routes.PHASE_RULES,
        phase: RulesetPhases.SINGLE_REDIRECT,
        readScope: phaseMeta(RulesetPhases.SINGLE_REDIRECT).readScope,
      },
      {
        symbol: $r('sys.symbol.rectangle_stack'),
        title: 'Bulk Redirects',
        subtitle: '账号级批量重定向列表',
        route: Routes.REDIRECTS,
        phase: '',
        readScope: Scopes.REDIRECTS_READ,
      },
    ],
  },
  {
    title: '流量与内容',
    footer: '',
    entries: [
      {
        symbol: $r('sys.symbol.externaldrive'),
        title: '源站规则',
        subtitle: 'Host 头覆写 / 回源端口',
        route: Routes.PHASE_RULES,
        phase: RulesetPhases.ORIGIN,
        readScope: phaseMeta(RulesetPhases.ORIGIN).readScope,
      },
      {
        symbol: $r('sys.symbol.line_3_horizontal'),
        title: '配置规则',
        subtitle: '按表达式覆盖 Zone 设置',
        route: Routes.PHASE_RULES,
        phase: RulesetPhases.CONFIG,
        readScope: phaseMeta(RulesetPhases.CONFIG).readScope,
      },
      {
        symbol: $r('sys.symbol.square_stack_3d'),
        title: '压缩规则',
        subtitle: '响应压缩算法偏好',
        route: Routes.PHASE_RULES,
        phase: RulesetPhases.COMPRESSION,
        readScope: phaseMeta(RulesetPhases.COMPRESSION).readScope,
      },
      {
        symbol: $r('sys.symbol.exclamationmark_triangle'),
        title: '自定义错误',
        subtitle: '自定义错误响应内容',
        route: Routes.PHASE_RULES,
        phase: RulesetPhases.CUSTOM_ERRORS,
        readScope: phaseMeta(RulesetPhases.CUSTOM_ERRORS).readScope,
      },
    ],
  },
  {
    title: '改写与缓存',
    footer: '',
    entries: [
      {
        symbol: $r('sys.symbol.arrow_left_arrow_right'),
        title: 'Transform 规则',
        subtitle: 'URL 重写 / 头部修改',
        route: Routes.TRANSFORM,
        phase: '',
        readScope: Scopes.TRANSFORM_READ,
      },
      {
        symbol: $r('sys.symbol.archivebox'),
        title: '缓存规则',
        subtitle: 'Cache Rules',
        route: Routes.CACHE_RULES,
        phase: '',
        readScope: Scopes.CACHE_RULES_READ,
      },
      {
        symbol: $r('sys.symbol.code_slash'),
        title: 'Snippets',
        subtitle: '边缘 JS 片段',
        route: Routes.SNIPPETS,
        phase: '',
        readScope: Scopes.SNIPPETS_READ,
      },
    ],
  },
  {
    title: '传统与全局',
    footer: 'Page Rules 为传统功能，仅支持查看、启停与删除；其余规则类型支持在 App 内创建与编辑。',
    entries: [
      {
        symbol: $r('sys.symbol.doc_text'),
        title: 'Page Rules',
        subtitle: '传统页面规则，查看 / 启停 / 删除',
        route: Routes.PAGE_RULES,
        phase: '',
        readScope: 'page-rules.read',
      },
      {
        symbol: $r('sys.symbol.wand_and_stars'),
        title: 'URL 规范化',
        subtitle: '影响所有规则的表达式匹配',
        route: Routes.URL_NORMALIZATION,
        phase: '',
        readScope: phaseMeta(RulesetPhases.CONFIG).readScope,
      },
    ],
  },
];

@ComponentV2
export struct RulesHubPage {
  @Local zoneId: string = '';
  @Local zoneName: string = '';
  private pathStack: NavPathStack | null = null;

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  private open(entry: HubEntry): void {
    if (entry.readScope !== '' && !authManager.hasScope(entry.readScope)) {
      this.toast(`当前授权未包含 ${entry.readScope} 权限`);
      return;
    }
    if (entry.phase !== '') {
      const meta = phaseMeta(entry.phase);
      const param: PhaseRulesParam = {
        zoneId: this.zoneId,
        zoneName: this.zoneName,
        phase: entry.phase,
        title: meta.title,
      };
      this.pathStack?.pushPathByName(Routes.PHASE_RULES, param);
      return;
    }
    if (entry.route === Routes.REDIRECTS) {
      // 账号级页面无参
      this.pathStack?.pushPathByName(Routes.REDIRECTS, null);
      return;
    }
    const param: ZoneRouteParam = { zoneId: this.zoneId, zoneName: this.zoneName };
    this.pathStack?.pushPathByName(entry.route, param);
  }

  @Builder
  hubSection(section: HubSection) {
    Column({ space: 8 }) {
      Text(section.title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .padding({ left: 4 })
      Column() {
        ForEach(section.entries, (entry: HubEntry, index: number) => {
          NavRow({
            symbol: entry.symbol,
            title: entry.title,
            subtitle: entry.subtitle,
            onNav: () => {
              this.open(entry);
            },
          })
          if (index < section.entries.length - 1) {
            Divider()
              .strokeWidth(0.5)
              .color($r('sys.color.comp_divider'))
              .margin({ left: 64 })
          }
        }, (entry: HubEntry) => `${entry.route}-${entry.phase}`)
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_list_card'))
      .borderRadius(OCLayout.chipRadius)
      .border({ width: 0.5, color: $r('sys.color.comp_divider') })
      .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
      .clip(true)

      if (section.footer !== '') {
        Text(section.footer)
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .padding({ left: 4, right: 4 })
      }
    }
    .width('100%')
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        Scroll() {
          Column({ space: 18 }) {
            // 四个分组岛按视觉顺序错峰浮现
            ForEach(HUB_SECTIONS, (section: HubSection, index: number) => {
              RevealBox({ idx: index }) {
                this.hubSection(section)
              }
            }, (section: HubSection) => section.title)
          }
          .width('100%')
          .padding(OCLayout.pagePadding)
        }
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
    }
    .title(`${this.zoneName} · 规则`)
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as ZoneRouteParam;
      this.zoneId = param.zoneId;
      this.zoneName = param.zoneName;
    })
  }
}
