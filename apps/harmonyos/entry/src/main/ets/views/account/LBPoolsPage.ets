import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// 负载均衡·源站池（account 级）：列表（健康状态 / 源站数 / 监测）+ 新建 / 编辑（名称、多源站行、
// 最少可用源站、健康监测选择）+ 长按删除。对齐 iOS PoolListView；写操作按 LB_POOLS_WRITE 门控。
// origins 是整组字段：编辑时把现有 origin 的 port / header / vnet 原样带回，避免 PATCH 丢配置。
import { LBMonitor, LBOrigin, LBPool, LBPoolPayload, LoadBalancerService } from '../../services/LoadBalancerService';
import { accountStore } from '../../core/store/AccountStore';
import { authManager } from '../../core/auth/AuthManager';
import { Scopes } from '../../core/auth/Scopes';
import { BRAND_ORANGE, OCEmpty, OCError, OCLoading, SectionHeader } from '../common/Components';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';

/// 监测在下拉里的显示名（HTTP 类：方法+路径；其它：类型/端口）
function monitorSummary(monitor: LBMonitor): string {
  const type = (monitor.type ?? '').toUpperCase();
  if (monitor.type === 'http' || monitor.type === 'https') {
    return `${type} ${monitor.method ?? 'GET'} ${monitor.path ?? '/'}`;
  }
  if (monitor.port !== undefined) {
    return `${type} 端口 ${monitor.port}`;
  }
  return type !== '' ? type : monitor.id;
}

function poolStateLabel(pool: LBPool): string {
  if (pool.enabled === false) {
    return '已停用';
  }
  if (pool.healthy === true) {
    return '健康';
  }
  if (pool.healthy === false) {
    return '异常';
  }
  return '未知';
}

function poolStateColor(pool: LBPool): string {
  if (pool.enabled === false) {
    return '#9CA3AF';
  }
  if (pool.healthy === true) {
    return '#22C55E';
  }
  if (pool.healthy === false) {
    return '#DC2626';
  }
  return '#9CA3AF';
}

let originRowSeed = 0;

/// 源站编辑行（@Trace 让行内输入即时反映；original 保住 port / header / vnet 等未开放字段）
@ObservedV2
class OriginForm {
  readonly key: string;
  @Trace address: string;
  @Trace weight: string;
  @Trace enabled: boolean;
  original: LBOrigin | null;

  constructor(address: string, weight: string, enabled: boolean, original: LBOrigin | null) {
    originRowSeed += 1;
    this.key = `origin-${originRowSeed}`;
    this.address = address;
    this.weight = weight;
    this.enabled = enabled;
    this.original = original;
  }
}

@ObservedV2
class LBPoolsVM {
  @Trace pools: LBPool[] = [];
  @Trace monitors: LBMonitor[] = [];
  @Trace isLoading: boolean = false;
  @Trace isSaving: boolean = false;
  @Trace error: string = '';
  @Trace saveError: string = '';
  private service: LoadBalancerService = new LoadBalancerService();

