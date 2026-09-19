// 退款审核：Apple CONSUMPTION_REQUEST → 规则给默认倾向 → 管理员可改 → Send Consumption Information。
//
// 时间线（Apple 要求 12 小时内回应）：
//   t0      webhook 收到 CONSUMPTION_REQUEST，按规则算出默认倾向（suggested），入 refund_reviews，Bark 提醒
//   t0..10h 管理员在 /admin 选「全额 / 按比例 / 拒绝 / 不表态」→ 立即发送
//   10h     cron 兜底：仍未决定的按 suggested 发送
//   12h     截止；此前一直发送失败的标 expired
//
// 同意口径：隐私政策已声明「申请退款时向 Apple 提供购买与使用情况」，故 customerConsented 恒为 true
// （作者决策，2026-09-19）。

import {
	type ConsumptionRequest,
	type RefundPreference,
	type ServerApiConfig,
	sendConsumptionInformation,
} from "./server-api";
import type { DecodedNotification, Environment } from "./types";

export type Preference = RefundPreference | "NONE";
export const PREFERENCES: readonly Preference[] = ["GRANT_FULL", "GRANT_PRORATED", "DECLINE", "NONE"];
export const PREFERENCE_LABEL: Record<Preference, string> = {
	GRANT_FULL: "全额退款",
	GRANT_PRORATED: "按比例退款",
	DECLINE: "拒绝退款",
	NONE: "不表态",
};

const HOUR = 3_600_000;
export const RESPONSE_WINDOW_MS = 12 * HOUR;
/** 未决定的申请在收到后多久由 cron 按默认倾向发出（留 2h 给重试）。 */
export const AUTO_SEND_AFTER_MS = 10 * HOUR;
/** 扣款后多久内关掉自动续订，视为「不想要这笔扣款」。 */
export const QUICK_CANCEL_MS = 24 * HOUR;

// ---- 规则（纯函数）----

export interface ReviewFacts {
	productType?: string;
	/** 被申请退款的那笔扣款金额（milliunits） */
	price?: number;
	purchaseDate?: number;
	/** 该扣款之后第一次关闭自动续订的时间（ms），没有则 undefined */
	autoRenewDisabledAt?: number;
}

export interface Suggestion {
	preference: Preference;
	reason: string;
}

function formatGap(ms: number): string {
	if (ms < 60_000) return `${Math.max(0, Math.round(ms / 1000))} 秒`;
	if (ms < HOUR) return `${Math.round(ms / 60_000)} 分钟`;
	return `${(ms / HOUR).toFixed(1)} 小时`;
}

export function suggestPreference(f: ReviewFacts): Suggestion {
	const isSubscription = f.productType === "Auto-Renewable Subscription";
	if (
		isSubscription &&
		(f.price ?? 0) > 0 &&
		f.purchaseDate != null &&
		f.autoRenewDisabledAt != null &&
		f.autoRenewDisabledAt >= f.purchaseDate &&
		f.autoRenewDisabledAt - f.purchaseDate <= QUICK_CANCEL_MS
	) {
		return {
			preference: "GRANT_FULL",
			reason: `扣款后 ${formatGap(f.autoRenewDisabledAt - f.purchaseDate)}即关闭自动续订`,
		};
	}
	return { preference: "NONE", reason: "未命中规则：仅回传已交付，不表态" };
}

/** 组装发给 Apple 的请求体。不回传 consumptionPercentage（我们没有可靠的用量口径）。 */
export function buildConsumptionRequest(preference: Preference): ConsumptionRequest {
	return {
		customerConsented: true,
		deliveryStatus: "DELIVERED",
		// 免费层 + 试用 + 付费页功能说明 —— 购买前已提供了解功能的途径
		sampleContentProvided: true,
		...(preference === "NONE" ? {} : { refundPreference: preference }),
	};
}

// ---- 存储 ----

