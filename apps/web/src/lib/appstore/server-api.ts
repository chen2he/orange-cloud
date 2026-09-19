// App Store Server API 客户端（目前只用 Send Consumption Information）。
//
// 与 webhook 验签的「零密钥」路线不同：主动调 Apple 必须用 App Store Connect 私钥签 JWT
// （ES256，aud=appstoreconnect-v1，带 bid）。私钥走 Worker secret `APPLE_IAP_PRIVATE_KEY`（.p8 PEM 原文），
// key id / issuer id 非机密，放 wrangler.jsonc vars。任一缺失即视为未配置，调用方不发送。

import { importPKCS8, SignJWT } from "jose";
import type { Environment } from "./types";

export const BUNDLE_ID = "jiamin.chen.orange-cloud";

const HOSTS: Record<Environment, string> = {
	Production: "https://api.storekit.apple.com",
	Sandbox: "https://api.storekit-sandbox.apple.com",
};

export interface ServerApiConfig {
	privateKey: string;
	keyId: string;
	issuerId: string;
}

/** 从 Worker env 取配置；缺任一项返回 null（未配置）。 */
export function serverApiConfig(env: unknown): ServerApiConfig | null {
	const e = env as {
		APPLE_IAP_PRIVATE_KEY?: string;
		APPLE_IAP_KEY_ID?: string;
		APPLE_IAP_ISSUER_ID?: string;
	};
	if (!e.APPLE_IAP_PRIVATE_KEY || !e.APPLE_IAP_KEY_ID || !e.APPLE_IAP_ISSUER_ID) return null;
	return { privateKey: e.APPLE_IAP_PRIVATE_KEY, keyId: e.APPLE_IAP_KEY_ID, issuerId: e.APPLE_IAP_ISSUER_ID };
}

/** 签一枚短期 JWT（Apple 上限 60 分钟，这里 10 分钟）。 */
export async function signServerApiToken(cfg: ServerApiConfig, now: number = Date.now()): Promise<string> {
	// secret 可能以字面量 \n 存入（单行粘贴），还原成真正的换行再解析。
	const pem = cfg.privateKey.includes("\\n") ? cfg.privateKey.replace(/\\n/g, "\n") : cfg.privateKey;
	const key = await importPKCS8(pem.trim(), "ES256");
	const iat = Math.floor(now / 1000);
	return new SignJWT({ bid: BUNDLE_ID })
		.setProtectedHeader({ alg: "ES256", kid: cfg.keyId, typ: "JWT" })
		.setIssuer(cfg.issuerId)
		.setAudience("appstoreconnect-v1")
		.setIssuedAt(iat)
		.setExpirationTime(iat + 600)
		.sign(key);
}

// ---- Send Consumption Information（v2）----

export type DeliveryStatus =
	| "DELIVERED"
	| "UNDELIVERED_QUALITY_ISSUE"
	| "UNDELIVERED_WRONG_ITEM"
	| "UNDELIVERED_SERVER_OUTAGE"
	| "UNDELIVERED_OTHER";

export type RefundPreference = "GRANT_FULL" | "GRANT_PRORATED" | "DECLINE";

/** ConsumptionRequest 请求体（Apple 文档字段名原样）。 */
export interface ConsumptionRequest {
	customerConsented: true;
	deliveryStatus: DeliveryStatus;
	sampleContentProvided: boolean;
	refundPreference?: RefundPreference;
	/** 0–100000（milliunits）；自动续订 + GRANT_PRORATED 时必须省略。 */
	consumptionPercentage?: number;
}

export interface SendResult {
	ok: boolean;
	status: number;
	/** 失败时 Apple 的 errorCode / errorMessage，或网络错误描述 */
	error?: string;
}

/**
 * PUT /inApps/v2/transactions/consumption/{transactionId}。成功为 202。
 * 不抛错：网络异常也折成 { ok:false }，由调用方记录并在截止前重试。
 */
export async function sendConsumptionInformation(
	cfg: ServerApiConfig,
	environment: Environment,
	transactionId: string,
	body: ConsumptionRequest,
	fetchImpl: typeof fetch = fetch,
): Promise<SendResult> {
	try {
		const token = await signServerApiToken(cfg);
		const res = await fetchImpl(
			`${HOSTS[environment]}/inApps/v2/transactions/consumption/${encodeURIComponent(transactionId)}`,
			{
				method: "PUT",
				headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
				body: JSON.stringify(body),
				signal: AbortSignal.timeout(15_000),
			},
		);
		if (res.status === 202 || res.status === 200) return { ok: true, status: res.status };
		let error = `HTTP ${res.status}`;
		try {
			const j = (await res.json()) as { errorCode?: number; errorMessage?: string };
			if (j.errorCode || j.errorMessage) error = `HTTP ${res.status} ${j.errorCode ?? ""} ${j.errorMessage ?? ""}`.trim();
		} catch {
			// 无 JSON 体
		}
		return { ok: false, status: res.status, error };
	} catch (err) {
		return { ok: false, status: 0, error: err instanceof Error ? err.message : String(err) };
	}
}
