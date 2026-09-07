import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// IP 访问规则：列表 / 新建 / 改动作 / 删除（对齐 Android ZoneAccessRulesScreen）。
// configuration 创建后不可改，编辑仅开放 mode + notes。
import { FirewallAccessRule, FirewallService } from '../../services/FirewallService';
import { ZoneRouteParam } from '../../models/Routes';
import { BRAND_ORANGE, OCEmpty, OCError, OCLoading } from '../common/Components';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';

const MODES: string[] = ['block', 'challenge', 'js_challenge', 'managed_challenge', 'whitelist'];
const TARGETS: string[] = ['ip', 'ip_range', 'country', 'asn'];

function modeLabel(mode: string): string {
  if (mode === 'block') {
    return '拦截';
  }
  if (mode === 'challenge') {
    return '质询';
  }
  if (mode === 'js_challenge') {
    return 'JS 质询';
  }
  if (mode === 'managed_challenge') {
    return '托管质询';
  }
  if (mode === 'whitelist') {
    return '白名单';
  }
  return mode;
}

function targetLabel(target: string): string {
  if (target === 'ip') {
    return 'IP';
  }
  if (target === 'ip_range') {
    return 'IP 段';
  }
  if (target === 'country') {
    return '国家';
  }
  if (target === 'asn') {
    return 'ASN';
  }
  return target;
}

@ObservedV2
class AccessRulesVM {
  @Trace rules: FirewallAccessRule[] = [];
  @Trace isLoading: boolean = false;
  @Trace isSaving: boolean = false;
  @Trace error: string = '';
  @Trace saveError: string = '';

  private service: FirewallService = new FirewallService();

  async load(zoneId: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.rules = await this.service.list(zoneId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async save(zoneId: string, ruleId: string, mode: string, target: string, value: string,
    notes: string): Promise<boolean> {
    this.isSaving = true;
    this.saveError = '';
    try {
      if (ruleId === '') {
        const created = await this.service.create(zoneId, mode, target, value, notes);
        this.rules = [created].concat(this.rules);
      } else {
        const updated = await this.service.update(zoneId, ruleId, mode, notes);
        this.rules = this.rules.map((r: FirewallAccessRule) => r.id === ruleId ? updated : r);
      }
      return true;
    } catch (e) {
      this.saveError = (e as Error).message ?? '保存失败';
      return false;
    } finally {
      this.isSaving = false;
    }
  }

  async remove(zoneId: string, ruleId: string): Promise<string> {
    try {
      await this.service.remove(zoneId, ruleId);
      this.rules = this.rules.filter((r: FirewallAccessRule) => r.id !== ruleId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}

@ComponentV2
export struct AccessRulesPage {
  @Local vm: AccessRulesVM = new AccessRulesVM();
  @Local zoneId: string = '';
  @Local zoneName: string = '';
  @Local editorVisible: boolean = false;
  @Local editingId: string = '';
  @Local fMode: string = 'block';
  @Local fTarget: string = 'ip';
  @Local fValue: string = '';
  @Local fNotes: string = '';

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  private openEditor(rule: FirewallAccessRule | null): void {
    this.vm.saveError = '';
    if (rule) {
      this.editingId = rule.id;
      this.fMode = rule.mode ?? 'block';
      this.fTarget = rule.configuration?.target ?? 'ip';
      this.fValue = rule.configuration?.value ?? '';
      this.fNotes = rule.notes ?? '';
    } else {
      this.editingId = '';
      this.fMode = 'block';
      this.fTarget = 'ip';
      this.fValue = '';
      this.fNotes = '';
    }
    this.editorVisible = true;
  }

  private confirmDelete(rule: FirewallAccessRule): void {
    this.getUIContext().showAlertDialog({
      title: '删除访问规则',
      message: `确定删除对 ${rule.configuration?.value ?? ''} 的规则？`,
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

  @Builder
  ruleRow(rule: FirewallAccessRule) {
    Row({ space: 10 }) {
      Text(modeLabel(rule.mode ?? ''))
        .fontSize(10)
        .fontColor(rule.mode === 'whitelist' ? '#22C55E' : BRAND_ORANGE)
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .backgroundColor(rule.mode === 'whitelist' ? '#1A22C55E' : '#1AF48120')
        .borderRadius(4)
      Column({ space: 2 }) {
        Text(`${targetLabel(rule.configuration?.target ?? '')} · ${rule.configuration?.value ?? ''}`)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if ((rule.notes ?? '') !== '') {
          Text(rule.notes ?? '')
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(16)
    .margin({ left: 16, right: 16, top: 5, bottom: 5 })
    .onClick(() => {
      this.openEditor(rule);
    })
    .gesture(LongPressGesture().onAction(() => {
      this.confirmDelete(rule);
    }))
  }

  @Builder
  editorSheet() {
    Column({ space: 12 }) {
      Text(this.editingId === '' ? '新建访问规则' : '编辑访问规则（目标不可改）')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })

      Row({ space: 12 }) {
        Text('动作')
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        Select(MODES.map((m: string): SelectOption => ({ value: modeLabel(m) })))
          .selected(MODES.indexOf(this.fMode))
          .value(modeLabel(this.fMode))
          .font({ size: 14 })
          .onSelect((index: number) => {
            this.fMode = MODES[index];
          })
      }
      .width('100%')

      if (this.editingId === '') {
        Row({ space: 12 }) {
          Text('目标类型')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Blank()
          Select(TARGETS.map((t: string): SelectOption => ({ value: targetLabel(t) })))
            .selected(TARGETS.indexOf(this.fTarget))
            .value(targetLabel(this.fTarget))
            .font({ size: 14 })
            .onSelect((index: number) => {
              this.fTarget = TARGETS[index];
            })
        }
        .width('100%')

        TextInput({
          text: this.fValue,
          placeholder: this.fTarget === 'country' ? '国家代码，如 CN' : (this.fTarget === 'asn' ? 'AS13335' : '1.2.3.4 或 1.2.3.0/24'),
        })
          .fontSize(14)
          .width('100%')
          .onChange((value: string) => {
            this.fValue = value;
          })
      } else {
        Text(`${targetLabel(this.fTarget)} · ${this.fValue}`)
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
      }

      TextInput({ text: this.fNotes, placeholder: '备注（可选）' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fNotes = value;
        })

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
        .enabled(!this.vm.isSaving && (this.editingId !== '' || this.fValue.trim() !== ''))
        .onClick(() => {
          this.vm.save(this.zoneId, this.editingId, this.fMode, this.fTarget,
            this.fValue.trim(), this.fNotes.trim()).then((ok: boolean) => {
            if (ok) {
              this.editorVisible = false;
            }
          });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载访问规则…' })
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
        } else if (this.vm.rules.length === 0) {
          Column() {
            OCEmpty({ symbol: $r('sys.symbol.nosign'), title: '暂无 IP 访问规则', subtitle: '点右下角 + 创建；长按规则可删除' })
          }
          .width('100%')
          .height('100%')
        } else {
          List() {
            ForEach(this.vm.rules, (rule: FirewallAccessRule) => {
              ListItem() {
                this.ruleRow(rule)
              }
            }, (rule: FirewallAccessRule) => rule.id)
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
          .margin({ right: 20, bottom: 28 })
          .onClick(() => {
            this.openEditor(null);
          })
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: `${this.zoneName} · IP 访问规则` } } })
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
