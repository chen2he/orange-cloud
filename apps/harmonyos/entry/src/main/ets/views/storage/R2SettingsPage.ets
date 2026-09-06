import { HdsNavDestination } from '@kit.UIDesignKit';
// R2 桶设置：公开访问（r2.dev 托管域）/ 自定义域 / CORS 规则（对齐 iOS R2BucketSettingsView）。
// 入口：R2 对象列表右上角齿轮。写操作按 workers-r2.write 门控 + 确认弹窗。
import {
  R2CorsAllowed,
  R2CorsPolicy,
  R2CorsRule,
  R2CustomDomain,
  R2ManagedDomain,
} from '../../models/StorageModels';
import { IdNameParam } from '../../models/Routes';
import { StorageService } from '../../services/StorageService';
import { ApiError } from '../../core/network/CFApiClient';
import { ZoneService } from '../../services/ZoneService';
import { Zone } from '../../models/Models';
import { accountStore } from '../../core/store/AccountStore';
import { authManager } from '../../core/auth/AuthManager';
import { Scopes } from '../../core/auth/Scopes';
import { BRAND_ORANGE, OCLoading, SectionHeader, ToggleRow } from '../common/Components';
import { ocSheet } from '../common/Sheets';
import { pasteboard } from '@kit.BasicServicesKit';
import { namespaceLabel, namespaceSqlName, tableSqlName, R2Catalog, R2CatalogNamespace, R2CatalogService, R2CatalogTable } from '../../services/R2CatalogService';
import { R2SQLResult, R2SQLService } from '../../services/R2SQLService';
import { promptAction } from '@kit.ArkUI';
import { OCSkyBackground } from '../common/OCSky';

const CORS_METHODS: string[] = ['GET', 'PUT', 'POST', 'DELETE', 'HEAD'];

/// CORS 规则一行摘要（来源 + 方法）
function corsRuleTitle(rule: R2CorsRule): string {
  const origins = rule.allowed?.origins ?? [];
  return origins.length > 0 ? origins.join('，') : '（无来源）';
}

function corsRuleSubtitle(rule: R2CorsRule): string {
  const methods = (rule.allowed?.methods ?? []).join(' / ');
  const age = rule.maxAgeSeconds;
  if (age !== undefined) {
    return `${methods} · Max-Age ${age}s`;
  }
  return methods;
}

function domainStatusLine(domain: R2CustomDomain): string {
  const parts: string[] = [];
  parts.push(domain.enabled === true ? '已启用' : '已停用');
  const ssl = domain.status?.ssl;
  if (ssl !== undefined && ssl !== '') {
    parts.push(`SSL：${ssl}`);
  }
  const ownership = domain.status?.ownership;
  if (ownership !== undefined && ownership !== '') {
    parts.push(`归属：${ownership}`);
  }
  return parts.join(' · ');
}

@ObservedV2
class SettingsVM {
  @Trace managed: R2ManagedDomain | null = null;
  @Trace customDomains: R2CustomDomain[] = [];
  @Trace corsRules: R2CorsRule[] = [];
  @Trace zones: Zone[] = [];
  @Trace isLoading: boolean = false;
  @Trace isSaving: boolean = false;
  // 数据目录（Iceberg）。启用是计费动作，界面先弹确认再调这里。
  @Trace catalog: R2Catalog | null = null;
  @Trace catalogNamespaces: R2CatalogNamespace[] = [];
  @Trace catalogLoaded: boolean = false;
  // R2 SQL 控制台（独立主机 api.sql.cloudflarestorage.com，按扫描量计费）
  @Trace sqlTables: string[] = [];
  @Trace sqlRunning: boolean = false;
  @Trace sqlError: string = '';
  @Trace sqlResult: R2SQLResult | null = null;
  private catalogService: R2CatalogService = new R2CatalogService();
  private sqlService: R2SQLService = new R2SQLService();
  private service: StorageService = new StorageService();
  private zoneService: ZoneService = new ZoneService();

