import { NextRequest, NextResponse } from "next/server";
import { getCloudflareContext } from "@opennextjs/cloudflare";
import { constructEvent, StripeSignatureError } from "@/lib/stripe/webhook";
import { createStripeCode, revokeByPaymentIntent } from "@/lib/codes/store";
import { sendCodeEmail, type EmailBinding } from "@/lib/notify/email";

// Stripe webhook 入口。安全边界 = HMAC 验签（STRIPE_WEBHOOK_SECRET）。
//
// 关键：微信 / 支付宝是「异步支付」—— checkout.session.completed 触发时可能仍 unpaid，
// 真正到账走 checkout.session.async_payment_succeeded。故只在 payment_status==='paid' 发码，
// 且两类事件都监听。退款 charge.refunded -> 撤销对应码。
//
// 在 Stripe Dashboard 配置 endpoint：https://o-c.do/api/stripe/webhook
//   勾选事件：checkout.session.completed / checkout.session.async_payment_succeeded / charge.refunded

export const dynamic = "force-dynamic";

interface CheckoutSessionObject {
	id: string;
	payment_status?: string;
	payment_intent?: string;
	amount_total?: number;
	currency?: string;
	customer_email?: string;
	customer_details?: { email?: string };
}

export async function POST(request: NextRequest): Promise<NextResponse> {
	const { env, ctx } = getCloudflareContext();
	const cfg = env as { STRIPE_WEBHOOK_SECRET?: string; EMAIL?: EmailBinding };

	// 必须用原始 body 验签（不能先 parse）。
	const raw = await request.text();
	let event;
	try {
		event = await constructEvent(raw, request.headers.get("stripe-signature"), cfg.STRIPE_WEBHOOK_SECRET ?? "");
	} catch (err) {
		if (!(err instanceof StripeSignatureError)) console.error("[stripe-webhook] verify error", err);
		return NextResponse.json({ error: "invalid signature" }, { status: 400 });
	}

	try {
		const db = env.IAP_DB;

		if (
			event.type === "checkout.session.completed" ||
			event.type === "checkout.session.async_payment_succeeded"
		) {
			const session = event.data.object as unknown as CheckoutSessionObject;
			if (session.payment_status === "paid") {
				const email = session.customer_details?.email ?? session.customer_email ?? null;
				const result = await createStripeCode(db, {
					sessionId: session.id,
					paymentIntent: session.payment_intent ?? null,
					amountTotal: session.amount_total ?? null,
					currency: session.currency ?? null,
					buyerEmail: email,
				});
				// 仅新生成时发邮件（幂等重投不重复发）；fire-and-forget，不阻塞对 Stripe 的 200。
				if (!result.duplicate && email) {
					ctx.waitUntil(sendCodeEmail(cfg.EMAIL, email, result.code));
				}
			}
		} else if (event.type === "charge.refunded") {
			// Stripe 对「部分退款」同样发 charge.refunded（refunded=false、amount_refunded < amount）。
			// 后台善意退一部分不该把买断码吊销：只有全额退款才撤销授权。
			const charge = event.data.object as {
				payment_intent?: string;
				refunded?: boolean;
				amount?: number;
				amount_refunded?: number;
			};
			const fullyRefunded =
				charge.refunded === true ||
				(typeof charge.amount === "number" &&
					typeof charge.amount_refunded === "number" &&
					charge.amount_refunded >= charge.amount);
			if (charge.payment_intent && fullyRefunded) {
				await revokeByPaymentIntent(db, charge.payment_intent);
			}
		}

		return NextResponse.json({ received: true });
	} catch (err) {
		// 存储 / 瞬时错误返回 5xx，让 Stripe 在重试窗口内重投（写入幂等，安全）。
		console.error("[stripe-webhook] handle error", err);
		return NextResponse.json({ error: "handler error" }, { status: 500 });
	}
}
