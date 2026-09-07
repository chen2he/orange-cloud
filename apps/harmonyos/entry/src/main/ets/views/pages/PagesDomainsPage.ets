import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// Pages 自定义域名（对照 iOS PagesDomainsView）：列表 + 添加 + 删除 + 域名详情。
// 详情含状态、CNAME 目标（可复制）、以及 zone 不在 Cloudflare 时的 TXT 归属验证记录。
import { pasteboard } from '@kit.BasicServicesKit';
import { NameParam } from '../../models/Routes';
import { PagesDomain } from '../../models/WorkerModels';
import { PagesService } from '../../services/PagesService';
import { DNSService } from '../../services/DNSService';
import { DNSRecord, DNSRecordPayload } from '../../models/Models';
import { accountStore } from '../../core/store/AccountStore';
import { authManager } from '../../core/auth/AuthManager';
import { Scopes } from '../../core/auth/Scopes';
import { BRAND_ORANGE, BRAND_ORANGE_BG, DANGER_RED, InfoRow, OCEmpty, OCLoading } from '../common/Components';
import { ocSheetCompact } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';
import { OCLayout } from '../common/Daybreak';

/// 状态 → 颜色（active 绿 / pending 黄 / 其它红），对照 iOS PagesDomainStatusBadge
function statusColor(status: string): string {
  if (status === 'active') {
    return '#22C55E';
  }
  if (status === 'pending' || status === 'initializing') {
    return '#EAB308';
  }
  return DANGER_RED;
}

function statusLabel(status: string): string {
  switch (status) {
    case 'active':
      return '已生效';
    case 'pending':
      return '待生效';
    case 'initializing':
      return '初始化中';
    case 'deleted':
      return '已删除';
    default:
      return status === '' ? '未知' : status;
  }
}

@ObservedV2
class PagesDomainsVM {
  @Trace domains: PagesDomain[] = [];
  @Trace isLoading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace isSaving: boolean = false;
  @Trace error: string = '';
  /// 项目的 pages.dev 子域，作为 CNAME 目标展示
  @Trace cnameTarget: string = '';
  /// 每个域名的解析状态：'resolved' | 'conflicting' | 'missing' | 'external' | 'unknown'
  @Trace dnsStates: Map<string, string> = new Map<string, string>();
  /// 冲突/已解析时展示的记录内容
  @Trace dnsContents: Map<string, string> = new Map<string, string>();
  @Trace isMutating: boolean = false;

  private service: PagesService = new PagesService();
  private dns: DNSService = new DNSService();