export interface RefundReviewRow {
	notification_uuid: string;
	transaction_id: string;
	original_transaction_id: string | null;
	product_id: string | null;
	product_type: string | null;
	environment: string | null;
	reason: string | null;
	price_millis: number | null;
	currency: string | null;
	storefront: string | null;
	purchase_date: number | null;
	requested_at: number;
	deadline_at: number;
	suggested: Preference;
	suggested_reason: string | null;
	decision: Preference | null;
	decided_by: string | null;
	status: "pending" | "sent" | "expired";
	attempts: number;
	last_error: string | null;
	sent_at: number | null;
	sent_body: string | null;
	outcome: string | null;
	outcome_at: number | null;
}

/**
 * webhook 收到 CONSUMPTION_REQUEST 时调用（在 processNotification 之后）。
 * INSERT OR IGNORE 按 notification_uuid 幂等。返回规则建议，供 Bark 推送展示。
 */
export async function recordConsumptionRequest(
	db: D1Database,
	decoded: DecodedNotification,
	now: number = Date.now(),
): Promise<Suggestion | null> {
	const { payload, transaction } = decoded;
	if (payload.notificationType !== "CONSUMPTION_REQUEST" || !transaction) return null;

	let autoRenewDisabledAt: number | undefined;
	if (transaction.purchaseDate != null) {
		const row = await db
			.prepare(
				`SELECT MIN(signed_date) AS at FROM notifications
				 WHERE original_transaction_id = ?
				   AND notification_type = 'DID_CHANGE_RENEWAL_STATUS'
				   AND subtype = 'AUTO_RENEW_DISABLED'
				   AND signed_date >= ?`,
			)
			.bind(transaction.originalTransactionId, transaction.purchaseDate)
			.first<{ at: number | null }>();
		autoRenewDisabledAt = row?.at ?? undefined;
	}

	const suggestion = suggestPreference({
		productType: transaction.type,
		price: transaction.price,
		purchaseDate: transaction.purchaseDate,
		autoRenewDisabledAt,
	});
	const requestedAt = payload.signedDate ?? now;
	const reason = typeof payload.data?.consumptionRequestReason === "string" ? payload.data.consumptionRequestReason : null;

	await db
		.prepare(
			`INSERT OR IGNORE INTO refund_reviews
			 (notification_uuid, transaction_id, original_transaction_id, product_id, product_type,
			  environment, reason, price_millis, currency, storefront, purchase_date,
			  requested_at, deadline_at, suggested, suggested_reason, created_at, updated_at)
			 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		)
		.bind(
			payload.notificationUUID,
			transaction.transactionId,
			transaction.originalTransactionId,
			transaction.productId ?? null,
			transaction.type ?? null,
			payload.data?.environment ?? transaction.environment ?? "Production",
			reason,
			transaction.price ?? null,
			transaction.currency ?? null,
			transaction.storefront ?? null,
			transaction.purchaseDate ?? null,
			requestedAt,
			requestedAt + RESPONSE_WINDOW_MS,
			suggestion.preference,
			suggestion.reason,
			now,
			now,
		)
		.run();
	return suggestion;
}

/** 收到 REFUND / REFUND_DECLINED 时回填结果，方便在后台看倾向是否被采纳。 */
export async function recordRefundOutcome(
	db: D1Database,
	decoded: DecodedNotification,
	now: number = Date.now(),
): Promise<void> {
	const type = decoded.payload.notificationType;
	const txn = decoded.transaction?.transactionId;
	if ((type !== "REFUND" && type !== "REFUND_DECLINED") || !txn) return;
	await db
		.prepare(`UPDATE refund_reviews SET outcome = ?, outcome_at = ?, updated_at = ? WHERE transaction_id = ?`)
		.bind(type, decoded.payload.signedDate ?? now, now, txn)
		.run();
}

export async function listRefundReviews(db: D1Database, limit = 30): Promise<RefundReviewRow[]> {
	const { results } = await db
		.prepare(`SELECT * FROM refund_reviews ORDER BY requested_at DESC LIMIT ?`)
		.bind(limit)
		.all<RefundReviewRow>();
	return results ?? [];
}

// ---- 发送 ----

async function sendRow(
	db: D1Database,
	cfg: ServerApiConfig | null,
	row: RefundReviewRow,
	now: number,
	fetchImpl?: typeof fetch,
): Promise<boolean> {
	const preference = row.decision ?? row.suggested;
	const decidedBy = row.decision ? "admin" : "auto";
	if (!cfg) {
		await db
			.prepare(`UPDATE refund_reviews SET last_error = ?, updated_at = ? WHERE notification_uuid = ?`)
			.bind("未配置 APPLE_IAP_PRIVATE_KEY / KEY_ID / ISSUER_ID", now, row.notification_uuid)
			.run();
		return false;
	}
	const body = buildConsumptionRequest(preference);
	const env: Environment = row.environment === "Sandbox" ? "Sandbox" : "Production";
	const res = await sendConsumptionInformation(cfg, env, row.transaction_id, body, fetchImpl);
	if (res.ok) {
		await db
			.prepare(
				`UPDATE refund_reviews
				 SET status = 'sent', decided_by = ?, sent_at = ?, sent_body = ?, attempts = attempts + 1,
				     last_error = NULL, updated_at = ?
				 WHERE notification_uuid = ?`,
			)
			.bind(decidedBy, now, JSON.stringify(body), now, row.notification_uuid)
			.run();
		return true;
	}
	await db
		.prepare(
			`UPDATE refund_reviews SET attempts = attempts + 1, last_error = ?, updated_at = ? WHERE notification_uuid = ?`,
		)
		.bind(res.error ?? `HTTP ${res.status}`, now, row.notification_uuid)
		.run();
	return false;
}

export type DecideResult = "sent" | "failed" | "not_found" | "closed";

/**
 * 管理员决定：写入 decision（作用于同一 transaction_id 的全部待发申请）并立即发送。
 * 已发送 / 已过期的申请不可再改（Apple 只接受一次回应）。
 */
export async function decideRefundReview(
	db: D1Database,
	cfg: ServerApiConfig | null,
	notificationUUID: string,
	decision: Preference,
	now: number = Date.now(),
	fetchImpl?: typeof fetch,
): Promise<DecideResult> {
	const target = await db
		.prepare(`SELECT * FROM refund_reviews WHERE notification_uuid = ?`)
		.bind(notificationUUID)
		.first<RefundReviewRow>();
	if (!target) return "not_found";
	if (target.status !== "pending" || now > target.deadline_at) return "closed";

	await db
		.prepare(
			`UPDATE refund_reviews SET decision = ?, updated_at = ?
			 WHERE transaction_id = ? AND status = 'pending'`,
		)
		.bind(decision, now, target.transaction_id)
		.run();
	const { results } = await db
		.prepare(`SELECT * FROM refund_reviews WHERE transaction_id = ? AND status = 'pending' AND deadline_at >= ?`)
		.bind(target.transaction_id, now)
		.all<RefundReviewRow>();

	let allOk = true;
	for (const row of results ?? []) {
		if (!(await sendRow(db, cfg, row, now, fetchImpl))) allOk = false;
	}
	return allOk ? "sent" : "failed";
}

export interface SweepResult {
	sent: number;
	failed: number;
	expired: number;
}

/**
 * cron 兜底：先把过了 12h 截止的待发标 expired；再把「管理员已决定但发送失败」
 * 与「收到已满 10h 仍未决定」的申请发出去。发送失败留 pending，下一轮重试。
 */
export async function sweepRefundReviews(
	db: D1Database,
	cfg: ServerApiConfig | null,
	now: number = Date.now(),
	fetchImpl?: typeof fetch,
): Promise<SweepResult> {
	const expired = await db
		.prepare(`UPDATE refund_reviews SET status = 'expired', updated_at = ? WHERE status = 'pending' AND deadline_at < ?`)
		.bind(now, now)
		.run();
	const { results } = await db
		.prepare(
			`SELECT * FROM refund_reviews
			 WHERE status = 'pending' AND (decision IS NOT NULL OR requested_at <= ?)
			 ORDER BY requested_at`,
		)
		.bind(now - AUTO_SEND_AFTER_MS)
		.all<RefundReviewRow>();

	const out: SweepResult = { sent: 0, failed: 0, expired: expired.meta?.changes ?? 0 };
	for (const row of results ?? []) {
		if (await sendRow(db, cfg, row, now, fetchImpl)) out.sent++;
		else out.failed++;
	}
	return out;
}
