import { NextRequest, NextResponse } from "next/server";
import { getCloudflareContext } from "@opennextjs/cloudflare";
import { isApiAuthed } from "@/lib/admin/auth";
import { decideRefundReview, type Preference, PREFERENCES } from "@/lib/appstore/refund-review";
import { serverApiConfig } from "@/lib/appstore/server-api";

// 后台对 Apple 退款申请（CONSUMPTION_REQUEST）表态，并立即经 Send Consumption Information 发给 Apple。
// body: { uuid: notification_uuid, decision: GRANT_FULL | GRANT_PRORATED | DECLINE | NONE }
//   200 已发送；409 已发送 / 已过 12h 截止；404 无此申请；502 Apple 拒收或未配置密钥（cron 会在截止前重试）
export const dynamic = "force-dynamic";

export async function POST(request: NextRequest): Promise<NextResponse> {
	const { env } = getCloudflareContext();
	if (!(await isApiAuthed(request, (env as { ADMIN_PASSWORD?: string }).ADMIN_PASSWORD))) {
		return NextResponse.json({ error: "unauthorized" }, { status: 401 });
	}

	let body: { uuid?: unknown; decision?: unknown };
	try {
		body = (await request.json()) as typeof body;
	} catch {
		return NextResponse.json({ error: "bad_request" }, { status: 400 });
	}
	const uuid = typeof body.uuid === "string" ? body.uuid : "";
	const decision = body.decision as Preference;
	if (!uuid || !PREFERENCES.includes(decision)) {
		return NextResponse.json({ error: "bad_request" }, { status: 400 });
	}

	const result = await decideRefundReview(env.IAP_DB, serverApiConfig(env), uuid, decision);
	switch (result) {
		case "sent":
			return NextResponse.json({ ok: true });
		case "not_found":
			return NextResponse.json({ error: "not_found" }, { status: 404 });
		case "closed":
			return NextResponse.json({ error: "closed" }, { status: 409 });
		default:
			return NextResponse.json({ error: "send_failed" }, { status: 502 });
	}
}