  async load(accountId: string, projectName: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.domains = await this.service.listDomains(accountId, projectName);
      this.loaded = true;
      try {
        const project = await this.service.getProject(accountId, projectName);
        this.cnameTarget = project.subdomain ?? '';
      } catch (e) {
        // 取不到子域不影响域名列表，只是详情少一行 CNAME
      }
      await this.refreshDNSStates();
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  /// 逐域名查解析记录判断状态。zone 不在本账号（无 zone_tag）→ external；
  /// 无 dns.read 或查询失败 → unknown（可能是别的账号的 zone，403 属正常）。
  async refreshDNSStates(): Promise<void> {
    const states = new Map<string, string>();
    const contents = new Map<string, string>();
    const canRead = authManager.hasScope(Scopes.DNS_READ);
    for (const domain of this.domains) {
      const zoneTag = domain.zone_tag ?? '';
      if (zoneTag === '') {
        states.set(domain.name, 'external');
        continue;
      }
      if (!canRead || this.cnameTarget === '') {
        states.set(domain.name, 'unknown');
        continue;
      }
      try {
        const all = await this.dns.fetchRecords(zoneTag);
        const records = all.filter((r: DNSRecord) => {
          const type = r.type.toUpperCase();
          return r.name === domain.name && (type === 'CNAME' || type === 'A' || type === 'AAAA');
        });
        const hit = records.find((r: DNSRecord) => r.content.toLowerCase() === this.cnameTarget.toLowerCase());
        if (hit !== undefined) {
          states.set(domain.name, 'resolved');
          contents.set(domain.name, hit.content);
        } else if (records.length > 0) {
          states.set(domain.name, 'conflicting');
          contents.set(domain.name, records[0].content);
        } else {
          states.set(domain.name, 'missing');
        }
      } catch (e) {
        states.set(domain.name, 'unknown');
      }
    }
    this.dnsStates = states;
    this.dnsContents = contents;
  }

  /// 在域名所在 zone 建一条已代理的 CNAME → <project>.pages.dev
  async createCNAME(domain: PagesDomain): Promise<string> {
    const zoneTag = domain.zone_tag ?? '';
    if (zoneTag === '' || this.cnameTarget === '') {
      return '该域名不在当前账号的 Cloudflare 区域内，请到域名服务商处配置';
    }
    if (this.isMutating) {
      return '';
    }
    this.isMutating = true;
    try {
      const payload: DNSRecordPayload = {
        type: 'CNAME',
        name: domain.name,
        content: this.cnameTarget,
        ttl: 1,
        proxied: true,
      };
      await this.dns.createRecord(zoneTag, payload);
      this.dnsStates.set(domain.name, 'resolved');
      this.dnsContents.set(domain.name, this.cnameTarget);
      // Map 是引用类型，就地改不会触发刷新，重建一份
      this.dnsStates = new Map<string, string>(this.dnsStates);
      this.dnsContents = new Map<string, string>(this.dnsContents);
      return '';
    } catch (e) {
      return (e as Error).message ?? '创建 CNAME 失败';
    } finally {
      this.isMutating = false;
    }
  }

  /// 重新触发域名校验（pending / 校验失败时用）
  async retry(accountId: string, projectName: string, domainName: string): Promise<string> {
    this.isMutating = true;
    try {
      await this.service.retryDomain(accountId, projectName, domainName);
      await this.load(accountId, projectName);
      return '';
    } catch (e) {
      return (e as Error).message ?? '重新验证失败';
    } finally {
      this.isMutating = false;
    }
  }

  async add(accountId: string, projectName: string, name: string): Promise<string> {
    this.isSaving = true;
    try {
      await this.service.addDomain(accountId, projectName, name);
      this.domains = await this.service.listDomains(accountId, projectName);
      await this.refreshDNSStates();
      // 绑定后自动补解析：zone 在本账号且尚无记录时直接建 CNAME，省掉用户再点一次。
      // 失败不影响绑定结果，静默回退到详情里的手动按钮。
      if (authManager.hasScope(Scopes.DNS_WRITE) && this.dnsStates.get(name) === 'missing') {
        const domain = this.domains.find((d: PagesDomain) => d.name === name);
        if (domain !== undefined) {
          await this.createCNAME(domain);
        }
      }
      return '';
    } catch (e) {
      return (e as Error).message ?? '添加失败';
    } finally {
      this.isSaving = false;
    }
  }

  async remove(accountId: string, projectName: string, name: string): Promise<string> {
    try {
      await this.service.deleteDomain(accountId, projectName, name);
      this.domains = this.domains.filter((d: PagesDomain) => d.name !== name);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}

@ComponentV2
export struct PagesDomainsPage {
  @Local vm: PagesDomainsVM = new PagesDomainsVM();
  @Local projectName: string = '';
  @Local addSheetVisible: boolean = false;
  @Local detailVisible: boolean = false;
  @Local selected: PagesDomain | null = null;
  @Local fDomain: string = '';
  @Local refreshing: boolean = false;

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  private canWrite(): boolean {
    if (!authManager.hasScope(Scopes.PAGES_WRITE)) {
      this.toast('当前授权未包含 Pages 写权限（pages.write）');
      return false;
    }
    return true;
  }

  private copy(value: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.toast('已复制');
    }).catch(() => {
    });
  }

  /// 当前选中域名的解析状态（未查到按 unknown）
  private dnsState(): string {
    if (this.selected === null) {
      return 'unknown';
    }
    return this.vm.dnsStates.get(this.selected!.name) ?? 'unknown';
  }

  private confirmDelete(domain: PagesDomain): void {
    this.getUIContext().showAlertDialog({
      title: `删除域名「${domain.name}」？`,
      message: '将从该 Pages 项目移除此域名，不影响已有 DNS 记录。',
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '删除域名',
        fontColor: DANGER_RED,
        action: () => {
          this.vm.remove(accountStore.selectedId, this.projectName, domain.name).then((err: string) => {
            if (err === '') {
              this.detailVisible = false;
              this.toast('已删除');
            } else {
              this.toast(err);
            }
          });
        },
      },
    });
  }

