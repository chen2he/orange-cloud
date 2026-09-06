// Turnstile 人机验证：widget 列表 / 新建 / 编辑 / 密钥轮换 / 删除（对齐 iOS Views/Turnstile）。
// 读 challenge-widgets.read，写操作按 challenge-widgets.write 门控；入口在概览页「网络」岛，
// 整模块是 Pro 闸门（对齐 iOS ProGatedValueLink(feature: .turnstile)）。
import { Routes, NameParam } from '../../models/Routes';
import {
  TurnstileService, TurnstileWidget, TurnstileWidgetInput,
  TURNSTILE_MODES, turnstileModeLabel, turnstileModeDetail,
} from '../../services/TurnstileService';
import { accountStore } from '../../core/store/AccountStore';
import { authManager } from '../../core/auth/AuthManager';
import { Scopes } from '../../core/auth/Scopes';
import { BRAND_ORANGE, DANGER_RED, OCEmpty, OCError, OCLoading, OCTag, ResourceCard, SectionHeader } from '../common/Components';
import { OCLayout } from '../common/Daybreak';
import { OCSkyBackground } from '../common/OCSky';
import { ocSheet } from '../common/Sheets';
import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';

/// 每行一个域名，去空白去空行去重（保序，小写）——对齐 iOS TurnstileEditorSheet.domains
function parseDomains(text: string): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  text.split('\n').forEach((line: string) => {
    const item = line.trim().toLowerCase();
    if (item !== '' && !seen.has(item)) {
      seen.add(item);
      out.push(item);
    }
  });
  return out;
}

@ObservedV2
class TurnstileVM {
  @Trace widgets: TurnstileWidget[] = [];
  @Trace isLoading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace error: string = '';
  @Trace isSaving: boolean = false;
  @Trace saveError: string = '';
  private service: TurnstileService = new TurnstileService();

  async load(): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.widgets = await this.service.list(accountStore.selectedId);
      this.loaded = true;
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async detail(sitekey: string): Promise<TurnstileWidget | null> {
    try {
      return await this.service.detail(accountStore.selectedId, sitekey);
    } catch (e) {
      return null;
    }
  }

  async save(sitekey: string, input: TurnstileWidgetInput): Promise<TurnstileWidget | null> {
    this.isSaving = true;
    this.saveError = '';
    try {
      const saved = sitekey === ''
        ? await this.service.create(accountStore.selectedId, input)
        : await this.service.update(accountStore.selectedId, sitekey, input);
      await this.load();
      return saved;
    } catch (e) {
      this.saveError = (e as Error).message ?? '保存失败';
      return null;
    } finally {
      this.isSaving = false;
    }
  }

  async remove(sitekey: string): Promise<string> {
    try {
      await this.service.remove(accountStore.selectedId, sitekey);
      this.widgets = this.widgets.filter((w: TurnstileWidget) => w.sitekey !== sitekey);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }

  async rotate(sitekey: string, immediately: boolean): Promise<TurnstileWidget | null> {
    try {
      return await this.service.rotateSecret(accountStore.selectedId, sitekey, immediately);
    } catch (e) {
      this.error = (e as Error).message ?? '轮换失败';
      return null;
    }
  }
}

/// 列表与详情共用一个 VM 实例：详情页保存 / 删除后列表即时同步
const turnstileVM: TurnstileVM = new TurnstileVM();

@ComponentV2
export struct TurnstileListPage {
  @Local vm: TurnstileVM = turnstileVM;
  @Local refreshing: boolean = false;
  @Local showEditor: boolean = false;
  /// 编辑表单状态（sitekey 为空 = 新建）
  @Local fSitekey: string = '';
  @Local fName: string = '';
  @Local fModeIndex: number = 0;
  @Local fDomains: string = '';
  @Local fBotFight: boolean = false;
  @Local fRegionIndex: number = 0;
  /// 编辑时原样回写，避免 PUT 丢配置
  private editingClearance: string = '';
  private pathStack: NavPathStack | null = null;
  private canWrite: boolean = authManager.hasScope(Scopes.CHALLENGE_WIDGETS_WRITE);

