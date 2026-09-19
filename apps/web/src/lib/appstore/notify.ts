// 把一条 App Store Server Notification 转成 Bark 推送，让作者实时知道发生了什么。
// buildBarkMessage 是纯函数（可单测）；notifyAppleEvent 负责发送（无 key 则跳过）。

import { type BarkPush, sendBark } from "../notify/bark";
import type { DecodedNotification } from "./types";

// 「入账」通知类型：真正有钱进账的事件（新订阅 / 续期 / 买断 / 优惠兑换）。
// 退款、到期、续订开关、价格调整、退款申请等都不算入账——尤其 CONSUMPTION_REQUEST（退款申请）
// 会带上原购价（非 0），仅凭金额无法区分，必须靠类型闸门。
const REVENUE_TYPES = new Set<string>([
	"SUBSCRIBED",
	"DID_RENEW",
	"ONE_TIME_CHARGE",
	"OFFER_REDEEMED",
]);

// 通知类型 → 中文标签（带 emoji）。未知类型回退原始字符串。
const TYPE_LABEL: Record<string, string> = {
	SUBSCRIBED: "🎉 新订阅",
	DID_RENEW: "🔁 订阅续期",
	DID_CHANGE_RENEWAL_STATUS: "⚙️ 续订开关变更",
	DID_CHANGE_RENEWAL_PREF: "🔀 套餐变更",
	DID_FAIL_TO_RENEW: "⚠️ 续订失败",
	EXPIRED: "📕 订阅到期",
	GRACE_PERIOD_EXPIRED: "⌛ 宽限期结束",
	OFFER_REDEEMED: "🎟️ 优惠兑换",
	PRICE_INCREASE: "💱 价格调整",
	REFUND: "↩️ 退款",
	REFUND_DECLINED: "🚫 退款被拒",
	REFUND_REVERSED: "↪️ 退款撤销",
	REVOKE: "🔕 权益撤销",
	CONSUMPTION_REQUEST: "📨 退款申请",
	RENEWAL_EXTENDED: "📅 续订已延长",
	RENEWAL_EXTENSION: "📅 续订延长",
	ONE_TIME_CHARGE: "💰 买断购买",
	TEST: "🧪 测试通知",
};

// 商品 ID → 友好名。
const PRODUCT_LABEL: Record<string, string> = {
	"jiamin.chen.orange_cloud.pro.monthly": "Pro 月度",
	"jiamin.chen.orange_cloud.pro.yearly": "Pro 年度",
	"jiamin.chen.orange_cloud.pro.lifetime": "Pro 买断",
};

function formatPrice(price?: number, currency?: string): string | null {
	// Apple 的 price 为货币 milliunits（$19.99 → 19990）。
	if (typeof price !== "number" || !currency) return null;
	return `${(price / 1000).toFixed(2)} ${currency}`;
}

export interface BuiltMessage {
	title: string;
	body: string;
	group: string;
	isSandbox: boolean;
	/** Bark 推送级别：仅「入账且金额>0」的生产事件用 timeSensitive 穿透专注模式。 */
	level: NonNullable<BarkPush["level"]>;
}

/** 解码后的通知 → Bark 标题/正文（纯函数）。 */
export function buildBarkMessage(decoded: DecodedNotification): BuiltMessage {
	const { payload, transaction } = decoded;
	const type = payload.notificationType;
	const environment = payload.data?.environment ?? transaction?.environment ?? "Production";
	const isSandbox = environment === "Sandbox";

	const label = TYPE_LABEL[type] ?? `📣 ${type}`;
	const title = isSandbox ? `🧪 ${label}` : label;

	// 正文：subtype · 商品 · 价格 · storefront · 环境（缺的省略）。
	const parts: string[] = [];
	if (payload.subtype) parts.push(payload.subtype);
	if (transaction?.productId) {
		parts.push(PRODUCT_LABEL[transaction.productId] ?? transaction.productId);
	}
	const price = formatPrice(transaction?.price, transaction?.currency);
	if (price) parts.push(price);
	if (transaction?.storefront) parts.push(transaction.storefront);
	parts.push(environment);
	if (transaction?.offerIdentifier) parts.push(transaction?.offerIdentifier);

	// 入账（收入类型）且金额 > 0 才是「真金白银」，用 timeSensitive 穿透专注模式；
	// 其余生产事件用 active（正常提醒、不穿透），沙盒一律 passive（静默入列）。
	const isPaidRevenue =
		REVENUE_TYPES.has(type) && typeof transaction?.price === "number" && transaction.price > 0;
	const level: BuiltMessage["level"] = isSandbox ? "passive" : isPaidRevenue ? "timeSensitive" : "active";

	return {
		title,
		body: parts.join(" · "),
		group: !isSandbox ? "Orange Cloud IAP" : "[🧪]Orange Cloud IAP",
		isSandbox,
		level,
	};
}

/**
 * 构造并发送 Bark 推送。无 deviceKey（未配置）则静默跳过。
 * 供 webhook 在 ctx.waitUntil 里 fire-and-forget；发送失败仅记日志、不抛。
 */
export async function notifyAppleEvent(
	deviceKey: string | undefined,
	decoded: DecodedNotification,
	server?: string,
	/** 附加信息（如退款申请的规则建议）：追加到正文，可带点击跳转 url。 */
	extra?: { note?: string; url?: string },
): Promise<void> {
	if (!deviceKey) return;
	const msg = buildBarkMessage(decoded);
	const push: BarkPush = {
		title: msg.title,
		body: extra?.note ? `${msg.body}\n${extra.note}` : msg.body,
		...(extra?.url ? { url: extra.url } : {}),
		group: msg.group,
		icon: "https://o-c.do/icons/icon-64.png",
		// 级别在 buildBarkMessage 里决定：仅「入账且金额>0」穿透专注模式。
		level: msg.level,
		// 只有入账（== timeSensitive）才响，其余（退款申请 / 到期 / 沙盒…）一律静默。
		...(msg.level === "timeSensitive" ? { sound: "paymentsuccess" } : {}),
	};
	try {
		await sendBark(deviceKey, push, server);
	} catch (err) {
		console.error("[apple-notifications] bark push failed", err);
	}
}
