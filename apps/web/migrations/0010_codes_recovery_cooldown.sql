-- 找回激活码邮件的发送冷却 + 邮箱查找的表达式索引。
--
-- /api/resend-code 没有任何凭证门槛，此前每次请求都会真发一封邮件：
-- 对着一个已知买家邮箱循环请求就是邮件轰炸（还烧 Email Service 配额与发件信誉）。
-- 记下最近一次发送时间，同一邮箱冷却期内只发一封（口径见 lib/codes/store.ts claimRecoveryEmailSlot）。
ALTER TABLE codes ADD COLUMN recovery_sent_at INTEGER;

-- 找回 / 绑定都按 LOWER(buyer_email) 查，普通列索引 idx_codes_email 用不上（全表扫）。
CREATE INDEX IF NOT EXISTS idx_codes_email_lower ON codes (LOWER(buyer_email));
