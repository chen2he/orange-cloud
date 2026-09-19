// 国家/地区 2 字母 ISO 代码 → 地理中心点（近似质心），供全球流量地图打气泡用。
// 只覆盖高流量常见国家；未知代码在地图侧跳过。
// clientCountryName 来自 Cloudflare，是 2 字母 ISO 3166-1 alpha-2 大写代码（US/CN/GB…），
// 特殊值 "T1"（Tor）等无质心则被跳过。

export interface Centroid {
  lat: number;
  lng: number;
}

// 用显式 Map 而非 Record 字面量，规避 arkts-no-untyped-obj-literals。
const CENTROIDS: Map<string, Centroid> = new Map<string, Centroid>([
  ['US', { lat: 39.8, lng: -98.6 }],
  ['CN', { lat: 35.9, lng: 104.2 }],
  ['HK', { lat: 22.3, lng: 114.2 }],
  ['TW', { lat: 23.7, lng: 121.0 }],
  ['JP', { lat: 36.2, lng: 138.3 }],
  ['KR', { lat: 36.5, lng: 127.8 }],
  ['IN', { lat: 22.6, lng: 79.0 }],
  ['SG', { lat: 1.35, lng: 103.8 }],
  ['GB', { lat: 54.0, lng: -2.0 }],
  ['DE', { lat: 51.2, lng: 10.5 }],
  ['FR', { lat: 46.6, lng: 2.4 }],
  ['NL', { lat: 52.1, lng: 5.3 }],
  ['ES', { lat: 40.0, lng: -3.7 }],
  ['IT', { lat: 42.8, lng: 12.6 }],
  ['RU', { lat: 61.5, lng: 105.3 }],
  ['CA', { lat: 56.1, lng: -106.3 }],
  ['AU', { lat: -25.3, lng: 133.8 }],
  ['BR', { lat: -14.2, lng: -51.9 }],
  ['MX', { lat: 23.6, lng: -102.5 }],
  ['AR', { lat: -38.4, lng: -63.6 }],
  ['ID', { lat: -2.5, lng: 118.0 }],
  ['MY', { lat: 4.2, lng: 101.9 }],
  ['TH', { lat: 15.9, lng: 100.9 }],
  ['VN', { lat: 14.1, lng: 108.3 }],
  ['PH', { lat: 12.9, lng: 121.8 }],
  ['TR', { lat: 39.0, lng: 35.2 }],
  ['SA', { lat: 23.9, lng: 45.1 }],
  ['AE', { lat: 23.4, lng: 53.8 }],
  ['IL', { lat: 31.0, lng: 34.9 }],
  ['ZA', { lat: -30.6, lng: 22.9 }],
  ['EG', { lat: 26.8, lng: 30.8 }],
  ['NG', { lat: 9.1, lng: 8.7 }],
  ['KE', { lat: -0.02, lng: 37.9 }],
  ['MA', { lat: 31.8, lng: -7.1 }],
  ['PL', { lat: 51.9, lng: 19.1 }],
  ['SE', { lat: 60.1, lng: 18.6 }],
  ['NO', { lat: 60.5, lng: 8.5 }],
  ['FI', { lat: 61.9, lng: 25.7 }],
  ['DK', { lat: 56.3, lng: 9.5 }],
  ['IE', { lat: 53.4, lng: -8.2 }],
  ['CH', { lat: 46.8, lng: 8.2 }],
  ['AT', { lat: 47.5, lng: 14.6 }],
  ['BE', { lat: 50.5, lng: 4.5 }],
  ['PT', { lat: 39.4, lng: -8.2 }],
  ['GR', { lat: 39.1, lng: 21.8 }],
  ['CZ', { lat: 49.8, lng: 15.5 }],
  ['RO', { lat: 45.9, lng: 24.9 }],
  ['HU', { lat: 47.2, lng: 19.5 }],
  ['UA', { lat: 48.4, lng: 31.2 }],
  ['BG', { lat: 42.7, lng: 25.5 }],
  ['SK', { lat: 48.7, lng: 19.7 }],
  ['RS', { lat: 44.0, lng: 21.0 }],
  ['HR', { lat: 45.1, lng: 15.2 }],
  ['LT', { lat: 55.2, lng: 23.9 }],
  ['LV', { lat: 56.9, lng: 24.6 }],
  ['EE', { lat: 58.6, lng: 25.0 }],
  ['IS', { lat: 65.0, lng: -18.6 }],
  ['LU', { lat: 49.8, lng: 6.1 }],
  ['NZ', { lat: -40.9, lng: 174.9 }],
  ['CL', { lat: -35.7, lng: -71.5 }],
  ['CO', { lat: 4.6, lng: -74.3 }],
  ['PE', { lat: -9.2, lng: -75.0 }],
  ['VE', { lat: 6.4, lng: -66.6 }],
  ['EC', { lat: -1.8, lng: -78.2 }],
  ['UY', { lat: -32.5, lng: -55.8 }],
  ['PK', { lat: 30.4, lng: 69.3 }],
  ['BD', { lat: 23.7, lng: 90.4 }],
  ['LK', { lat: 7.9, lng: 80.8 }],
  ['NP', { lat: 28.4, lng: 84.1 }],
  ['KZ', { lat: 48.0, lng: 66.9 }],
  ['IR', { lat: 32.4, lng: 53.7 }],
  ['IQ', { lat: 33.2, lng: 43.7 }],
  ['QA', { lat: 25.4, lng: 51.2 }],
  ['KW', { lat: 29.3, lng: 47.5 }],
  ['JO', { lat: 30.6, lng: 36.2 }],
  ['LB', { lat: 33.9, lng: 35.9 }],
  ['DZ', { lat: 28.0, lng: 1.7 }],
  ['TN', { lat: 33.9, lng: 9.6 }],
  ['GH', { lat: 7.9, lng: -1.0 }],
  ['ET', { lat: 9.1, lng: 40.5 }],
  ['TZ', { lat: -6.4, lng: 34.9 }],
  ['UG', { lat: 1.4, lng: 32.3 }],
  ['MM', { lat: 21.9, lng: 95.9 }],
  ['KH', { lat: 12.6, lng: 104.9 }],
  ['LA', { lat: 19.9, lng: 102.5 }],
  ['MN', { lat: 46.9, lng: 103.8 }],
  ['MO', { lat: 22.2, lng: 113.5 }],
]);

/// 查询国家/地区代码的质心；未知返回 undefined（大小写不敏感，做大写规整）。
export function centroidFor(code: string): Centroid | undefined {
  if (code.length !== 2) {
    return undefined;
  }
  return CENTROIDS.get(code.toUpperCase());
}
