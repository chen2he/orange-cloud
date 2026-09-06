// Worker 域名与路由（对照 iOS WorkerRoutesView）：
// workers.dev 子域开关 + 自定义域（挂/卸）+ Zone 路由（加/删）。
//
// 权限分两组：子域 / 自定义域是 account 级，按 workers-scripts.write 门控；
// Zone 路由是 zone 级独立权限组，按 workers-routes.write 门控——两者不能混用一个判断。
// 路由端点是 zone 级的，账号下每个 zone 各查一次再过滤到本脚本。
import { Zone } from '../../models/Models';
import { NameParam } from '../../models/Routes';
import { WorkerCustomDomain, WorkerRoute } from '../../models/WorkerModels';
import { WorkerService } from '../../services/WorkerService';
import { ZoneService } from '../../services/ZoneService';
import { accountStore } from '../../core/store/AccountStore';
import { authManager } from '../../core/auth/AuthManager';
import { Scopes } from '../../core/auth/Scopes';
import { BRAND_ORANGE, DANGER_RED, OCLoading, ToggleRow } from '../common/Components';
import { ocSheetCompact } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';
import { GlassIsland, OCLayout, RevealBox } from '../common/Daybreak';

/// 路由 + 它所属的 zone（路由端点是 zone 级，删除时要带回 zoneId）
interface ScopedRoute {
  zoneId: string;
  zoneName: string;
  route: WorkerRoute;
}

@ObservedV2
class DomainsVM {
  @Trace subdomainOn: boolean = false;
  @Trace domains: WorkerCustomDomain[] = [];
  @Trace routes: ScopedRoute[] = [];
  @Trace zones: Zone[] = [];
  @Trace isLoading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace isSaving: boolean = false;
  @Trace error: string = '';

  private service: WorkerService = new WorkerService();
  private zoneService: ZoneService = new ZoneService();

