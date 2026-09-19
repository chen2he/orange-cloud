// 自包含 BLAKE3 哈希（无第三方依赖），移植自 iOS Core/Crypto/Blake3.swift。
// Cloudflare Pages「直接上传」部署给每个文件算的资源键是
//   blake3(base64(文件内容) + 扩展名) 的 hex 前 32 位
// 鸿蒙 Crypto Kit 不提供 BLAKE3，故在此按官方参考实现移植
//（IV / 消息置换 / 7 轮 G 混合 / 区块树 + 根标志），已对官方测试向量校验。
//
// 仅做哈希（非 keyed / 非 derive_key）。ArkTS 的 number 是 double，所有 32 位运算
// 必须显式 `>>> 0` 收敛，加法用 `(a + b) >>> 0`——漏一处就会静默算错哈希。

const IV: number[] = [
  0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
  0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
];

const MSG_PERMUTATION: number[] = [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8];

const CHUNK_START = 1 << 0;
const CHUNK_END = 1 << 1;
const PARENT = 1 << 2;
const ROOT = 1 << 3;

const BLOCK_LEN = 64;
const CHUNK_LEN = 1024;

function rotr(x: number, n: number): number {
  return ((x >>> n) | (x << (32 - n))) >>> 0;
}

function add32(a: number, b: number): number {
  return (a + b) >>> 0;
}

function g(s: number[], a: number, b: number, c: number, d: number, mx: number, my: number): void {
  s[a] = add32(add32(s[a], s[b]), mx);
  s[d] = rotr((s[d] ^ s[a]) >>> 0, 16);
  s[c] = add32(s[c], s[d]);
  s[b] = rotr((s[b] ^ s[c]) >>> 0, 12);
  s[a] = add32(add32(s[a], s[b]), my);
  s[d] = rotr((s[d] ^ s[a]) >>> 0, 8);
  s[c] = add32(s[c], s[d]);
  s[b] = rotr((s[b] ^ s[c]) >>> 0, 7);
}

function roundFn(s: number[], m: number[]): void {
  // 列
  g(s, 0, 4, 8, 12, m[0], m[1]);
  g(s, 1, 5, 9, 13, m[2], m[3]);
  g(s, 2, 6, 10, 14, m[4], m[5]);
  g(s, 3, 7, 11, 15, m[6], m[7]);
  // 对角
  g(s, 0, 5, 10, 15, m[8], m[9]);
  g(s, 1, 6, 11, 12, m[10], m[11]);
  g(s, 2, 7, 8, 13, m[12], m[13]);
  g(s, 3, 4, 9, 14, m[14], m[15]);
}

function permute(m: number[]): number[] {
  const p: number[] = new Array<number>(16).fill(0);
  for (let i = 0; i < 16; i++) {
    p[i] = m[MSG_PERMUTATION[i]];
  }
  return p;
}

/// 返回 16 个字（前 8 为链值，全部 16 用于根输出）。
/// counter 是 64 位，ArkTS 用 double 承载——区块计数不会接近 2^53，安全。
function compress(cv: number[], blockWords: number[], counter: number,
  blockLen: number, flags: number): number[] {
  const counterLo = (counter % 0x100000000) >>> 0;
  const counterHi = Math.floor(counter / 0x100000000) >>> 0;
  const state: number[] = [
    cv[0], cv[1], cv[2], cv[3], cv[4], cv[5], cv[6], cv[7],
    IV[0], IV[1], IV[2], IV[3],
    counterLo, counterHi, blockLen >>> 0, flags >>> 0,
  ];
  let m = blockWords.slice();
  for (let r = 0; r < 7; r++) {
    roundFn(state, m);
    if (r < 6) {
      m = permute(m); // 轮间置换，最后一轮后不置换
    }
  }
  for (let i = 0; i < 8; i++) {
    state[i] = (state[i] ^ state[i + 8]) >>> 0;
    state[i + 8] = (state[i + 8] ^ cv[i]) >>> 0;
  }
  return state;
}

/// 64 字节小端 → 16 个 uint32
function wordsFrom(block: Uint8Array): number[] {
  const w: number[] = new Array<number>(16).fill(0);
  for (let i = 0; i < 16; i++) {
    const o = i * 4;
    w[i] = ((block[o]) | (block[o + 1] << 8) | (block[o + 2] << 16) | (block[o + 3] << 24)) >>> 0;
  }
  return w;
}

/// 节点输出（chunk 末块 / 父节点）
class Blake3Output {
  inputCV: number[];
  blockWords: number[];
  counter: number;
  blockLen: number;
  flags: number;

  constructor(inputCV: number[], blockWords: number[], counter: number, blockLen: number, flags: number) {
    this.inputCV = inputCV;
    this.blockWords = blockWords;
    this.counter = counter;
    this.blockLen = blockLen;
    this.flags = flags;
  }

  chainingValue(): number[] {
    return compress(this.inputCV, this.blockWords, this.counter, this.blockLen, this.flags).slice(0, 8);
  }

