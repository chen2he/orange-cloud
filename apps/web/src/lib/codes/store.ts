// 激活码的 D1 读写。沿用本仓 appstore/store.ts 的幂等套路（meta.changes 判重）。
// 纯决策在 redeem.ts，本文件只做 I/O。

import { decideRedeem, MAX_ACTIVATIONS, type CodeRow, type RedeemDecision } from "./redeem";
import { canRequestRefund, type RefundReason, type RefundableRow } from "./refund";
import { canSelfReset, type SelfResetReason } from "./selfreset";
import { canSelfBindEmail, type BindReason } from "./bind";
import { generateCode } from "./code";

export interface StripeCodeInput {
	sessionId: string;
	paymentIntent?: string | null;
	amountTotal?: number | null;
	currency?: string | null;
	buyerEmail?: string | null;
	product?: string;
}

export interface CreateResult {
	code: string; // 规范化核心串
	duplicate: boolean; // 该 session 已处理过（幂等命中），未生成新码
}

/**
 * 为一笔 Stripe 付款生成并写入一枚激活码；按 stripe_session_id 幂等。
 * 随机串极小概率撞主键 -> INSERT OR IGNORE + 重试。
 */
export async function createStripeCode(
	db: D1Database,
	input: StripeCodeInput,
	now: number = Date.now(),
): Promise<CreateResult> {
	const existing = await db
		.prepare(`SELECT code FROM codes WHERE stripe_session_id = ?`)
		.bind(input.sessionId)
		.first<{ code: string }>();
	if (existing) return { code: existing.code, duplicate: true };

	for (let attempt = 0; attempt < 5; attempt++) {
		const code = generateCode();
		const res = await db
			.prepare(
				`INSERT OR IGNORE INTO codes
				 (code, product, status, source, stripe_session_id, stripe_payment_intent,
				  amount_total, currency, buyer_email, created_at)
				 VALUES (?, ?, 'active', 'stripe', ?, ?, ?, ?, ?, ?)`,
			)
			.bind(
				code,
				input.product ?? "pro.lifetime",
				input.sessionId,
				input.paymentIntent ?? null,
				input.amountTotal ?? null,
				input.currency ?? null,
				input.buyerEmail ?? null,
				now,
			)
			.run();
		if ((res.meta?.changes ?? 0) === 1) return { code, duplicate: false };

		// changes==0：要么 session 唯一键撞了（并发重复投递），要么 code 撞了。复查 session：
		const again = await db
			.prepare(`SELECT code FROM codes WHERE stripe_session_id = ?`)
			.bind(input.sessionId)
			.first<{ code: string }>();
		if (again) return { code: again.code, duplicate: true };
		// 否则是 code 撞主键，换一个重试
	}
	throw new Error("code generation failed after retries");
}

/** 在线兑换 / 周期复核：判定 + （首次）绑定设备 / （复核）刷新心跳。 */
export async function redeemCode(
	db: D1Database,
	code: string,
	installId: string,
	now: number = Date.now(),
	max: number = MAX_ACTIVATIONS,
): Promise<RedeemDecision> {
	const row = await db
		.prepare(`SELECT code, product, status FROM codes WHERE code = ?`)
		.bind(code)
		.first<CodeRow>();
	const bound = row
		? (
				await db
					.prepare(`SELECT install_id FROM code_activations WHERE code = ?`)
					.bind(code)
					.all<{ install_id: string }>()
			).results ?? []
		: [];

	const decision = decideRedeem(
		row,
		bound.map((b) => b.install_id),
		installId,
		max,
	);

	if (decision.ok && decision.bind) {
		// 上面的「数设备 → 判定」是读后写，两台新设备并发抢最后一个名额会双双通过。
		// 把名额上限写进 INSERT 的 WHERE 里，由 SQLite 单条语句保证原子；changes=0 即没抢到。
		const inserted = await db
			.prepare(
				`INSERT INTO code_activations (code, install_id, activated_at, last_seen_at)
				 SELECT ?, ?, ?, ?
				 WHERE NOT EXISTS (SELECT 1 FROM code_activations WHERE code = ? AND install_id = ?)
				   AND (SELECT COUNT(*) FROM code_activations WHERE code = ?) < ?`,
			)
			.bind(code, installId, now, now, code, installId, code, max)
			.run();
		if ((inserted.meta?.changes ?? 0) === 0) {
			const mine = await db
				.prepare(`SELECT 1 AS x FROM code_activations WHERE code = ? AND install_id = ?`)
				.bind(code, installId)
				.first<{ x: number }>();
			if (!mine) {
				return { ok: false, reason: "device_limit", product: decision.product, bind: false };
			}
		}
	} else if (decision.ok) {
		await db
			.prepare(`UPDATE code_activations SET last_seen_at = ? WHERE code = ? AND install_id = ?`)
			.bind(now, code, installId)
			.run();
	}
	return decision;
}

