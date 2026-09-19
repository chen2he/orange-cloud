// 官网「指南」feed（对齐 iOS GuideService）：公开只读接口，不走 CFApiClient（无需登录、非 Cloudflare API）。
//   GET https://o-c.do/api/guides                  → 两语清单
//   GET https://o-c.do/api/guides/{locale}/{slug}  → 正文结构化块（官网把已渲染的文章解析成块）
// 响应原样落磁盘（cacheDir/guides），断网时回退缓存，读过的文章离线可看。
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GlobalContext } from '../core/system/GlobalContext';

const BASE = 'https://o-c.do/api/guides';
export const GUIDES_SITE_URL = 'https://o-c.do/guides';
const DOMAIN = 0x0001;
const TAG = 'GuideService';

export interface GuideSummary {
  slug: string;
  title: string;
  blurb: string;
  description: string;
  updated: string;
  readingTime: string;
  url: string;
}

export interface GuideCollection {
  title: string;
  description: string;
  url: string;
  guides: GuideSummary[];
}

export interface GuideIndex {
  version: number;
  locales: Record<string, GuideCollection>;
}

/// 正文块：type 决定取哪些字段（heading/paragraph/note/list/code/quote/figure/table）。
/// 行内文本是极小 markdown 子集（** * ` [text](url)），由 GuideInline 解析渲染。
export interface GuideBlock {
  type: string;
  level?: number;
  text?: string;
  md?: string;
  items?: string[];
  ordered?: boolean;
  headers?: string[];
  rows?: string[][];
  alt?: string;
}

export interface GuideArticle {
  locale: string;
  slug: string;
  title: string;
  description: string;
  updated: string;
  readingTime: string;
  url: string;
  blocks: GuideBlock[];
}

function cacheDir(): string {
  const dir = `${GlobalContext.getBase().cacheDir}/guides`;
  try {
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir);
    }
  } catch (e) {
  }
  return dir;
}

function cachePath(key: string): string {
  const safe = key.replace(/[^A-Za-z0-9_-]/g, '_');
  return `${cacheDir()}/${safe}.json`;
}

function saveCache(key: string, text: string): void {
  try {
    const file = fileIo.openSync(cachePath(key),
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    fileIo.writeSync(file.fd, text);
    fileIo.closeSync(file);
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'cache write failed: %{public}s', (e as Error).message ?? '');
  }
}

function loadCache(key: string): string | null {
  try {
    const path = cachePath(key);
    if (!fileIo.accessSync(path)) {
      return null;
    }
    return fileIo.readTextSync(path);
  } catch (e) {
    return null;
  }
}

async function fetchText(url: string): Promise<string> {
  const session = http.createHttp();
  try {
    const response = await session.request(url, {
      method: http.RequestMethod.GET,
      header: { 'Accept': 'application/json' } as Record<string, string>,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 20000,
    });
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(`HTTP ${response.responseCode}`);
    }
    return response.result as string;
  } finally {
    session.destroy();
  }
}

export class GuideService {
  /// 先走网络；失败（断网 / 5xx / 解析失败）回退磁盘缓存，缓存也没有才抛错
  private async fetchJson<T>(url: string, cacheKey: string): Promise<T> {
    try {
      const text = await fetchText(url);
      const parsed = JSON.parse(text) as T;
      saveCache(cacheKey, text);
      return parsed;
    } catch (e) {
      const cached = loadCache(cacheKey);
      if (cached !== null) {
        try {
          hilog.info(DOMAIN, TAG, 'serve from disk cache: %{public}s', cacheKey);
          return JSON.parse(cached) as T;
        } catch (err) {
        }
      }
      throw e as Error;
    }
  }

  index(): Promise<GuideIndex> {
    return this.fetchJson<GuideIndex>(BASE, 'index');
  }

  article(locale: string, slug: string): Promise<GuideArticle> {
    return this.fetchJson<GuideArticle>(`${BASE}/${encodeURIComponent(locale)}/${encodeURIComponent(slug)}`,
      `${locale}_${slug}`);
  }

  /// 首屏先用缓存垫底（打开即有内容），网络结果回来再替换
  cachedArticle(locale: string, slug: string): GuideArticle | null {
    const cached = loadCache(`${locale}_${slug}`);
    if (cached === null) {
      return null;
    }
    try {
      return JSON.parse(cached) as GuideArticle;
    } catch (e) {
      return null;
    }
  }
}
