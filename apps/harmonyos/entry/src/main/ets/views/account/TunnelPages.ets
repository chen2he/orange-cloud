// Cloudflare Tunnel：列表（状态/活跃连接）+ 详情（公共主机名 CRUD / 连接令牌 / 清理失活连接）
// + 新建 + 删除（对齐 iOS Views/Tunnels）。
import { pasteboard } from '@kit.BasicServicesKit';
import { Tunnel, TunnelConnection } from '../../models/AccountModels';
import { Routes, IdNameParam } from '../../models/Routes';
import { AccountModuleService, TunnelConfigData, TunnelIngressRule } from '../../services/AccountModuleService';
import { accountStore } from '../../core/store/AccountStore';
import { authManager } from '../../core/auth/AuthManager';
import { Scopes } from '../../core/auth/Scopes';
import { formatTimeAgo } from '../../core/util/Format';
import { BRAND_ORANGE, BRAND_ORANGE_BG, InfoRow, OCEmpty, OCError, OCLoading, ResourceCard } from '../common/Components';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';
import { OCLayout } from '../common/Daybreak';

/// 公共主机名表单支持的服务协议（对齐 iOS IngressServiceKind）
interface IngressKindOption {
  label: string;
  scheme: string;
  placeholder: string;
}

const INGRESS_KINDS: IngressKindOption[] = [
  { label: 'HTTP', scheme: 'http://', placeholder: 'localhost:8000' } as IngressKindOption,
  { label: 'HTTPS', scheme: 'https://', placeholder: 'localhost:8000' } as IngressKindOption,
  { label: 'TCP', scheme: 'tcp://', placeholder: 'localhost:5432' } as IngressKindOption,
  { label: 'SSH', scheme: 'ssh://', placeholder: 'localhost:22' } as IngressKindOption,
  { label: 'RDP', scheme: 'rdp://', placeholder: 'localhost:3389' } as IngressKindOption,
  { label: '其他', scheme: '', placeholder: 'unix:/path/to.sock' } as IngressKindOption,
];

/// 兜底规则（无 hostname，或 service 是 http_status 形态）。列表里隐藏、回写时自动补末尾。
function ruleIsCatchAll(rule: TunnelIngressRule): boolean {
  const hostname = rule.hostname ?? '';
  return hostname === '' || rule.service.startsWith('http_status:');
}

/// 从 service 前缀识别协议档位（编辑表单回填），认不出归「其他」
function kindIndexForService(service: string): number {
  for (let i = 0; i < INGRESS_KINDS.length - 1; i++) {
    if (service.startsWith(INGRESS_KINDS[i].scheme)) {
      return i;
    }
  }
  return INGRESS_KINDS.length - 1;
}

function tunnelColor(status: string): string {
  if (status === 'healthy') {
    return '#22C55E';
  }
  if (status === 'degraded') {
    return '#EAB308';
  }
  if (status === 'down') {
    return '#DC2626';
  }
  return '#9CA3AF';
}

function tunnelLabel(status: string): string {
  if (status === 'healthy') {
    return '健康';
  }
  if (status === 'degraded') {
    return '降级';
  }
  if (status === 'down') {
    return '离线';
  }
  if (status === 'inactive') {
    return '未激活';
  }
  return status;
}

/** 列表行副标题：有内嵌连接数时附带，字段被移除后只留状态。 */
function tunnelSubtitle(tunnel: Tunnel): string {
  const label = tunnelLabel(tunnel.status ?? '');
  const count = (tunnel.connections ?? []).length;
  return count > 0 ? `${label} · ${count} 个活跃连接` : label;
}

@ObservedV2
class TunnelListVM {
  @Trace tunnels: Tunnel[] = [];
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  @Trace isCreating: boolean = false;
  @Trace createError: string = '';
  private service: AccountModuleService = new AccountModuleService();

  async load(): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.tunnels = await this.service.listTunnels(accountStore.selectedId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async create(name: string): Promise<boolean> {
    this.isCreating = true;
    this.createError = '';
    try {
      await this.service.createTunnel(accountStore.selectedId, name);
      await this.load();
      return true;
    } catch (e) {
      this.createError = (e as Error).message ?? '创建失败';
      return false;
    } finally {
      this.isCreating = false;
    }
  }
}

@ComponentV2
export struct TunnelListPage {
  @Local vm: TunnelListVM = new TunnelListVM();
  @Local refreshing: boolean = false;
  @Local showCreate: boolean = false;
  @Local fName: string = '';
  private pathStack: NavPathStack | null = null;