/** 退款撤销：按 payment_intent 找到码并置 revoked。返回受影响的码（无匹配返回 null）。 */
export async function revokeByPaymentIntent(
	db: D1Database,
	paymentIntent: string,
	reason: string = "refund",
	now: number = Date.now(),
): Promise<string | null> {
	const row = await db
		.prepare(`SELECT code FROM codes WHERE stripe_payment_intent = ?`)
		.bind(paymentIntent)
		.first<{ code: string }>();
	if (!row) return null;
	await db
		.prepare(`UPDATE codes SET status = 'revoked', revoked_at = ?, revoke_reason = ? WHERE code = ?`)
		.bind(now, reason, row.code)
		.run();
	return row.code;
}

// —— 退款申请（官网自助）/ 后台审批 ——

/** 用户自助申请退款：判定资格（30 天政策）后置 refund_status='requested'。 */
export async function requestRefund(
	db: D1Database,
	code: string,
	reason: string,
	now: number = Date.now(),
): Promise<{ ok: boolean; reason: RefundReason }> {
	const row = await db
		.prepare(`SELECT source, stripe_payment_intent, status, refund_status, created_at FROM codes WHERE code = ?`)
		.bind(code)
		.first<RefundableRow>();
	const decision = canRequestRefund(row, now);
	if (!decision.ok) return decision;
	await db
		.prepare(
			`UPDATE codes SET refund_status = 'requested', refund_requested_at = ?, refund_reason = ? WHERE code = ?`,
		)
		.bind(now, reason || null, code)
		.run();
	return { ok: true, reason: "ok" };
}

/** 后台审批要用的最小字段（含 payment_intent 以便发 Stripe 退款）。 */
export async function getCodeForRefund(
	db: D1Database,
	code: string,
): Promise<{ code: string; paymentIntent: string | null; status: string; refundStatus: string } | null> {
	const row = await db
		.prepare(`SELECT code, stripe_payment_intent, status, refund_status FROM codes WHERE code = ?`)
		.bind(code)
		.first<{ code: string; stripe_payment_intent: string | null; status: string; refund_status: string }>();
	if (!row) return null;
	return {
		code: row.code,
		paymentIntent: row.stripe_payment_intent,
		status: row.status,
		refundStatus: row.refund_status,
	};
}

/** 后台批准：标记已退款并撤销码（charge.refunded webhook 也会撤销，幂等）。 */
export async function markRefundApproved(db: D1Database, code: string, now: number = Date.now()): Promise<void> {
	await db
		.prepare(
			`UPDATE codes SET refund_status = 'approved', status = 'revoked', revoked_at = ?, revoke_reason = 'refund' WHERE code = ?`,
		)
		.bind(now, code)
		.run();
}

/** 后台拒绝退款申请。 */
export async function markRefundRejected(db: D1Database, code: string): Promise<void> {
	await db.prepare(`UPDATE codes SET refund_status = 'rejected' WHERE code = ?`).bind(code).run();
}

// —— 设备解绑 ——

/** 设备自助反激活：删除该 (code, install_id) 绑定，释放一个名额。返回是否删到行。 */
export async function deactivate(db: D1Database, code: string, installId: string): Promise<boolean> {
	const res = await db
		.prepare(`DELETE FROM code_activations WHERE code = ? AND install_id = ?`)
		.bind(code, installId)
		.run();
	return (res.meta?.changes ?? 0) > 0;
}

/** 后台解除某码的全部设备绑定（「换了所有设备被锁」的人工恢复）。返回解绑设备数。 */
export async function resetActivations(db: D1Database, code: string): Promise<number> {
	const res = await db.prepare(`DELETE FROM code_activations WHERE code = ?`).bind(code).run();
	return res.meta?.changes ?? 0;
}

export interface SelfResetOutcome {
	ok: boolean;
	reason: SelfResetReason;
	removed?: number;
	nextAt?: number;
}

