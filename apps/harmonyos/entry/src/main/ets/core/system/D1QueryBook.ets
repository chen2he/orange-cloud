// D1 查询控制台的「最近执行 / 收藏」按数据库分键落盘（对齐 iOS D1QueryHistoryStore）。
//
// 只存 SQL 文本本身：最近 12 条（执行成功才入，失败语句不值得回填）、收藏 20 条；
// 单条超 2000 字符只留前段，避免偏好存储被撑大。
import { AppPrefs } from './AppPrefs';

const KEY_PREFIX = 'd1_book_';
const MAX_HISTORY = 12;
const MAX_FAVORITES = 20;
const MAX_SQL_LENGTH = 2000;

interface BookPayload {
  history?: string[];
  favorites?: string[];
}

/// 规范化：去首尾空白、压缩换行为单空格、超长截断。空串返回 ''（不入库）
export function normalizeSql(sql: string): string {
  const compact = sql.trim().replace(/\s+/g, ' ');
  if (compact === '') {
    return '';
  }
  return compact.length > MAX_SQL_LENGTH ? compact.substring(0, MAX_SQL_LENGTH) : compact;
}

@ObservedV2
export class D1QueryBook {
  @Trace history: string[] = [];
  @Trace favorites: string[] = [];
  private dbId: string = '';

  async loadFor(dbId: string): Promise<void> {
    this.dbId = dbId;
    const raw = await AppPrefs.getString(KEY_PREFIX + dbId, '');
    if (raw === '') {
      this.history = [];
      this.favorites = [];
      return;
    }
    try {
      const payload = JSON.parse(raw) as BookPayload;
      this.history = payload.history ?? [];
      this.favorites = payload.favorites ?? [];
    } catch (e) {
      this.history = [];
      this.favorites = [];
    }
  }

  private async persist(): Promise<void> {
    if (this.dbId === '') {
      return;
    }
    const payload: BookPayload = { history: this.history, favorites: this.favorites };
    await AppPrefs.putString(KEY_PREFIX + this.dbId, JSON.stringify(payload));
  }

  /// 执行成功后记一条（去重后置顶，封顶 12 条）
  async record(sql: string): Promise<void> {
    const key = normalizeSql(sql);
    if (key === '') {
      return;
    }
    const rest = this.history.filter((s: string) => s !== key);
    const next = [key].concat(rest);
    this.history = next.length > MAX_HISTORY ? next.slice(0, MAX_HISTORY) : next;
    await this.persist();
  }

  isFavorite(sql: string): boolean {
    const key = normalizeSql(sql);
    return key !== '' && this.favorites.includes(key);
  }

  /// 切换收藏；返回切换后是否已收藏（超上限时丢弃最旧一条）
  async toggleFavorite(sql: string): Promise<boolean> {
    const key = normalizeSql(sql);
    if (key === '') {
      return false;
    }
    const nowFavorite = !this.favorites.includes(key);
    if (nowFavorite) {
      const next = [key].concat(this.favorites);
      this.favorites = next.length > MAX_FAVORITES ? next.slice(0, MAX_FAVORITES) : next;
    } else {
      this.favorites = this.favorites.filter((s: string) => s !== key);
    }
    await this.persist();
    return nowFavorite;
  }
}

/// 结果集 → CSV 文本（RFC 4180）：含逗号 / 双引号 / 换行的字段用双引号包裹，内部双引号翻倍
export function toCsv(columns: string[], rows: Record<string, string>[]): string {
  const escape = (value: string): string => {
    if (value.includes(',') || value.includes('"') || value.includes('\n') || value.includes('\r')) {
      return `"${value.replace(/"/g, '""')}"`;
    }
    return value;
  };
  const lines: string[] = [];
  lines.push(columns.map(escape).join(','));
  for (const row of rows) {
    const cells: string[] = [];
    for (const col of columns) {
      cells.push(escape(row[col] ?? ''));
    }
    lines.push(cells.join(','));
  }
  return lines.join('\n');
}