  /// 拉命名空间下的表清单，供控制台点按插入表引用（失败静默，不挡手输 SQL）
  async loadSqlTables(bucket: string): Promise<void> {
    if (this.sqlTables.length > 0) {
      return;
    }
    const accountId = accountStore.selectedId;
    const refs: string[] = [];
    for (const ns of this.catalogNamespaces) {
      try {
        const tables = await this.catalogService.tables(accountId, bucket, namespaceSqlName(ns));
        for (const table of tables) {
          const ref = tableSqlName(table);
          if (ref !== '' && !refs.includes(ref)) {
            refs.push(ref);
          }
        }
      } catch (e) {
        // 单个命名空间读失败不影响其余
      }
    }
    this.sqlTables = refs;
  }

  /// 执行一条只读查询。独立主机对 OAuth token 的接受度官方未明说，401/403 给定向指引。
  async runSql(bucket: string, sql: string): Promise<void> {
    const trimmed = sql.trim();
    if (trimmed === '' || this.sqlRunning) {
      return;
    }
    this.sqlRunning = true;
    this.sqlError = '';
    try {
      this.sqlResult = await this.sqlService.query(accountStore.selectedId, bucket, trimmed);
    } catch (e) {
      const err = e as ApiError;
      if (err.code === 401 || err.code === 403) {
        this.sqlError = 'R2 SQL 查询被拒绝。请确认授权包含 R2 SQL / 数据目录 / R2 读权限；若仍失败，说明该接口暂不接受 App 的登录方式，请先用 Wrangler 查询。';
      } else {
        this.sqlError = (e as Error).message ?? '查询失败';
      }
      this.sqlResult = null;
    } finally {
      this.sqlRunning = false;
    }
  }

  /// 三块各自 best-effort：某块不可用（如桶从未设过 CORS 回 404）不连累其余
  async setCatalogEnabled(bucket: string, enabled: boolean): Promise<string> {
    this.isSaving = true;
    try {
      if (enabled) {
        await this.catalogService.enable(accountStore.selectedId, bucket);
      } else {
        await this.catalogService.disable(accountStore.selectedId, bucket);
      }
      await this.load(bucket);
      return '';
    } catch (e) {
      return (e as Error).message ?? '设置失败';
    } finally {
      this.isSaving = false;
    }
  }

  async load(bucket: string): Promise<void> {
    this.isLoading = true;
    const accountId = accountStore.selectedId;
    try {
      this.managed = await this.service.getManagedDomain(accountId, bucket);
    } catch (e) {
      this.managed = null;
    }
    // 数据目录：未启用时接口 404，按「未启用」处理而非报错
    try {
      this.catalog = await this.catalogService.catalog(accountId, bucket);
    } catch (e) {
      this.catalog = null;
    }
    if (this.catalog?.status === 'active') {
      try {
        this.catalogNamespaces = await this.catalogService.namespaces(accountId, bucket);
      } catch (e) {
        this.catalogNamespaces = [];
      }
    } else {
      this.catalogNamespaces = [];
    }
    this.catalogLoaded = true;
    try {
      this.customDomains = await this.service.listCustomDomains(accountId, bucket);
    } catch (e) {
      this.customDomains = [];
    }
    try {
      const policy = await this.service.getCorsPolicy(accountId, bucket);
      this.corsRules = policy.rules ?? [];
    } catch (e) {
      this.corsRules = [];
    }
    this.isLoading = false;
    // zone 列表仅供「添加自定义域」下拉选择，失败静默（可手输 zoneId）
    try {
      this.zones = await this.zoneService.fetchZones(accountId);
    } catch (e) {
      this.zones = [];
    }
  }

  async setManagedEnabled(bucket: string, enabled: boolean): Promise<string> {
    if (this.isSaving) {
      return '';
    }
    this.isSaving = true;
    try {
      await this.service.setManagedDomainEnabled(accountStore.selectedId, bucket, enabled);
      try {
        this.managed = await this.service.getManagedDomain(accountStore.selectedId, bucket);
      } catch (e) {
      }
      return '';
    } catch (e) {
      return (e as Error).message ?? '操作失败';
    } finally {
      this.isSaving = false;
    }
  }

