// 退款审核：规则 / 请求体 / JWT 签名的单测 + 真实 SQL（node:sqlite）的入库、表态、兜底发送集成测试。

import { readdirSync, readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { decodeProtectedHeader, exportPKCS8, exportSPKI, generateKeyPair, importSPKI, jwtVerify } from "jose";
import { beforeEach, describe, expect, it } from "vitest";
import {
	AUTO_SEND_AFTER_MS,
	buildConsumptionRequest,
	decideRefundReview,
	listRefundReviews,
	recordConsumptionRequest,
	recordRefundOutcome,
	RESPONSE_WINDOW_MS,
	suggestPreference,
	sweepRefundReviews,
} from "./refund-review";
import { BUNDLE_ID, type ServerApiConfig, sendConsumptionInformation, signServerApiToken } from "./server-api";
import type { DecodedNotification } from "./types";

// ---- 最小 D1 适配器 ----
class FakeStmt {
	private args: unknown[] = [];
	constructor(
		private readonly db: DatabaseSync,
		private readonly sql: string,
	) {}
	bind(...args: unknown[]): this {
		this.args = args;
		return this;
	}
	async run() {
		const info = this.db.prepare(this.sql).run(...(this.args as never[]));
		return { success: true, meta: { changes: Number(info.changes) } };
	}
	async all() {
		return { results: this.db.prepare(this.sql).all(...(this.args as never[])) };
	}
	async first() {
		return this.db.prepare(this.sql).get(...(this.args as never[])) ?? null;
	}
}
class FakeD1 {
	constructor(private readonly db: DatabaseSync) {}
	prepare(sql: string): FakeStmt {
		return new FakeStmt(this.db, sql);
	}
}

const migDir = new URL("../../../migrations/", import.meta.url);
const schema = readdirSync(migDir)
	.filter((f) => f.endsWith(".sql"))
	.sort()
	.map((f) => readFileSync(new URL(f, migDir), "utf8"))
	.join("\n");

const T0 = Date.UTC(2026, 8, 14, 17, 58, 37); // 扣款时刻
const MIN = 60_000;

let raw: DatabaseSync;
let db: D1Database;

beforeEach(() => {
	raw = new DatabaseSync(":memory:");
	raw.exec(schema);
	db = new FakeD1(raw) as unknown as D1Database;
});

let cfg: ServerApiConfig;
let publicPem: string;
beforeEach(async () => {
	if (cfg) return;
	const { privateKey, publicKey } = await generateKeyPair("ES256", { extractable: true });
	cfg = { privateKey: await exportPKCS8(privateKey), keyId: "KEY123", issuerId: "issuer-uuid" };
	publicPem = await exportSPKI(publicKey);
});

function consumptionRequest(uuid: string, opts: { txn?: string; signedDate?: number; type?: string; price?: number } = {}): DecodedNotification {
	return {
		payload: {
			notificationType: "CONSUMPTION_REQUEST",
			notificationUUID: uuid,
			signedDate: opts.signedDate ?? T0 + 3 * 86_400_000,
			data: { bundleId: BUNDLE_ID, environment: "Production", consumptionRequestReason: "UNINTENDED_PURCHASE" },
		},
		transaction: {
			transactionId: opts.txn ?? "210003185482518",
			originalTransactionId: "210003118039058",
			productId: "jiamin.chen.orange_cloud.pro.yearly",
			type: opts.type ?? "Auto-Renewable Subscription",
			purchaseDate: T0,
			price: opts.price ?? 19990,
			currency: "USD",
			storefront: "USA",
		},
	};
}

function seedAutoRenewDisabled(at: number, uuid = "n-disable") {
	raw.exec(
		`INSERT INTO notifications (notification_uuid, notification_type, subtype, original_transaction_id, signed_date, received_at, raw_payload)
		 VALUES ('${uuid}', 'DID_CHANGE_RENEWAL_STATUS', 'AUTO_RENEW_DISABLED', '210003118039058', ${at}, ${at}, '{}')`,
	);
}

/** 记录每次调用的假 fetch */
function fakeFetch(status = 202) {
	const calls: { url: string; init: RequestInit }[] = [];
	const impl = (async (url: string, init: RequestInit) => {
		calls.push({ url, init });
		return new Response(status === 202 ? null : JSON.stringify({ errorCode: 4000023, errorMessage: "bad" }), { status });
	}) as unknown as typeof fetch;
	return { calls, impl };
}

describe("suggestPreference", () => {
	const base = { productType: "Auto-Renewable Subscription", price: 19990, purchaseDate: T0 };

	it("扣款后很快关自动续订 → 全额", () => {
		const s = suggestPreference({ ...base, autoRenewDisabledAt: T0 + 16_000 });
		expect(s.preference).toBe("GRANT_FULL");
		expect(s.reason).toContain("16 秒");
	});
	it("超过 24h 才关 → 不表态", () => {
		expect(suggestPreference({ ...base, autoRenewDisabledAt: T0 + 25 * 60 * MIN }).preference).toBe("NONE");
	});
	it("从没关自动续订 → 不表态", () => {
		expect(suggestPreference(base).preference).toBe("NONE");
	});
	it("买断 / 免费试用交易不适用", () => {
		expect(suggestPreference({ ...base, productType: "Non-Consumable", autoRenewDisabledAt: T0 + MIN }).preference).toBe("NONE");
		expect(suggestPreference({ ...base, price: 0, autoRenewDisabledAt: T0 + MIN }).preference).toBe("NONE");
	});
});

describe("buildConsumptionRequest", () => {
	it("NONE 不带 refundPreference，恒带同意与已交付", () => {
		expect(buildConsumptionRequest("NONE")).toEqual({
			customerConsented: true,
			deliveryStatus: "DELIVERED",
			sampleContentProvided: true,
		});
		expect(buildConsumptionRequest("DECLINE").refundPreference).toBe("DECLINE");
		// 自动续订 + GRANT_PRORATED 不得带 consumptionPercentage
		expect(buildConsumptionRequest("GRANT_PRORATED")).not.toHaveProperty("consumptionPercentage");
	});
});

describe("server-api", () => {
	it("JWT：ES256 + kid + aud/iss/bid，能用公钥验过", async () => {
		const token = await signServerApiToken(cfg);
		expect(decodeProtectedHeader(token)).toMatchObject({ alg: "ES256", kid: "KEY123", typ: "JWT" });
		const { payload } = await jwtVerify(token, await importSPKI(publicPem, "ES256"), {
			issuer: "issuer-uuid",
			audience: "appstoreconnect-v1",
		});
		expect(payload.bid).toBe(BUNDLE_ID);
		expect((payload.exp ?? 0) - (payload.iat ?? 0)).toBeLessThanOrEqual(3600);
	});

	it("secret 以字面量 \\n 存入也能解析", async () => {
		const oneLine = { ...cfg, privateKey: cfg.privateKey.replace(/\n/g, "\\n") };
		await expect(signServerApiToken(oneLine)).resolves.toMatch(/^ey/);
	});

	it("PUT v2 端点、按环境选主机；非 202 折成错误", async () => {
		const ok = fakeFetch(202);
		const r = await sendConsumptionInformation(cfg, "Sandbox", "123", buildConsumptionRequest("NONE"), ok.impl);
		expect(r.ok).toBe(true);
		expect(ok.calls[0].url).toBe("https://api.storekit-sandbox.apple.com/inApps/v2/transactions/consumption/123");
		expect(ok.calls[0].init.method).toBe("PUT");

		const bad = fakeFetch(400);
		const r2 = await sendConsumptionInformation(cfg, "Production", "123", buildConsumptionRequest("NONE"), bad.impl);
		expect(r2).toMatchObject({ ok: false, status: 400 });
		expect(r2.error).toContain("4000023");
	});
});

describe("退款审核存储（真实 SQL）", () => {
	it("入库：命中快取消规则 → 默认全额；12h 截止；重复通知幂等", async () => {
		seedAutoRenewDisabled(T0 + 16_000);
		const s = await recordConsumptionRequest(db, consumptionRequest("c1"));
		expect(s?.preference).toBe("GRANT_FULL");
		await recordConsumptionRequest(db, consumptionRequest("c1"));
		const rows = await listRefundReviews(db);
		expect(rows).toHaveLength(1);
		expect(rows[0]).toMatchObject({ suggested: "GRANT_FULL", reason: "UNINTENDED_PURCHASE", status: "pending" });
		expect(rows[0].deadline_at - rows[0].requested_at).toBe(RESPONSE_WINDOW_MS);
	});

	it("扣款之前的关闭记录（上一周期）不算", async () => {
		seedAutoRenewDisabled(T0 - 30 * 86_400_000);
		expect((await recordConsumptionRequest(db, consumptionRequest("c1")))?.preference).toBe("NONE");
	});

	it("非 CONSUMPTION_REQUEST 忽略", async () => {
		const n = consumptionRequest("x");
		n.payload.notificationType = "DID_RENEW";
		expect(await recordConsumptionRequest(db, n)).toBeNull();
		expect(await listRefundReviews(db)).toHaveLength(0);
	});

	it("管理员表态：同交易的多条待发申请一起发出，之后不可再改", async () => {
		const now = T0 + 3 * 86_400_000;
		await recordConsumptionRequest(db, consumptionRequest("c1", { signedDate: now }));
		await recordConsumptionRequest(db, consumptionRequest("c2", { signedDate: now + MIN }));
		const f = fakeFetch(202);
		expect(await decideRefundReview(db, cfg, "c1", "DECLINE", now + 2 * MIN, f.impl)).toBe("sent");
		expect(f.calls).toHaveLength(2);
		expect(JSON.parse(String(f.calls[0].init.body))).toMatchObject({ refundPreference: "DECLINE", customerConsented: true });
		const rows = await listRefundReviews(db);
		expect(rows.every((r) => r.status === "sent" && r.decided_by === "admin")).toBe(true);
		expect(await decideRefundReview(db, cfg, "c1", "GRANT_FULL", now + 3 * MIN, f.impl)).toBe("closed");
		expect(await decideRefundReview(db, cfg, "nope", "GRANT_FULL", now, f.impl)).toBe("not_found");
	});

	it("未配置密钥：不发送、记错误、保持待发", async () => {
		const now = T0 + 3 * 86_400_000;
		await recordConsumptionRequest(db, consumptionRequest("c1", { signedDate: now }));
		expect(await decideRefundReview(db, null, "c1", "GRANT_FULL", now + MIN)).toBe("failed");
		const [row] = await listRefundReviews(db);
		expect(row).toMatchObject({ status: "pending", decision: "GRANT_FULL" });
		expect(row.last_error).toContain("APPLE_IAP_PRIVATE_KEY");
	});

	it("cron 兜底：未满 10h 不发；满 10h 按默认发；Apple 拒收留待重试；过 12h 标过期", async () => {
		const t = T0 + 3 * 86_400_000;
		seedAutoRenewDisabled(T0 + 16_000);
		await recordConsumptionRequest(db, consumptionRequest("c1", { signedDate: t }));

		const f = fakeFetch(202);
		expect(await sweepRefundReviews(db, cfg, t + AUTO_SEND_AFTER_MS - MIN, f.impl)).toEqual({ sent: 0, failed: 0, expired: 0 });

		const bad = fakeFetch(500);
		expect(await sweepRefundReviews(db, cfg, t + AUTO_SEND_AFTER_MS, bad.impl)).toMatchObject({ failed: 1 });
		expect((await listRefundReviews(db))[0]).toMatchObject({ status: "pending", attempts: 1 });

		expect(await sweepRefundReviews(db, cfg, t + AUTO_SEND_AFTER_MS + 30 * MIN, f.impl)).toMatchObject({ sent: 1 });
		const [row] = await listRefundReviews(db);
		expect(row).toMatchObject({ status: "sent", decided_by: "auto", attempts: 2 });
		expect(JSON.parse(row.sent_body ?? "{}")).toMatchObject({ refundPreference: "GRANT_FULL" });

		// 另一条一直没发出去 → 过 12h 截止标过期
		await recordConsumptionRequest(db, consumptionRequest("c3", { txn: "other", signedDate: t }));
		expect(await sweepRefundReviews(db, cfg, t + RESPONSE_WINDOW_MS + MIN, f.impl)).toMatchObject({ expired: 1, sent: 0 });
	});

	it("REFUND / REFUND_DECLINED 回填结果", async () => {
		await recordConsumptionRequest(db, consumptionRequest("c1"));
		const refund = consumptionRequest("r1");
		refund.payload.notificationType = "REFUND";
		await recordRefundOutcome(db, refund);
		expect((await listRefundReviews(db))[0].outcome).toBe("REFUND");
	});
});