  async load(accountId: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.pools = await this.service.listPools(accountId);
      try {
        this.monitors = await this.service.listMonitors(accountId);
      } catch (e) {
        this.monitors = [];
      }
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async save(accountId: string, poolId: string, body: LBPoolPayload): Promise<boolean> {
    this.isSaving = true;
    this.saveError = '';
    try {
      if (poolId === '') {
        await this.service.createPool(accountId, body);
      } else {
        await this.service.updatePool(accountId, poolId, body);
      }
      await this.load(accountId);
      return true;
    } catch (e) {
      this.saveError = (e as Error).message ?? '保存失败';
      return false;
    } finally {
      this.isSaving = false;
    }
  }

  async remove(accountId: string, poolId: string): Promise<string> {
    try {
      await this.service.deletePool(accountId, poolId);
      this.pools = this.pools.filter((p: LBPool) => p.id !== poolId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }

  monitorName(monitorId: string): string {
    const found = this.monitors.find((m: LBMonitor) => m.id === monitorId);
    return found !== undefined ? monitorSummary(found) : '已配置';
  }
}

@ComponentV2
export struct LBPoolsPage {
  @Local vm: LBPoolsVM = new LBPoolsVM();
  @Local editorVisible: boolean = false;
  @Local editingId: string = '';
  @Local fName: string = '';
  @Local fMinOrigins: string = '1';
  @Local fMonitorIndex: number = 0; // 0 = 不启用，i>0 = monitors[i-1]
  @Local rows: OriginForm[] = [];
  private editingMonitor: string = ''; // 编辑前池上已挂的监测 ID（用于识别「取消挂载」）

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  private canWrite(): boolean {
    return authManager.hasScope(Scopes.LB_POOLS_WRITE);
  }

  private openEditor(pool: LBPool | null): void {
    if (!this.canWrite()) {
      this.toast('当前授权缺少源站池写权限');
      return;
    }
    this.vm.saveError = '';
    if (pool) {
      this.editingId = pool.id;
      this.fName = pool.name ?? '';
      this.fMinOrigins = `${pool.minimum_origins ?? 1}`;
      this.editingMonitor = pool.monitor ?? '';
      const idx = this.vm.monitors.findIndex((m: LBMonitor) => m.id === (pool.monitor ?? ''));
      this.fMonitorIndex = idx >= 0 ? idx + 1 : 0;
      this.rows = (pool.origins ?? []).map((o: LBOrigin): OriginForm =>
      new OriginForm(o.address ?? '', `${o.weight ?? 1}`, o.enabled !== false, o));
      if (this.rows.length === 0) {
        this.rows = [new OriginForm('', '1', true, null)];
      }
    } else {
      this.editingId = '';
      this.fName = '';
      this.fMinOrigins = '1';
      this.editingMonitor = '';
      this.fMonitorIndex = 0;
      this.rows = [new OriginForm('', '1', true, null)];
    }
    this.editorVisible = true;
  }

  private buildPayload(): LBPoolPayload {
    const origins: LBOrigin[] = [];
    for (const row of this.rows) {
      const address = row.address.trim();
      if (address === '') {
        continue;
      }
      const weight = Number.parseFloat(row.weight.trim());
      // origin.name 为 API 必填：沿用原名，新源站用地址清洗出合法名
      const fallbackName = address.replace(/[^a-zA-Z0-9_.-]/g, '-');
      const origin: LBOrigin = {
        name: (row.original?.name ?? '') !== '' ? row.original?.name : fallbackName,
        address: address,
        enabled: row.enabled,
        weight: !Number.isNaN(weight) && weight >= 0 ? weight : 1,
        port: row.original?.port,
        header: row.original?.header,
        virtual_network_id: row.original?.virtual_network_id,
      };
      origins.push(origin);
    }
    const minRaw = Number.parseInt(this.fMinOrigins.trim());
    const minimum = !Number.isNaN(minRaw) && minRaw >= 1 ? minRaw : 1;
    const selectedMonitor = this.fMonitorIndex > 0 && this.fMonitorIndex <= this.vm.monitors.length
      ? this.vm.monitors[this.fMonitorIndex - 1].id : '';
    const payload: LBPoolPayload = {
      name: this.fName.trim(),
      origins: origins,
      minimum_origins: minimum,
    };
    if (selectedMonitor !== '') {
      payload.monitor = selectedMonitor;
    } else if (this.editingMonitor !== '') {
      // 原来挂了监测、现改为不启用：显式传空串请求取消挂载（省略字段 PATCH 会原样保留）
      payload.monitor = '';
    }
    return payload;
  }

  private hasValidOrigin(): boolean {
    return this.rows.some((row: OriginForm) => row.address.trim() !== '');
  }

  private confirmDelete(pool: LBPool): void {
    if (!this.canWrite()) {
      this.toast('当前授权缺少源站池写权限');
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '删除源站池',
      message: `确定删除「${pool.name ?? pool.id}」？引用它的负载均衡器会受影响。`,
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '删除',
        fontColor: '#DC2626',
        action: () => {
          this.vm.remove(accountStore.selectedId, pool.id).then((err: string) => {
            this.toast(err === '' ? '已删除' : err);
          });
        },
      },
    });
  }

  @Builder
  poolRow(pool: LBPool) {
    Row({ space: 10 }) {
      Circle({ width: 10, height: 10 })
        .fill(poolStateColor(pool))
      Column({ space: 2 }) {
        Text(pool.name ?? pool.id)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${poolStateLabel(pool)} · ${(pool.origins ?? []).length} 个源站` +
          ((pool.monitor ?? '') !== '' ? ` · 监测：${this.vm.monitorName(pool.monitor ?? '')}` : ''))
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
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
      this.openEditor(pool);
    })
    .gesture(LongPressGesture().onAction(() => {
      this.confirmDelete(pool);
    }))
  }

  @Builder
  originRow(row: OriginForm) {
    Row({ space: 8 }) {
      TextInput({ text: row.address, placeholder: 'IP 或主机名' })
        .fontSize(13)
        .layoutWeight(1)
        .onChange((value: string) => {
          row.address = value;
        })
      TextInput({ text: row.weight, placeholder: '权重' })
        .fontSize(13)
        .width(64)
        .type(InputType.NUMBER_DECIMAL)
        .onChange((value: string) => {
          row.weight = value;
        })
      Toggle({ type: ToggleType.Switch, isOn: row.enabled })
        .selectedColor($r('app.color.oc_brand'))
        .onChange((isOn: boolean) => {
          row.enabled = isOn;
        })
      Text('移除')
        .fontSize(12)
        .fontColor('#DC2626')
        .onClick(() => {
          this.rows = this.rows.filter((r: OriginForm) => r.key !== row.key);
        })
    }
    .width('100%')
  }

  @Builder
  editorSheet() {
    Scroll() {
      Column({ space: 12 }) {
        Text(this.editingId === '' ? '新建源站池' : '编辑源站池')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .margin({ top: 8 })

        TextInput({ text: this.fName, placeholder: '池名称（如 primary-pool）' })
          .fontSize(14)
          .width('100%')
          .onChange((value: string) => {
            this.fName = value;
          })

        Text(`源站（${this.rows.length}）`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
        ForEach(this.rows, (row: OriginForm) => {
          this.originRow(row)
        }, (row: OriginForm) => row.key)
        Text('+ 添加源站')
          .fontSize(13)
          .fontColor($r('app.color.oc_brand_text'))
          .width('100%')
          .onClick(() => {
            this.rows = this.rows.concat([new OriginForm('', '1', true, null)]);
          })

        Row({ space: 12 }) {
          Text('最少可用源站')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Blank()
          TextInput({ text: this.fMinOrigins })
            .fontSize(13)
            .width(64)
            .type(InputType.Number)
            .onChange((value: string) => {
              this.fMinOrigins = value;
            })
        }
        .width('100%')

        Row({ space: 12 }) {
          Text('健康监测')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Blank()
          Select([{ value: '不启用' } as SelectOption]
            .concat(this.vm.monitors.map((m: LBMonitor): SelectOption => ({ value: monitorSummary(m) }))))
            .selected(this.fMonitorIndex)
            .value(this.fMonitorIndex > 0 && this.fMonitorIndex <= this.vm.monitors.length
              ? monitorSummary(this.vm.monitors[this.fMonitorIndex - 1]) : '不启用')
            .font({ size: 14 })
            .onSelect((index: number) => {
              this.fMonitorIndex = index;
            })
        }
        .width('100%')

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
          .enabled(!this.vm.isSaving && this.fName.trim() !== '' && this.hasValidOrigin())
          .onClick(() => {
            this.vm.save(accountStore.selectedId, this.editingId, this.buildPayload()).then((ok: boolean) => {
              if (ok) {
                this.editorVisible = false;
                this.toast(this.editingId === '' ? '已创建' : '已保存');
              }
            });
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 24 })
    }
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .width('100%')
    .height('100%')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载源站池…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '') {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load(accountStore.selectedId).catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.pools.length === 0) {
          Column() {
            OCEmpty({
              symbol: $r('sys.symbol.square_grid_2x2'),
              title: '暂无源站池',
              subtitle: this.canWrite() ? '点右下角 + 创建；长按池可删除' : '当前授权无池写权限',
            })
          }
          .width('100%')
          .height('100%')
        } else {
          List() {
            ListItem() {
              SectionHeader({ title: `源站池（${this.vm.pools.length}）` })
            }
            ForEach(this.vm.pools, (pool: LBPool) => {
              ListItem() {
                this.poolRow(pool)
              }
            }, (pool: LBPool) => pool.id)
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
        }

        if (this.canWrite()) {
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
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({ content: { title: { mainTitle: '源站池' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.editorVisible, this.editorSheet(), ocSheet(() => {
      this.editorVisible = false;
    }))
    .onReady(() => {
      this.vm.load(accountStore.selectedId).catch(() => {
      });
    })
  }
}