  private toast(msg: string): void {
    if (msg !== '') {
      promptAction.showToast({ message: msg });
    }
  }

  private openCreate(): void {
    if (!this.canWrite) {
      this.deniedAlert();
      return;
    }
    this.fSitekey = '';
    this.fName = '';
    this.fModeIndex = 0;
    this.fDomains = '';
    this.fBotFight = false;
    this.fRegionIndex = 0;
    this.editingClearance = '';
    this.vm.saveError = '';
    this.showEditor = true;
  }

  private deniedAlert(): void {
    promptAction.showDialog({
      title: '权限不足',
      message: '当前授权未包含 Turnstile 编辑权限（challenge-widgets.write）。请在设置里对该身份「升级授权」后重试。',
      buttons: [{ text: '好', color: '#666666' }],
    }).catch(() => {
    });
  }

  private confirmDelete(widget: TurnstileWidget): void {
    if (!this.canWrite) {
      this.deniedAlert();
      return;
    }
    promptAction.showDialog({
      title: `删除组件「${widget.name}」？`,
      message: '嵌在网站上的该组件将立即失效，此操作不可撤销。',
      buttons: [{ text: '取消', color: '#666666' }, { text: '删除', color: DANGER_RED }],
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        this.vm.remove(widget.sitekey).then((err: string) => {
          this.toast(err === '' ? '已删除' : err);
        });
      }
    }).catch(() => {
    });
  }

  @Builder
  editorSheet() {
    Scroll() {
      Column({ space: 12 }) {
        Text(this.fSitekey === '' ? '新建组件' : '编辑组件')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .margin({ top: 8 })

        TextInput({ text: this.fName, placeholder: '名称，如：官网登录页' })
          .fontSize(14)
          .width('100%')
          .onChange((value: string) => {
            this.fName = value;
          })

        Row({ space: 12 }) {
          Text('模式')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Blank()
          Select(TURNSTILE_MODES.map((m: string): SelectOption => ({ value: turnstileModeLabel(m) })))
            .selected(this.fModeIndex)
            .value(turnstileModeLabel(TURNSTILE_MODES[this.fModeIndex]))
            .font({ size: 14 })
            .onSelect((index: number) => {
              this.fModeIndex = index;
            })
        }
        .width('100%')

        Text(turnstileModeDetail(TURNSTILE_MODES[this.fModeIndex]))
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')

        Text('域名')
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
        TextArea({ text: this.fDomains, placeholder: '每行一个主机名或 IP，留空 = 任意主机名' })
          .fontSize(13)
          .fontFamily('monospace')
          .height(110)
          .width('100%')
          .onChange((value: string) => {
            this.fDomains = value;
          })
        Text(parseDomains(this.fDomains).length > 10
          ? `最多 10 个域名（当前 ${parseDomains(this.fDomains).length} 个）。`
          : '子域自动生效；留空表示任意主机名均可使用。')
          .fontSize(11)
          .fontColor(parseDomains(this.fDomains).length > 10 ? DANGER_RED : $r('sys.color.font_tertiary'))
          .width('100%')

        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text('Bot Fight Mode')
              .fontSize(14)
              .fontColor($r('sys.color.font_primary'))
            Text('对疑似机器人发放高算力挑战，加大自动化攻击成本')
              .fontSize(11)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.fBotFight })
            .selectedColor(BRAND_ORANGE)
            .onChange((isOn: boolean) => {
              this.fBotFight = isOn;
            })
        }
        .width('100%')

