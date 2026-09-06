// 资源列表排序（Workers / Pages 等通用，对齐 iOS ResourceSortMenu）：
// 默认（名称）/ 创建日期 / 最近更新；选择按列表种类持久化到偏好，下次进页沿用。
import { AppPrefs } from '../../core/system/AppPrefs';

export const SORT_KEYS: string[] = ['name', 'created', 'modified'];

export function sortLabel(key: string): string {
  if (key === 'created') {
    return '创建日期';
  }
  if (key === 'modified') {
    return '最近更新';
  }
  return '默认（名称）';
}

/// ISO8601 串 → 毫秒；空/非法值沉底（返回 0）
function dateValue(text: string | undefined): number {
  if (text === undefined || text === '') {
    return 0;
  }
  const ms = Date.parse(text);
  return isNaN(ms) ? 0 : ms;
}

/// 按日期倒序（新的在前），名称序保持调用方给的原顺序
export function sortByDateDesc<T>(items: T[], key: (item: T) => string | undefined): T[] {
  const copy = items.slice();
  copy.sort((a: T, b: T) => dateValue(key(b)) - dateValue(key(a)));
  return copy;
}

/// 排序偏好（scope 区分列表：'workers' / 'pages'）
export async function loadSortKey(scope: string): Promise<string> {
  const saved = await AppPrefs.getString(`sort_${scope}`, 'name');
  return SORT_KEYS.includes(saved) ? saved : 'name';
}

export async function saveSortKey(scope: string, key: string): Promise<void> {
  await AppPrefs.putString(`sort_${scope}`, key);
}