  rootOutputBytes(outLen: number): Uint8Array {
    const out = new Uint8Array(outLen);
    let filled = 0;
    let outputBlockCounter = 0;
    while (filled < outLen) {
      const ws = compress(this.inputCV, this.blockWords, outputBlockCounter, this.blockLen,
        (this.flags | ROOT) >>> 0);
      for (const w of ws) {
        for (let b = 0; b < 4; b++) {
          if (filled >= outLen) {
            break;
          }
          out[filled] = (w >>> (8 * b)) & 0xFF;
          filled++;
        }
        if (filled >= outLen) {
          break;
        }
      }
      outputBlockCounter++;
    }
    return out;
  }
}

function parentOutput(left: number[], right: number[], key: number[], flags: number): Blake3Output {
  const bw = left.concat(right);
  return new Blake3Output(key, bw, 0, BLOCK_LEN, (PARENT | flags) >>> 0);
}

function parentCV(left: number[], right: number[], key: number[], flags: number): number[] {
  return parentOutput(left, right, key, flags).chainingValue();
}

/// 增量哈希器
class Blake3Hasher {
  private key: number[] = IV.slice();
  private flags: number = 0;
  private chunkCV: number[] = IV.slice();
  private chunkCounter: number = 0;
  private block: Uint8Array = new Uint8Array(BLOCK_LEN);
  private blockLen: number = 0;
  private blocksCompressed: number = 0;
  private cvStack: number[][] = [];

  private startFlag(): number {
    return this.blocksCompressed === 0 ? CHUNK_START : 0;
  }

  private chunkConsumed(): number {
    return this.blocksCompressed * BLOCK_LEN + this.blockLen;
  }

  update(input: Uint8Array): void {
    let i = 0;
    while (i < input.length) {
      // 当前 chunk 已满 → 收口出 CV、合并进栈、开新 chunk
      if (this.chunkConsumed() === CHUNK_LEN) {
        const cv = this.chunkOutput().chainingValue();
        const totalChunks = this.chunkCounter + 1;
        this.addChunkCV(cv, totalChunks);
        this.chunkCV = this.key.slice();
        this.chunkCounter = totalChunks;
        this.block = new Uint8Array(BLOCK_LEN);
        this.blockLen = 0;
        this.blocksCompressed = 0;
      }
      const want = CHUNK_LEN - this.chunkConsumed();
      const take = Math.min(want, input.length - i);
      this.feedChunk(input, i, i + take);
      i += take;
    }
  }

  /// 把 input[start, end) （≤ 当前 chunk 剩余空间）喂进当前 chunk
  private feedChunk(input: Uint8Array, start: number, end: number): void {
    let i = start;
    while (i < end) {
      if (this.blockLen === BLOCK_LEN) {
        const bw = wordsFrom(this.block);
        this.chunkCV = compress(this.chunkCV, bw, this.chunkCounter, BLOCK_LEN,
          (this.flags | this.startFlag()) >>> 0).slice(0, 8);
        this.blocksCompressed++;
        this.block = new Uint8Array(BLOCK_LEN);
        this.blockLen = 0;
      }
      const want = BLOCK_LEN - this.blockLen;
      const take = Math.min(want, end - i);
      for (let k = 0; k < take; k++) {
        this.block[this.blockLen + k] = input[i + k];
      }
      this.blockLen += take;
      i += take;
    }
  }

  private chunkOutput(): Blake3Output {
    return new Blake3Output(this.chunkCV, wordsFrom(this.block), this.chunkCounter, this.blockLen,
      (this.flags | this.startFlag() | CHUNK_END) >>> 0);
  }

  private addChunkCV(newCV: number[], totalChunks: number): void {
    let cv = newCV;
    let tc = totalChunks;
    while (tc % 2 === 0) {
      const left = this.cvStack.pop();
      if (left === undefined) {
        break;
      }
      cv = parentCV(left, cv, this.key, this.flags);
      tc = Math.floor(tc / 2);
    }
    this.cvStack.push(cv);
  }

  finalize(outputLen: number): Uint8Array {
    let output = this.chunkOutput();
    let remaining = this.cvStack.length;
    while (remaining > 0) {
      remaining--;
      output = parentOutput(this.cvStack[remaining], output.chainingValue(), this.key, this.flags);
    }
    return output.rootOutputBytes(outputLen);
  }
}

/// 完整 32 字节摘要
export function blake3Hash(input: Uint8Array): Uint8Array {
  const hasher = new Blake3Hasher();
  hasher.update(input);
  return hasher.finalize(32);
}

/// hex 摘要取前 prefixChars 个字符（Pages 资源键取前 32）
export function blake3HexPrefix(input: Uint8Array, prefixChars: number): string {
  const digest = blake3Hash(input);
  let hex = '';
  for (const byte of digest) {
    hex += byte.toString(16).padStart(2, '0');
  }
  return hex.substring(0, prefixChars);
}