        // region 创建后不可改，编辑时不出现
        if (this.fSitekey === '') {
          Row({ space: 12 }) {
            Column({ space: 2 }) {
              Text('区域')
                .fontSize(14)
                .fontColor($r('sys.color.font_primary'))
              Text('创建后不可更改')
                .fontSize(11)
                .fontColor($r('sys.color.font_tertiary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Select([{ value: '全球' } as SelectOption, { value: '中国' } as SelectOption])
              .selected(this.fRegionIndex)
              .value(this.fRegionIndex === 1 ? '中国' : '全球')
              .font({ size: 14 })
              .onSelect((index: number) => {
                this.fRegionIndex = index;
              })
          }
          .width('100%')
        }

        if (this.vm.saveError !== '') {
          Text(this.vm.saveError)
            .fontSize(13)
            .fontColor(DANGER_RED)
            .width('100%')
        }

        Button(this.vm.isSaving ? '正在保存…' : (this.fSitekey === '' ? '创建' : '保存'))
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor(BRAND_ORANGE)
          .enabled(!this.vm.isSaving && this.fName.trim() !== '' && parseDomains(this.fDomains).length <= 10)
          .onClick(() => {
            const input: TurnstileWidgetInput = {
              name: this.fName.trim(),
              mode: TURNSTILE_MODES[this.fModeIndex],
              domains: parseDomains(this.fDomains),
              bot_fight_mode: this.fBotFight,
              region: this.fSitekey === '' ? (this.fRegionIndex === 1 ? 'china' : 'world') : undefined,
              clearance_level: this.editingClearance === '' ? undefined : this.editingClearance,
            };
            this.vm.save(this.fSitekey, input).then((saved: TurnstileWidget | null) => {
              if (saved !== null) {
                this.showEditor = false;
                this.toast(this.fSitekey === '' ? '已创建' : '已保存');
              }
            });
          })
      }
      .padding({ left: 20, right: 20, bottom: 24 })
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .width('100%')
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        OCSkyBackground()
        if (this.vm.isLoading && this.vm.widgets.length === 0) {
          Column() {
            OCLoading({ text: '正在加载 Turnstile 组件…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '') {
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
        } else if (this.vm.widgets.length === 0) {
          Column() {
            OCEmpty({
              symbol: $r('sys.symbol.checkmark_shield'),
              title: '没有 Turnstile 组件',
              subtitle: 'Turnstile 是 Cloudflare 的免费人机验证，替代传统验证码。点右下角 + 新建后把 sitekey 嵌进网站即可。',
            })
          }
          .width('100%')
          .height('100%')
        } else {
          Refresh({ refreshing: this.refreshing }) {
            List() {
              ForEach(this.vm.widgets, (widget: TurnstileWidget) => {
                ListItem() {
                  ResourceCard({
                    symbol: $r('sys.symbol.checkmark_shield'),
                    title: widget.name,
                    subtitle: widget.sitekey,
                    trailing: turnstileModeLabel(widget.mode),
                    onTap: () => {
                      const param: NameParam = { name: widget.sitekey };
                      this.pathStack?.pushPathByName(Routes.TURNSTILE_DETAIL, param);
                    },
                    onLongPress: () => {
                      this.confirmDelete(widget);
                    },
                  })
                }
                .margin({ left: 16, right: 16, top: 5, bottom: 5 })
              }, (widget: TurnstileWidget) => widget.sitekey)
            }
            .width('100%')
            .height('100%')
            .scrollBar(BarState.Off)
          }
          .width('100%')
          .height('100%')
          .onRefreshing(() => {
            this.refreshing = true;
            this.vm.load().then(() => {
              this.refreshing = false;
            }).catch(() => {
              this.refreshing = false;
            });
          })
        }

        Button('+')
          .width(52)
          .height(52)
          .fontSize(26)
          .fontColor(Color.White)
          .backgroundColor(BRAND_ORANGE)
          .borderRadius(26)
          .shadow({ radius: 12, color: '#40000000', offsetY: 4 })
          .margin({ right: 20, bottom: 28 })
          .onClick(() => {
            this.openCreate();
          })
      }
      .width('100%')
      .height('100%')
    }
    .title('Turnstile')
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.showEditor, this.editorSheet(), ocSheet(() => {
      this.showEditor = false;
    }))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.vm.load().catch(() => {
      });
    })
  }
}