  @Builder
  addSheet() {
    Column({ space: 14 }) {
      Text('添加自定义域名')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
      Text('域名在 Cloudflare 上时会自动配置解析；不在时需按详情里的 TXT 记录完成归属验证。')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({ placeholder: 'example.com', text: this.fDomain })
        .onChange((value: string) => {
          this.fDomain = value;
        })
      Button(this.vm.isSaving ? '正在添加…' : '添加')
        .width('100%')
        .height(46)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm.isSaving && this.fDomain.trim() !== '')
        .onClick(() => {
          this.vm.add(accountStore.selectedId, this.projectName, this.fDomain.trim())
            .then((err: string) => {
              if (err === '') {
                this.addSheetVisible = false;
                this.fDomain = '';
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

  /// 可复制行（CNAME / TXT 记录共用）
  @Builder
  copyRow(label: string, value: string) {
    Row({ space: 10 }) {
      Text(label)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
      Blank()
      Text(value)
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .textAlign(TextAlign.End)
      SymbolGlyph($r('sys.symbol.square_on_square_fill'))
        .fontSize(15)
        .fontColor([$r('app.color.oc_brand_text')])
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => {
      this.copy(value);
    })
  }

  /// DNS 状态段：已指向 / 未指向 / 可一键添加 / 不在本账号 / 查不了
  @Builder
  dnsSection() {
    if (this.selected !== null) {
      Text('DNS')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .padding({ left: 4 })
      Column() {
        if (this.dnsState() === 'resolved') {
          Row({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.checkmark_circle'))
              .fontSize(17)
              .fontColor(['#22C55E'])
            Text('已指向本项目')
              .fontSize(14)
              .fontColor($r('sys.color.font_primary'))
            Blank()
            Text(this.vm.dnsContents.get(this.selected!.name) ?? '')
              .fontSize(12)
              .fontFamily('monospace')
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .textAlign(TextAlign.End)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        } else if (this.dnsState() === 'conflicting') {
          Row({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
              .fontSize(17)
              .fontColor(['#EAB308'])
            Text('未指向本项目')
              .fontSize(14)
              .fontColor($r('sys.color.font_primary'))
            Blank()
            Text(this.vm.dnsContents.get(this.selected!.name) ?? '')
              .fontSize(12)
              .fontFamily('monospace')
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .textAlign(TextAlign.End)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        } else if (this.dnsState() === 'missing') {
          Row({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.plus_circle'))
              .fontSize(17)
              .fontColor([$r('app.color.oc_brand_text')])
            Text('添加 CNAME 记录')
              .fontSize(14)
              .fontColor($r('app.color.oc_brand_text'))
            Blank()
            if (this.vm.isMutating) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color(BRAND_ORANGE)
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .onClick(() => {
            if (!authManager.hasScope(Scopes.DNS_WRITE)) {
              this.toast('当前授权未包含 DNS 写权限（dns.write）');
              return;
            }
            this.vm.createCNAME(this.selected!).then((err: string) => {
              this.toast(err === '' ? '已添加 CNAME 记录' : err);
            });
          })
          Text(`将在该域名所在的区域添加一条已代理的 CNAME 记录，指向 ${this.vm.cnameTarget}。`)
            .fontSize(11)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 12 })
        } else if (this.dnsState() === 'external') {
          Text(`该域名不在当前账号的 Cloudflare 区域内，请在域名服务商处添加指向 ${this.vm.cnameTarget} 的 CNAME 记录。`)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
            .padding(14)
        } else {
          Text('无法查询该域名的解析记录（可能缺少 dns.read 权限，或该区域不属于当前账号）。')
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
            .padding(14)
        }
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_list_card'))
      .borderRadius(OCLayout.chipRadius)
      .clip(true)
    }
  }

  @Builder
  detailSheet() {
    Column({ space: 12 }) {
      if (this.selected !== null) {
        Text(this.selected!.name)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .margin({ top: 8 })

        Column() {
          Row({ space: 10 }) {
            Text('状态')
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
            Blank()
            Text(statusLabel(this.selected!.status ?? ''))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(statusColor(this.selected!.status ?? ''))
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor($r('app.color.oc_brand_bg'))
              .borderRadius(8)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          if (this.vm.cnameTarget !== '') {
            Divider()
              .strokeWidth(0.5)
              .color($r('sys.color.comp_divider'))
              .margin({ left: 16 })
            this.copyRow('CNAME', this.vm.cnameTarget)
          }
        }
        .width('100%')
        .backgroundColor($r('sys.color.comp_background_list_card'))
        .borderRadius(OCLayout.chipRadius)
        .clip(true)

        // zone 不在 Cloudflare 时，CF 会给一条 TXT 记录做归属验证
        if ((this.selected!.validation_data?.method ?? '') === 'txt' &&
          (this.selected!.validation_data?.status ?? '') !== 'active' &&
          (this.selected!.validation_data?.txt_name ?? '') !== '') {
          Text('验证 TXT 记录')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
            .padding({ left: 4 })
          Column() {
            this.copyRow('记录名', this.selected!.validation_data!.txt_name!)
            Divider()
              .strokeWidth(0.5)
              .color($r('sys.color.comp_divider'))
              .margin({ left: 16 })
            this.copyRow('记录值', this.selected!.validation_data?.txt_value ?? '')
          }
          .width('100%')
          .backgroundColor($r('sys.color.comp_background_list_card'))
          .borderRadius(OCLayout.chipRadius)
          .clip(true)
        }

        // 验证 / 校验失败原因（有就展示，别让用户对着 pending 干等）
        if ((this.selected!.verification_data?.error_message ?? '') !== '' ||
          (this.selected!.validation_data?.error_message ?? '') !== '') {
          Text(this.selected!.verification_data?.error_message ??
            this.selected!.validation_data?.error_message ?? '')
            .fontSize(12)
            .fontColor(DANGER_RED)
            .width('100%')
        }

        // DNS 段（对照 iOS dnsSection）：按解析状态给不同出口
        this.dnsSection()

        if ((this.selected!.status ?? '') !== 'active') {
          Button(this.vm.isMutating ? '正在重新验证…' : '重新验证')
            .width('100%')
            .height(46)
            .fontSize(15)
            .fontColor($r('app.color.oc_brand_text'))
            .backgroundColor($r('sys.color.comp_background_list_card'))
            .borderRadius(OCLayout.chipRadius)
            .enabled(!this.vm.isMutating)
            .onClick(() => {
              if (!this.canWrite()) {
                return;
              }
              this.vm.retry(accountStore.selectedId, this.projectName, this.selected!.name)
                .then((err: string) => {
                  this.toast(err === '' ? '已重新触发验证' : err);
                });
            })
        }

        Button('删除域名')
          .width('100%')
          .height(46)
          .fontSize(15)
          .fontColor(DANGER_RED)
          .backgroundColor($r('sys.color.comp_background_list_card'))
          .borderRadius(OCLayout.chipRadius)
          .onClick(() => {
            if (this.canWrite()) {
              this.confirmDelete(this.selected!);
            }
          })
      }
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  @Builder
  domainRow(domain: PagesDomain) {
    Row({ space: 10 }) {
      Circle({ width: 8, height: 8 })
        .fill(statusColor(domain.status ?? ''))
      Column({ space: 3 }) {
        Text(domain.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(statusLabel(domain.status ?? ''))
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Image($r('sys.media.ohos_ic_public_arrow_right'))
        .width(14)
        .height(14)
        .fillColor($r('sys.color.font_tertiary'))
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .onClick(() => {
      this.selected = domain;
      this.detailVisible = true;
    })
    .gesture(LongPressGesture().onAction(() => {
      if (this.canWrite()) {
        this.confirmDelete(domain);
      }
    }))
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading && !this.vm.loaded) {
          Column() {
            OCLoading({ text: '正在加载域名…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.domains.length === 0) {
          Column() {
            OCEmpty({
              symbol: $r('sys.symbol.globe_and_keyboard'),
              title: '尚无自定义域名',
              subtitle: this.vm.error !== '' ? this.vm.error : '项目默认可通过 pages.dev 子域访问',
            })
          }
          .width('100%')
          .height('100%')
        } else {
          Refresh({ refreshing: this.refreshing }) {
            Scroll() {
              Column({ space: 8 }) {
                Text(`共 ${this.vm.domains.length} 个 · 点按看详情，长按删除`)
                  .fontSize(13)
                  .fontColor($r('sys.color.font_secondary'))
                  .width('100%')
                  .padding({ left: 4 })
                Column() {
                  ForEach(this.vm.domains, (domain: PagesDomain, index: number) => {
                    this.domainRow(domain)
                    if (index < this.vm.domains.length - 1) {
                      Divider()
                        .strokeWidth(0.5)
                        .color($r('sys.color.comp_divider'))
                        .margin({ left: 14 })
                    }
                  }, (domain: PagesDomain) => domain.id)
                }
                .width('100%')
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(OCLayout.chipRadius)
                .clip(true)
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
            this.vm.load(accountStore.selectedId, this.projectName).then(() => {
              this.refreshing = false;
            }).catch(() => {
              this.refreshing = false;
            });
          })
        }
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: '自定义域名' }, menu: { value: [{ content: { icon: $r('sys.symbol.plus'), label: '添加', action: () => { if (this.canWrite()) { this.fDomain = ''; this.addSheetVisible = true; } } } }] } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.addSheetVisible, this.addSheet(), ocSheetCompact(() => {
      this.addSheetVisible = false;
    }))
    .bindSheet(this.detailVisible, this.detailSheet(), ocSheetCompact(() => {
      this.detailVisible = false;
    }))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as NameParam;
      this.projectName = param.name;
      this.vm.load(accountStore.selectedId, param.name).catch(() => {
      });
    })
  }
}
