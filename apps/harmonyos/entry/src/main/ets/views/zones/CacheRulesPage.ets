// 缓存规则（Rulesets http_request_cache_settings）：列表 / 启停 / 新建 / 编辑 / 删除。
// 表单开放：表达式 + 缓存资格（缓存/绕过）+ 边缘 TTL 覆写（对齐 Android ZoneCacheRulesScreen 常用面）。
import { BrowserTTL, cacheRuleHasAdvanced, EdgeTTL, RuleActionParameters, RulesetPhases, RulesetRule,
  RulesetRuleCreate, ServeStale } from '../../models/RulesetModels';
import { ZoneRouteParam } from '../../models/Routes';
import { RulesetVM } from '../../services/RulesetService';
import { BRAND_ORANGE, OCEmpty, OCError, OCLoading } from '../common/Components';
import { RuleRow } from './RuleComponents';
import { ExpressionBuilder } from './ExpressionBuilder';
import { lintExpression } from '../../models/RuleExpressionBuilder';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';

@ComponentV2
export struct CacheRulesPage {
  @Local vm: RulesetVM = new RulesetVM(RulesetPhases.CACHE_SETTINGS);
  @Local zoneId: string = '';
  @Local zoneName: string = '';
  @Local editorVisible: boolean = false;
  @Local editingId: string = '';
  @Local fDescription: string = '';
  @Local fExpression: string = '';
  @Local fCache: boolean = true;
  @Local fEnabled: boolean = true;
  @Local fEdgeTtl: string = '';
  @Local fBrowserTtl: string = '';
  @Local fServeStale: boolean = false;
  @Local fRespectEtags: boolean = false;
  @Local fOriginErrorPassthru: boolean = false;
  /// 含 App 未开放的高级设置（缓存键 / Cache Reserve / Vary 多版本缓存等）→ 本条只读，
  /// 免得整量回写把控制台里配好的高级项丢掉（对齐 iOS isReadOnly）
  @Local fReadOnly: boolean = false;
  /// 编辑时原样保留的按状态码 TTL（App 不提供编辑但不能丢）
  private preservedStatusCodeTtl: object[] | undefined = undefined;

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  private rules(): RulesetRule[] {
    return this.vm.ruleset?.rules ?? [];
  }

  private openEditor(rule: RulesetRule | null): void {
    this.vm.saveError = '';
    if (rule) {
      const params = rule.action_parameters;
      this.editingId = rule.id;
      this.fDescription = rule.description ?? '';
      this.fExpression = rule.expression ?? '';
      this.fEnabled = rule.enabled !== false;
      this.fCache = params?.cache !== false;
      const ttl = params?.edge_ttl?.default;
      this.fEdgeTtl = ttl !== undefined ? `${ttl}` : '';
      const browserTtl = params?.browser_ttl?.default;
      this.fBrowserTtl = browserTtl !== undefined ? `${browserTtl}` : '';
      // serve_stale 的语义是「更新时不提供陈旧内容」，界面按正向开关展示
      this.fServeStale = params?.serve_stale?.disable_stale_while_updating === false;
      this.fRespectEtags = params?.respect_strong_etags === true;
      this.fOriginErrorPassthru = params?.origin_error_page_passthru === true;
      this.preservedStatusCodeTtl = params?.edge_ttl?.status_code_ttl;
      this.fReadOnly = cacheRuleHasAdvanced(params);
    } else {
      this.editingId = '';
      this.fDescription = '';
      this.fExpression = '';
      this.fEnabled = true;
      this.fCache = true;
      this.fEdgeTtl = '';
      this.fBrowserTtl = '';
      this.fServeStale = false;
      this.fRespectEtags = false;
      this.fOriginErrorPassthru = false;
      this.preservedStatusCodeTtl = undefined;
      this.fReadOnly = false;
    }
    this.editorVisible = true;
  }

  private submit(): void {
    const lint: string = lintExpression(this.fExpression.trim());
    if (lint !== '') {
      this.toast(lint);
      return;
    }
    const params: RuleActionParameters = { cache: this.fCache };
    if (this.fCache) {
      const ttl = Number.parseInt(this.fEdgeTtl.trim());
      const edgeTtl: EdgeTTL = !Number.isNaN(ttl) && ttl > 0
        ? { mode: 'override_origin', default: ttl }
        : { mode: 'respect_origin' };
      // 按状态码 TTL 不开放编辑，但原样带回，避免整量回写丢配置
      edgeTtl.status_code_ttl = this.preservedStatusCodeTtl;
      params.edge_ttl = edgeTtl;
      const browserTtl = Number.parseInt(this.fBrowserTtl.trim());
      const browser: BrowserTTL = !Number.isNaN(browserTtl) && browserTtl > 0
        ? { mode: 'override_origin', default: browserTtl }
        : { mode: 'respect_origin' };
      params.browser_ttl = browser;
      const stale: ServeStale = { disable_stale_while_updating: !this.fServeStale };
      params.serve_stale = stale;
      params.respect_strong_etags = this.fRespectEtags;
      params.origin_error_page_passthru = this.fOriginErrorPassthru;
    }
    const rule: RulesetRuleCreate = {
      action: 'set_cache_settings',
      expression: this.fExpression.trim(),
      description: this.fDescription.trim(),
      enabled: this.fEnabled,
      action_parameters: params,
    };
    this.vm.save(this.zoneId, this.editingId, rule).then((ok: boolean) => {
      if (ok) {
        this.editorVisible = false;
      }
    });
  }

