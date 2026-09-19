// Token 只存关键资产（Asset Store Kit，等价 iOS Keychain / Android EncryptedPrefs）。
// 多身份：按身份 UUID 拼 alias。
// 关键约束：Asset 的 SECRET 单值硬上限 1024 字节，而 CF token（两条 JWT + 60+ scope 串）
// 序列化后常 >1400 字节，必须**分块存**（每块 ≤900 字节，用 alias 后缀 _0/_1/…，另存 _count）。
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';

export interface StoredToken {
  accessToken: string;
  refreshToken?: string;
  /// 过期时刻（Unix 毫秒）
  expiresAtMs: number;
  scope: string;
}

/// 单块上限（留足余量，Asset SECRET 硬顶 1024 字节；token 全是 ASCII，字节=字符）
const CHUNK_SIZE = 900;
/// clear 兜底扫描的最大块数（900×20=18KB，远超任何 token）
const MAX_CHUNKS = 20;

function base(sessionId: string): string {
  return `cf_oauth_token_${sessionId}`;
}

function chunkAlias(sessionId: string, index: number): string {
  return `${base(sessionId)}_${index}`;
}

function countAlias(sessionId: string): string {
  return `${base(sessionId)}_count`;
}

function toBytes(text: string): Uint8Array {
  return new util.TextEncoder().encodeInto(text);
}

function fromBytes(bytes: Uint8Array): string {
  return util.TextDecoder.create('utf-8').decodeToString(bytes);
}

async function addSecret(alias: string, value: string): Promise<void> {
  const attrs: asset.AssetMap = new Map();
  attrs.set(asset.Tag.ALIAS, toBytes(alias));
  attrs.set(asset.Tag.SECRET, toBytes(value));
  attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
  await asset.add(attrs);
}

async function readSecret(alias: string): Promise<string | null> {
  const query: asset.AssetMap = new Map();
  query.set(asset.Tag.ALIAS, toBytes(alias));
  query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
  try {
    const found = await asset.query(query);
    if (found.length === 0) {
      return null;
    }
    return fromBytes(found[0].get(asset.Tag.SECRET) as Uint8Array);
  } catch (e) {
    return null;
  }
}

async function removeAlias(alias: string): Promise<void> {
  const query: asset.AssetMap = new Map();
  query.set(asset.Tag.ALIAS, toBytes(alias));
  try {
    await asset.remove(query);
  } catch (e) {
    // 不存在则忽略
  }
}

export class TokenStore {
  static async save(sessionId: string, token: StoredToken): Promise<void> {
    await TokenStore.clear(sessionId);
    const serialized = JSON.stringify(token);
    const chunks = Math.max(1, Math.ceil(serialized.length / CHUNK_SIZE));
    for (let i = 0; i < chunks; i++) {
      const part = serialized.substring(i * CHUNK_SIZE, (i + 1) * CHUNK_SIZE);
      await addSecret(chunkAlias(sessionId, i), part);
    }
    await addSecret(countAlias(sessionId), `${chunks}`);
  }

  static async load(sessionId: string): Promise<StoredToken | null> {
    const countStr = await readSecret(countAlias(sessionId));
    if (countStr === null) {
      return null;
    }
    const count = Number.parseInt(countStr);
    if (Number.isNaN(count) || count <= 0) {
      return null;
    }
    let serialized = '';
    for (let i = 0; i < count; i++) {
      const part = await readSecret(chunkAlias(sessionId, i));
      if (part === null) {
        return null; // 块缺失，视为无效
      }
      serialized += part;
    }
    try {
      return JSON.parse(serialized) as StoredToken;
    } catch (e) {
      return null;
    }
  }

  static async clear(sessionId: string): Promise<void> {
    await removeAlias(countAlias(sessionId));
    for (let i = 0; i < MAX_CHUNKS; i++) {
      await removeAlias(chunkAlias(sessionId, i));
    }
    // 兼容早期未分块写入的旧 alias
    await removeAlias(base(sessionId));
  }
}
