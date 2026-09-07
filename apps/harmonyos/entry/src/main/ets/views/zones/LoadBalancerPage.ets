import { OCAddActionBar, OC_ACTION_BAR_CLEARANCE } from '../common/ActionBar';
import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// 负载均衡（zone 级）：LB 列表 + 启停开关 + 详情 sheet（转向策略 / 会话保持 / 代理 / TTL / 默认+回退池，池解析为名称与健康）
// + 新建 / 编辑 sheet + 长按删除（对齐 iOS LoadBalancerListView 完整 CRUD），页顶入口跳「源站池 / 健康监测」。
import { LoadBalancer, Pool, PoolOrigin } from '../../models/AccountModels';
import { Routes, ZoneRouteParam } from '../../models/Routes';
import { AccountModuleService } from '../../services/AccountModuleService';
import { LoadBalancerPayload, LoadBalancerService } from '../../services/LoadBalancerService';
import { accountStore } from '../../core/store/AccountStore';
import { authManager } from '../../core/auth/AuthManager';
import { Scopes } from '../../core/auth/Scopes';
import { BRAND_ORANGE, InfoRow, NavRow, OCEmpty, OCError, OCLoading, SectionHeader, ToggleRow } from '../common/Components';
import { GlassIsland } from '../common/Daybreak';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';

/// 编辑表单开放的转向策略 / 会话保持选项（当前值不在集合内时动态并入，避免改丢高级策略）
const STEERING_OPTIONS: string[] = ['off', 'random', 'least_outstanding_requests'];
const AFFINITY_OPTIONS: string[] = ['none', 'cookie', 'ip_cookie'];

function withCurrent(options: string[], current: string): string[] {
  if (current !== '' && !options.includes(current)) {
    return options.concat([current]);
  }
  return options;
}

function steeringLabel(policy: string | undefined): string {
  switch (policy ?? '') {
    case 'off':
    case '':
      return '默认（按池顺序故障转移）';
    case 'geo':
      return '地理位置';
    case 'random':
      return '随机';
    case 'dynamic_latency':
      return '动态延迟';
    case 'proximity':
      return '就近';
    case 'least_outstanding_requests':
      return '最少未完成请求';
    case 'least_connections':
      return '最少连接';
    default:
      return policy ?? '默认';
  }
}

function affinityLabel(affinity: string | undefined): string {
  switch (affinity ?? '') {
    case 'none':
    case '':
      return '不启用';
    case 'cookie':
      return 'Cookie';
    case 'ip_cookie':
      return 'IP + Cookie';
    case 'header':
      return '请求头';
    default:
      return affinity ?? '不启用';
  }
}

/// 池健康：全部启用的源站视为健康，任一被禁用则标异常（简化口径，无健康监测实时数据）
function poolHealthy(pool: Pool | undefined): boolean {
  if (pool === undefined) {
    return false;
  }
  if (pool.enabled === false) {
    return false;
  }
  const origins = pool.origins ?? [];
  if (origins.length === 0) {
    return pool.healthy !== false;
  }
  return origins.every((o: PoolOrigin) => o.enabled !== false);
}

@ObservedV2
class LBVM {
  @Trace items: LoadBalancer[] = [];
  @Trace pools: Pool[] = [];
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  @Trace savingId: string = '';
  @Trace detail: LoadBalancer | null = null;
  @Trace isSaving: boolean = false;
  @Trace saveError: string = '';
  private service: AccountModuleService = new AccountModuleService();
  private lbService: LoadBalancerService = new LoadBalancerService();

