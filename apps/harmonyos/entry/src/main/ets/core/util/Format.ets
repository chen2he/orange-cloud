// 展示格式化工具。
// 注意：数据单位 B/KB/MB/GB 固定拉丁符号、不本地化（对齐 iOS Shared/ByteFormat 决策）。

export function formatBytes(bytes: number): string {
  if (bytes < 1024) {
    return `${bytes} B`;
  }
  const units: string[] = ['KB', 'MB', 'GB', 'TB'];
  let value = bytes;
  let unitIndex = -1;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value = value / 1024;
    unitIndex++;
  }
  const digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
  return `${value.toFixed(digits)} ${units[unitIndex]}`;
}

export function formatCount(count: number): string {
  if (count >= 1000000000) {
    return `${(count / 1000000000).toFixed(1)}B`;
  }
  if (count >= 1000000) {
    return `${(count / 1000000).toFixed(1)}M`;
  }
  if (count >= 1000) {
    return `${(count / 1000).toFixed(1)}K`;
  }
  return `${count}`;
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

/// ISO 8601 → 本地 "MM-dd HH:mm"
export function formatDateTime(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) {
    return iso;
  }
  return `${pad2(date.getMonth() + 1)}-${pad2(date.getDate())} ${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
}

/// ISO 8601 → "x 分钟前 / x 小时前 / MM-dd"
export function formatTimeAgo(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) {
    return iso;
  }
  const diffMs = Date.now() - date.getTime();
  const minutes = Math.floor(diffMs / 60000);
  if (minutes < 1) {
    return '刚刚';
  }
  if (minutes < 60) {
    return `${minutes} 分钟前`;
  }
  const hours = Math.floor(minutes / 60);
  if (hours < 24) {
    return `${hours} 小时前`;
  }
  const days = Math.floor(hours / 24);
  if (days < 30) {
    return `${days} 天前`;
  }
  return `${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}`;
}