  async addDomain(bucket: string, domain: string, zoneId: string): Promise<string> {
    if (this.isSaving) {
      return '';
    }
    this.isSaving = true;
    try {
      const created = await this.service.addCustomDomain(accountStore.selectedId, bucket, domain, zoneId);
      this.customDomains = this.customDomains.concat([created]);
      return '';
    } catch (e) {
      return (e as Error).message ?? '添加失败';
    } finally {
      this.isSaving = false;
    }
  }

  async removeDomain(bucket: string, domain: string): Promise<string> {
    try {
      await this.service.removeCustomDomain(accountStore.selectedId, bucket, domain);
      this.customDomains = this.customDomains.filter((d: R2CustomDomain) => d.domain !== domain);
      return '';
    } catch (e) {
      return (e as Error).message ?? '移除失败';
    }
  }

  /// 追加一条 CORS 规则（R2 是整组 PUT，回写现有 + 新规则）
  async addCorsRule(bucket: string, rule: R2CorsRule): Promise<string> {
    if (this.isSaving) {
      return '';
    }
    this.isSaving = true;
    try {
      const next = this.corsRules.concat([rule]);
      const policy: R2CorsPolicy = { rules: next };
      await this.service.putCorsPolicy(accountStore.selectedId, bucket, policy);
      this.corsRules = next;
      return '';
    } catch (e) {
      return (e as Error).message ?? '添加失败';
    } finally {
      this.isSaving = false;
    }
  }

  /// 删单条：剩余整组回写；删空则 DELETE 清除策略（对齐 iOS deleteCorsRule）
  async removeCorsRule(bucket: string, index: number): Promise<string> {
    if (index < 0 || index >= this.corsRules.length) {
      return '';
    }
    const next = this.corsRules.filter((rule: R2CorsRule, i: number) => i !== index);
    try {
      if (next.length === 0) {
        await this.service.deleteCorsPolicy(accountStore.selectedId, bucket);
      } else {
        const policy: R2CorsPolicy = { rules: next };
        await this.service.putCorsPolicy(accountStore.selectedId, bucket, policy);
      }
      this.corsRules = next;
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }

  async clearCors(bucket: string): Promise<string> {
    try {
      await this.service.deleteCorsPolicy(accountStore.selectedId, bucket);
      this.corsRules = [];
      return '';
    } catch (e) {
      return (e as Error).message ?? '清除失败';
    }
  }
}

@ComponentV2
export struct R2SettingsPage {
  @Local vm: SettingsVM = new SettingsVM();
  @Local bucket: string = '';
  @Local showAddDomain: boolean = false;
  @Local fDomain: string = '';
  @Local fZoneId: string = '';
  @Local showAddCors: boolean = false;
  @Local fOrigins: string = '*';
  @Local fMethods: string[] = ['GET'];
  @Local fHeaders: string = '';
  @Local fMaxAge: string = '3600';
  /// R2 SQL 控制台
  @Local showSql: boolean = false;
  @Local sqlText: string = '';

  /// R2 SQL 走独立主机，另需 r2-catalog-sql.read
  private canQuerySql: boolean = authManager.hasScope(Scopes.R2_CATALOG_SQL_READ);
  /// 展示行数上限（查询本身不截断——扫描量在服务端已发生，截断只为渲染）
  private static readonly SQL_MAX_ROWS: number = 500;

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  /// 点按表引用插入到 SQL 文本
  private insertTableRef(ref: string): void {
    if (this.sqlText.trim() === '') {
      this.sqlText = `SELECT * FROM ${ref} LIMIT 100`;
    } else if (this.sqlText.endsWith(' ') || this.sqlText.endsWith('\n')) {
      this.sqlText = `${this.sqlText}${ref}`;
    } else {
      this.sqlText = `${this.sqlText} ${ref}`;
    }
  }

