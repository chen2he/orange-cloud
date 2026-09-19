// Pub/Sub push 请求的鉴权与解码。
//
// 安全边界 = Google 签发的 OIDC ID Token：在 Pub/Sub 订阅上配置
// 「身份验证 → 服务账号 + audience」后，每次推送都会带
//   Authorization: Bearer <ID Token>
// 该 token 由 Google 用 https://www.googleapis.com/oauth2/v3/certs 的私钥签发，
// 我们只需公钥验签 + 校验 aud / iss / email —— 与 Apple 侧一样不需要保管任何密钥。
//
// 解码后再校验 packageName，拒绝别人的 topic 误配 / 恶意转发到本端点。

import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from "jose";
import type { DecodedPlayNotification, DeveloperNotification, PubSubEnvelope } from "./types";
import { toMillis } from "./types";

export class PlayVerifyError extends Error {
	constructor(message: string) {
		super(message);
		this.name = "PlayVerifyError";
	}
}

const GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs";
const GOOGLE_ISSUERS = ["https://accounts.google.com", "accounts.google.com"];

let remoteJwks: JWTVerifyGetKey | undefined;
function googleJwks(): JWTVerifyGetKey {
	// createRemoteJWKSet 自带缓存与轮换，模块级复用即可（每个 isolate 一份）。
	remoteJwks ??= createRemoteJWKSet(new URL(GOOGLE_JWKS_URL));
	return remoteJwks;
}

export interface PlayVerifyOptions {
	/** Pub/Sub 订阅里配置的 audience（建议填端点 URL）。 */
	audience: string;
	/** 推送用的服务账号邮箱；配置后强制比对 token 的 email 声明。 */
	serviceAccountEmail?: string;
	/** 期望的 Android 包名，用于拒绝非本 App 的通知。 */
	packageName: string;
	/** 测试注入的验签公钥来源；缺省用 Google 的远端 JWKS。 */
	keys?: JWTVerifyGetKey;
}

/** 校验 Authorization 头里的 Google OIDC token。 */
export async function verifyPushToken(
	authorization: string | null,
	opts: PlayVerifyOptions,
): Promise<void> {
	// 必须是 `Bearer <token>`：没有头、没有前缀、空 token 一律未鉴权。
	const token = /^Bearer\s+(\S+)$/i.exec((authorization ?? "").trim())?.[1];
	if (!token) throw new PlayVerifyError("missing bearer token");

	let payload: Record<string, unknown>;
	try {
		const verified = await jwtVerify(token, opts.keys ?? googleJwks(), {
			issuer: GOOGLE_ISSUERS,
			audience: opts.audience,
		});
		payload = verified.payload as Record<string, unknown>;
	} catch (err) {
		throw new PlayVerifyError(`invalid id token: ${(err as Error).message}`);
	}

	if (opts.serviceAccountEmail) {
		const email = typeof payload.email === "string" ? payload.email : "";
		if (email !== opts.serviceAccountEmail || payload.email_verified !== true) {
			throw new PlayVerifyError("unexpected token subject");
		}
	}
}

/** base64 / base64url 文本 -> UTF-8 字符串。 */
function decodeBase64(data: string): string {
	const normalized = data.replace(/-/g, "+").replace(/_/g, "/");
	const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
	const binary = atob(padded);
	const bytes = new Uint8Array(binary.length);
	for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
	return new TextDecoder().decode(bytes);
}

/** 解析 Pub/Sub 信封 -> DeveloperNotification。 */
export function decodeEnvelope(envelope: PubSubEnvelope): DecodedPlayNotification {
	const message = envelope.message;
	if (!message?.data) throw new PlayVerifyError("missing message.data");

	const messageId = message.messageId ?? message.message_id;
	if (!messageId) throw new PlayVerifyError("missing message id");

	let notification: DeveloperNotification;
	try {
		notification = JSON.parse(decodeBase64(message.data)) as DeveloperNotification;
	} catch {
		throw new PlayVerifyError("message.data is not base64 JSON");
	}

	// eventTimeMillis 缺失（理论上不会）时退回 publishTime，再退回当下，
	// 保证乱序保护始终有一个单调可比的水位。
	const eventTimeMillis =
		toMillis(notification.eventTimeMillis) ??
		(message.publishTime ?? message.publish_time
			? Date.parse((message.publishTime ?? message.publish_time) as string)
			: Date.now());

	return { messageId, eventTimeMillis, notification };
}

/** 完整校验一次 push 请求：token -> 信封 -> 包名。 */
export async function verifyPushRequest(
	authorization: string | null,
	envelope: PubSubEnvelope,
	opts: PlayVerifyOptions,
): Promise<DecodedPlayNotification> {
	await verifyPushToken(authorization, opts);
	const decoded = decodeEnvelope(envelope);
	const pkg = decoded.notification.packageName;
	// 没带包名的信封也拒：留空就绕过包名 pin，等于没校验。
	if (!pkg || pkg !== opts.packageName) {
		throw new PlayVerifyError(`unexpected packageName ${pkg ?? "(missing)"}`);
	}
	return decoded;
}
