// 把一条 Play 通知写入统一账本（platform='play'）。
//
// 结构与 lib/appstore/store.ts 完全对称：一次 db.batch 原子提交，
//   notifications —— INSERT OR IGNORE，Pub/Sub messageId 去重（重投递幂等）
//   transactions  —— 按 orderId upsert（退款回写 revocation_date）
//   subscriptions —— 按 purchaseToken upsert，带 eventTime 乱序保护
// 全是幂等写，因此返回 5xx 让 Pub/Sub 重投递是安全的（重放不会污染数据）。

import type { PlayLedgerRows } from "./logic";

export interface PlayProcessResult {
	/** messageId 已存在（重复投递，业务表仍会被幂等重放） */
	duplicate: boolean;
	notificationType: string;
	messageId: string;
	transactionRecorded: boolean;
	subscriptionUpdated: boolean;
}

export async function storeLedgerRows(
	db: D1Database,
	rows: PlayLedgerRows,
): Promise<PlayProcessResult> {
	const { notification: nf, transaction: tx, subscription: sub } = rows;
	const statements: D1PreparedStatement[] = [];

	// 1) 原始通知审计 + 幂等（app_apple_id 是 Apple 专属，Play 恒 NULL）
	statements.push(
		db
			.prepare(
				`INSERT OR IGNORE INTO notifications
				 (notification_uuid, notification_type, subtype, original_transaction_id,
				  transaction_id, bundle_id, environment, signed_date, app_apple_id,
				  received_at, raw_payload, platform)
				 VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, 'play')`,
			)
			.bind(
				nf.notificationUuid,
				nf.notificationType,
				nf.subtype,
				nf.purchaseToken,
				nf.orderId,
				nf.packageName,
				nf.environment,
				nf.eventTime,
				nf.receivedAt,
				nf.raw,
			),
	);

	// 2) 财务流水（offer_type / in_app_ownership_type / revocation_reason 是 Apple 专属，留空）
	if (tx) {
		statements.push(
			db
				.prepare(
					`INSERT INTO transactions
					 (transaction_id, original_transaction_id, product_id, type, purchase_date,
					  expires_date, price_millis, dev_revenue_millis, currency, order_state,
					  in_app_ownership_type, offer_type, offer_identifier, storefront, revocation_date,
					  revocation_reason, environment, notification_type, notification_subtype, signed_date,
					  created_at, updated_at, platform)
					 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, 'play')
					 ON CONFLICT(transaction_id) DO UPDATE SET
					   expires_date = COALESCE(excluded.expires_date, transactions.expires_date),
					   price_millis = COALESCE(excluded.price_millis, transactions.price_millis),
					   dev_revenue_millis = COALESCE(excluded.dev_revenue_millis, transactions.dev_revenue_millis),
					   currency = COALESCE(excluded.currency, transactions.currency),
					   -- 宽限期恢复后同一个 orderId 会从 PENDING 变 PROCESSED，需要覆盖。
					   order_state = COALESCE(excluded.order_state, transactions.order_state),
					   product_id = COALESCE(excluded.product_id, transactions.product_id),
					   purchase_date = COALESCE(transactions.purchase_date, excluded.purchase_date),
					   offer_identifier = COALESCE(excluded.offer_identifier, transactions.offer_identifier),
					   storefront = COALESCE(excluded.storefront, transactions.storefront),
					   revocation_date = COALESCE(excluded.revocation_date, transactions.revocation_date),
					   environment = excluded.environment,
					   notification_type = excluded.notification_type,
					   notification_subtype = excluded.notification_subtype,
					   signed_date = excluded.signed_date,
					   updated_at = excluded.updated_at
					 -- 乱序保护：Pub/Sub 至少一次投递且不保序，迟到的旧事件不覆盖新状态。
					 WHERE transactions.signed_date IS NULL
					    OR excluded.signed_date IS NULL
					    OR excluded.signed_date >= transactions.signed_date`,
				)
				.bind(
					tx.orderId,
					tx.purchaseToken,
					tx.productId,
					tx.type,
					tx.purchaseDate,
					tx.expiresDate,
					tx.priceMillis,
					tx.devRevenueMillis,
					tx.currency,
					tx.orderState,
					tx.offerIdentifier,
					tx.storefront,
					tx.revocationDate,
					tx.environment,
					nf.notificationType,
					nf.subtype,
					nf.eventTime,
					nf.receivedAt,
					nf.receivedAt,
				),
		);
	}

	// 3) 权益状态（乱序保护：仅当 eventTime 不旧于已存水位才覆盖）
	if (sub) {
		statements.push(
			db
				.prepare(
					`INSERT INTO subscriptions
					 (original_transaction_id, product_id, status, auto_renew_status,
					  auto_renew_product_id, environment, purchase_date, expires_date,
					  is_lifetime, last_notification_type, last_subtype, price_millis,
					  currency, offer_type, last_signed_date, updated_at, platform, linked_token)
					 VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, 'play', ?)
					 ON CONFLICT(original_transaction_id) DO UPDATE SET
					   product_id = COALESCE(excluded.product_id, subscriptions.product_id),
					   status = excluded.status,
					   auto_renew_status = COALESCE(excluded.auto_renew_status, subscriptions.auto_renew_status),
					   environment = excluded.environment,
					   purchase_date = COALESCE(subscriptions.purchase_date, excluded.purchase_date),
					   expires_date = COALESCE(excluded.expires_date, subscriptions.expires_date),
					   is_lifetime = MAX(excluded.is_lifetime, subscriptions.is_lifetime),
					   last_notification_type = excluded.last_notification_type,
					   last_subtype = excluded.last_subtype,
					   price_millis = COALESCE(excluded.price_millis, subscriptions.price_millis),
					   currency = COALESCE(excluded.currency, subscriptions.currency),
					   linked_token = COALESCE(excluded.linked_token, subscriptions.linked_token),
					   last_signed_date = excluded.last_signed_date,
					   updated_at = excluded.updated_at
					 WHERE excluded.last_signed_date >= subscriptions.last_signed_date`,
				)
				.bind(
					sub.purchaseToken,
					sub.productId,
					sub.status,
					sub.autoRenewStatus,
					sub.environment,
					sub.purchaseDate,
					sub.expiresDate,
					sub.isLifetime ? 1 : 0,
					nf.notificationType,
					nf.subtype,
					sub.priceMillis,
					sub.currency,
					nf.eventTime,
					nf.receivedAt,
					sub.linkedToken,
				),
		);

		// 升降级 / 重新订阅会换发 purchaseToken：把被顶替的旧行落幕，
		// 否则「活跃权益」会把同一个用户数两次。已退款 / 已撤销的不动。
		if (sub.linkedToken) {
			statements.push(
				db
					.prepare(
						`UPDATE subscriptions SET status = 'expired', updated_at = ?
						 WHERE original_transaction_id = ? AND platform = 'play'
						   AND status NOT IN ('refunded', 'revoked', 'expired')`,
					)
					.bind(nf.receivedAt, sub.linkedToken),
			);
		}
	}

	const results = await db.batch(statements);
	const duplicate = (results[0]?.meta?.changes ?? 0) === 0;

	return {
		duplicate,
		notificationType: nf.notificationType,
		messageId: nf.notificationUuid,
		transactionRecorded: Boolean(tx),
		subscriptionUpdated: Boolean(sub),
	};
}