  /// R2 SQL 查询控制台：编辑器 + 表引用芯片 + 计费提示 + 结果表
  @Builder
  sqlSheet() {
    Scroll() {
      Column({ space: 12 }) {
        Text('R2 SQL')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .margin({ top: 8 })

        TextArea({ text: this.sqlText, placeholder: 'SELECT * FROM namespace.table LIMIT 100' })
          .fontSize(13)
          .fontFamily('monospace')
          .height(130)
          .width('100%')
          .onChange((value: string) => {
            this.sqlText = value;
          })

        if (this.vm.sqlTables.length > 0) {
          Scroll() {
            Row({ space: 6 }) {
              ForEach(this.vm.sqlTables, (ref: string) => {
                Text(ref)
                  .fontSize(11)
                  .fontFamily('monospace')
                  .fontColor($r('app.color.oc_brand_text'))
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .backgroundColor('#1FF48120')
                  .borderRadius(10)
                  .onClick(() => {
                    this.insertTableRef(ref);
                  })
              }, (ref: string) => ref)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }

        Text('只读查询（SELECT / EXPLAIN）。按扫描数据量计费：每月前 10 GB 免费，超出 $0.0025/GB，单次查询至少计 10 MB——大表请先加 WHERE / LIMIT。')
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')

        Button(this.vm.sqlRunning ? '正在查询…' : '运行')
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.oc_brand_cta'))
          .enabled(!this.vm.sqlRunning && this.sqlText.trim() !== '')
          .onClick(() => {
            this.vm.runSql(this.bucket, this.sqlText).catch(() => {
            });
          })

        if (this.vm.sqlError !== '') {
          Text(this.vm.sqlError)
            .fontSize(12)
            .fontColor('#DC2626')
            .width('100%')
        }

        if (this.vm.sqlResult !== null) {
          if (this.vm.sqlResult!.rows.length === 0) {
            Text('执行成功，无返回行')
              .fontSize(14)
              .fontColor('#2E7D32')
              .width('100%')
          } else {
            Text(`${this.vm.sqlResult!.rows.length} 行 · ${this.vm.sqlResult!.columns.length} 列`)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
            // 横向滚动 + 每列定宽（同 D1 控制台口径，避免宽表把行挤成一团）
            Scroll() {
              Column({ space: 4 }) {
                Row() {
                  ForEach(this.vm.sqlResult!.columns, (col: string) => {
                    Text(col)
                      .fontSize(11)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('sys.color.font_secondary'))
                      .width(140)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }, (col: string) => col)
                }
                Divider()
                  .strokeWidth(0.5)
                  .color($r('sys.color.comp_divider'))
                ForEach(this.vm.sqlResult!.rows.slice(0, R2SettingsPage.SQL_MAX_ROWS),
                  (row: Record<string, string>, index: number) => {
                    Row() {
                      ForEach(this.vm.sqlResult!.columns, (col: string) => {
                        Text(row[col] ?? '')
                          .fontSize(11)
                          .fontFamily('monospace')
                          .fontColor($r('sys.color.font_primary'))
                          .width(140)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }, (col: string) => col)
                    }
                  }, (row: Record<string, string>, index: number) => `${index}`)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Auto)
            .width('100%')
            if (this.vm.sqlResult!.rows.length > R2SettingsPage.SQL_MAX_ROWS) {
              Text(`仅显示前 ${R2SettingsPage.SQL_MAX_ROWS} 行（共 ${this.vm.sqlResult!.rows.length} 行）`)
                .fontSize(11)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
            }
          }
        }
      }
      .padding({ left: 20, right: 20, bottom: 24 })
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .width('100%')
  }

  /// 写权限门控：无 workers-r2.write 时统一提示
  private guardWrite(): boolean {
    if (authManager.hasScope(Scopes.R2_WRITE)) {
      return true;
    }
    this.toast('当前授权未包含 R2 写权限（workers-r2.write），请重新授权后再试');
    return false;
  }

  private copyText(text: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.toast('已复制');
    }).catch(() => {
      this.toast('复制失败');
    });
  }

  /// r2.dev 开关：开启有安全提示确认；关闭也确认（对外公开状态变更）。
  /// 取消时重载设置，把被用户拨动过的开关拉回真实状态。
  private confirmManagedToggle(on: boolean): void {
    this.getUIContext().showAlertDialog({
      title: on ? '启用公开访问' : '停用公开访问',
      message: on
        ? '启用后，桶内所有对象都可通过 r2.dev 子域被任何人匿名读取。该域仅供开发测试且有速率限制，生产请用自定义域。确定启用？'
        : '停用后 r2.dev 公开地址将立即失效。确定停用？',
      primaryButton: { value: '取消', action: () => {
        this.vm.load(this.bucket).catch(() => {
        });
      } },
      secondaryButton: {
        value: on ? '启用' : '停用',
        fontColor: on ? '#DC2626' : BRAND_ORANGE,
        action: () => {
          this.vm.setManagedEnabled(this.bucket, on).then((err: string) => {
            this.toast(err === '' ? (on ? '已启用公开访问' : '已停用公开访问') : err);
          });
        },
      },
    });
  }

  private confirmRemoveDomain(domain: R2CustomDomain): void {
    this.getUIContext().showAlertDialog({
      title: '移除自定义域',
      message: `确定断开「${domain.domain}」？该域名将不再指向此存储桶。`,
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '移除',
        fontColor: '#DC2626',
        action: () => {
          this.vm.removeDomain(this.bucket, domain.domain).then((err: string) => {
            this.toast(err === '' ? '已移除' : err);
          });
        },
      },
    });
  }