/** 用户自助重置：邮箱验证 + 30 天频率限制通过后，解除全部设备绑定并记录重置时刻。 */
export async function selfResetDevices(
	db: D1Database,
	code: string,
	email: string,
	now: number = Date.now(),
): Promise<SelfResetOutcome> {
	const row = await db
		.prepare(`SELECT status, buyer_email, last_self_reset_at FROM codes WHERE code = ?`)
		.bind(code)
		.first<{ status: string; buyer_email: string | null; last_self_reset_at: number | null }>();
	const decision = canSelfReset(row, email, now);
	if (!decision.ok) return { ok: false, reason: decision.reason, nextAt: decision.nextAt };

	const removed = await resetActivations(db, code);
	await db.prepare(`UPDATE codes SET last_self_reset_at = ? WHERE code = ?`).bind(now, code).run();
	return { ok: true, reason: "ok", removed };
}

// —— 后台手动生成（媒体 / 评测分发，无支付、无 buyer_email）+ 绑定邮箱 ——

/** 后台批量生成手动激活码（source=manual）。返回核心串数组。 */
export async function createManualCodes(
	db: D1Database,
	count: number,
	note: string | null,
	email: string | null,
	now: number = Date.now(),
): Promise<string[]> {
	const out: string[] = [];
	for (let i = 0; i < count; i++) out.push(await insertManualCode(db, note, email, now));
	return out;
}

async function insertManualCode(
	db: D1Database,
	note: string | null,
	email: string | null,
	now: number,
): Promise<string> {
	for (let attempt = 0; attempt < 5; attempt++) {
		const code = generateCode();
		const res = await db
			.prepare(
				`INSERT OR IGNORE INTO codes (code, product, status, source, buyer_email, note, created_at)
				 VALUES (?, 'pro.lifetime', 'active', 'manual', ?, ?, ?)`,
			)
			.bind(code, email, note, now)
			.run();
		if ((res.meta?.changes ?? 0) === 1) return code;
	}
	throw new Error("manual code generation failed after retries");
}

/** 绑定 / 修改某码的邮箱（后台 admin 用，可覆盖已绑定）。 */
export async function setBuyerEmail(db: D1Database, code: string, email: string): Promise<boolean> {
	const res = await db.prepare(`UPDATE codes SET buyer_email = ? WHERE code = ?`).bind(email, code).run();
	return (res.meta?.changes ?? 0) > 0;
}

/** 用户自助绑定邮箱：仅「尚未绑定」的有效码可绑（WHERE buyer_email IS NULL 兜并发）。 */
export async function selfBindEmail(
	db: D1Database,
	code: string,
	email: string,
): Promise<{ ok: boolean; reason: BindReason }> {
	const row = await db
		.prepare(`SELECT status, buyer_email FROM codes WHERE code = ?`)
		.bind(code)
		.first<{ status: string; buyer_email: string | null }>();
	const decision = canSelfBindEmail(row);
	if (!decision.ok) return decision;
	await db
		.prepare(`UPDATE codes SET buyer_email = ? WHERE code = ? AND buyer_email IS NULL`)
		.bind(email, code)
		.run();
	return { ok: true, reason: "ok" };
}

/** 找回：按邮箱（忽略大小写）查该邮箱名下的有效码，返回核心串数组。 */
export async function findActiveCodesByEmail(db: D1Database, email: string): Promise<string[]> {
	const rows = await db
		.prepare(`SELECT code FROM codes WHERE LOWER(buyer_email) = ? AND status = 'active'`)
		.bind(email.trim().toLowerCase())
		.all<{ code: string }>();
	return (rows.results ?? []).map((r) => r.code);
}

/** 找回邮件的默认冷却：同一邮箱 10 分钟内只发一封。 */
export const RECOVERY_EMAIL_COOLDOWN_MS = 10 * 60 * 1000;

/**
 * 抢占「找回激活码」邮件的发送资格：同一邮箱冷却期内只允许一次。
 * /api/resend-code 不需要任何凭证，没有冷却就是一个对客户邮箱的轰炸器（顺带烧发件配额）。
 * 用一条条件 UPDATE 落时间戳，原子且不依赖内存状态（Workers 多实例）。
 * 返回 true 表示本次可以发。
 */
export async function claimRecoveryEmailSlot(
	db: D1Database,
	email: string,
	now: number = Date.now(),
	cooldownMs: number = RECOVERY_EMAIL_COOLDOWN_MS,
): Promise<boolean> {
	const res = await db
		.prepare(
			`UPDATE codes SET recovery_sent_at = ?
			 WHERE LOWER(buyer_email) = ? AND status = 'active'
			   AND (recovery_sent_at IS NULL OR recovery_sent_at < ?)`,
		)
		.bind(now, email.trim().toLowerCase(), now - cooldownMs)
		.run();
	return (res.meta?.changes ?? 0) > 0;
}
