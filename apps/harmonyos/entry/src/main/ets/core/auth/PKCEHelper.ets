// PKCE (RFC 7636)：code_verifier 随机生成，code_challenge = BASE64URL(SHA256(verifier))
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

/// base64url 编码（无 padding，RFC 4648 §5）
function base64URLEncode(bytes: Uint8Array): string {
  const helper = new util.Base64Helper();
  return helper.encodeToStringSync(bytes)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
}

export class PKCEHelper {
  /// 生成 43–128 字符的 code_verifier（32 字节随机数 → 43 字符 base64url）
  static generateCodeVerifier(): string {
    const rand = cryptoFramework.createRandom();
    const blob = rand.generateRandomSync(32);
    return base64URLEncode(blob.data);
  }

  /// code_challenge = BASE64URL(SHA256(code_verifier))，method 固定 S256
  static async generateCodeChallenge(verifier: string): Promise<string> {
    const md = cryptoFramework.createMd('SHA256');
    const input: cryptoFramework.DataBlob = { data: new util.TextEncoder().encodeInto(verifier) };
    await md.update(input);
    const digest = await md.digest();
    return base64URLEncode(digest.data);
  }
}