  private confirmRemoveCors(index: number, rule: R2CorsRule): void {
    this.getUIContext().showAlertDialog({
      title: '删除 CORS 规则',
      message: `确定删除「${corsRuleTitle(rule)}」？剩余规则将整组回写。`,
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '删除',
        fontColor: '#DC2626',
        action: () => {
          this.vm.removeCorsRule(this.bucket, index).then((err: string) => {
            this.toast(err === '' ? '已删除' : err);
          });
        },
      },
    });
  }

  private confirmClearCors(): void {
    this.getUIContext().showAlertDialog({
      title: '清除全部 CORS',
      message: '确定清除该桶的全部 CORS 规则？此操作不可撤销。',
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '清除',
        fontColor: '#DC2626',
        action: () => {
          this.vm.clearCors(this.bucket).then((err: string) => {
            this.toast(err === '' ? '已清除' : err);
          });
        },
      },
    });
  }

  private toggleMethod(method: string): void {
    if (this.fMethods.includes(method)) {
      this.fMethods = this.fMethods.filter((m: string) => m !== method);
    } else {
      this.fMethods = this.fMethods.concat([method]);
    }
  }

  /// 提交添加 CORS 规则：origins 每行一个；headers 逗号分隔（可空）；maxAge 数字（可空）
  private submitCorsRule(): void {
    const origins = this.fOrigins.split('\n')
      .map((s: string) => s.trim())
      .filter((s: string) => s !== '');
    if (origins.length === 0 || this.fMethods.length === 0) {
      this.toast('来源与方法不能为空');
      return;
    }
    const headers = this.fHeaders.split(',')
      .map((s: string) => s.trim())
      .filter((s: string) => s !== '');
    const allowed: R2CorsAllowed = {
      methods: CORS_METHODS.filter((m: string) => this.fMethods.includes(m)),
      origins: origins,
    };
    if (headers.length > 0) {
      allowed.headers = headers;
    }
    const rule: R2CorsRule = { allowed: allowed };
    const age = Number.parseInt(this.fMaxAge.trim());
    if (!Number.isNaN(age) && age >= 0) {
      rule.maxAgeSeconds = age;
    }
    this.vm.addCorsRule(this.bucket, rule).then((err: string) => {
      if (err === '') {
        this.showAddCors = false;
        this.toast('已添加');
      } else {
        this.toast(err);
      }
    });
  }

  @Builder
  addDomainSheet() {
    Column({ space: 12 }) {
      Text('添加自定义域')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      Text('域名须属于本账号下已接入 Cloudflare 的 zone，连接后自动下发 DNS 与证书。')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({ text: this.fDomain, placeholder: '域名，如 files.example.com' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fDomain = value;
        })
      if (this.vm.zones.length > 0) {
        Row({ space: 12 }) {
          Text('所属域名')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Blank()
          Select(this.vm.zones.map((z: Zone): SelectOption => ({ value: z.name })))
            .selected(this.vm.zones.findIndex((z: Zone) => z.id === this.fZoneId))
            .value(this.fZoneId === '' ? '选择 zone' :
            (this.vm.zones.find((z: Zone) => z.id === this.fZoneId)?.name ?? '选择 zone'))
            .font({ size: 14 })
            .onSelect((index: number) => {
              if (index >= 0 && index < this.vm.zones.length) {
                this.fZoneId = this.vm.zones[index].id;
              }
            })
        }
        .width('100%')
      }
      TextInput({ text: this.fZoneId, placeholder: '或手动输入 Zone ID' })
        .fontSize(13)
        .width('100%')
        .onChange((value: string) => {
          this.fZoneId = value;
        })
      Button(this.vm.isSaving ? '正在添加…' : '添加')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm.isSaving && this.fDomain.trim() !== '' && this.fZoneId.trim() !== '')
        .onClick(() => {
          this.vm.addDomain(this.bucket, this.fDomain.trim(), this.fZoneId.trim()).then((err: string) => {
            if (err === '') {
              this.showAddDomain = false;
              this.fDomain = '';
              this.toast('已添加，证书签发需要几分钟');
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
  addCorsSheet() {
    Column({ space: 12 }) {
      Text('添加 CORS 规则')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      Text('允许来源（每行一个，* 表示全部）')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextArea({ text: this.fOrigins, placeholder: '*' })
        .fontSize(13)
        .height(72)
        .width('100%')
        .onChange((value: string) => {
          this.fOrigins = value;
        })
      Text('允许方法')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      Row({ space: 8 }) {
        ForEach(CORS_METHODS, (method: string) => {
          Text(method)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.fMethods.includes(method) ? $r('app.color.oc_brand_text') : $r('sys.color.font_primary'))
            .backgroundColor(this.fMethods.includes(method) ? $r('app.color.oc_brand_bg') : $r('sys.color.comp_background_tertiary'))
            .borderRadius(14)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick(() => {
              this.toggleMethod(method);
            })
        }, (method: string) => method)
      }
      .width('100%')
      TextInput({ text: this.fHeaders, placeholder: '允许请求头（逗号分隔，可留空）' })
        .fontSize(13)
        .width('100%')
        .onChange((value: string) => {
          this.fHeaders = value;
        })
      TextInput({ text: this.fMaxAge, placeholder: 'Max-Age（秒），默认 3600' })
        .fontSize(13)
        .width('100%')
        .onChange((value: string) => {
          this.fMaxAge = value;
        })
      Button(this.vm.isSaving ? '正在保存…' : '添加')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm.isSaving && this.fOrigins.trim() !== '' && this.fMethods.length > 0)
        .onClick(() => {
          this.submitCorsRule();
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  /// 启用数据目录是计费动作，先弹确认
  private confirmEnableCatalog(): void {
    promptAction.showDialog({
      title: '启用数据目录',
      message: '启用后该桶将作为 Apache Iceberg 目录，目录操作按量计费（每月含 100 万次免费额度）。目录已启用时手动删除对象会破坏目录。',
      buttons: [{ text: '取消', color: '#666666' }, { text: '启用', color: $r('app.color.oc_brand') }],
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        this.vm.setCatalogEnabled(this.bucket, true).then((err: string) => {
          if (err !== '') {
            promptAction.showToast({ message: err });
          }
        });
      }
    }).catch(() => {
    });
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载桶设置…' })
          }
          .width('100%')
          .height('100%')
        } else {
          Scroll() {
            Column({ space: 4 }) {
              // ---- 公开访问（r2.dev）----
              Column() {
                SectionHeader({ title: '公开开发 URL（r2.dev）' })
                Column() {
                  ToggleRow({
                    title: '启用 r2.dev 公开访问',
                    subtitle: '仅供开发测试，有速率限制',
                    isOn: this.vm.managed?.enabled === true,
                    isEnabled: !this.vm.isSaving,
                    onToggle: (on: boolean) => {
                      if (this.guardWrite()) {
                        this.confirmManagedToggle(on);
                      } else {
                        // 无写权限：重载把开关拉回真实状态
                        this.vm.load(this.bucket).catch(() => {
                        });
                      }
                    },
                  })
                  if (this.vm.managed?.enabled === true && (this.vm.managed?.domain ?? '') !== '') {
                    Divider()
                      .color($r('sys.color.comp_divider'))
                      .margin({ left: 14, right: 14 })
                    Row({ space: 10 }) {
                      Text(`https://${this.vm.managed?.domain ?? ''}`)
                        .fontSize(12)
                        .fontFamily('monospace')
                        .fontColor($r('sys.color.font_primary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                      Text('复制')
                        .fontSize(13)
                        .fontColor($r('app.color.oc_brand_text'))
                        .onClick(() => {
                          this.copyText(`https://${this.vm.managed?.domain ?? ''}`);
                        })
                    }
                    .width('100%')
                    .padding({ left: 14, right: 14, top: 10, bottom: 12 })
                  }
                }
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(14)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .clip(true)
                .margin({ left: 16, right: 16 })
              }
              .width('100%')

              // ---- 自定义域 ----
              Column() {
                Row() {
                  SectionHeader({ title: `自定义域（${this.vm.customDomains.length}）· 长按移除` })
                  Blank()
                  Text('＋添加')
                    .fontSize(13)
                    .fontColor($r('app.color.oc_brand_text'))
                    .padding({ right: 20, top: 16 })
                    .onClick(() => {
                      if (this.guardWrite()) {
                        this.showAddDomain = true;
                      }
                    })
                }
                .width('100%')

                Column() {
                  if (this.vm.customDomains.length === 0) {
                    Text('未连接自定义域')
                      .fontSize(13)
                      .fontColor($r('sys.color.font_secondary'))
                      .width('100%')
                      .padding(14)
                  } else {
                    ForEach(this.vm.customDomains, (domain: R2CustomDomain) => {
                      Column({ space: 3 }) {
                        Text(domain.domain)
                          .fontSize(14)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('sys.color.font_primary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(domainStatusLine(domain))
                          .fontSize(11)
                          .fontColor(domain.enabled === true ? '#22C55E' : $r('sys.color.font_tertiary'))
                      }
                      .alignItems(HorizontalAlign.Start)
                      .width('100%')
                      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                      .gesture(LongPressGesture().onAction(() => {
                        if (this.guardWrite()) {
                          this.confirmRemoveDomain(domain);
                        }
                      }))
                    }, (domain: R2CustomDomain) => domain.domain)
                  }
                }
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(14)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .clip(true)
                .margin({ left: 16, right: 16 })
              }
              .width('100%')

              // ---- 数据目录（Iceberg）----
              if (this.vm.catalogLoaded) {
                Column() {
                  SectionHeader({ title: '数据目录' })
                  Column({ space: 8 }) {
                    ToggleRow({
                      title: '启用数据目录',
                      subtitle: '把这个桶变成可被 Spark、Snowflake 等引擎查询的 Iceberg 数据仓库',
                      isOn: this.vm.catalog?.status === 'active',
                      isEnabled: !this.vm.isSaving,
                      onToggle: (on: boolean) => {
                        if (on) {
                          this.confirmEnableCatalog();
                        } else {
                          this.vm.setCatalogEnabled(this.bucket, false).then((err: string) => {
                            if (err !== '') {
                              promptAction.showToast({ message: err });
                            }
                          });
                        }
                      },
                    })
                    if (this.vm.catalog?.status === 'active') {
                      if ((this.vm.catalog?.name ?? '') !== '') {
                        Text(this.vm.catalog?.name)
                          .fontSize(12)
                          .fontColor($r('sys.color.font_secondary'))
                          .width('100%')
                          .padding({ left: 14, right: 14 })
                      }
                      if (this.vm.catalogNamespaces.length === 0) {
                        Text('暂无命名空间')
                          .fontSize(12)
                          .fontColor($r('sys.color.font_secondary'))
                          .width('100%')
                          .padding({ left: 14, right: 14, bottom: 10 })
                      } else {
                        ForEach(this.vm.catalogNamespaces, (ns: R2CatalogNamespace, index: number) => {
                          Text(namespaceLabel(ns))
                            .fontSize(12)
                            .fontColor($r('sys.color.font_primary'))
                            .width('100%')
                            .padding({ left: 14, right: 14, bottom: 4 })
                        }, (ns: R2CatalogNamespace, index: number) => `${index}`)
                      }
                      // R2 SQL 控制台（2026-08 起计费：$0.0025/GB 扫描、10GB/月免费）
                      if (this.canQuerySql) {
                        Row({ space: 10 }) {
                          SymbolGlyph($r('sys.symbol.code_slash'))
                            .fontSize(17)
                            .fontColor([$r('app.color.oc_brand_text')])
                          Text('R2 SQL 查询')
                            .fontSize(14)
                            .fontColor($r('app.color.oc_brand_text'))
                        }
                        .width('100%')
                        .padding({ left: 14, right: 14, top: 10, bottom: 12 })
                        .onClick(() => {
                          this.showSql = true;
                          this.vm.loadSqlTables(this.bucket).catch(() => {
                          });
                        })
                      }
                    }
                  }
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(14)
                  .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                  .clip(true)
                  .margin({ left: 16, right: 16 })
                }
                .width('100%')
              }

              // ---- CORS ----
              Column() {
                Row() {
                  SectionHeader({ title: `CORS 规则（${this.vm.corsRules.length}）· 长按删除` })
                  Blank()
                  Text('＋添加')
                    .fontSize(13)
                    .fontColor($r('app.color.oc_brand_text'))
                    .padding({ right: 20, top: 16 })
                    .onClick(() => {
                      if (this.guardWrite()) {
                        this.showAddCors = true;
                      }
                    })
                }
                .width('100%')

                Column() {
                  if (this.vm.corsRules.length === 0) {
                    Text('未配置 CORS 规则')
                      .fontSize(13)
                      .fontColor($r('sys.color.font_secondary'))
                      .width('100%')
                      .padding(14)
                  } else {
                    ForEach(this.vm.corsRules, (rule: R2CorsRule, index: number) => {
                      Column({ space: 3 }) {
                        Text(corsRuleTitle(rule))
                          .fontSize(14)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('sys.color.font_primary'))
                          .maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(corsRuleSubtitle(rule))
                          .fontSize(11)
                          .fontColor($r('sys.color.font_secondary'))
                      }
                      .alignItems(HorizontalAlign.Start)
                      .width('100%')
                      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                      .gesture(LongPressGesture().onAction(() => {
                        if (this.guardWrite()) {
                          this.confirmRemoveCors(index, rule);
                        }
                      }))
                    }, (rule: R2CorsRule, index: number) => `cors:${index}:${corsRuleTitle(rule)}`)
                  }
                }
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(14)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .clip(true)
                .margin({ left: 16, right: 16 })

                if (this.vm.corsRules.length > 0) {
                  Text('清除全部 CORS')
                    .fontSize(13)
                    .fontColor('#DC2626')
                    .width('100%')
                    .textAlign(TextAlign.Center)
                    .padding({ top: 12 })
                    .onClick(() => {
                      if (this.guardWrite()) {
                        this.confirmClearCors();
                      }
                    })
                }

                Text('跨域资源共享：允许指定来源的网页脚本访问桶内对象。规则为整组写入。')
                  .fontSize(12)
                  .fontColor($r('sys.color.font_secondary'))
                  .width('100%')
                  .padding({ left: 20, right: 20, top: 10 })
              }
              .width('100%')
              .margin({ bottom: 24 })
            }
            .width('100%')
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
    .titleBar({ content: { title: { mainTitle: `${this.bucket} · 桶设置` } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.showAddDomain, this.addDomainSheet(), ocSheet(() => {
      this.showAddDomain = false;
    }))
    .bindSheet(this.showSql, this.sqlSheet(), ocSheet(() => {
      this.showSql = false;
    }))
    .bindSheet(this.showAddCors, this.addCorsSheet(), ocSheet(() => {
      this.showAddCors = false;
    }))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as IdNameParam;
      this.bucket = param.name;
      this.vm.load(param.name).catch(() => {
      });
    })
  }
}
