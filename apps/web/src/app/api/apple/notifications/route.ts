import { NextRequest, NextResponse } from "next/server";
import { getCloudflareContext } from "@opennextjs/cloudflare";
import { NotificationVerifyError, verifyNotification } from "@/lib/appstore/verify";
import { APPLE_FORWARD_URL, forwardRawNotification } from "@/lib/appstore/forward";
import { processNotification } from "@/lib/appstore/store";
import { notifyAppleEvent } from "@/lib/appstore/notify";
import {
	PREFERENCE_LABEL,
	recordConsumptionRequest,
	recordRefundOutcome,
	type Suggestion,
} from "@/lib/appstore/refund-review";
import type { DecodedNotification } from "@/lib/appstore/types";

// App Store Server Notifications V2 入口 —— Apple 服务器在购买 / 续订 / 退款 / 流失时
// 秒级推送的签名 webhook。POST body: { "signedPayload": "<JWS>" }。
//
// 安全边界 = JWS 验签（Apple 公钥链，无需任何 secret）。返回码约定：
//   400 缺 signedPayload；401 验签失败 / bundleId 不符；
//   200 处理成功（含未知类型、重复通知）；5xx 仅存储 / 瞬时错误（让 Apple 重试）。
//
// 配置：App Store Connect → App 信息 → App Store Server Notifications（Version 2），
//   Production / Sandbox URL 都填 https://o-c.do/api/apple/notifications

export const dynamic = "force-dynamic";

const EXPECTED_BUNDLE_ID = "jiamin.chen.orange-cloud";

export async function POST(request: NextRequest): Promise<NextResponse> {
	const { env, ctx } = getCloudflareContext();

	// 1) 取出 signedPayload。原始文本留着，验签通过后要原封不动转发一份出去。
	const rawBody = await request.text();
	let signedPayload: string | undefined;
	try {
		const body = JSON.parse(rawBody) as { signedPayload?: unknown };
		if (typeof body.signedPayload === "string") signedPayload = body.signedPayload;
	} catch {
		// 非 JSON 体 —— 落到下面的 400
	}
	if (!signedPayload) {
		return NextResponse.json({ error: "missing signedPayload" }, { status: 400 });
	}

	// 2) 验签 + 解码（外层通知 + 内层交易 / 续订）。任何验签失败一律 401，
	//    避免对伪造请求触发 5xx 重试风暴（真 Apple 通知不会走到这）。
	let decoded: DecodedNotification;
	try {
		decoded = await verifyNotification(signedPayload);
	} catch (err) {
		if (!(err instanceof NotificationVerifyError)) {
			console.error("[apple-notifications] unexpected verify error", err);
		}
		return NextResponse.json({ error: "invalid signature" }, { status: 401 });
	}

	// 3) bundleId 校验：拒绝非本 App 的通知
	const bundleId =
		decoded.payload.data?.bundleId ??
		decoded.payload.summary?.bundleId ??
		decoded.transaction?.bundleId;
	// 带交易的通知一定带 bundleId；缺失即视为伪造（TEST 等无交易通知可以没有）。
	if ((bundleId && bundleId !== EXPECTED_BUNDLE_ID) || (!bundleId && decoded.transaction)) {
		return NextResponse.json({ error: "unexpected bundleId" }, { status: 401 });
	}

	// 4) 原封不动转发一份给外部 webhook（fire-and-forget，不影响给 Apple 的响应）。
	//    放在验签之后，避免把伪造请求中继出去；重复通知照转，转发端自行去重。
	//    ASC_FORWARD_URL 可覆盖地址，置空字符串则停用。
	{
		const cfg = env as { ASC_FORWARD_URL?: string };
		const url = cfg.ASC_FORWARD_URL ?? APPLE_FORWARD_URL;
		if (url) {
			ctx.waitUntil(
				forwardRawNotification(rawBody, {
					url,
					contentType: request.headers.get("content-type"),
				}),
			);
		}
	}

	// 5) 入库。存储失败返回 5xx —— Apple 会在数日的重试窗口内重发（幂等安全）。
	try {
		const result = await processNotification(env.IAP_DB, decoded);

		// 5b) 退款审核：CONSUMPTION_REQUEST 入 refund_reviews（规则给默认倾向，等管理员或 cron 发给 Apple）；
		//     REFUND / REFUND_DECLINED 回填结果。两者都幂等；失败只记日志，不让 Apple 因此重试整条通知。
		let suggestion: Suggestion | null = null;
		try {
			suggestion = await recordConsumptionRequest(env.IAP_DB, decoded);
			await recordRefundOutcome(env.IAP_DB, decoded);
		} catch (err) {
			console.error("[apple-notifications] refund review error", err);
		}

		// 6) 入库成功后推一条 Bark 到作者 iPhone（fire-and-forget，不阻塞对 Apple 的 200）。
		//    跳过重复通知（Apple 会重发）以免刷屏；未配置 BARK_KEY 则静默跳过。
		//    BARK_KEY / 可选 BARK_SERVER 经 wrangler secret / .dev.vars 注入（不在生成的 env 类型里，故 cast）。
		if (!result.duplicate) {
			const cfg = env as { BARK_KEY?: string; BARK_SERVER?: string };
			const extra = suggestion
				? {
						note: `默认倾向：${PREFERENCE_LABEL[suggestion.preference]}（${suggestion.reason}）· 10 小时内可在后台改`,
						url: "https://o-c.do/admin#refund-reviews",
					}
				: undefined;
			ctx.waitUntil(notifyAppleEvent(cfg.BARK_KEY, decoded, cfg.BARK_SERVER, extra));
		}

		return NextResponse.json(
			{ ok: true, duplicate: result.duplicate, type: result.notificationType },
			{ status: 200 },
		);
	} catch (err) {
		console.error("[apple-notifications] store error", err);
		return NextResponse.json({ error: "storage error" }, { status: 500 });
	}
}
