import { HdsNavDestination } from '@kit.UIDesignKit';
// D1：数据库列表 + 新建 → SQL 查询控制台（对齐 Android D1Screens）。
import { D1Database, D1QueryResult } from '../../models/StorageModels';
import { Routes, IdNameParam, D1TableParam } from '../../models/Routes';
import { StorageService } from '../../services/StorageService';
import { accountStore } from '../../core/store/AccountStore';
import { authManager } from '../../core/auth/AuthManager';
import { Scopes } from '../../core/auth/Scopes';
import { formatBytes } from '../../core/util/Format';
import { BRAND_ORANGE, BRAND_ORANGE_BG, OCEmpty, OCError, OCLoading, ResourceCard } from '../common/Components';
import { ocSheet, ocSheetCompact } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';
import { D1QueryBook, toCsv } from '../../core/system/D1QueryBook';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';

// ---- D1 大表四层防线（口径逐条对齐 iOS StorageViewModels + D1TableView / D1QueryView）----
// 取数层：TEXT/BLOB 亲和列 substr 截断取数，编辑前按 rowid 再取整行完整值；
// 渲染层：外层横向 Scroll + 内层纵向 List（LazyForEach 懒加载）+ 每列定宽；
// 数量层：表浏览分页 50 行/页、驻留 1000 行封顶；
// 提醒层：SELECT/WITH 无 LIMIT 执行前提醒，控制台结果只驻留前 500 行、展示前 100 行。

const D1_CELL_LIMIT = 256; // 单元格取数/展示截断长度（iOS cellLimit）
const D1_PAGE_SIZE = 50; // 表浏览每页行数（iOS pageSize）
const D1_MAX_LOADED_ROWS = 1000; // 表浏览驻留行数封顶（iOS maxLoadedRows）
const D1_MAX_STORED_ROWS = 500; // 控制台单条语句结果驻留封顶（iOS maxStoredRows）
const D1_MAX_DISPLAY_ROWS = 100; // 控制台结果表展示行数（iOS D1ResultCard.maxRows）
const D1_LARGE_FIELD_LIMIT = 8000; // 行编辑器大字段转只读预览阈值（iOS largeFieldLimit）
const D1_ROWID_KEY = '_oc_rowid_'; // rowid 取数别名，避免与同名真实列冲突（iOS rowidKey）
const D1_COL_MIN_WIDTH = 44; // 列内容最小宽（iOS 44pt）
const D1_COL_MAX_WIDTH = 180; // 列内容最大宽（iOS 180pt）
const D1_CELL_PADDING = 16; // 单元格左右 padding 合计（padding 8 两侧）

/// 单元格展示文本：NULL 显示 NULL、空串显示 ''、超长截 256 字符加省略号（对齐 iOS displayText）
function d1CellDisplay(value: string | undefined): string {
  if (value === undefined || value === null) {
    return 'NULL';
  }
  const text = `${value}`;
  if (text.length > D1_CELL_LIMIT) {
    return `${text.substring(0, D1_CELL_LIMIT)}…`;
  }
  return text === '' ? "''" : text;
}

/// 数值/布尔/时间列值天然短，取原值；TEXT/BLOB/无声明类型才 substr 截断（对齐 iOS isTruncatable）
function d1IsTruncatable(declaredType: string): boolean {
  const t = declaredType.toUpperCase();
  if (t.includes('INT') || t.includes('REAL') || t.includes('FLOA') || t.includes('DOUB')
    || t.includes('DEC') || t.includes('NUM') || t.includes('BOOL') || t.includes('DATE') || t.includes('TIME')) {
    return false;
  }
  return true;
}

/// 估算文本渲染宽度（vp，12fp 等宽字口径）：CJK 按 12、拉丁按 7.2；无系统测量依赖，够列宽用
function d1TextUnits(text: string): number {
  let width: number = 0;
  for (let i = 0; i < text.length; i++) {
    width += text.charCodeAt(i) > 0xFF ? 12 : 7.2;
    if (width >= D1_COL_MAX_WIDTH) {
      return D1_COL_MAX_WIDTH;
    }
  }
  return width;
}

/// 列宽 = 表头与前 50 行采样的估宽取大，夹在 44…180 再加 padding（对齐 iOS computeColumnWidths）
function d1EstimateColWidths(columns: string[], rows: Record<string, string>[]): Record<string, number> {
  const widths: Record<string, number> = {};
  const sample = rows.length < 50 ? rows.length : 50;
  for (const col of columns) {
    let maxWidth = d1TextUnits(col);
    for (let i = 0; i < sample; i++) {
      const w = d1TextUnits(d1CellDisplay(rows[i][col]));
      if (w > maxWidth) {
        maxWidth = w;
      }
      if (maxWidth >= D1_COL_MAX_WIDTH) {
        break;
      }
    }
    let clamped = Math.ceil(maxWidth);
    if (clamped < D1_COL_MIN_WIDTH) {
      clamped = D1_COL_MIN_WIDTH;
    }
    if (clamped > D1_COL_MAX_WIDTH) {
      clamped = D1_COL_MAX_WIDTH;
    }
    widths[col] = clamped + D1_CELL_PADDING;
  }
  return widths;
}

