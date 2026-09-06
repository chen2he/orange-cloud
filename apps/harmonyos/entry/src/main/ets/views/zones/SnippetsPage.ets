// Snippets：片段列表（点入编辑、长按删除）+ 规则整组管理（对齐 Android SnippetsScreens）。
import { Snippet, SnippetRule, SnippetService } from '../../services/SnippetService';
import { Routes, SnippetEditParam, ZoneRouteParam } from '../../models/Routes';
import { formatTimeAgo } from '../../core/util/Format';
import { BRAND_ORANGE, OCEmpty, OCError, OCLoading, SectionHeader } from '../common/Components';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';

@ObservedV2
export class SnippetsVM {
  @Trace snippets: Snippet[] = [];
  @Trace rules: SnippetRule[] = [];
  @Trace isLoading: boolean = false;
  @Trace error: string = '';

  private service: SnippetService = new SnippetService();

  async load(zoneId: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.snippets = await this.service.list(zoneId);
      this.rules = await this.service.rules(zoneId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async removeSnippet(zoneId: string, name: string): Promise<string> {
    try {
      await this.service.remove(zoneId, name);
      this.snippets = this.snippets.filter((s: Snippet) => s.snippet_name !== name);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }

  /// 规则整组回写（toggle/删除/新增都全量 PUT）
  async saveRules(zoneId: string, rules: SnippetRule[]): Promise<string> {
    try {
      await this.service.putRules(zoneId, rules);
      this.rules = rules;
      return '';
    } catch (e) {
      return (e as Error).message ?? '保存规则失败';
    }
  }
}

@ComponentV2
export struct SnippetsPage {
  @Local vm: SnippetsVM = new SnippetsVM();
  @Local zoneId: string = '';
  @Local zoneName: string = '';
  @Local ruleSheetVisible: boolean = false;
  @Local fRuleExpression: string = '';
  @Local fRuleSnippet: string = '';
  private pathStack: NavPathStack | null = null;

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  private openEdit(name: string): void {
    const param: SnippetEditParam = { zoneId: this.zoneId, zoneName: this.zoneName, snippetName: name };
    this.pathStack?.pushPathByName(Routes.SNIPPET_EDIT, param);
  }

  private confirmDeleteSnippet(snippet: Snippet): void {
    this.getUIContext().showAlertDialog({
      title: '删除 Snippet',
      message: `确定删除「${snippet.snippet_name}」？关联规则会失效。`,
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#DC2626',
        action: () => {
          this.vm.removeSnippet(this.zoneId, snippet.snippet_name).then((err: string) => {
            this.toast(err === '' ? '已删除' : err);
          });
        },
      },
    });
  }

  @Builder
  ruleRow(rule: SnippetRule, index: number) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(rule.snippet_name)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        Text(rule.expression)
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .fontFamily('monospace')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: rule.enabled === true })
        .selectedColor($r('app.color.oc_brand'))
        .onChange((isOn: boolean) => {
          if (isOn !== (rule.enabled === true)) {
            const next = this.vm.rules.map((r: SnippetRule, i: number): SnippetRule => {
              if (i === index) {
                const toggled: SnippetRule = {
                  expression: r.expression,
                  snippet_name: r.snippet_name,
                  enabled: isOn,
                  description: r.description,
                };
                return toggled;
              }
              return r;
            });
            this.vm.saveRules(this.zoneId, next).then((err: string) => {
              this.toast(err);
            });
          }
        })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .gesture(LongPressGesture().onAction(() => {
      const next = this.vm.rules.filter((r: SnippetRule, i: number) => i !== index);
      this.vm.saveRules(this.zoneId, next).then((err: string) => {
        this.toast(err === '' ? '已删除规则' : err);
      });
    }))
  }

  @Builder
  addRuleSheet() {
    Column({ space: 12 }) {
      Text('添加 Snippet 规则')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })

      Row({ space: 12 }) {
        Text('片段')
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        Select(this.vm.snippets.map((s: Snippet): SelectOption => ({ value: s.snippet_name })))
          .selected(this.vm.snippets.findIndex((s: Snippet) => s.snippet_name === this.fRuleSnippet))
          .value(this.fRuleSnippet !== '' ? this.fRuleSnippet : '选择片段')
          .font({ size: 14 })
          .onSelect((index: number) => {
            this.fRuleSnippet = this.vm.snippets[index].snippet_name;
          })
      }
      .width('100%')

      TextArea({ text: this.fRuleExpression, placeholder: '触发表达式，如 (http.request.uri.path contains "/api/")' })
        .fontSize(12)
        .height(90)
        .width('100%')
        .onChange((value: string) => {
          this.fRuleExpression = value;
        })

      Button('添加（整组回写）')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(this.fRuleSnippet !== '' && this.fRuleExpression.trim() !== '')
        .onClick(() => {
          const newRule: SnippetRule = {
            expression: this.fRuleExpression.trim(),
            snippet_name: this.fRuleSnippet,
            enabled: true,
          };
          this.vm.saveRules(this.zoneId, this.vm.rules.concat([newRule])).then((err: string) => {
            if (err === '') {
              this.ruleSheetVisible = false;
              this.fRuleExpression = '';
            } else {
              this.toast(err);
            }
          });
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
            OCLoading({ text: '正在加载 Snippets…' })
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
                SectionHeader({ title: `片段（${this.vm.snippets.length}）· 点入编辑，长按删除` })
                if (this.vm.snippets.length === 0) {
                  Column() {
                    OCEmpty({ symbol: $r('sys.symbol.doc_plaintext'), title: '暂无 Snippet', subtitle: '点右下角 + 新建边缘 JS 片段' })
                  }
                  .height(180)
                } else {
                  Column() {
                    ForEach(this.vm.snippets, (snippet: Snippet) => {
                      Row({ space: 10 }) {
                        Text('📜')
                          .fontSize(18)
                        Column({ space: 2 }) {
                          Text(snippet.snippet_name)
                            .fontSize(14)
                            .fontWeight(FontWeight.Medium)
                            .fontColor($r('sys.color.font_primary'))
                          if (snippet.modified_on) {
                            Text(`更新于 ${formatTimeAgo(snippet.modified_on ?? '')}`)
                              .fontSize(11)
                              .fontColor($r('sys.color.font_tertiary'))
                          }
                        }
                        .alignItems(HorizontalAlign.Start)
                        .layoutWeight(1)

                        Image($r('sys.media.ohos_ic_public_arrow_right'))
                          .width(16)
                          .height(16)
                          .fillColor($r('sys.color.font_tertiary'))
                      }
                      .width('100%')
                      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                      .onClick(() => {
                        this.openEdit(snippet.snippet_name);
                      })
                      .gesture(LongPressGesture().onAction(() => {
                        this.confirmDeleteSnippet(snippet);
                      }))
                    }, (snippet: Snippet) => snippet.snippet_name)
                  }
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(14)
                  .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                  .clip(true)
                  .margin({ left: 16, right: 16 })
                }
              }
              .width('100%')

              Column() {
                Row() {
                  SectionHeader({ title: `触发规则（${this.vm.rules.length}）· 长按删除` })
                  Blank()
                  Text('＋加规则')
                    .fontSize(13)
                    .fontColor($r('app.color.oc_brand_text'))
                    .padding({ right: 20, top: 16 })
                    .onClick(() => {
                      if (this.vm.snippets.length === 0) {
                        this.toast('先创建一个 Snippet');
                        return;
                      }
                      this.fRuleSnippet = this.vm.snippets[0].snippet_name;
                      this.ruleSheetVisible = true;
                    })
                }
                .width('100%')

                if (this.vm.rules.length === 0) {
                  Text('尚无触发规则；片段需要规则才会在边缘执行')
                    .fontSize(12)
                    .fontColor($r('sys.color.font_tertiary'))
                    .padding({ left: 20, top: 4, bottom: 8 })
                    .width('100%')
                } else {
                  Column() {
                    ForEach(this.vm.rules, (rule: SnippetRule, index: number) => {
                      this.ruleRow(rule, index)
                    }, (rule: SnippetRule, index: number) => `${index}-${rule.snippet_name}`)
                  }
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(14)
                  .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                  .clip(true)
                  .margin({ left: 16, right: 16 })
                }
              }
              .width('100%')
              .margin({ bottom: 90 })
            }
            .width('100%')
          }
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .width('100%')
          .height('100%')
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
            this.openEdit('');
          })
      }
      .width('100%')
      .height('100%')
    }
    .title(`${this.zoneName} · Snippets`)
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.ruleSheetVisible, this.addRuleSheet(), ocSheet(() => {
      this.ruleSheetVisible = false;
    }))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as ZoneRouteParam;
      this.zoneId = param.zoneId;
      this.zoneName = param.zoneName;
      this.vm.load(param.zoneId).catch(() => {
      });
    })
    .onShown(() => {
      // 从编辑页返回后刷新列表
      if (this.zoneId !== '' && !this.vm.isLoading) {
        this.vm.load(this.zoneId).catch(() => {
        });
      }
    })
  }
}
