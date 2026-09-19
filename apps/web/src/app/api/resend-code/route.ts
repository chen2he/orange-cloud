import { NextRequest, NextResponse } from "next/server";
import { getCloudflareContext } from "@opennextjs/cloudflare";
import { claimRecoveryEmailSlot, findActiveCodesByEmail } from "@/lib/codes/store";
import { sendCodesRecoveryEmail, type EmailBinding } from "@/lib/notify/email";

// 找回激活码：按邮箱查该邮箱名下的有效码，重新发到「该邮箱」（只发给本人邮箱，不回显给请求方）。
// 反枚举：无论是否查到都回 ok（不泄露某邮箱是否有购买记录）。
export const dynamic = "force-dynamic";

export async function POST(request: NextRequest): Promise<NextResponse> {
	let body: { email?: unknown };
	try {
		body = (await request.json()) as typeof body;
	} catch {
		return NextResponse.json({ ok: false, reason: "bad_request" }, { status: 400 });
	}
	const email = typeof body.email === "string" ? body.email.trim() : "";
	if (!email || !email.includes("@")) {
		return NextResponse.json({ ok: false, reason: "bad_request" }, { status: 400 });
	}

	const { env, ctx } = getCloudflareContext();
	const cores = await findActiveCodesByEmail(env.IAP_DB, email);
	// 冷却期内重复请求静默吞掉（仍回 ok，不给请求方任何「有/没有」的信号）。
	if (cores.length > 0 && (await claimRecoveryEmailSlot(env.IAP_DB, email))) {
		const cfg = env as { EMAIL?: EmailBinding };
		ctx.waitUntil(sendCodesRecoveryEmail(cfg.EMAIL, email, cores));
	}
	// 始终回 ok（反枚举）
	return NextResponse.json({ ok: true });
}