/// LazyForEach 数据源：行数组懒加载渲染（嵌套横向 Scroll 里 List 高度确定时懒加载才生效；
/// 若个别版本退化为全量渲染，也不劣于 ForEach，行为兜底安全）
class D1RowSource implements IDataSource {
  private rows: Record<string, string>[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): Record<string, string> {
    return this.rows[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  /// 整包替换（首页加载/重载）
  reload(rows: Record<string, string>[]): void {
    this.rows = rows.slice();
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  /// 增量追加（翻页）：按条通知，避免整表重建
  append(rows: Record<string, string>[]): void {
    for (const row of rows) {
      this.rows.push(row);
      for (const listener of this.listeners) {
        listener.onDataAdd(this.rows.length - 1);
      }
    }
  }
}

@ObservedV2
class D1ListVM {
  @Trace databases: D1Database[] = [];
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  @Trace isCreating: boolean = false;
  @Trace createError: string = '';
  private service: StorageService = new StorageService();

  // 表数量：详情端点的 num_tables 不可靠（常年 0），改用与表浏览同款 sqlite_master 查询、客户端计数行数。
  private async countTables(acct: string, dbId: string): Promise<number> {
    try {
      const sql =
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%'";
      const res: D1QueryResult[] = await this.service.query(acct, dbId, sql);
      const rows = res.length > 0 ? (res[0].results ?? []) : [];
      return rows.length;
    } catch (e) {
    }
    return 0;
  }

  async load(): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      const list = await this.service.listDatabases(accountStore.selectedId);
      this.databases = list;
      this.isLoading = false;
      const acct = accountStore.selectedId;
      // 1) 并发补 file_size（列表端点常年 0，详情端点给真值）
      const enriched = await Promise.all(list.map(async (db: D1Database): Promise<D1Database> => {
        try {
          return await this.service.getDatabase(acct, db.uuid);
        } catch (e) {
          return db;
        }
      }));
      this.databases = enriched.slice();
      // 2) 串行补表数——并发 D1 查询会丢结果（详情页单查询正常、列表并发全回 0），逐库串行并逐条回填。
      for (let i = 0; i < enriched.length; i++) {
        enriched[i].num_tables = await this.countTables(acct, enriched[i].uuid);
        this.databases = enriched.slice();
      }
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
      await this.service.createDatabase(accountStore.selectedId, name);
      await this.load();
      return true;
    } catch (e) {
      this.createError = (e as Error).message ?? '创建失败';
      return false;
    } finally {
      this.isCreating = false;
    }
  }

  async remove(databaseId: string): Promise<string> {
    try {
      await this.service.deleteDatabase(accountStore.selectedId, databaseId);
      this.databases = this.databases.filter((d: D1Database) => d.uuid !== databaseId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}

@ComponentV2
export struct D1DatabasesPage {
  @Local vm: D1ListVM = new D1ListVM();
  @Local refreshing: boolean = false;
  @Local showCreate: boolean = false;
  @Local fName: string = '';
  // 删库二次确认（严格：须原样输入库名，对齐 iOS D1DeleteConfirmView）
  @Local confirmVisible: boolean = false;
  @Local confirmDb: D1Database | null = null;
  @Local confirmTyped: string = '';
  @Local confirmDeleting: boolean = false;
  private pathStack: NavPathStack | null = null;

  private confirmDelete(db: D1Database): void {
    this.confirmDb = db;
    this.confirmTyped = '';
    this.confirmDeleting = false;
    this.vm.error = '';
    this.confirmVisible = true;
  }

  @Builder
  confirmSheet() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
        .fontSize(48)
        .fontColor(['#DC2626'])
        .margin({ top: 8 })
      Text('永久删除数据库')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
      Text(`此操作将永久删除数据库 ${this.confirmDb?.name ?? ''} 及其全部表和数据，无法撤销，也无法恢复。`)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
        .width('100%')

      Column({ space: 6 }) {
        Text('输入数据库名称以确认')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
        TextInput({ text: this.confirmTyped, placeholder: this.confirmDb?.name ?? '' })
          .fontSize(14)
          .fontFamily('monospace')
          .width('100%')
          .enableKeyboardOnFocus(true)
          .onChange((value: string) => {
            this.confirmTyped = value;
          })
      }
      .margin({ top: 4 })

      if (this.vm.error !== '') {
        Text(this.vm.error)
          .fontSize(13)
          .fontColor('#DC2626')
          .width('100%')
      }

      Button(this.confirmDeleting ? '正在删除…' : '永久删除')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .backgroundColor('#DC2626')
        .enabled(!this.confirmDeleting && this.confirmTyped.trim() === (this.confirmDb?.name ?? ' '))
        .onClick(() => {
          const db = this.confirmDb;
          if (!db) {
            return;
          }
          this.confirmDeleting = true;
          this.vm.remove(db.uuid).then((err: string) => {
            this.confirmDeleting = false;
            if (err === '') {
              this.confirmVisible = false;
              this.getUIContext().getPromptAction().showToast({ message: '已删除' });
            } else {
              this.getUIContext().getPromptAction().showToast({ message: err });
            }
          });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  @Builder
  createSheet() {
    Column({ space: 12 }) {
      Text('新建 D1 数据库')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      TextInput({ text: this.fName, placeholder: '数据库名' })
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
        .backgroundColor($r('app.color.oc_brand_cta'))
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
    HdsNavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        OCSkyBackground()
        if (this.vm.isLoading && this.vm.databases.length === 0) {
          Column() {
            OCLoading({ text: '正在加载数据库…' })
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
        } else if (this.vm.databases.length === 0) {
          Column() {
            OCEmpty({ symbol: $r('sys.symbol.square_stack_3d'), title: '暂无 D1 数据库', subtitle: '点右下角 + 创建' })
          }
          .width('100%')
          .height('100%')
        } else {
          Refresh({ refreshing: this.refreshing }) {
            List() {
              ForEach(this.vm.databases, (db: D1Database) => {
                ListItem() {
                  ResourceCard({
                    symbol: $r('sys.symbol.square_stack_3d'),
                    title: db.name,
                    subtitle: `${db.num_tables ?? 0} 张表 · ${formatBytes(db.file_size ?? 0)}`,
                    onTap: () => {
                      const param: IdNameParam = { id: db.uuid, name: db.name };
                      this.pathStack?.pushPathByName(Routes.D1_QUERY, param);
                    },
                    onLongPress: () => {
                      this.confirmDelete(db);
                    },
                  })
                }
                .margin({ left: 16, right: 16, top: 5, bottom: 5 })
                // key 含 num_tables/file_size：仅 uuid 时，异步补全的表数/体积变化不触发 ForEach 重渲染。
              }, (db: D1Database) => `${db.uuid}-${db.num_tables ?? -1}-${db.file_size ?? -1}`)
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
          .backgroundColor($r('app.color.oc_brand_cta'))
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
    .titleBar({ content: { title: { mainTitle: 'D1 数据库' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.showCreate, this.createSheet(), ocSheet(() => {
      this.showCreate = false;
    }))
    .bindSheet(this.confirmVisible, this.confirmSheet(), ocSheetCompact(() => {
      this.confirmVisible = false;
    }))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.vm.load().catch(() => {
      });
    })
  }
}

@ObservedV2
class D1QueryVM {
  @Trace columns: string[] = [];
  @Trace rows: Record<string, string>[] = [];
  @Trace running: boolean = false;
  @Trace error: string = '';
  @Trace info: string = '';
  @Trace tables: string[] = [];
  // 截断驻留前的原始行数（数量层提示用）
  @Trace originalRowCount: number = 0;
  // 各列定宽（首包采样估算一次）
  @Trace colWidths: Record<string, number> = {};
  private service: StorageService = new StorageService();

  /// 用户表清单（排除 sqlite_ / _cf_ 内建表）
  async loadTables(dbId: string): Promise<void> {
    try {
      const sql =
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' ORDER BY name";
      const results: D1QueryResult[] = await this.service.query(accountStore.selectedId, dbId, sql);
      const first = results.length > 0 ? results[0] : undefined;
      const rows = first?.results ?? [];
      const names: string[] = [];
      for (const row of rows) {
        const value = row['name'];
        if (value !== undefined && value !== null) {
          names.push(`${value}`);
        }
      }
      this.tables = names;
    } catch (e) {
      this.tables = [];
    }
  }

  cell(row: Record<string, string>, col: string): string {
    // 展示层截断：控制台是任意 SQL、无法在取数层 substr，超长单元格截 256 字符（对齐 iOS cellDisplay）
    return d1CellDisplay(row[col]);
  }

  colWidth(col: string): number {
    return this.colWidths[col] ?? 120;
  }

  /// 展示行封顶：结果表只渲染前 100 行（驻留另按 500 封顶，对齐 iOS D1ResultCard.maxRows）
  displayRows(): Record<string, string>[] {
    if (this.rows.length > D1_MAX_DISPLAY_ROWS) {
      return this.rows.slice(0, D1_MAX_DISPLAY_ROWS);
    }
    return this.rows;
  }

  /// 提醒层：SELECT / WITH 且不带 LIMIT，执行前提醒可能返回大量行（对齐 iOS needsLimitReminder）
  needsLimitReminder(sql: string): boolean {
    const statement = sql.trim().toLowerCase();
    if (!statement.startsWith('select') && !statement.startsWith('with')) {
      return false;
    }
    return statement.search(/\blimit\b/) < 0;
  }

  /// 导出当前结果集为 CSV：只导已驻留的行（不为导出再发一次无上限查询）。
  /// 返回 ''=成功、'cancel'=用户取消、其它=错误信息。
  async exportCsv(dbName: string): Promise<string> {
    if (this.rows.length === 0) {
      return '没有可导出的结果';
    }
    let fd = -1;
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [`${dbName}-query.csv`];
      const documentPicker = new picker.DocumentViewPicker();
      const uris = await documentPicker.save(options);
      if (!uris || uris.length === 0) {
        return 'cancel';
      }
      const text = toCsv(this.columns, this.rows);
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fd = file.fd;
      fileIo.writeSync(fd, text);
      return '';
    } catch (e) {
      return (e as Error).message ?? '导出失败';
    } finally {
      if (fd >= 0) {
        try {
          fileIo.closeSync(fd);
        } catch (e) {
        }
      }
    }
  }

  async run(dbId: string, sql: string): Promise<void> {
    this.running = true;
    this.error = '';
    this.info = '';
    try {
      const results: D1QueryResult[] = await this.service.query(accountStore.selectedId, dbId, sql);
      const first = results.length > 0 ? results[0] : undefined;
      const rows = first?.results ?? [];
      // 数量层：大结果集整包驻留内存是 hang / 内存告警源头，只保留前 500 行，原始行数留作提示
      this.originalRowCount = rows.length;
      this.rows = rows.length > D1_MAX_STORED_ROWS ? rows.slice(0, D1_MAX_STORED_ROWS) : rows;
      this.columns = this.rows.length > 0 ? Object.keys(this.rows[0]) : [];
      this.colWidths = d1EstimateColWidths(this.columns, this.rows);
      const meta = first?.meta;
      if (meta) {
        this.info =
          `${this.originalRowCount} 行 · 读 ${meta.rows_read ?? 0} · 写 ${meta.rows_written ?? 0} · ${meta.duration ?? 0}ms`;
      } else {
        this.info = `${this.originalRowCount} 行`;
      }
    } catch (e) {
      this.error = (e as Error).message ?? '查询失败';
    } finally {
      this.running = false;
    }
  }
}

@ComponentV2
export struct D1QueryPage {
  @Local vm: D1QueryVM = new D1QueryVM();
  @Local dbId: string = '';
  @Local dbName: string = '';
  @Local sql: string = 'SELECT name FROM sqlite_master WHERE type=\'table\';';
  /// 最近执行 / 收藏（按数据库分键落盘，对照 iOS D1QueryHistoryStore）
  @Local book: D1QueryBook = new D1QueryBook();
  private pathStack: NavPathStack | null = null;

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  /// 执行并在成功后入历史（失败语句不回填）
  private execute(): void {
    const statement = this.sql.trim();
    this.vm.run(this.dbId, statement).then(() => {
      if (this.vm.error === '') {
        this.book.record(statement).catch(() => {
        });
      }
    }).catch(() => {
    });
  }

  /// 最近 / 收藏芯片条：点按回填到编辑器
  @Builder
  sqlChips(title: string, items: string[], starred: boolean) {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        SymbolGlyph(starred ? $r('sys.symbol.star_fill') : $r('sys.symbol.clock'))
          .fontSize(13)
          .fontColor([starred ? BRAND_ORANGE : $r('sys.color.font_tertiary')])
        Text(title)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      Scroll() {
        Row({ space: 6 }) {
          ForEach(items, (item: string) => {
            Text(item)
              .fontSize(11)
              .fontFamily('monospace')
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 240 })
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor($r('sys.color.comp_background_tertiary'))
              .borderRadius(10)
              .onClick(() => {
                this.sql = item;
              })
          }, (item: string) => item)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  tableList() {
    Column() {
      Text('表')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 6 })
      Column() {
        ForEach(this.vm.tables, (table: string, index: number) => {
          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.list_bullet'))
              .fontSize(18)
              .fontColor([$r('app.color.oc_brand_text')])
            Text(table)
              .fontSize(14)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Image($r('sys.media.ohos_ic_public_arrow_right'))
              .width(14)
              .height(14)
              .fillColor($r('sys.color.font_tertiary'))
          }
          .width('100%')
          .padding({ left: 16, right: 12, top: 11, bottom: 11 })
          .onClick(() => {
            const param: D1TableParam = { dbId: this.dbId, dbName: this.dbName, table: table };
            this.pathStack?.pushPathByName(Routes.D1_TABLE, param);
          })
          if (index < this.vm.tables.length - 1) {
            Divider()
              .strokeWidth(0.5)
              .color($r('sys.color.comp_divider'))
              .margin({ left: 46 })
          }
        }, (table: string) => table)
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_list_card'))
      .borderRadius(12)
      .border({ width: 0.5, color: $r('sys.color.comp_divider') })
      .clip(true)
    }
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        Column({ space: 10 }) {
          if (this.vm.tables.length > 0) {
            this.tableList()
          }
          if (this.book.favorites.length > 0) {
            this.sqlChips('收藏', this.book.favorites, true)
          }
          if (this.book.history.length > 0) {
            this.sqlChips('最近', this.book.history, false)
          }

          TextArea({ text: this.sql, placeholder: '输入 SQL' })
            .fontSize(13)
            .fontFamily('monospace')
            .height(100)
            .width('100%')
            .onChange((value: string) => {
              this.sql = value;
            })

          Row({ space: 16 }) {
            Row({ space: 5 }) {
              SymbolGlyph(this.book.isFavorite(this.sql) ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
                .fontSize(15)
                .fontColor([this.book.isFavorite(this.sql) ? BRAND_ORANGE : $r('sys.color.font_tertiary')])
              Text(this.book.isFavorite(this.sql) ? '取消收藏' : '收藏此 SQL')
                .fontSize(12)
                .fontColor($r('sys.color.font_secondary'))
            }
            .onClick(() => {
              this.book.toggleFavorite(this.sql).then((nowFav: boolean) => {
                this.toast(nowFav ? '已收藏' : '已取消收藏');
              }).catch(() => {
              });
            })
            Blank()
            if (this.vm.rows.length > 0) {
              Row({ space: 5 }) {
                SymbolGlyph($r('sys.symbol.arrow_up_circle'))
                  .fontSize(15)
                  .fontColor([$r('app.color.oc_brand_text')])
                Text('导出 CSV')
                  .fontSize(12)
                  .fontColor($r('app.color.oc_brand_text'))
              }
              .onClick(() => {
                this.vm.exportCsv(this.dbName).then((err: string) => {
                  if (err === '') {
                    this.toast('已导出');
                  } else if (err !== 'cancel') {
                    this.toast(err);
                  }
                });
              })
            }
          }
          .width('100%')

          Button(this.vm.running ? '执行中…' : '执行')
            .width('100%')
            .height(42)
            .fontSize(15)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.oc_brand_cta'))
            .enabled(!this.vm.running && this.sql.trim() !== '')
            .onClick(() => {
              // 提醒层：不带 LIMIT 的 SELECT 在大表上会整包返回，先提醒、确认后再执行
              if (this.vm.needsLimitReminder(this.sql)) {
                this.getUIContext().showAlertDialog({
                  title: '查询未带 LIMIT',
                  message: '大表可能返回大量行，造成等待和内存占用。建议加 LIMIT 后执行。',
                  autoCancel: true,
                  primaryButton: {
                    value: '取消',
                    action: () => {
                    },
                  },
                  secondaryButton: {
                    value: '仍要执行',
                    fontColor: BRAND_ORANGE,
                    action: () => {
                      this.execute();
                    },
                  },
                });
              } else {
                this.execute();
              }
            })

          if (this.vm.info !== '') {
            Text(this.vm.info)
              .fontSize(11)
              .fontColor($r('sys.color.font_tertiary'))
              .width('100%')
          }
          if (this.vm.originalRowCount > D1_MAX_DISPLAY_ROWS) {
            Text(`仅显示前 ${D1_MAX_DISPLAY_ROWS} 行（共 ${this.vm.originalRowCount} 行）`)
              .fontSize(11)
              .fontColor($r('sys.color.font_tertiary'))
              .width('100%')
          }
          if (this.vm.error !== '') {
            Text(this.vm.error)
              .fontSize(13)
              .fontColor('#DC2626')
              .width('100%')
          }

          if (this.vm.rows.length > 0) {
            // 渲染层：外层纵向 + 内层横向双轴滚动，每列定宽（展示已封顶 100 行，Column 体量有界）
            Scroll() {
              Scroll() {
                Column() {
                  // 表头
                  Row() {
                    ForEach(this.vm.columns, (col: string) => {
                      Text(col)
                        .fontSize(12)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('sys.color.font_primary'))
                        .width(this.vm.colWidth(col))
                        .padding(8)
                        .backgroundColor($r('sys.color.comp_background_tertiary'))
                    }, (col: string) => col)
                  }

                  ForEach(this.vm.displayRows(), (row: Record<string, string>, index: number) => {
                    Row() {
                      ForEach(this.vm.columns, (col: string) => {
                        Text(this.vm.cell(row, col))
                          .fontSize(12)
                          .fontColor($r('sys.color.font_secondary'))
                          .width(this.vm.colWidth(col))
                          .padding(8)
                          .maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }, (col: string) => col)
                    }
                    .border({ width: { top: 0.5 }, color: $r('sys.color.comp_divider') })
                  }, (row: Record<string, string>, index: number) => `${index}`)
                }
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
            }
            .align(Alignment.Top)
            .scrollBar(BarState.Off)
            .layoutWeight(1)
            .width('100%')
          }
        }
        .padding(16)
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({ content: { title: { mainTitle: `${this.dbName} · 查询` } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as IdNameParam;
      this.dbId = param.id;
      this.dbName = param.name;
      this.vm.loadTables(this.dbId).catch(() => {
      });
      this.book.loadFor(this.dbId).catch(() => {
      });
    })
  }
}

@ObservedV2
class D1TableVM {
  @Trace columns: string[] = [];
  @Trace schema: Record<string, string>[] = [];
  @Trace rowCount: number = 0;
  @Trace hasMore: boolean = false;
  @Trace reachedCap: boolean = false;
  @Trace isLoading: boolean = false;
  @Trace isLoadingMore: boolean = false;
  @Trace error: string = '';
  @Trace saving: boolean = false;
  @Trace saveError: string = '';
  // 各列定宽（首页采样估算一次，懒加载行直接用定宽保证列对齐）
  @Trace colWidths: Record<string, number> = {};
  @Trace totalWidth: number = 0;
  // 索引清单（PRAGMA index_list，只读补充信息，对齐 iOS indexCard）
  @Trace indexes: Record<string, string>[] = [];
  // 行数据走 LazyForEach 数据源（非 @Trace：更新经 listener 通知，避免大数组整体观测开销）
  rowSource: D1RowSource = new D1RowSource();
  private rows: Record<string, string>[] = [];
  private offset: number = 0;
  private service: StorageService = new StorageService();

  cell(row: Record<string, string>, col: string): string {
    return d1CellDisplay(row[col]);
  }

  colWidth(col: string): number {
    return this.colWidths[col] ?? 120;
  }

  /// 可编辑列（columns 来自 PRAGMA，天然不含 rowid 别名列）
  editableColumns(): string[] {
    return this.columns.filter((c: string) => c !== D1_ROWID_KEY);
  }

  /// 列声明类型（供取数层判断是否 substr 截断）
  private declaredType(col: string): string {
    for (const s of this.schema) {
      if (`${s['name']}` === col) {
        return `${s['type'] ?? ''}`;
      }
    }
    return '';
  }

  /// 标识符（表名/列名）双引号转义
  private quoteIdent(ident: string): string {
    return `"${ident.replace(/"/g, '""')}"`;
  }

  /// 取数层：分页查询的列投影。TEXT/BLOB 亲和列只取前 cellLimit+1 个字符（+1 用于判断
  /// 原值是否更长），数值/时间列取原值；完整值在行编辑时按 rowid 单独取（对齐 iOS projection）。
  private projection(): string {
    if (this.columns.length === 0) {
      return '*';
    }
    const parts: string[] = [];
    for (const col of this.columns) {
      const q = this.quoteIdent(col);
      if (d1IsTruncatable(this.declaredType(col))) {
        parts.push(`substr(${q}, 1, ${D1_CELL_LIMIT + 1}) AS ${q}`);
      } else {
        parts.push(q);
      }
    }
    return parts.join(', ');
  }

  /// 取一页：多取 1 行用于判断是否还有下一页（对齐 iOS fetchPage）
  private async fetchPage(dbId: string, table: string, offset: number): Promise<Record<string, string>[]> {
    const sql = `SELECT rowid AS ${D1_ROWID_KEY}, ${this.projection()} FROM ${this.quoteIdent(table)}` +
      ` LIMIT ${D1_PAGE_SIZE + 1} OFFSET ${offset}`;
    const results: D1QueryResult[] = await this.service.query(accountStore.selectedId, dbId, sql);
    const first = results.length > 0 ? results[0] : undefined;
    const page = (first?.results ?? []).slice();
    this.hasMore = page.length > D1_PAGE_SIZE;
    if (this.hasMore) {
      page.pop();
    }
    return page;
  }

  private syncCounters(): void {
    this.rowCount = this.rows.length;
    this.reachedCap = this.rows.length >= D1_MAX_LOADED_ROWS;
  }

  async load(dbId: string, table: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      // 列信息（PRAGMA table_info）：列序/声明类型以 schema 为准
      const infoResults: D1QueryResult[] =
        await this.service.query(accountStore.selectedId, dbId, `PRAGMA table_info(${this.quoteIdent(table)})`);
      const infoFirst = infoResults.length > 0 ? infoResults[0] : undefined;
      this.schema = infoFirst?.results ?? [];
      const names: string[] = [];
      for (const s of this.schema) {
        const name = s['name'];
        if (name !== undefined && name !== null && `${name}` !== '') {
          names.push(`${name}`);
        }
      }
      this.columns = names;

      // 首页 50 行（数量层：分页拉取，驻留 1000 行封顶）
      this.offset = 0;
      this.rows = await this.fetchPage(dbId, table, 0);
      // schema 取不到时兜底：从首行键名推列（去掉 rowid 别名）
      if (this.columns.length === 0 && this.rows.length > 0) {
        this.columns = Object.keys(this.rows[0]).filter((c: string) => c !== D1_ROWID_KEY);
      }
      this.rowSource.reload(this.rows);
      this.syncCounters();
      // 索引：读失败不影响表浏览（老库 / 权限受限时静默留空）
      try {
        const idxResults: D1QueryResult[] =
          await this.service.query(accountStore.selectedId, dbId, `PRAGMA index_list(${this.quoteIdent(table)})`);
        const idxFirst = idxResults.length > 0 ? idxResults[0] : undefined;
        this.indexes = idxFirst?.results ?? [];
      } catch (e) {
        this.indexes = [];
      }
      // 渲染层：列宽首页采样一次算定
      this.colWidths = d1EstimateColWidths(this.columns, this.rows);
      let total: number = 0;
      for (const col of this.columns) {
        total += this.colWidths[col] ?? 120;
      }
      this.totalWidth = total;
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  /// 翻页追加：先取下一页、成功后再推进 offset（瞬时失败不永久跳页，对齐 iOS loadMore）
  async loadMore(dbId: string, table: string): Promise<void> {
    if (!this.hasMore || this.isLoading || this.isLoadingMore || this.reachedCap) {
      return;
    }
    this.isLoadingMore = true;
    try {
      const next = await this.fetchPage(dbId, table, this.offset + D1_PAGE_SIZE);
      this.offset += D1_PAGE_SIZE;
      for (const row of next) {
        this.rows.push(row);
      }
      this.rowSource.append(next);
      this.syncCounters();
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoadingMore = false;
    }
  }

  /// 取数层（回程）：行编辑前按 rowid 取整行完整值——列表里大字段是 substr 截断的，
  /// 直接编辑保存会把截断值写回。无截断单元格直接复用当前行，免一次网络往返（对齐 iOS fullRow）。
  async fullRow(dbId: string, table: string, row: Record<string, string>): Promise<Record<string, string> | null> {
    let hasTruncated = false;
    for (const key of Object.keys(row)) {
      const value = row[key];
      if (value !== undefined && value !== null && `${value}`.length > D1_CELL_LIMIT) {
        hasTruncated = true;
        break;
      }
    }
    const rowid = row[D1_ROWID_KEY];
    if (!hasTruncated || rowid === undefined || rowid === null || `${rowid}` === '') {
      return row;
    }
    try {
      const results: D1QueryResult[] = await this.service.query(accountStore.selectedId, dbId,
        `SELECT rowid AS ${D1_ROWID_KEY}, * FROM ${this.quoteIdent(table)} WHERE rowid = ?`, [`${rowid}`]);
      const first = results.length > 0 ? results[0] : undefined;
      const fullRows = first?.results ?? [];
      return fullRows.length > 0 ? fullRows[0] : row;
    } catch (e) {
      this.saveError = (e as Error).message ?? '读取整行失败';
      return null;
    }
  }

  /// 保存一行编辑：按 rowid 定位 UPDATE，只写变更列，值走参数化绑定（对齐 iOS updateRow）。成功后重载。
  async saveRow(dbId: string, table: string, rowid: string, changes: Record<string, string>): Promise<boolean> {
    if (rowid === '' || rowid === undefined) {
      this.saveError = '缺少 rowid，无法定位该行';
      return false;
    }
    this.saving = true;
    this.saveError = '';
    try {
      const cols = Object.keys(changes);
      if (cols.length === 0) {
        this.saving = false;
        return true;
      }
      const assignments: string[] = [];
      const params: string[] = [];
      for (const col of cols) {
        assignments.push(`${this.quoteIdent(col)} = ?`);
        params.push(changes[col]);
      }
      params.push(rowid);
      const sql = `UPDATE ${this.quoteIdent(table)} SET ${assignments.join(', ')} WHERE rowid = ?`;
      await this.service.query(accountStore.selectedId, dbId, sql, params);
      await this.load(dbId, table);
      return true;
    } catch (e) {
      this.saveError = (e as Error).message ?? '保存失败';
      return false;
    } finally {
      this.saving = false;
    }
  }

  /// DROP TABLE
  async dropTable(dbId: string, table: string): Promise<string> {
    try {
      await this.service.query(accountStore.selectedId, dbId, `DROP TABLE ${this.quoteIdent(table)}`);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}

@ComponentV2
export struct D1TablePage {
  @Local vm: D1TableVM = new D1TableVM();
  @Local dbId: string = '';
  @Local dbName: string = '';
  @Local table: string = '';
  @Local editVisible: boolean = false;
  @Local editRowid: string = '';
  @Local editFields: Record<string, string> = {};
  // 变更判定基线：打开编辑器时各列完整原值（NULL 列记 wasNull，留空保持 NULL）
  @Local editOriginals: Record<string, string> = {};
  @Local editWasNull: Record<string, boolean> = {};
  @Local editLoading: boolean = false;
  // 删表二次确认（严格：须原样输入表名）
  @Local dropVisible: boolean = false;
  @Local dropTyped: string = '';
  @Local dropping: boolean = false;
  private pathStack: NavPathStack | null = null;

  private get canWrite(): boolean {
    return authManager.hasScope(Scopes.D1_WRITE);
  }

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  /// 打开行编辑：列表里大字段是截断取数的，先按 rowid 取整行完整值，
  /// 再预填各列（NULL → 空串并记 wasNull），保存只提交变更列。
  private openEditor(row: Record<string, string>): void {
    if (!this.canWrite) {
      this.toast('当前授权未包含 D1 写权限（d1.write）');
      return;
    }
    const rowidVal = row[D1_ROWID_KEY];
    if (rowidVal === undefined || rowidVal === null) {
      this.toast('该行缺少 rowid，无法编辑');
      return;
    }
    if (this.editLoading) {
      return;
    }
    this.editLoading = true;
    this.vm.fullRow(this.dbId, this.table, row).then((full: Record<string, string> | null) => {
      this.editLoading = false;
      if (full === null) {
        this.toast(this.vm.saveError !== '' ? this.vm.saveError : '读取整行失败');
        return;
      }
      this.editRowid = `${rowidVal}`;
      const fields: Record<string, string> = {};
      const originals: Record<string, string> = {};
      const wasNull: Record<string, boolean> = {};
      for (const col of this.vm.editableColumns()) {
        const v = full[col];
        const isNull = v === undefined || v === null;
        wasNull[col] = isNull;
        const text = isNull ? '' : `${v}`;
        fields[col] = text;
        originals[col] = text;
      }
      this.editFields = fields;
      this.editOriginals = originals;
      this.editWasNull = wasNull;
      this.vm.saveError = '';
      this.editVisible = true;
    }).catch(() => {
      this.editLoading = false;
    });
  }

  /// 仅变更的列（原值为 NULL 且输入仍为空 → 视为未变更，对齐 iOS changes）
  private changedFields(): Record<string, string> {
    const result: Record<string, string> = {};
    for (const col of this.vm.editableColumns()) {
      const current = this.editFields[col] ?? '';
      if (this.editWasNull[col] === true) {
        if (current !== '') {
          result[col] = current;
        }
      } else if (current !== (this.editOriginals[col] ?? '')) {
        result[col] = current;
      }
    }
    return result;
  }

  private confirmDropTable(): void {
    if (!this.canWrite) {
      this.toast('当前授权未包含 D1 写权限（d1.write）');
      return;
    }
    this.dropTyped = '';
    this.dropping = false;
    this.vm.saveError = '';
    this.dropVisible = true;
  }

  @Builder
  dropSheet() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
        .fontSize(48)
        .fontColor(['#DC2626'])
        .margin({ top: 8 })
      Text('永久删除表')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
      Text(`此操作将永久删除表 ${this.table} 及其全部数据，无法撤销，也无法恢复。`)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
        .width('100%')

      Column({ space: 6 }) {
        Text('输入表名称以确认')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
        TextInput({ text: this.dropTyped, placeholder: this.table })
          .fontSize(14)
          .fontFamily('monospace')
          .width('100%')
          .enableKeyboardOnFocus(true)
          .onChange((value: string) => {
            this.dropTyped = value;
          })
      }
      .margin({ top: 4 })

      if (this.vm.saveError !== '') {
        Text(this.vm.saveError)
          .fontSize(13)
          .fontColor('#DC2626')
          .width('100%')
      }

      Button(this.dropping ? '正在删除…' : '永久删除表')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .backgroundColor('#DC2626')
        .enabled(!this.dropping && this.dropTyped.trim() === this.table)
        .onClick(() => {
          this.dropping = true;
          this.vm.dropTable(this.dbId, this.table).then((err: string) => {
            this.dropping = false;
            if (err === '') {
              this.dropVisible = false;
              this.toast('已删除表');
              this.pathStack?.pop();
            } else {
              this.vm.saveError = err;
            }
          });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  @Builder
  editSheet() {
    Column({ space: 12 }) {
      Text('编辑行')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      Text(`rowid ${this.editRowid}`)
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
      Text('只会提交修改过的列。原值为 NULL 的列留空则保持 NULL。')
        .fontSize(11)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')

      Scroll() {
        Column({ space: 12 }) {
          ForEach(this.vm.editableColumns(), (col: string) => {
            Column({ space: 4 }) {
              Row({ space: 6 }) {
                Text(col)
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_secondary'))
                Text(this.colType(col))
                  .fontSize(10)
                  .fontColor($r('sys.color.font_tertiary'))
              }
              .width('100%')

              if ((this.editFields[col] ?? '').length > D1_LARGE_FIELD_LIMIT) {
                // 大字段转只读预览：TextInput 排超大文本会卡主线程，改值走查询控制台（对齐 iOS largeFieldLimit）
                Column({ space: 4 }) {
                  Text(`${(this.editFields[col] ?? '').substring(0, 300)}…`)
                    .fontSize(12)
                    .fontFamily('monospace')
                    .fontColor($r('sys.color.font_secondary'))
                    .maxLines(4)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(`字段过大（${(this.editFields[col] ?? '').length} 字符），请在查询控制台修改`)
                    .fontSize(10)
                    .fontColor($r('sys.color.font_tertiary'))
                    .width('100%')
                }
                .width('100%')
                .padding(8)
                .backgroundColor($r('sys.color.comp_background_tertiary'))
                .borderRadius(8)
              } else if (this.colKind(col) === 'bool') {
                // 布尔：开关
                Row() {
                  Text(this.boolOn(col) ? 'true (1)' : 'false (0)')
                    .fontSize(14)
                    .fontColor($r('sys.color.font_primary'))
                  Blank()
                  Toggle({ type: ToggleType.Switch, isOn: this.boolOn(col) })
                    .selectedColor($r('app.color.oc_brand'))
                    .onChange((on: boolean) => {
                      this.setField(col, on ? '1' : '0');
                    })
                }
                .width('100%')
                .padding({ left: 4, right: 4 })
              } else if (this.colKind(col) === 'date') {
                // 时间戳：日期选择器
                Row({ space: 8 }) {
                  Text((this.editFields[col] ?? '') === '' ? '未设置' : (this.editFields[col] ?? ''))
                    .fontSize(14)
                    .fontFamily('monospace')
                    .fontColor($r('sys.color.font_primary'))
                    .layoutWeight(1)
                  Text('选择日期')
                    .fontSize(13)
                    .fontColor($r('app.color.oc_brand_text'))
                    .onClick(() => {
                      this.pickDate(col);
                    })
                }
                .width('100%')
                .padding({ top: 8, bottom: 8, left: 4, right: 4 })
                .backgroundColor($r('sys.color.comp_background_tertiary'))
                .borderRadius(8)
              } else {
                TextInput({ text: this.editFields[col] ?? '', placeholder: 'NULL / 空则存空串' })
                  .fontSize(14)
                  .fontFamily('monospace')
                  .type(this.colKind(col) === 'number' ? InputType.NUMBER_DECIMAL : InputType.Normal)
                  .width('100%')
                  .onChange((value: string) => {
                    // 走 setField 整体重赋：@Local 只观测重赋，保存按钮的变更判定才会随输入刷新
                    this.setField(col, value);
                  })
              }
            }
            .width('100%')
          }, (col: string) => col)
        }
        .width('100%')
        .padding({ bottom: 8 })
      }
      .align(Alignment.Top)
      .layoutWeight(1)
      .width('100%')

      if (this.vm.saveError !== '') {
        Text(this.vm.saveError)
          .fontSize(13)
          .fontColor('#DC2626')
          .width('100%')
      }

      Button(this.vm.saving ? '保存中…' : '保存')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm.saving && Object.keys(this.changedFields()).length > 0)
        .onClick(() => {
          this.vm.saveRow(this.dbId, this.table, this.editRowid, this.changedFields()).then((ok: boolean) => {
            if (ok) {
              this.editVisible = false;
              this.toast('已保存');
            }
          });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
    .height('100%')
  }

  /// 列的声明类型（大写）
  private colType(col: string): string {
    for (const s of this.vm.schema) {
      if (`${s['name']}` === col) {
        return `${s['type'] ?? ''}`.toUpperCase();
      }
    }
    return '';
  }

  /// 按声明类型判定输入控件：bool→开关，date→日期选择，number→数字键盘，其余→文本
  private colKind(col: string): string {
    const t = this.colType(col);
    if (t.includes('BOOL')) {
      return 'bool';
    }
    if (t.includes('DATE') || t.includes('TIME')) {
      return 'date';
    }
    if (t.includes('INT') || t.includes('REAL') || t.includes('NUM') || t.includes('FLOA')
      || t.includes('DOUB') || t.includes('DEC')) {
      return 'number';
    }
    return 'text';
  }

  /// 改字段：整体重赋新对象，触发 @Local 重渲染（开关/日期显示才会更新）
  private setField(col: string, value: string): void {
    const next: Record<string, string> = {};
    for (const k of Object.keys(this.editFields)) {
      next[k] = this.editFields[k];
    }
    next[col] = value;
    this.editFields = next;
  }

  /// bool 列当前是否为真（1 / true / yes）
  private boolOn(col: string): boolean {
    const v = (this.editFields[col] ?? '').trim().toLowerCase();
    return v === '1' || v === 'true' || v === 'yes' || v === 't';
  }

  /// 把当前字段值解析成 Date（供日期选择器初值）；解析失败用今天
  private fieldDate(col: string): Date {
    const raw = (this.editFields[col] ?? '').trim();
    if (raw !== '') {
      // 纯数字视作 epoch（<1e12 为秒）
      if (/^-?\d+$/.test(raw)) {
        const n = Number.parseInt(raw);
        const ms = raw.length <= 11 ? n * 1000 : n;
        const d = new Date(ms);
        if (!Number.isNaN(d.getTime())) {
          return d;
        }
      } else {
        const d = new Date(raw);
        if (!Number.isNaN(d.getTime())) {
          return d;
        }
      }
    }
    return new Date();
  }

  private ymd(d: Date): string {
    const m = d.getMonth() + 1;
    const day = d.getDate();
    return `${d.getFullYear()}-${m < 10 ? '0' : ''}${m}-${day < 10 ? '0' : ''}${day}`;
  }

  private pickDate(col: string): void {
    DatePickerDialog.show({
      start: new Date('1970-01-01'),
      end: new Date('2100-12-31'),
      selected: this.fieldDate(col),
      onDateAccept: (value: Date) => {
        this.setField(col, this.ymd(value));
      },
    });
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载表数据…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '') {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load(this.dbId, this.table).catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else {
          Column({ space: 10 }) {
            // 直接展示表格（不再单列「列信息」清单）；表头即列名
            Row() {
              Text(this.canWrite ? `已加载 ${this.vm.rowCount} 行 · 点行可编辑` : `已加载 ${this.vm.rowCount} 行`)
                .fontSize(11)
                .fontColor($r('sys.color.font_tertiary'))
                .layoutWeight(1)
              Text('删除表')
                .fontSize(13)
                .fontColor('#DC2626')
                .padding({ left: 8, top: 4, bottom: 4 })
                .onClick(() => {
                  this.confirmDropTable();
                })
            }
            .width('100%')

            // 索引卡（PRAGMA index_list，只读补充信息，对照 iOS indexCard）
            if (this.vm.indexes.length > 0) {
              Column({ space: 6 }) {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.list_bullet'))
                    .fontSize(13)
                    .fontColor([$r('sys.color.font_tertiary')])
                  Text('索引')
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('sys.color.font_secondary'))
                }
                .width('100%')
                ForEach(this.vm.indexes, (idx: Record<string, string>, i: number) => {
                  Row({ space: 8 }) {
                    Text(`${idx['name'] ?? ''}`)
                      .fontSize(11)
                      .fontFamily('monospace')
                      .fontColor($r('sys.color.font_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    if (`${idx['unique'] ?? '0'}` === '1') {
                      Text('UNIQUE')
                        .fontSize(10)
                        .fontColor($r('app.color.oc_brand_text'))
                    }
                    Text(`${idx['origin'] ?? ''}`)
                      .fontSize(10)
                      .fontColor($r('sys.color.font_tertiary'))
                  }
                  .width('100%')
                }, (idx: Record<string, string>, i: number) => `${i}`)
              }
              .width('100%')
              .padding(12)
              .backgroundColor($r('sys.color.comp_background_list_card'))
              .borderRadius(12)
              .border({ width: 0.5, color: $r('sys.color.comp_divider') })
            }

            if (this.vm.rowCount > 0) {
              // 渲染层：外层横向 Scroll + 内层纵向 List（LazyForEach 懒加载）。
              // 纵向滚动容器是 List 本身且高度确定（layoutWeight 撑满），懒加载在这种嵌套下才真实生效；
              // 每列定宽（首页采样算定），行滚出屏即回收，1000 行封顶也不撑爆布局与内存。
              Scroll() {
                Column() {
                  Row() {
                    ForEach(this.vm.columns, (col: string) => {
                      Text(col)
                        .fontSize(12)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('sys.color.font_primary'))
                        .width(this.vm.colWidth(col))
                        .padding(8)
                        .backgroundColor($r('sys.color.comp_background_tertiary'))
                    }, (col: string) => col)
                  }

                  List() {
                    LazyForEach(this.vm.rowSource, (row: Record<string, string>, index: number) => {
                      ListItem() {
                        Row() {
                          ForEach(this.vm.columns, (col: string) => {
                            Text(this.vm.cell(row, col))
                              .fontSize(12)
                              .fontColor($r('sys.color.font_secondary'))
                              .width(this.vm.colWidth(col))
                              .padding(8)
                              .maxLines(2)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                          }, (col: string) => col)
                        }
                        .border({ width: { top: 0.5 }, color: $r('sys.color.comp_divider') })
                        .onClick(() => {
                          this.openEditor(row);
                        })
                      }
                    }, (row: Record<string, string>, index: number) => `${index}`)
                  }
                  .width(this.vm.totalWidth)
                  .layoutWeight(1)
                  .scrollBar(BarState.Off)
                  .onReachEnd(() => {
                    // 数量层：滚到底自动翻页，驻留 1000 行封顶后停止（loadMore 内部守卫）
                    this.vm.loadMore(this.dbId, this.table).catch(() => {
                    });
                  })
                }
                .height('100%')
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .align(Alignment.TopStart)
              .layoutWeight(1)
              .width('100%')

              if (this.vm.reachedCap) {
                Text(`已加载 ${D1_MAX_LOADED_ROWS} 行，请在查询控制台用 WHERE 条件继续筛选`)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                  .width('100%')
              } else if (this.vm.isLoadingMore) {
                Text('正在加载更多…')
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                  .width('100%')
              }
            } else {
              OCEmpty({ symbol: $r('sys.symbol.list_bullet'), title: '空表', subtitle: '该表暂无数据行' })
            }
          }
          .padding(16)
          .width('100%')
          .height('100%')
        }
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({ content: { title: { mainTitle: this.table } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.editVisible, this.editSheet(), ocSheet(() => {
      this.editVisible = false;
    }))
    .bindSheet(this.dropVisible, this.dropSheet(), ocSheetCompact(() => {
      this.dropVisible = false;
    }))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as D1TableParam;
      this.dbId = param.dbId;
      this.dbName = param.dbName;
      this.table = param.table;
      this.vm.load(this.dbId, this.table).catch(() => {
      });
    })
  }
}
