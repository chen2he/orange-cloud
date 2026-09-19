import { NextRequest, NextResponse } from "next/server";
import { getCloudflareContext } from "@opennextjs/cloudflare";
import { PlayApi, PlayApiError } from "@/lib/play/api";
import { enrichNotification } from "@/lib/play/enrich";
import { buildLedgerRows } from "@/lib/play/logic";
import { notifyPlayEvent } from "@/lib/play/notify";
import { storeLedgerRows } from "@/lib/play/store";
import { PlayVerifyError, verifyPushRequest } from "@/lib/play/verify";
import type { PlayEnrichment, PubSubEnvelope } from "@/lib/play/types";

// Google Play Real-time Developer Notifications 入口 —— Play 在订阅 / 买断 /
// 退款事件时经 Cloud Pub/Sub 推来的 push 请求。
//
// 安全边界 = Pub/Sub 附带的 Google OIDC ID Token（公钥验签，无需保管密钥）+ 包名校验。
// 金额 / 状态要另外回查 Play Developer API，需要服务账号私钥（PLAY_SA_JSON）；
// 未配置时仍记录事件，只是没有金额（看板会显示为无价交易）。
//
// 返回码约定（Pub/Sub 对任何非 2xx 都会退避重投递）：
//   400 信封坏了（重投也没用，但 Pub/Sub 仍会重试，最终进死信 / 过期）
//   401 验签失败
//   200 处理成功（含重复投递）
//   503 未配置 / 富化遇到瞬时故障（故意让 Pub/Sub 重投递以补齐金额）
//
// 配置见 README「Google Play 入账」：GCP topic + push 订阅（带 OIDC）、
// Play Console 绑定 topic、wrangler secret 注入 PLAY_* 三个值。

export const dynamic = "force-dynamic";

const PACKAGE_NAME = "jiamin.chen.orangecloud";

interface PlayEnv {
	PLAY_PUSH_AUDIENCE?: string;
	PLAY_PUSH_SA_EMAIL?: string;
	PLAY_SA_JSON?: string;
	BARK_KEY?: string;
	BARK_SERVER?: string;
}

export async function POST(request: NextRequest): Promise<NextResponse> {
	const { env, ctx } = getCloudflareContext();
	const cfg = env as CloudflareEnv & PlayEnv;

	// 未配置 audience 一律 fail-closed：宁可不收，也不裸奔接受任何 POST。
	// 服务账号邮箱同样必须配置：只验 aud 的话，任何 Google 账号都能对本端点 URL 签一枚
	// OIDC token（gcloud auth print-identity-token --audiences=…）往账本里塞 play 行。
	if (!cfg.PLAY_PUSH_AUDIENCE || !cfg.PLAY_PUSH_SA_EMAIL) {
		return NextResponse.json({ error: "not configured" }, { status: 503 });
	}

	let envelope: PubSubEnvelope;
	try {
		envelope = (await request.json()) as PubSubEnvelope;
	} catch {
		return NextResponse.json({ error: "bad json" }, { status: 400 });
	}

	let decoded;
	try {
		decoded = await verifyPushRequest(request.headers.get("authorization"), envelope, {
			audience: cfg.PLAY_PUSH_AUDIENCE,
			serviceAccountEmail: cfg.PLAY_PUSH_SA_EMAIL,
			packageName: PACKAGE_NAME,
		});
	} catch (err) {
		if (!(err instanceof PlayVerifyError)) {
			console.error("[play-notifications] unexpected verify error", err);
			return NextResponse.json({ error: "verify error" }, { status: 500 });
		}
		// 信封本身坏掉（不是签名问题）算 400，其余一律 401。
		const bad = /message\.data|message id|base64/i.test(err.message);
		return NextResponse.json({ error: err.message }, { status: bad ? 400 : 401 });
	}

	// 富化：拿金额 / 状态 / 地区。瞬时失败先照常入库，再用 503 换一次重投递补齐。
	let enrichment: PlayEnrichment = {};
	let retryForEnrichment = false;
	try {
		enrichment = await enrichNotification(
			PlayApi.from(cfg.PLAY_SA_JSON, PACKAGE_NAME),
			decoded,
		);
	} catch (err) {
		const retryable = err instanceof PlayApiError ? err.retryable : true;
		retryForEnrichment = retryable;
		console.error("[play-notifications] enrich failed", { retryable, err });
	}

	const rows = buildLedgerRows(decoded, enrichment);

	try {
		const result = await storeLedgerRows(env.IAP_DB, rows);

		// 入库成功后推一条 Bark（fire-and-forget）。重复投递跳过以免刷屏。
		if (!result.duplicate) {
			ctx.waitUntil(notifyPlayEvent(cfg.BARK_KEY, rows, cfg.BARK_SERVER));
		}

		if (retryForEnrichment) {
			return NextResponse.json(
				{ ok: true, stored: true, enriched: false, type: result.notificationType },
				{ status: 503 },
			);
		}
		return NextResponse.json(
			{ ok: true, duplicate: result.duplicate, type: result.notificationType },
			{ status: 200 },
		);
	} catch (err) {
		console.error("[play-notifications] store error", err);
		return NextResponse.json({ error: "storage error" }, { status: 500 });
	}
}