  @Builder
  createSheet() {
    Column({ space: 12 }) {
      Text('新建 Tunnel')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      TextInput({ text: this.fName, placeholder: 'Tunnel 名称' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fName = value;
        })
      if (this.vm.createError !== '') {
        Text(this.vm.createError)
          .fontSize(13)
          .fontColor('#DC2626')
          .width('100%')
      }
      Button(this.vm.isCreating ? '正在创建…' : '创建')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor(BRAND_ORANGE)
        .enabled(!this.vm.isCreating && this.fName.trim() !== '')
        .onClick(() => {
          this.vm.create(this.fName.trim()).then((ok: boolean) => {
            if (ok) {
              this.showCreate = false;
              this.fName = '';
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
        if (this.vm.isLoading && this.vm.tunnels.length === 0) {
          Column() {
            OCLoading({ text: '正在加载 Tunnel…' })
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
        } else if (this.vm.tunnels.length === 0) {
          Column() {
            OCEmpty({ symbol: $r('sys.symbol.wifi_router'), title: '暂无 Tunnel', subtitle: '点右下角 + 创建' })
          }
          .width('100%')
          .height('100%')
        } else {
          Refresh({ refreshing: this.refreshing }) {
            List() {
              ForEach(this.vm.tunnels, (tunnel: Tunnel) => {
                ListItem() {
                  ResourceCard({
                    symbol: $r('sys.symbol.wifi_router'),
                    title: tunnel.name,
                    // 连接数来自列表响应内嵌的 connections，CF 将于 2026-10-05 移除该字段。
                    // 字段消失后只留状态——不为列表每行单发一次连接请求（N+1），
                    // 也不能无条件显示 0，否则健康隧道会被误标成「0 个活跃连接」。
                    subtitle: tunnelSubtitle(tunnel),
                    onTap: () => {
                      const param: IdNameParam = { id: tunnel.id, name: tunnel.name };
                      this.pathStack?.pushPathByName(Routes.TUNNEL_DETAIL, param);
                    },
                  })
                }
                .margin({ left: 16, right: 16, top: 5, bottom: 5 })
              }, (tunnel: Tunnel) => tunnel.id)
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
            this.showCreate = true;
          })
      }
      .width('100%')
      .height('100%')
    }
    .title('Cloudflare Tunnel')
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.showCreate, this.createSheet(), ocSheet(() => {
      this.showCreate = false;
    }))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.vm.load().catch(() => {
      });
    })
  }
}

@ObservedV2
class TunnelDetailVM {
  @Trace tunnel: Tunnel | null = null;
  @Trace isLoading: boolean = false;
  // 活跃连接：首帧用内嵌数组占位，随后由专用端点覆盖
  // （内嵌字段 CF 将于 2026-10-05 移除，届时占位恒为空、完全依赖端点）
  @Trace connections: TunnelConnection[] = [];
  @Trace connectionsLoading: boolean = false;
  // 公共主机名（ingress）
  @Trace config: TunnelConfigData | null = null;
  @Trace routes: TunnelIngressRule[] = [];
  @Trace routesLoading: boolean = false;
  @Trace routesError: string = '';
  @Trace isSavingRoutes: boolean = false;
  // 连接令牌
  @Trace token: string = '';
  @Trace tokenLoading: boolean = false;
  @Trace tokenError: string = '';
  private service: AccountModuleService = new AccountModuleService();

  async load(tunnelId: string): Promise<void> {
    this.isLoading = true;
    try {
      this.tunnel = await this.service.getTunnel(accountStore.selectedId, tunnelId);
      this.connections = this.tunnel.connections ?? [];
    } catch (e) {
    } finally {
      this.isLoading = false;
    }
    await this.loadConnections(tunnelId);
  }

  /** 拉取活跃连接。失败不报错——详情页其余内容仍可用，保留占位数据即可。 */
  async loadConnections(tunnelId: string): Promise<void> {
    this.connectionsLoading = true;
    try {
      this.connections = await this.service.tunnelConnections(accountStore.selectedId, tunnelId);
    } catch (e) {
      // 保留内嵌占位，不打断详情页
    } finally {
      this.connectionsLoading = false;
    }
  }

  async loadConfig(tunnelId: string): Promise<void> {
    this.routesLoading = true;
    this.routesError = '';
    try {
      const config = await this.service.getTunnelConfig(accountStore.selectedId, tunnelId);
      this.config = config;
      this.routes = (config.ingress ?? []).filter((r: TunnelIngressRule) => !ruleIsCatchAll(r));
    } catch (e) {
      this.routesError = (e as Error).message ?? '加载失败';
    } finally {
      this.routesLoading = false;
    }
  }

  async loadToken(tunnelId: string): Promise<void> {
    this.tokenLoading = true;
    this.tokenError = '';
    try {
      this.token = await this.service.getTunnelToken(accountStore.selectedId, tunnelId);
    } catch (e) {
      this.tokenError = (e as Error).message ?? '获取令牌失败';
    } finally {
      this.tokenLoading = false;
    }
  }

  /// 整组回写 ingress：可见规则 + 末条 catch-all（复用原 catch-all 条目保住其 originRequest；
  /// config 对象上其余未建模键——warp-routing / 全局 originRequest——随原对象一并回写不丢失）。
  async saveRoutes(tunnelId: string, visible: TunnelIngressRule[]): Promise<string> {
    const config: TunnelConfigData = this.config ?? ({} as TunnelConfigData);
    let catchAll: TunnelIngressRule | null = null;
    for (const rule of config.ingress ?? []) {
      if (ruleIsCatchAll(rule)) {
        catchAll = rule;
      }
    }
    const fallback: TunnelIngressRule = catchAll ?? ({ service: 'http_status:404' } as TunnelIngressRule);
    config.ingress = visible.concat([fallback]);
    this.isSavingRoutes = true;
    try {
      const updated = await this.service.updateTunnelConfig(accountStore.selectedId, tunnelId, config);
      this.config = updated;
      this.routes = (updated.ingress ?? []).filter((r: TunnelIngressRule) => !ruleIsCatchAll(r));
      return '';
    } catch (e) {
      return (e as Error).message ?? '保存失败';
    } finally {
      this.isSavingRoutes = false;
    }
  }

  /// 清理失活连接（活跃 cloudflared 会自动重连），完成后刷新详情
  async cleanConnections(tunnelId: string): Promise<string> {
    try {
      await this.service.deleteTunnelConnections(accountStore.selectedId, tunnelId);
      await this.load(tunnelId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '清理失败';
    }
  }

  async remove(tunnelId: string): Promise<string> {
    try {
      await this.service.deleteTunnel(accountStore.selectedId, tunnelId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}

@ComponentV2
export struct TunnelDetailPage {
  @Local vm: TunnelDetailVM = new TunnelDetailVM();
  @Local tunnelId: string = '';
  @Local tunnelName: string = '';
  @Local canWrite: boolean = false;
  // 公共主机名表单（新增/编辑共用；editIndex 为 -1 表示新增）
  @Local routeSheetVisible: boolean = false;
  @Local editIndex: number = -1;
  @Local fHost: string = '';
  @Local fKindIndex: number = 0;
  @Local fTarget: string = '';
  @Local fPath: string = '';
  // 令牌揭示
  @Local tokenRevealed: boolean = false;
  private pathStack: NavPathStack | null = null;

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
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

  /// `cloudflared service install <token>` 安装命令；未揭示时只露令牌前 8 位
  private installCommand(masked: boolean): string {
    if (masked) {
      return `cloudflared service install ${this.vm.token.substring(0, 8)}…••••`;
    }
    return `cloudflared service install ${this.vm.token}`;
  }

  private openRouteSheet(index: number): void {
    if (index >= 0 && index < this.vm.routes.length) {
      const rule = this.vm.routes[index];
      const kindIndex = kindIndexForService(rule.service);
      this.fHost = rule.hostname ?? '';
      this.fKindIndex = kindIndex;
      this.fTarget = kindIndex === INGRESS_KINDS.length - 1
        ? rule.service
        : rule.service.substring(INGRESS_KINDS[kindIndex].scheme.length);
      this.fPath = rule.path ?? '';
    } else {
      this.fHost = '';
      this.fKindIndex = 0;
      this.fTarget = '';
      this.fPath = '';
    }
    this.editIndex = index;
    this.routeSheetVisible = true;
  }

  private saveRoute(): void {
    const kind = INGRESS_KINDS[this.fKindIndex];
    const service = kind.scheme === '' ? this.fTarget.trim() : `${kind.scheme}${this.fTarget.trim()}`;
    const original: TunnelIngressRule | null =
      (this.editIndex >= 0 && this.editIndex < this.vm.routes.length) ? this.vm.routes[this.editIndex] : null;
    const trimmedPath = this.fPath.trim();
    const rule: TunnelIngressRule = {
      hostname: this.fHost.trim(),
      service: service,
      path: trimmedPath === '' ? undefined : trimmedPath,
      originRequest: original?.originRequest,
    };
    const visible: TunnelIngressRule[] = this.vm.routes.slice();
    if (original !== null) {
      visible[this.editIndex] = rule;
    } else {
      visible.push(rule);
    }
    this.vm.saveRoutes(this.tunnelId, visible).then((err: string) => {
      if (err === '') {
        this.routeSheetVisible = false;
        this.toast('已保存');
      } else {
        this.toast(err);
      }
    });
  }

  private confirmDeleteRoute(index: number): void {
    if (index < 0 || index >= this.vm.routes.length) {
      return;
    }
    const hostname = this.vm.routes[index].hostname ?? '';
    this.getUIContext().showAlertDialog({
      title: '删除公共主机名',
      message: `确定删除「${hostname}」的路由？对外解析的 CNAME 需到 DNS 自行清理。`,
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '删除',
        fontColor: '#DC2626',
        action: () => {
          const visible = this.vm.routes.filter((r: TunnelIngressRule, i: number) => i !== index);
          this.vm.saveRoutes(this.tunnelId, visible).then((err: string) => {
            this.toast(err === '' ? '已删除' : err);
          });
        },
      },
    });
  }

  private confirmCleanConnections(): void {
    this.getUIContext().showAlertDialog({
      title: '清理失活连接',
      message: '清除该隧道登记的全部连接记录；活跃的 cloudflared 会自动重连。',
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '清理',
        fontColor: '#DC2626',
        action: () => {
          this.vm.cleanConnections(this.tunnelId).then((err: string) => {
            this.toast(err === '' ? '已清理' : err);
          });
        },
      },
    });
  }

  private confirmDelete(): void {
    this.getUIContext().showAlertDialog({
      title: '删除 Tunnel',
      message: `确定删除「${this.tunnelName}」？关联连接会断开。`,
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '删除',
        fontColor: '#DC2626',
        action: () => {
          this.vm.remove(this.tunnelId).then((err: string) => {
            if (err === '') {
              this.pathStack?.pop();
            } else {
              this.getUIContext().getPromptAction().showToast({ message: err });
            }
          });
        },
      },
    });
  }

  // 分组小标签（对照样板 ZoneDetailPage 的组头）
  @Builder
  groupHeader(title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .padding({ left: 4 })
  }

  /// Hero 卡（对照样板 ZoneDetailPage.heroCard）：Tunnel 图标 + 名称大字 + 状态点·活跃连接数
  @Builder
  heroCard() {
    Column({ space: 10 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.wifi_router'))
          .fontSize(26)
          .fontColor([BRAND_ORANGE])
      }
      .width(52)
      .height(52)
      .backgroundColor(BRAND_ORANGE_BG)
      .borderRadius(14)

      Text(this.tunnelName)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 8 }) {
        Row({ space: 5 }) {
          Circle({ width: 7, height: 7 })
            .fill(tunnelColor(this.vm.tunnel?.status ?? ''))
          Text(tunnelLabel(this.vm.tunnel?.status ?? ''))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(tunnelColor(this.vm.tunnel?.status ?? ''))
        }
        Text(`${this.vm.connections.length} 个活跃连接`)
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
      }
    }
    .width('100%')
    .padding(OCLayout.islandPadding)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(OCLayout.islandRadius)
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
  }

  @Builder
  routeSheet() {
    Column({ space: 12 }) {
      Text(this.editIndex >= 0 ? '编辑公共主机名' : '添加公共主机名')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      TextInput({ text: this.fHost, placeholder: 'hostname，如 app.example.com' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fHost = value;
        })
      Row({ space: 12 }) {
        Text('协议')
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        Select(INGRESS_KINDS.map((k: IngressKindOption): SelectOption => ({ value: k.label })))
          .selected(this.fKindIndex)
          .value(INGRESS_KINDS[this.fKindIndex].label)
          .font({ size: 14 })
          .onSelect((index: number) => {
            this.fKindIndex = index;
          })
      }
      .width('100%')
      TextInput({ text: this.fTarget, placeholder: INGRESS_KINDS[this.fKindIndex].placeholder })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fTarget = value;
        })
      TextInput({ text: this.fPath, placeholder: '路径正则（可选），如 /api/.*' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fPath = value;
        })
      Text('cloudflared 把命中该主机名的请求转发到这个本地地址；对外解析请到 DNS 配置代理 CNAME。')
        .fontSize(11)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      Button(this.vm.isSavingRoutes ? '正在保存…' : '保存')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor(BRAND_ORANGE)
        .enabled(!this.vm.isSavingRoutes && this.fHost.trim() !== '' && this.fTarget.trim() !== '')
        .onClick(() => {
          this.saveRoute();
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载详情…' })
          }
          .width('100%')
          .height('100%')
        } else {
          Scroll() {
            Column({ space: 18 }) {
              this.heroCard()

              // 信息（对照 iOS infoSection：状态 / 创建时间 / 连接数 / Tunnel ID）
              Column({ space: 8 }) {
                this.groupHeader('信息')
                Column() {
                  InfoRow({ label: '状态', value: tunnelLabel(this.vm.tunnel?.status ?? '') })
                  InfoRow({ label: '创建时间', value: formatTimeAgo(this.vm.tunnel?.created_at ?? '') })
                  InfoRow({ label: '活跃连接', value: `${this.vm.connections.length}` })
                  InfoRow({ label: 'Tunnel ID', value: this.tunnelId })
                }
                .width('100%')
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(OCLayout.chipRadius)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
                .clip(true)
              }
              .width('100%')

              // 公共主机名（ingress 路由）
              Column({ space: 8 }) {
                Row() {
                  Text(this.canWrite ? '公共主机名 · 长按删除' : '公共主机名')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('sys.color.font_secondary'))
                    .layoutWeight(1)
                    .padding({ left: 4 })
                  if (this.canWrite) {
                    Text('＋添加')
                      .fontSize(13)
                      .fontColor(BRAND_ORANGE)
                      .padding({ left: 8, right: 4 })
                      .onClick(() => {
                        this.openRouteSheet(-1);
                      })
                  }
                }
                .width('100%')

                Column() {
                  if (this.vm.routesLoading) {
                    Text('正在加载配置…')
                      .fontSize(13)
                      .fontColor($r('sys.color.font_secondary'))
                      .width('100%')
                      .padding(14)
                  } else if (this.vm.routesError !== '') {
                    Text(`${this.vm.routesError} · 点按重试`)
                      .fontSize(13)
                      .fontColor('#DC2626')
                      .width('100%')
                      .padding(14)
                      .onClick(() => {
                        this.vm.loadConfig(this.tunnelId).catch(() => {
                        });
                      })
                  } else if (this.vm.routes.length === 0) {
                    Text(this.canWrite ? '暂无公共主机名路由，点右上角＋添加' : '暂无公共主机名路由')
                      .fontSize(13)
                      .fontColor($r('sys.color.font_secondary'))
                      .width('100%')
                      .padding(14)
                  } else {
                    ForEach(this.vm.routes, (rule: TunnelIngressRule, index: number) => {
                      Column({ space: 2 }) {
                        Text(rule.hostname ?? '')
                          .fontSize(14)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('sys.color.font_primary'))
                          .width('100%')
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text((rule.path ?? '') !== '' ? `${rule.service} · ${rule.path}` : rule.service)
                          .fontSize(11)
                          .fontColor($r('sys.color.font_secondary'))
                          .width('100%')
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .width('100%')
                      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                      .onClick(() => {
                        if (this.canWrite) {
                          this.openRouteSheet(index);
                        }
                      })
                      .gesture(LongPressGesture().onAction(() => {
                        if (this.canWrite) {
                          this.confirmDeleteRoute(index);
                        }
                      }))
                    }, (rule: TunnelIngressRule, index: number) => `${index}-${rule.hostname ?? ''}-${rule.service}`)
                  }
                }
                .width('100%')
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(OCLayout.chipRadius)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
                .clip(true)
              }
              .width('100%')

              // 连接令牌（argotunnel.write 才可读；等同隧道凭据）
              if (this.canWrite) {
                Column({ space: 8 }) {
                  this.groupHeader('连接令牌')
                  Column({ space: 10 }) {
                    if (this.vm.tokenLoading) {
                      Text('正在获取令牌…')
                        .fontSize(13)
                        .fontColor($r('sys.color.font_secondary'))
                        .width('100%')
                    } else if (this.vm.tokenError !== '') {
                      Text(`${this.vm.tokenError} · 点按重试`)
                        .fontSize(13)
                        .fontColor('#DC2626')
                        .width('100%')
                        .onClick(() => {
                          this.vm.loadToken(this.tunnelId).catch(() => {
                          });
                        })
                    } else if (this.vm.token !== '') {
                      Text('在目标机器安装 cloudflared 后，以管理员身份运行下面的命令即可连接隧道。')
                        .fontSize(12)
                        .fontColor($r('sys.color.font_secondary'))
                        .width('100%')
                      Text(this.installCommand(!this.tokenRevealed))
                        .fontSize(11)
                        .fontColor($r('sys.color.font_primary'))
                        .width('100%')
                        .padding(10)
                        .backgroundColor($r('sys.color.background_secondary'))
                        .borderRadius(8)
                        .wordBreak(WordBreak.BREAK_ALL)
                        .maxLines(this.tokenRevealed ? 8 : 1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Row({ space: 16 }) {
                        Text(this.tokenRevealed ? '隐藏令牌' : '显示令牌')
                          .fontSize(13)
                          .fontColor($r('sys.color.font_primary'))
                          .onClick(() => {
                            this.tokenRevealed = !this.tokenRevealed;
                          })
                        Text('复制命令')
                          .fontSize(13)
                          .fontColor(BRAND_ORANGE)
                          .onClick(() => {
                            this.copyText(this.installCommand(false));
                          })
                        Blank()
                      }
                      .width('100%')
                      Text('令牌等同于隧道凭据，请妥善保管，不要公开分享。')
                        .fontSize(11)
                        .fontColor($r('sys.color.font_tertiary'))
                        .width('100%')
                    }
                  }
                  .width('100%')
                  .padding(OCLayout.islandPadding)
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(OCLayout.chipRadius)
                  .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                  .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
                  .clip(true)
                }
                .width('100%')
              }

              if (this.vm.connections.length > 0) {
                Column({ space: 8 }) {
                  this.groupHeader('连接')
                  Column() {
                    ForEach(this.vm.connections, (conn: TunnelConnection) => {
                      Column({ space: 2 }) {
                        Text(`${conn.colo_name ?? ''} · ${conn.origin_ip ?? ''}`)
                          .fontSize(13)
                          .fontColor($r('sys.color.font_primary'))
                          .width('100%')
                        Text(`cloudflared ${conn.client_version ?? ''} · ${formatTimeAgo(conn.opened_at ?? '')}`)
                          .fontSize(11)
                          .fontColor($r('sys.color.font_secondary'))
                          .width('100%')
                      }
                      .width('100%')
                      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                    }, (conn: TunnelConnection, index: number) => conn.id ?? `${index}`)
                  }
                  .width('100%')
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(OCLayout.chipRadius)
                  .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                  .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
                  .clip(true)
                }
                .width('100%')
              }

              // 危险区（对照 iOS dangerSection：清理连接 + 删除放最后一组）
              Column({ space: 10 }) {
                if (this.canWrite) {
                  Button('清理失活连接')
                    .width('100%')
                    .height(46)
                    .fontSize(15)
                    .fontColor($r('sys.color.font_primary'))
                    .backgroundColor($r('sys.color.comp_background_list_card'))
                    .borderRadius(OCLayout.chipRadius)
                    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                    .onClick(() => {
                      this.confirmCleanConnections();
                    })
                }

                Button('删除 Tunnel')
                  .width('100%')
                  .height(46)
                  .fontSize(15)
                  .fontColor('#DC2626')
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(OCLayout.chipRadius)
                  .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                  .onClick(() => {
                    this.confirmDelete();
                  })
              }
              .width('100%')
              .margin({ bottom: 8 })
            }
            .width('100%')
            .padding(OCLayout.pagePadding)
          }
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .width('100%')
          .height('100%')
        }
      }
      .width('100%')
      .height('100%')
    }
    .title(this.tunnelName)
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.routeSheetVisible, this.routeSheet(), ocSheet(() => {
      this.routeSheetVisible = false;
    }))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as IdNameParam;
      this.tunnelId = param.id;
      this.tunnelName = param.name;
      this.canWrite = authManager.hasScope(Scopes.TUNNEL_WRITE);
      this.vm.load(param.id).catch(() => {
      });
      this.vm.loadConfig(param.id).catch(() => {
      });
      if (this.canWrite) {
        this.vm.loadToken(param.id).catch(() => {
        });
      }
    })
  }
}
