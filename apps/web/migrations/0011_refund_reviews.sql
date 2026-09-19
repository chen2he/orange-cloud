-- 退款审核（Apple CONSUMPTION_REQUEST → Send Consumption Information）。
--
-- 顾客向 Apple 申请退款时，Apple 推 CONSUMPTION_REQUEST；开发者可在 12 小时内
-- PUT /inApps/v2/transactions/consumption/{transactionId} 回传使用情况与退款倾向。
-- 一条通知一行（Apple 可能对同一笔交易多次发起），决策按 transaction_id 作用于全部待发行。
--
-- status 流转：pending →（管理员决定即发 / cron 在 10h 后按规则默认发）→ sent
--             发送失败留 pending 并累计 attempts，超过 12h 截止仍未成功 → expired。
CREATE TABLE IF NOT EXISTS refund_reviews (
	notification_uuid       TEXT PRIMARY KEY,
	transaction_id          TEXT NOT NULL,
	original_transaction_id TEXT,
	product_id              TEXT,
	product_type            TEXT,            -- "Auto-Renewable Subscription" / "Non-Consumable"
	environment             TEXT,            -- Production / Sandbox
	reason                  TEXT,            -- consumptionRequestReason
	price_millis            INTEGER,
	currency                TEXT,
	storefront              TEXT,
	purchase_date           INTEGER,         -- 被申请退款的那笔交易的扣款时间（ms）
	requested_at            INTEGER NOT NULL, -- 通知 signedDate（ms）
	deadline_at             INTEGER NOT NULL, -- requested_at + 12h
	suggested               TEXT NOT NULL,   -- 规则默认：GRANT_FULL / DECLINE / GRANT_PRORATED / NONE（不表态）
	suggested_reason        TEXT,            -- 规则命中说明（给后台看）
	decision                TEXT,            -- 管理员选择（NULL = 未决定，走 suggested）
	decided_by              TEXT,            -- admin / auto
	status                  TEXT NOT NULL DEFAULT 'pending', -- pending / sent / expired
	attempts                INTEGER NOT NULL DEFAULT 0,
	last_error              TEXT,
	sent_at                 INTEGER,
	sent_body               TEXT,            -- 实际发给 Apple 的 JSON（审计）
	outcome                 TEXT,            -- 之后收到的 REFUND / REFUND_DECLINED
	outcome_at              INTEGER,
	created_at              INTEGER NOT NULL,
	updated_at              INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_refund_reviews_status ON refund_reviews (status, requested_at);
CREATE INDEX IF NOT EXISTS idx_refund_reviews_txn ON refund_reviews (transaction_id);