@ComponentV2
export struct TurnstileDetailPage {
  @Local vm: TurnstileVM = turnstileVM;
  @Local sitekey: string = '';
  @Local widget: TurnstileWidget | null = null;
  @Local secretRevealed: boolean = false;
  @Local showEditor: boolean = false;
  @Local fName: string = '';
  @Local fModeIndex: number = 0;
  @Local fDomains: string = '';
  @Local fBotFight: boolean = false;
  private editingClearance: string = '';
  private pathStack: NavPathStack | null = null;
  private canWrite: boolean = authManager.hasScope(Scopes.CHALLENGE_WIDGETS_WRITE);

  private toast(msg: string): void {
    if (msg !== '') {
      promptAction.showToast({ message: msg });
    }
  }

  private copyText(text: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.toast('已复制');
    }).catch(() => {
      this.toast('复制失败');
    });
  }

  private openEditor(): void {
    const w = this.widget;
    if (w === null) {
      return;
    }
    this.fName = w.name;
    const idx = TURNSTILE_MODES.indexOf(w.mode);
    this.fModeIndex = idx < 0 ? 0 : idx;
    this.fDomains = (w.domains ?? []).join('\n');
    this.fBotFight = w.bot_fight_mode === true;
    this.editingClearance = w.clearance_level ?? '';
    this.vm.saveError = '';
    this.showEditor = true;
  }

  /// 轮换密钥：立即作废 / 保留 2 小时宽限
  private confirmRotate(): void {
    promptAction.showDialog({
      title: '轮换密钥',
      message: '轮换后服务端需改用新密钥调用 siteverify。选择宽限可让旧密钥再工作 2 小时，平滑过渡。',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '保留 2 小时', color: BRAND_ORANGE },
        { text: '立即作废', color: DANGER_RED },
      ],
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 0) {
        return;
      }
      this.vm.rotate(this.sitekey, result.index === 2).then((updated: TurnstileWidget | null) => {
        if (updated !== null) {
          this.widget = updated;
          this.secretRevealed = true;
          this.toast('密钥已轮换');
          this.vm.load().catch(() => {
          });
        } else {
          this.toast(this.vm.error);
        }
      });
    }).catch(() => {
    });
  }

  private confirmDelete(): void {
    const w = this.widget;
    if (w === null) {
      return;
    }
    promptAction.showDialog({
      title: `删除组件「${w.name}」？`,
      message: '嵌在网站上的该组件将立即失效，此操作不可撤销。',
      buttons: [{ text: '取消', color: '#666666' }, { text: '删除', color: DANGER_RED }],
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        this.vm.remove(w.sitekey).then((err: string) => {
          if (err === '') {
            this.toast('已删除');
            this.pathStack?.pop();
          } else {
            this.toast(err);
          }
        });
      }
    }).catch(() => {
    });
  }

  /// maskable 只表明这一行是不是密文行；是否遮住由 Builder 内部读 this.secretRevealed 现算
  /// ——@Builder 值参数是静态的，传 masked 进来点了眼睛不会重绘（同类 bug）。
  @Builder
  keyRow(label: string, value: string, maskable: boolean, onTap: () => void) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(label)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        Text(maskable && !this.secretRevealed ? '••••••••••••••••••••••••' : value)
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolGlyph(maskable && !this.secretRevealed ? $r('sys.symbol.eye') : $r('sys.symbol.square_on_square_fill'))
        .fontSize(16)
        .fontColor([$r('sys.color.font_tertiary')])
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(onTap)
  }

  @Builder
  editorSheet() {
    Scroll() {
      Column({ space: 12 }) {
        Text('编辑组件')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .margin({ top: 8 })

        TextInput({ text: this.fName, placeholder: '名称' })
          .fontSize(14)
          .width('100%')
          .onChange((value: string) => {
            this.fName = value;
          })

        Row({ space: 12 }) {
          Text('模式')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Blank()
          Select(TURNSTILE_MODES.map((m: string): SelectOption => ({ value: turnstileModeLabel(m) })))
            .selected(this.fModeIndex)
            .value(turnstileModeLabel(TURNSTILE_MODES[this.fModeIndex]))
            .font({ size: 14 })
            .onSelect((index: number) => {
              this.fModeIndex = index;
            })
        }
        .width('100%')

        Text(turnstileModeDetail(TURNSTILE_MODES[this.fModeIndex]))
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')

        TextArea({ text: this.fDomains, placeholder: '每行一个主机名或 IP，留空 = 任意主机名' })
          .fontSize(13)
          .fontFamily('monospace')
          .height(110)
          .width('100%')
          .onChange((value: string) => {
            this.fDomains = value;
          })

        Row({ space: 12 }) {
          Text('Bot Fight Mode')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.fBotFight })
            .selectedColor(BRAND_ORANGE)
            .onChange((isOn: boolean) => {
              this.fBotFight = isOn;
            })
        }
        .width('100%')

        if (this.vm.saveError !== '') {
          Text(this.vm.saveError)
            .fontSize(13)
            .fontColor(DANGER_RED)
            .width('100%')
        }

        Button(this.vm.isSaving ? '正在保存…' : '保存')
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor(BRAND_ORANGE)
          .enabled(!this.vm.isSaving && this.fName.trim() !== '' && parseDomains(this.fDomains).length <= 10)
          .onClick(() => {
            const input: TurnstileWidgetInput = {
              name: this.fName.trim(),
              mode: TURNSTILE_MODES[this.fModeIndex],
              domains: parseDomains(this.fDomains),
              bot_fight_mode: this.fBotFight,
              clearance_level: this.editingClearance === '' ? undefined : this.editingClearance,
            };
            this.vm.save(this.sitekey, input).then((saved: TurnstileWidget | null) => {
              if (saved !== null) {
                // PUT 响应不带 secret 时保留已有值，避免密钥行凭空消失
                if ((saved.secret ?? '') === '' && this.widget !== null) {
                  saved.secret = this.widget!.secret;
                }
                this.widget = saved;
                this.showEditor = false;
                this.toast('已保存');
              }
            });
          })
      }
      .padding({ left: 20, right: 20, bottom: 24 })
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .width('100%')
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        Scroll() {
          Column({ space: 4 }) {
            if (this.widget === null) {
              Column() {
                OCLoading({ text: '正在加载组件…' })
              }
              .width('100%')
              .padding({ top: 60 })
            } else {
              // 集成密钥
              Column() {
                SectionHeader({ title: '集成密钥' })
                Column() {
                  this.keyRow('Sitekey', this.widget!.sitekey, false, () => {
                    this.copyText(this.widget!.sitekey);
                  })
                  if ((this.widget!.secret ?? '') !== '') {
                    Divider()
                      .strokeWidth(0.5)
                      .color($r('sys.color.comp_divider'))
                      .margin({ left: 16 })
                    this.keyRow('Secret', this.widget!.secret ?? '', true, () => {
                      if (this.secretRevealed) {
                        this.copyText(this.widget!.secret ?? '');
                      } else {
                        this.secretRevealed = true;
                      }
                    })
                  }
                  if (this.canWrite) {
                    Divider()
                      .strokeWidth(0.5)
                      .color($r('sys.color.comp_divider'))
                      .margin({ left: 16 })
                    Row({ space: 10 }) {
                      SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
                        .fontSize(17)
                        .fontColor([$r('app.color.oc_brand_text')])
                      Text('轮换密钥')
                        .fontSize(14)
                        .fontColor($r('app.color.oc_brand_text'))
                    }
                    .width('100%')
                    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                    .onClick(() => {
                      this.confirmRotate();
                    })
                  }
                }
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(OCLayout.chipRadius)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .clip(true)
                .margin({ left: 16, right: 16 })
                Text('sitekey 嵌进网页组件，secret 用于服务端 siteverify 校验——secret 请勿泄露。点按可复制。')
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                  .width('100%')
                  .padding({ left: 20, right: 20, top: 6 })
              }
              .width('100%')

              // 配置
              Column() {
                SectionHeader({ title: '配置' })
                Column({ space: 10 }) {
                  Row({ space: 8 }) {
                    Text('模式')
                      .fontSize(14)
                      .fontColor($r('sys.color.font_secondary'))
                    Blank()
                    OCTag({ text: turnstileModeLabel(this.widget!.mode) })
                  }
                  .width('100%')
                  Row({ space: 8 }) {
                    Text('域名')
                      .fontSize(14)
                      .fontColor($r('sys.color.font_secondary'))
                    Blank()
                    Text((this.widget!.domains ?? []).length === 0
                      ? '任意主机名'
                      : (this.widget!.domains ?? []).join('、'))
                      .fontSize(13)
                      .fontColor($r('sys.color.font_primary'))
                      .textAlign(TextAlign.End)
                      .layoutWeight(1)
                  }
                  .width('100%')
                  Row({ space: 8 }) {
                    Text('区域')
                      .fontSize(14)
                      .fontColor($r('sys.color.font_secondary'))
                    Blank()
                    Text(this.widget!.region === 'china' ? '中国' : '全球')
                      .fontSize(13)
                      .fontColor($r('sys.color.font_primary'))
                  }
                  .width('100%')
                  if (this.widget!.bot_fight_mode === true) {
                    Row({ space: 8 }) {
                      Text('Bot Fight Mode')
                        .fontSize(14)
                        .fontColor($r('sys.color.font_secondary'))
                      Blank()
                      Text('已开启')
                        .fontSize(13)
                        .fontColor($r('sys.color.font_primary'))
                    }
                    .width('100%')
                  }
                }
                .width('100%')
                .padding(14)
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(OCLayout.chipRadius)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .margin({ left: 16, right: 16 })
                Text('组件在所列域名及其子域生效；域名留空表示任意主机名均可使用。')
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                  .width('100%')
                  .padding({ left: 20, right: 20, top: 6 })
              }
              .width('100%')

              if (this.canWrite) {
                Column() {
                  SectionHeader({ title: '危险操作' })
                  Button('删除组件')
                    .width('100%')
                    .height(46)
                    .fontSize(15)
                    .fontColor(DANGER_RED)
                    .backgroundColor($r('sys.color.comp_background_list_card'))
                    .borderRadius(OCLayout.chipRadius)
                    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                    .margin({ left: 16, right: 16 })
                    .onClick(() => {
                      this.confirmDelete();
                    })
                }
                .width('100%')
              }
            }
          }
          .width('100%')
          .padding({ top: 4, bottom: 28 })
        }
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
    }
    .title(this.widget?.name ?? 'Turnstile')
    .backgroundColor($r('sys.color.background_secondary'))
    .menus(this.canWrite ? [{
      value: '编辑',
      action: () => {
        this.openEditor();
      },
    }] as NavigationMenuItem[] : [])
    .bindSheet(this.showEditor, this.editorSheet(), ocSheet(() => {
      this.showEditor = false;
    }))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as NameParam;
      this.sitekey = param.name;
      // 列表响应通常已含 secret，先用缓存即时渲染，再单查兜底拿完整对象
      const cached = this.vm.widgets.find((w: TurnstileWidget) => w.sitekey === param.name);
      if (cached !== undefined) {
        this.widget = cached;
      }
      this.vm.detail(param.name).then((fresh: TurnstileWidget | null) => {
        if (fresh !== null) {
          this.widget = fresh;
        }
      });
    })
  }
}