  private confirmDelete(rule: RulesetRule): void {
    this.getUIContext().showAlertDialog({
      title: '删除缓存规则',
      message: `确定删除「${rule.description ?? rule.id}」？`,
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#DC2626',
        action: () => {
          this.vm.remove(this.zoneId, rule.id).then((err: string) => {
            this.toast(err === '' ? '已删除' : err);
          });
        },
      },
    });
  }

  /// 开关行（缓存高级选项共用；只读规则整体禁用）
  /// isOn 传取值函数而非布尔值：@Builder 的值参数是静态的，传死值时开关与 state 会脱钩
  /// （模型拒绝改动时界面不回弹）。函数在 Builder 内部调用，读到的状态才会被追踪重绘。
  @Builder
  optionRow(title: string, subtitle: string, isOn: () => boolean, onToggle: (on: boolean) => void) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
        Text(subtitle)
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: isOn() })
        .selectedColor($r('app.color.oc_brand'))
        .enabled(!this.fReadOnly)
        .onChange((on: boolean) => {
          onToggle(on);
        })
    }
    .width('100%')
  }

  @Builder
  editorSheet() {
    Column({ space: 12 }) {
      Text(this.editingId === '' ? '新建缓存规则' : '编辑缓存规则')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })

      TextInput({ text: this.fDescription, placeholder: '规则描述' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fDescription = value;
        })

      ExpressionBuilder({
        expression: this.fExpression,
        onChange: (e: string) => {
          this.fExpression = e;
        },
      })

      Row({ space: 12 }) {
        Column({ space: 2 }) {
          Text(this.fCache ? '缓存资格：缓存' : '缓存资格：绕过缓存')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Text(this.fCache ? '命中表达式的请求走边缘缓存' : '命中表达式的请求直连源站')
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.fCache })
          .selectedColor($r('app.color.oc_brand'))
          .onChange((isOn: boolean) => {
            this.fCache = isOn;
          })
      }
      .width('100%')

      if (this.fCache) {
        TextInput({ text: this.fEdgeTtl, placeholder: '边缘 TTL 秒数（留空 = 遵循源站）' })
          .type(InputType.Number)
          .fontSize(14)
          .width('100%')
          .enabled(!this.fReadOnly)
          .onChange((value: string) => {
            this.fEdgeTtl = value;
          })
        TextInput({ text: this.fBrowserTtl, placeholder: '浏览器 TTL 秒数（留空 = 遵循源站）' })
          .type(InputType.Number)
          .fontSize(14)
          .width('100%')
          .enabled(!this.fReadOnly)
          .onChange((value: string) => {
            this.fBrowserTtl = value;
          })
        this.optionRow('重新验证时提供陈旧内容', '回源更新时先返回旧缓存，减少等待', (): boolean => this.fServeStale,
          (on: boolean) => {
            this.fServeStale = on;
          })
        this.optionRow('尊重强 ETag', '按源站强 ETag 判定缓存是否命中', (): boolean => this.fRespectEtags,
          (on: boolean) => {
            this.fRespectEtags = on;
          })
        this.optionRow('透传源站错误页', '源站 5xx 时直接把错误页返回给访客', (): boolean => this.fOriginErrorPassthru,
          (on: boolean) => {
            this.fOriginErrorPassthru = on;
          })
      }

      this.optionRow('启用', '关闭后规则保留但不生效', (): boolean => this.fEnabled, (on: boolean) => {
        this.fEnabled = on;
      })

      if (this.fReadOnly) {
        Text('这条规则含 App 未开放的高级设置（缓存键 / Cache Reserve / Vary 多版本缓存等），为避免保存时丢配置，此处只读。请在 Cloudflare 控制台修改。')
          .fontSize(11)
          .fontColor('#EA580C')
          .width('100%')
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
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm.isSaving && !this.fReadOnly && this.fExpression.trim() !== '')
        .onClick(() => {
          this.submit();
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载缓存规则…' })
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
        } else if (this.rules().length === 0) {
          Column() {
            OCEmpty({ symbol: $r('sys.symbol.archivebox'), title: '暂无缓存规则', subtitle: '点右下角 + 创建第一条规则' })
          }
          .width('100%')
          .height('100%')
        } else {
          List() {
            ForEach(this.rules(), (rule: RulesetRule) => {
              ListItem() {
                RuleRow({
                  rule: rule,
                  busy: this.vm.isSaving,
                  onEdit: () => {
                    this.openEditor(rule);
                  },
                  onToggle: (enabled: boolean) => {
                    this.vm.toggle(this.zoneId, rule.id, enabled).then((err: string) => {
                      this.toast(err);
                    });
                  },
                  onDelete: () => {
                    this.confirmDelete(rule);
                  },
                })
              }
            }, (rule: RulesetRule) => rule.id)
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
          .shadow({ radius: 12, color: '#40000000', offsetY: 4 })
          .margin({ right: 20, bottom: 28 })
          .onClick(() => {
            this.openEditor(null);
          })
      }
      .width('100%')
      .height('100%')
    }
    .title(`${this.zoneName} · 缓存规则`)
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.editorVisible, this.editorSheet(), ocSheet(() => {
      this.editorVisible = false;
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
