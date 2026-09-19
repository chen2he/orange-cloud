// 把解码后的通知写入 D1 后台账本。
//
// 三张表一次 db.batch 原子提交：
//   notifications —— INSERT OR IGNORE，notification_uuid 去重（Apple 重发幂等）
//   transactions  —— 按 transaction_id upsert（退款会回写同一笔的撤销字段）
//   subscriptions —— 按 originalTransactionId upsert，DO UPDATE 带 signedDate 乱序保护
// 因为全是幂等写，Apple 因 5xx 重试时重放同一通知不会污染数据。

import { deriveSubscription } from "./notification-logic";
import type { DecodedNotification } from "./types";

export interface ProcessResult {
	/** notification_uuid 已存在（重复通知，未改动业务表） */
	duplicate: boolean;
	notificationType: string;
	notificationUUID: string;
	subscriptionUpdated: boolean;
	transactionRecorded: boolean;
}

export async function processNotification(
	db: D1Database,
	decoded: DecodedNotification,
	receivedAt: number = Date.now(),
): Promise<ProcessResult> {
	const { payload, transaction } = decoded;
	const signedDate = payload.signedDate ?? receivedAt;
	const statements: D1PreparedStatement[] = [];

	// 1) 原始通知审计 + 幂等
	statements.push(
		db
			.prepare(
				`INSERT OR IGNORE INTO notifications
				 (notification_uuid, notification_type, subtype, original_transaction_id,
				  transaction_id, bundle_id, environment, signed_date, app_apple_id,
				  received_at, raw_payload)
				 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			)
			.bind(
				payload.notificationUUID,
				payload.notificationType,
				payload.subtype ?? null,
				transaction?.originalTransactionId ?? null,
				transaction?.transactionId ?? null,
				payload.data?.bundleId ?? null,
				payload.data?.environment ?? null,
				signedDate,
				payload.data?.appAppleId ?? null,
				receivedAt,
				JSON.stringify(decoded),
			),
	);

	// 2) 财务流水
	if (transaction) {
		statements.push(
			db
				.prepare(
					`INSERT INTO transactions
					 (transaction_id, original_transaction_id, product_id, type, purchase_date,
					  expires_date, price_millis, currency, in_app_ownership_type, offer_type,
					  offer_identifier, storefront, revocation_date, revocation_reason, environment,
					  notification_type, notification_subtype, signed_date, created_at, updated_at)
					 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
					 ON CONFLICT(transaction_id) DO UPDATE SET
					   expires_date = COALESCE(excluded.expires_date, transactions.expires_date),
					   price_millis = COALESCE(excluded.price_millis, transactions.price_millis),
					   currency = COALESCE(excluded.currency, transactions.currency),
					   offer_identifier = COALESCE(excluded.offer_identifier, transactions.offer_identifier),
					   storefront = COALESCE(excluded.storefront, transactions.storefront),
					   revocation_date = COALESCE(excluded.revocation_date, transactions.revocation_date),
					   revocation_reason = COALESCE(excluded.revocation_reason, transactions.revocation_reason),
					   notification_type = excluded.notification_type,
					   notification_subtype = excluded.notification_subtype,
					   signed_date = excluded.signed_date,
					   updated_at = excluded.updated_at
					 -- 乱序保护（与 subscriptions 同口径）：Apple 会重投/乱序，迟到的更旧通知
					 -- 不能把 REFUND 行的 notification_type 又翻回 DID_RENEW。
					 WHERE transactions.signed_date IS NULL
					    OR excluded.signed_date IS NULL
					    OR excluded.signed_date >= transactions.signed_date`,
				)
				.bind(
					transaction.transactionId,
					transaction.originalTransactionId,
					transaction.productId ?? null,
					transaction.type ?? null,
					transaction.purchaseDate ?? null,
					transaction.expiresDate ?? null,
					transaction.price ?? null,
					transaction.currency ?? null,
					transaction.inAppOwnershipType ?? null,
					transaction.offerType ?? null,
					transaction.offerIdentifier ?? null,
					transaction.storefront ?? null,
					transaction.revocationDate ?? null,
					transaction.revocationReason ?? null,
					transaction.environment ?? null,
					payload.notificationType,
					payload.subtype ?? null,
					signedDate,
					receivedAt,
					receivedAt,
				),
		);
	}

	// 3) 订阅当前状态（乱序保护：仅当 signedDate 不旧于已存值才覆盖）
	const derived = deriveSubscription(decoded);
	if (derived) {
		statements.push(
			db
				.prepare(
					`INSERT INTO subscriptions
					 (original_transaction_id, product_id, status, auto_renew_status,
					  auto_renew_product_id, environment, purchase_date, expires_date,
					  is_lifetime, last_notification_type, last_subtype, price_millis,
					  currency, offer_type, last_signed_date, updated_at)
					 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
					 ON CONFLICT(original_transaction_id) DO UPDATE SET
					   product_id = COALESCE(excluded.product_id, subscriptions.product_id),
					   status = excluded.status,
					   auto_renew_status = COALESCE(excluded.auto_renew_status, subscriptions.auto_renew_status),
					   auto_renew_product_id = COALESCE(excluded.auto_renew_product_id, subscriptions.auto_renew_product_id),
					   environment = COALESCE(excluded.environment, subscriptions.environment),
					   purchase_date = COALESCE(excluded.purchase_date, subscriptions.purchase_date),
					   expires_date = COALESCE(excluded.expires_date, subscriptions.expires_date),
					   is_lifetime = MAX(excluded.is_lifetime, subscriptions.is_lifetime),
					   last_notification_type = excluded.last_notification_type,
					   last_subtype = excluded.last_subtype,
					   price_millis = COALESCE(excluded.price_millis, subscriptions.price_millis),
					   currency = COALESCE(excluded.currency, subscriptions.currency),
					   offer_type = COALESCE(excluded.offer_type, subscriptions.offer_type),
					   last_signed_date = excluded.last_signed_date,
					   updated_at = excluded.updated_at
					 WHERE excluded.last_signed_date >= subscriptions.last_signed_date`,
				)
				.bind(
					derived.originalTransactionId,
					derived.productId ?? null,
					derived.status,
					derived.autoRenewStatus ?? null,
					derived.autoRenewProductId ?? null,
					derived.environment ?? null,
					derived.purchaseDate ?? null,
					derived.expiresDate ?? null,
					derived.isLifetime ? 1 : 0,
					payload.notificationType,
					payload.subtype ?? null,
					derived.priceMillis ?? null,
					derived.currency ?? null,
					derived.offerType ?? null,
					signedDate,
					receivedAt,
				),
		);
	}

	const results = await db.batch(statements);
	const duplicate = (results[0]?.meta?.changes ?? 0) === 0;

	return {
		duplicate,
		notificationType: payload.notificationType,
		notificationUUID: payload.notificationUUID,
		subscriptionUpdated: Boolean(derived) && !duplicate,
		transactionRecorded: Boolean(transaction) && !duplicate,
	};
}
