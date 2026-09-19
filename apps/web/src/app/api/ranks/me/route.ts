import { NextRequest, NextResponse } from "next/server";
import { getCloudflareContext } from "@opennextjs/cloudflare";
import { fetchCountryRankCached, type RankParsed } from "@/lib/ranks/capture";

// 访客所在地区的当前 App Store 排名（首页 ISR 缓存页 → 客户端 <HomeRankBadge> 挂载后请求本接口）。
//
// 访客地区是任意国家，而我们只「定时采集」7 个地区入库，库里查不到 DE 这类，
// 故这里不查库、直接「实时」请求 Apple 目录接口取访客所在地区的榜单：
//   1) 访客地区有榜单名次 → 展示该地区
//   2) 否则（接口有数据但未上榜 / 该地区未上架 404）→ 回落实时查 US
//   3) US 也未上榜 → ranked:false（首页不展示徽章）
//
// 浏览器侧 private/max-age=1800 缓存：同一访客 30 分钟内只打一次，限制对 Apple 的请求量。
export const dynamic = "force-dynamic";

const FALLBACK_COUNTRY = "us";

async function safeRank(country: string, waitUntil?: (p: Promise<unknown>) => void): Promise<RankParsed | null> {
	try {
		return await fetchCountryRankCached(country, waitUntil);
	} catch {
		return null;
	}
}

export async function GET(request: NextRequest): Promise<NextResponse> {
	const { cf, ctx } = getCloudflareContext();
	const waitUntil = ctx?.waitUntil ? (p: Promise<unknown>) => ctx.waitUntil(p) : undefined;

	// 地区来源：Cloudflare 的 cf.country / CF-IPCountry；?country= 仅供本地验证覆盖。
	const ipCountry = (cf?.country ?? request.headers.get("cf-ipcountry") ?? "").toLowerCase();
	const override = request.nextUrl.searchParams.get("country")?.toLowerCase();
	const visitor = override ?? ipCountry;

	const headers = { "cache-control": "private, max-age=1800" };
	const notRanked = NextResponse.json({ ranked: false }, { headers });

	// 1) 实时查访客所在地区（合法两位国家码才查）。
	let country = /^[a-z]{2}$/.test(visitor) ? visitor : "";
	let parsed = country ? await safeRank(country, waitUntil) : null;

	// 2) 访客地区无榜单数据（未上榜 / 未上架）→ 回落实时查 US（避免对 US 重复查）。
	if ((!parsed || parsed.position == null) && country !== FALLBACK_COUNTRY) {
		country = FALLBACK_COUNTRY;
		parsed = await safeRank(FALLBACK_COUNTRY, waitUntil);
	}

	// 3) US 也没上榜 → 不展示。
	if (!parsed || parsed.position == null) return notRanked;

	return NextResponse.json(
		{ ranked: true, country, position: parsed.position, genreName: parsed.genreName },
		{ headers },
	);
}