  async load(accountId: string, scriptName: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      try {
        this.zones = await this.zoneService.fetchZones(accountId);
      } catch (e) {
      }
      try {
        this.domains = await this.service.customDomains(accountId, scriptName);
      } catch (e) {
      }
      // 子域可能未在账号开通，单独容错，不阻断整页
      this.subdomainOn = await this.service.subdomain(accountId, scriptName);
      await this.loadRoutes(scriptName);
      this.loaded = true;
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  /// 逐 zone 查路由再过滤到本脚本；缺 zone 级读权限时静默跳过该 zone
  private async loadRoutes(scriptName: string): Promise<void> {
    const collected: ScopedRoute[] = [];
    for (const zone of this.zones) {
      try {
        const list = await this.service.routes(zone.id);
        for (const route of list) {
          if ((route.script ?? '') === scriptName) {
            collected.push({ zoneId: zone.id, zoneName: zone.name, route: route });
          }
        }
      } catch (e) {
      }
    }
    this.routes = collected;
  }

  async setSubdomain(accountId: string, scriptName: string, enabled: boolean): Promise<string> {
    try {
      await this.service.setSubdomain(accountId, scriptName, enabled);
      this.subdomainOn = enabled;
      return '';
    } catch (e) {
      return (e as Error).message ?? '切换失败';
    }
  }

  async attachDomain(accountId: string, scriptName: string, hostname: string, zoneId: string): Promise<string> {
    this.isSaving = true;
    try {
      await this.service.attachDomain(accountId, scriptName, hostname, zoneId);
      this.domains = await this.service.customDomains(accountId, scriptName);
      return '';
    } catch (e) {
      return (e as Error).message ?? '绑定失败';
    } finally {
      this.isSaving = false;
    }
  }

  async detachDomain(accountId: string, domainId: string): Promise<string> {
    try {
      await this.service.deleteDomain(accountId, domainId);
      this.domains = this.domains.filter((d: WorkerCustomDomain) => d.id !== domainId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '解绑失败';
    }
  }

  async addRoute(scriptName: string, zoneId: string, pattern: string): Promise<string> {
    this.isSaving = true;
    try {
      await this.service.createRoute(zoneId, pattern, scriptName);
      await this.loadRoutes(scriptName);
      return '';
    } catch (e) {
      return (e as Error).message ?? '添加失败';
    } finally {
      this.isSaving = false;
    }
  }

  async removeRoute(zoneId: string, routeId: string): Promise<string> {
    try {
      await this.service.deleteRoute(zoneId, routeId);
      this.routes = this.routes.filter((r: ScopedRoute) => r.route.id !== routeId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}

@ComponentV2
export struct WorkerDomainsPage {
  @Local vm: DomainsVM = new DomainsVM();
  @Local scriptName: string = '';
  @Local domainSheetVisible: boolean = false;
  @Local routeSheetVisible: boolean = false;
  @Local fHost: string = '';
  @Local fPattern: string = '';
  @Local fZoneIdx: number = 0;
  @Local refreshing: boolean = false;

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  /// 子域 / 自定义域：account 级写权限
  private canWriteScript(): boolean {
    if (!authManager.hasScope(Scopes.WORKERS_WRITE)) {
      this.toast('当前授权未包含 Workers 写权限（workers-scripts.write）');
      return false;
    }
    return true;
  }

  /// Zone 路由：zone 级独立权限组，与上面不是同一个 scope
  private canWriteRoute(): boolean {
    if (!authManager.hasScope(Scopes.WORKERS_ROUTES_WRITE)) {
      this.toast('当前授权未包含 Worker 路由写权限（workers-routes.write）');
      return false;
    }
    return true;
  }

  private zoneNames(): string[] {
    return this.vm.zones.map((z: Zone) => z.name);
  }

  private confirmDelete(title: string, message: string, onConfirm: () => void): void {
    this.getUIContext().showAlertDialog({
      title: title,
      message: message,
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: { value: '删除', fontColor: DANGER_RED, action: onConfirm },
    });
  }

  @Builder
  sectionHeader(title: string, action: string, onAdd: () => void) {
    Row() {
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_secondary'))
        .layoutWeight(1)
        .padding({ left: 4 })
      if (action !== '') {
        Text(action)
          .fontSize(13)
          .fontColor($r('app.color.oc_brand_text'))
          .padding({ left: 8, right: 4 })
          .onClick(onAdd)
      }
    }
    .width('100%')
  }


  @Builder
  emptyRow(text: string) {
    Text(text)
      .fontSize(13)
      .fontColor($r('sys.color.font_tertiary'))
      .width('100%')
      .padding(14)
  }

  @Builder
  domainSheet() {
    Column({ space: 14 }) {
      Text('绑定自定义域名')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
      Text('把一个主机名直接指向本脚本，Cloudflare 会自动签发证书并接管解析。')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      Row({ space: 10 }) {
        Text('所属域名')
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
        Blank()
        if (this.vm.zones.length > 0) {
          Select(this.zoneNames().map((name: string) => {
            return { value: name } as SelectOption;
          }))
            .selected(this.fZoneIdx)
            .value(this.vm.zones[this.fZoneIdx]?.name ?? '')
            .onSelect((index: number) => {
              this.fZoneIdx = index;
            })
        }
      }
      .width('100%')
      TextInput({ placeholder: 'api.example.com', text: this.fHost })
        .onChange((value: string) => {
          this.fHost = value;
        })
      Button(this.vm.isSaving ? '正在绑定…' : '绑定')
        .width('100%')
        .height(46)
        .backgroundColor($r('app.color.oc_brand'))
        .enabled(!this.vm.isSaving && this.fHost.trim() !== '' && this.vm.zones.length > 0)
        .onClick(() => {
          const zone = this.vm.zones[this.fZoneIdx];
          if (!zone) {
            return;
          }
          this.vm.attachDomain(accountStore.selectedId, this.scriptName, this.fHost.trim(), zone.id)
            .then((err: string) => {
              if (err === '') {
                this.domainSheetVisible = false;
                this.fHost = '';
                this.toast('已绑定');
              } else {
                this.toast(err);
              }
            });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  @Builder
  routeSheet() {
    Column({ space: 14 }) {
      Text('添加路由')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
      Text('匹配到该 pattern 的请求交给本脚本处理，支持通配符，如 example.com/api/*')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      Row({ space: 10 }) {
        Text('所属域名')
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
        Blank()
        if (this.vm.zones.length > 0) {
          Select(this.zoneNames().map((name: string) => {
            return { value: name } as SelectOption;
          }))
            .selected(this.fZoneIdx)
            .value(this.vm.zones[this.fZoneIdx]?.name ?? '')
            .onSelect((index: number) => {
              this.fZoneIdx = index;
            })
        }
      }
      .width('100%')
      TextInput({ placeholder: 'example.com/api/*', text: this.fPattern })
        .onChange((value: string) => {
          this.fPattern = value;
        })
      Button(this.vm.isSaving ? '正在添加…' : '添加')
        .width('100%')
        .height(46)
        .backgroundColor($r('app.color.oc_brand'))
        .enabled(!this.vm.isSaving && this.fPattern.trim() !== '' && this.vm.zones.length > 0)
        .onClick(() => {
          const zone = this.vm.zones[this.fZoneIdx];
          if (!zone) {
            return;
          }
          this.vm.addRoute(this.scriptName, zone.id, this.fPattern.trim()).then((err: string) => {
            if (err === '') {
              this.routeSheetVisible = false;
              this.fPattern = '';
              this.toast('已添加');
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
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading && !this.vm.loaded) {
          Column() {
            OCLoading({ text: '正在加载域名与路由…' })
          }
          .width('100%')
          .height('100%')
        } else {
          Refresh({ refreshing: this.refreshing }) {
            Scroll() {
              Column({ space: 18 }) {
                // workers.dev 子域
                RevealBox({ idx: 0 }) {
                  Column({ space: 8 }) {
                    this.sectionHeader('workers.dev 子域', '', () => {
                    })
                    GlassIsland({ pad: 0, cornerRadius: OCLayout.chipRadius }) {
                      ToggleRow({
                        title: '公网可访问',
                        subtitle: this.vm.subdomainOn
                          ? `${this.scriptName}.<账户>.workers.dev`
                          : '关闭后仅自定义域 / 路由可访问',
                        isOn: this.vm.subdomainOn,
                        onToggle: (on: boolean) => {
                          if (!this.canWriteScript()) {
                            return;
                          }
                          this.vm.setSubdomain(accountStore.selectedId, this.scriptName, on)
                            .then((err: string) => {
                              this.toast(err);
                            });
                        },
                      })
                    }
                  }
                  .width('100%')
                }

                // 自定义域
                RevealBox({ idx: 1 }) {
                  Column({ space: 8 }) {
                    this.sectionHeader(`自定义域名（${this.vm.domains.length}）· 长按解绑`, '绑定', () => {
                      if (this.canWriteScript()) {
                        this.fHost = '';
                        this.domainSheetVisible = true;
                      }
                    })
                    GlassIsland({ pad: 0, cornerRadius: OCLayout.chipRadius }) {
                      if (this.vm.domains.length === 0) {
                        this.emptyRow('尚无自定义域名')
                      } else {
                        ForEach(this.vm.domains, (domain: WorkerCustomDomain, index: number) => {
                          Column({ space: 3 }) {
                            Text(domain.hostname ?? '')
                              .fontSize(15)
                              .fontWeight(FontWeight.Medium)
                              .fontColor($r('sys.color.font_primary'))
                              .width('100%')
                            Text(domain.zone_name ?? '')
                              .fontSize(12)
                              .fontColor($r('sys.color.font_secondary'))
                              .width('100%')
                          }
                          .width('100%')
                          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                          .gesture(LongPressGesture().onAction(() => {
                            if (!this.canWriteScript()) {
                              return;
                            }
                            this.confirmDelete('解除绑定',
                              `将解除 ${domain.hostname ?? ''} 与本脚本的绑定。`, () => {
                                this.vm.detachDomain(accountStore.selectedId, domain.id).then((err: string) => {
                                  this.toast(err === '' ? '已解绑' : err);
                                });
                              });
                          }))
                          if (index < this.vm.domains.length - 1) {
                            Divider()
                              .strokeWidth(0.5)
                              .color($r('sys.color.comp_divider'))
                              .margin({ left: 14 })
                          }
                        }, (domain: WorkerCustomDomain) => domain.id)
                      }
                    }
                  }
                  .width('100%')
                }

                // Zone 路由
                RevealBox({ idx: 2 }) {
                  Column({ space: 8 }) {
                    this.sectionHeader(`路由（${this.vm.routes.length}）· 长按删除`, '添加', () => {
                      if (this.canWriteRoute()) {
                        this.fPattern = '';
                        this.routeSheetVisible = true;
                      }
                    })
                    GlassIsland({ pad: 0, cornerRadius: OCLayout.chipRadius }) {
                      if (this.vm.routes.length === 0) {
                        this.emptyRow('尚无路由')
                      } else {
                        ForEach(this.vm.routes, (item: ScopedRoute, index: number) => {
                          Column({ space: 3 }) {
                            Text(item.route.pattern)
                              .fontSize(15)
                              .fontFamily('monospace')
                              .fontColor($r('sys.color.font_primary'))
                              .width('100%')
                            Text(item.zoneName)
                              .fontSize(12)
                              .fontColor($r('sys.color.font_secondary'))
                              .width('100%')
                          }
                          .width('100%')
                          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                          .gesture(LongPressGesture().onAction(() => {
                            if (!this.canWriteRoute()) {
                              return;
                            }
                            this.confirmDelete('删除路由',
                              `将删除 ${item.route.pattern}，该路径不再由本脚本处理。`, () => {
                                this.vm.removeRoute(item.zoneId, item.route.id).then((err: string) => {
                                  this.toast(err === '' ? '已删除' : err);
                                });
                              });
                          }))
                          if (index < this.vm.routes.length - 1) {
                            Divider()
                              .strokeWidth(0.5)
                              .color($r('sys.color.comp_divider'))
                              .margin({ left: 14 })
                          }
                        }, (item: ScopedRoute) => item.route.id)
                      }
                    }
                  }
                  .width('100%')
                }
              }
              .width('100%')
              .padding(OCLayout.pagePadding)
            }
            .align(Alignment.Top)
            .scrollBar(BarState.Off)
            .width('100%')
            .height('100%')
          }
          .onRefreshing(() => {
            this.refreshing = true;
            this.vm.load(accountStore.selectedId, this.scriptName).then(() => {
              this.refreshing = false;
            }).catch(() => {
              this.refreshing = false;
            });
          })
        }
      }
      .width('100%')
      .height('100%')
    }
    .title('域名')
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.domainSheetVisible, this.domainSheet(), ocSheetCompact(() => {
      this.domainSheetVisible = false;
    }))
    .bindSheet(this.routeSheetVisible, this.routeSheet(), ocSheetCompact(() => {
      this.routeSheetVisible = false;
    }))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as NameParam;
      this.scriptName = param.name;
      this.vm.load(accountStore.selectedId, param.name).catch(() => {
      });
    })
  }
}