  async load(zoneId: string, accountId: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.items = await this.service.loadBalancers(zoneId);
      try {
        this.pools = await this.service.pools(accountId);
      } catch (e) {
        this.pools = [];
      }
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  poolById(id: string): Pool | undefined {
    return this.pools.find((p: Pool) => p.id === id);
  }

  poolName(id: string): string {
    const pool = this.poolById(id);
    return pool?.name ?? id;
  }

  async toggle(zoneId: string, lb: LoadBalancer, enabled: boolean): Promise<string> {
    this.savingId = lb.id;
    try {
      await this.service.setLoadBalancerEnabled(zoneId, lb.id, enabled);
      this.items = this.items.map((item: LoadBalancer): LoadBalancer => {
        if (item.id === lb.id) {
          const next: LoadBalancer = {
            id: item.id,
            name: item.name,
            enabled: enabled,
            default_pools: item.default_pools,
            proxied: item.proxied,
            steering_policy: item.steering_policy,
            session_affinity: item.session_affinity,
            fallback_pool: item.fallback_pool,
            ttl: item.ttl,
          };
          return next;
        }
        return item;
      });
      return '';
    } catch (e) {
      return (e as Error).message ?? '操作失败';
    } finally {
      this.savingId = '';
    }
  }

  /// 新建（lbId 为空）或编辑（PATCH 顶层合并，只带表单开放字段）
  async save(zoneId: string, accountId: string, lbId: string, body: LoadBalancerPayload): Promise<boolean> {
    this.isSaving = true;
    this.saveError = '';
    try {
      if (lbId === '') {
        await this.lbService.createLoadBalancer(zoneId, body);
      } else {
        await this.lbService.updateLoadBalancer(zoneId, lbId, body);
      }
      await this.load(zoneId, accountId);
      return true;
    } catch (e) {
      this.saveError = (e as Error).message ?? '保存失败';
      return false;
    } finally {
      this.isSaving = false;
    }
  }

  async remove(zoneId: string, lbId: string): Promise<string> {
    try {
      await this.lbService.deleteLoadBalancer(zoneId, lbId);
      this.items = this.items.filter((item: LoadBalancer) => item.id !== lbId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}

@ComponentV2
export struct LoadBalancerPage {
  @Local vm: LBVM = new LBVM();
  @Local zoneId: string = '';
  @Local zoneName: string = '';
  @Local detailVisible: boolean = false;
  @Local editorVisible: boolean = false;
  @Local editingId: string = '';
  @Local fName: string = '';
  @Local fDefaultPools: string[] = [];
  @Local fFallback: string = '';
  @Local fSteering: string = 'off';
  @Local fAffinity: string = 'none';
  @Local fProxied: boolean = true;
  @Local fTtl: string = '';
  private pathStack: NavPathStack | null = null;

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  private canWrite(): boolean {
    return authManager.hasScope(Scopes.LB_WRITE);
  }

  private openEditor(lb: LoadBalancer | null): void {
    if (!this.canWrite()) {
      this.toast('当前授权缺少负载均衡写权限');
      return;
    }
    this.vm.saveError = '';
    if (lb) {
      this.editingId = lb.id;
      this.fName = lb.name ?? '';
      this.fDefaultPools = (lb.default_pools ?? []).slice();
      this.fFallback = lb.fallback_pool ?? '';
      this.fSteering = lb.steering_policy ?? 'off';
      this.fAffinity = (lb.session_affinity ?? '') === '' ? 'none' : (lb.session_affinity ?? 'none');
      this.fProxied = lb.proxied === true;
      this.fTtl = lb.ttl !== undefined ? `${lb.ttl}` : '';
    } else {
      this.editingId = '';
      this.fName = this.zoneName !== '' ? `lb.${this.zoneName}` : '';
      this.fDefaultPools = [];
      this.fFallback = '';
      this.fSteering = 'off';
      this.fAffinity = 'none';
      this.fProxied = true;
      this.fTtl = '';
    }
    this.editorVisible = true;
  }

  private buildPayload(): LoadBalancerPayload {
    const payload: LoadBalancerPayload = {
      name: this.fName.trim(),
      default_pools: this.fDefaultPools,
      fallback_pool: this.fFallback,
      steering_policy: this.fSteering,
      session_affinity: this.fAffinity,
      proxied: this.fProxied,
    };
    if (!this.fProxied) {
      const ttl = Number.parseInt(this.fTtl.trim());
      if (!Number.isNaN(ttl) && ttl > 0) {
        payload.ttl = ttl;
      }
    }
    return payload;
  }

  private confirmDelete(lb: LoadBalancer): void {
    if (!this.canWrite()) {
      this.toast('当前授权缺少负载均衡写权限');
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '删除负载均衡器',
      message: `确定删除「${lb.name ?? lb.id}」？该主机名的流量调度会停止。`,
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '删除',
        fontColor: '#DC2626',
        action: () => {
          this.vm.remove(this.zoneId, lb.id).then((err: string) => {
            this.toast(err === '' ? '已删除' : err);
          });
        },
      },
    });
  }

  @Builder
  poolRow(poolId: string) {
    Row({ space: 10 }) {
      Circle({ width: 8, height: 8 })
        .fill(poolHealthy(this.vm.poolById(poolId)) ? '#22C55E' : '#DC2626')
      Text(this.vm.poolName(poolId))
        .fontSize(13)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(poolHealthy(this.vm.poolById(poolId)) ? '健康' : '异常')
        .fontSize(11)
        .fontColor(poolHealthy(this.vm.poolById(poolId)) ? '#22C55E' : '#DC2626')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  @Builder
  detailSheet() {
    Scroll() {
      Column({ space: 4 }) {
        Text(this.vm.detail?.name ?? this.vm.detail?.id ?? '')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .padding({ left: 20, right: 20, top: 8 })

        SectionHeader({ title: '配置' })
        Column() {
          InfoRow({ label: '状态', value: this.vm.detail?.enabled === false ? '已停用' : '已启用' })
          InfoRow({ label: '转向策略', value: steeringLabel(this.vm.detail?.steering_policy) })
          InfoRow({ label: '会话保持', value: affinityLabel(this.vm.detail?.session_affinity) })
          InfoRow({ label: '代理', value: this.vm.detail?.proxied === true ? '经 Cloudflare 代理' : '仅 DNS' })
          if (this.vm.detail?.proxied !== true && this.vm.detail?.ttl !== undefined) {
            InfoRow({ label: 'TTL', value: `${this.vm.detail?.ttl} 秒` })
          }
        }
        .backgroundColor($r('sys.color.comp_background_list_card'))
        .borderRadius(14)
        .clip(true)
        .margin({ left: 16, right: 16 })

        SectionHeader({ title: `默认池（${(this.vm.detail?.default_pools ?? []).length}）` })
        Column() {
          if ((this.vm.detail?.default_pools ?? []).length === 0) {
            Text('未配置默认池')
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
              .padding(16)
          } else {
            ForEach(this.vm.detail?.default_pools ?? [], (poolId: string) => {
              this.poolRow(poolId)
            }, (poolId: string, index: number) => `${poolId}-${index}`)
          }
        }
        .backgroundColor($r('sys.color.comp_background_list_card'))
        .borderRadius(14)
        .clip(true)
        .margin({ left: 16, right: 16 })

        if (this.vm.detail?.fallback_pool !== undefined && this.vm.detail?.fallback_pool !== '') {
          SectionHeader({ title: '回退池' })
          Column() {
            this.poolRow(this.vm.detail?.fallback_pool ?? '')
          }
          .backgroundColor($r('sys.color.comp_background_list_card'))
          .borderRadius(14)
          .clip(true)
          .margin({ left: 16, right: 16 })
        }

        if (this.canWrite()) {
          Row({ space: 12 }) {
            Button('编辑')
              .layoutWeight(1)
              .height(44)
              .fontSize(15)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.oc_brand_cta'))
              .onClick(() => {
                const lb = this.vm.detail;
                this.detailVisible = false;
                this.openEditor(lb);
              })
            Button('删除')
              .layoutWeight(1)
              .height(44)
              .fontSize(15)
              .fontColor('#DC2626')
              .backgroundColor($r('sys.color.comp_background_list_card'))
              .onClick(() => {
                const lb = this.vm.detail;
                this.detailVisible = false;
                if (lb !== null) {
                  this.confirmDelete(lb);
                }
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16 })
        }
      }
      .width('100%')
      .padding({ bottom: 24 })
    }
    .scrollBar(BarState.Off)
            // 贴底操作栏叠在内容上，底部留出净空
            .padding({ bottom: OC_ACTION_BAR_CLEARANCE })
    .align(Alignment.Top)
    .width('100%')
    .height('100%')
  }

  @Builder
  poolPickRow(pool: Pool) {
    Row({ space: 12 }) {
      Text(pool.name ?? pool.id)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Toggle({ type: ToggleType.Checkbox, isOn: this.fDefaultPools.includes(pool.id) })
        .selectedColor($r('app.color.oc_brand'))
        .onChange((isOn: boolean) => {
          if (isOn) {
            if (!this.fDefaultPools.includes(pool.id)) {
              this.fDefaultPools = this.fDefaultPools.concat([pool.id]);
            }
          } else {
            this.fDefaultPools = this.fDefaultPools.filter((id: string) => id !== pool.id);
          }
        })
    }
    .width('100%')
    .padding({ left: 14, right: 10, top: 6, bottom: 6 })
  }

  @Builder
  editorSheet() {
    Scroll() {
      Column({ space: 12 }) {
        Text(this.editingId === '' ? '新建负载均衡器' : '编辑负载均衡器')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .margin({ top: 8 })

        TextInput({ text: this.fName, placeholder: `主机名，如 lb.${this.zoneName}` })
          .fontSize(14)
          .width('100%')
          .onChange((value: string) => {
            this.fName = value;
          })

        Text(`默认池（已选 ${this.fDefaultPools.length}）`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
        if (this.vm.pools.length === 0) {
          Text('账号下暂无源站池，请先在「源站池」页创建')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
        } else {
          Column() {
            ForEach(this.vm.pools, (pool: Pool) => {
              this.poolPickRow(pool)
            }, (pool: Pool) => pool.id)
          }
          .backgroundColor($r('sys.color.comp_background_list_card'))
          .borderRadius(14)
          .clip(true)
        }

        Row({ space: 12 }) {
          Text('回退池')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Blank()
          Select(this.vm.pools.map((p: Pool): SelectOption => ({ value: p.name ?? p.id })))
            .selected(this.vm.pools.findIndex((p: Pool) => p.id === this.fFallback))
            .value(this.fFallback !== '' ? this.vm.poolName(this.fFallback) : '未选择')
            .font({ size: 14 })
            .onSelect((index: number) => {
              if (index >= 0 && index < this.vm.pools.length) {
                this.fFallback = this.vm.pools[index].id;
              }
            })
        }
        .width('100%')

        Row({ space: 12 }) {
          Text('转向策略')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Blank()
          Select(withCurrent(STEERING_OPTIONS, this.fSteering)
            .map((s: string): SelectOption => ({ value: steeringLabel(s) })))
            .selected(withCurrent(STEERING_OPTIONS, this.fSteering).indexOf(this.fSteering))
            .value(steeringLabel(this.fSteering))
            .font({ size: 14 })
            .onSelect((index: number) => {
              this.fSteering = withCurrent(STEERING_OPTIONS, this.fSteering)[index];
            })
        }
        .width('100%')

        Row({ space: 12 }) {
          Text('会话保持')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Blank()
          Select(withCurrent(AFFINITY_OPTIONS, this.fAffinity)
            .map((a: string): SelectOption => ({ value: affinityLabel(a) })))
            .selected(withCurrent(AFFINITY_OPTIONS, this.fAffinity).indexOf(this.fAffinity))
            .value(affinityLabel(this.fAffinity))
            .font({ size: 14 })
            .onSelect((index: number) => {
              this.fAffinity = withCurrent(AFFINITY_OPTIONS, this.fAffinity)[index];
            })
        }
        .width('100%')

        Column({ space: 2 }) {
          ToggleRow({
            title: '经 Cloudflare 代理',
            subtitle: '关闭则仅作 DNS 调度（可设 TTL）',
            isOn: this.fProxied,
            onToggle: (isOn: boolean) => {
              this.fProxied = isOn;
            },
          })
        }
        .backgroundColor($r('sys.color.comp_background_list_card'))
        .borderRadius(14)
        .clip(true)

        if (!this.fProxied) {
          Row({ space: 12 }) {
            Text('TTL（秒）')
              .fontSize(14)
              .fontColor($r('sys.color.font_primary'))
            Blank()
            TextInput({ text: this.fTtl, placeholder: '30' })
              .fontSize(13)
              .width(80)
              .type(InputType.Number)
              .onChange((value: string) => {
                this.fTtl = value;
              })
          }
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
          .enabled(!this.vm.isSaving && this.fName.trim() !== '' &&
            this.fDefaultPools.length > 0 && this.fFallback !== '')
          .onClick(() => {
            this.vm.save(this.zoneId, accountStore.selectedId, this.editingId, this.buildPayload())
              .then((ok: boolean) => {
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
        Column() {
          Column() {
            GlassIsland({ pad: 4 }) {
              Column() {
                NavRow({
                  symbol: $r('sys.symbol.square_grid_2x2'),
                  title: '源站池',
                  subtitle: '账号级源站分组与健康状态',
                  onNav: () => {
                    this.pathStack?.pushPathByName(Routes.LB_POOLS, null);
                  },
                })
                NavRow({
                  symbol: $r('sys.symbol.checkmark_circle'),
                  title: '健康监测',
                  subtitle: '探测源站可用性的规则',
                  onNav: () => {
                    this.pathStack?.pushPathByName(Routes.LB_MONITORS, null);
                  },
                })
              }
            }
          }
          .padding({ left: 16, right: 16, top: 8, bottom: 4 })

          if (this.vm.isLoading) {
            Column() {
              OCLoading({ text: '正在加载负载均衡…' })
            }
            .width('100%')
            .layoutWeight(1)
          } else if (this.vm.error !== '') {
            Column() {
              OCError({
                message: this.vm.error,
                onRetry: () => {
                  this.vm.load(this.zoneId, accountStore.selectedId).catch(() => {
                  });
                },
              })
            }
            .width('100%')
            .layoutWeight(1)
          } else if (this.vm.items.length === 0) {
            Column() {
              OCEmpty({
                symbol: $r('sys.symbol.square_grid_2x2'),
                title: '暂无负载均衡器',
                subtitle: this.canWrite() ? '负载均衡为付费功能；点右下角 + 创建' : '负载均衡为付费功能',
              })
            }
            .width('100%')
            .layoutWeight(1)
          } else {
            List() {
              ForEach(this.vm.items, (lb: LoadBalancer) => {
                ListItem() {
                  GlassIsland({ pad: 4 }) {
                    Column({ space: 2 }) {
                      ToggleRow({
                        title: lb.name ?? lb.id,
                        subtitle: `策略：${steeringLabel(lb.steering_policy)} · ${(lb.default_pools ?? []).length} 个默认池`,
                        isOn: lb.enabled === true,
                        isEnabled: this.vm.savingId === '',
                        onToggle: (on: boolean) => {
                          this.vm.toggle(this.zoneId, lb, on).then((err: string) => {
                            this.toast(err);
                          });
                        },
                      })
                      Text(this.canWrite() ? '点按查看详情，长按删除' : '点按查看详情')
                        .fontSize(11)
                        .fontColor($r('sys.color.font_secondary'))
                        .width('100%')
                        .padding({ left: 16, right: 16, bottom: 8 })
                    }
                    .onClick(() => {
                      this.vm.detail = lb;
                      this.detailVisible = true;
                    })
                    .gesture(LongPressGesture().onAction(() => {
                      this.confirmDelete(lb);
                    }))
                  }
                }
                .margin({ left: 16, right: 16, top: 5, bottom: 5 })
              }, (lb: LoadBalancer) => lb.id)
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Off)
          }
        }
        .width('100%')
        .height('100%')

        if (this.canWrite()) {
          // 主操作：贴底核心操作栏（替代右下角 FAB，拇指可达）
          OCAddActionBar({
            label: '新建负载均衡',
            onTap: () => {
              this.openEditor(null);
            },
          })
        }
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: `${this.zoneName} · 负载均衡` } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.detailVisible, this.detailSheet(), ocSheet(() => {
      this.detailVisible = false;
    }))
    .bindSheet(this.editorVisible, this.editorSheet(), ocSheet(() => {
      this.editorVisible = false;
    }))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as ZoneRouteParam;
      this.zoneId = param.zoneId;
      this.zoneName = param.zoneName;
      this.vm.load(param.zoneId, accountStore.selectedId).catch(() => {
      });
    })
  }
}
