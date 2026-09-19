import { NextRequest } from "next/server";
import { getCloudflareContext } from "@opennextjs/cloudflare";
import { BLANK_SVG, renderRankBadge } from "@/lib/ranks/badge";
import { fetchCountryRankCached } from "@/lib/ranks/capture";
import { bestFreshRank } from "@/lib/ranks/query";

// App Store 排名徽章（SVG），供 README 内嵌：
//   ?region=us  → 指定地区，「实时」查 Apple；有名次则展示，无名次（未上榜 / 未上架）返回空白图
//   无参         → 展示全地区「最好的」名次并标注区域（取自定时采集的库表，无法枚举全部商店故用追踪集）
// 无数据一律返回 1×1 透明空白图，README 不会出现裂图。整段 try/catch 兜底空白图。
// 响应 public 缓存：camo / 边缘代为缓存，实时分支对 Apple 的请求被压到每地区约每小时一次。
export const dynamic = "force-dynamic";

// 无参「最好名次」取自库表，用更宽松的新鲜窗口：漏抓一天也不至于变空白。
const FRESH_DAYS = 7;

function svg(body: string, maxAge: number): Response {
	return new Response(body, {
		headers: {
			"content-type": "image/svg+xml; charset=utf-8",
			"cache-control": `public, max-age=${maxAge}`,
		},
	});
}

export async function GET(request: NextRequest): Promise<Response> {
	const { env } = getCloudflareContext();
	const region = request.nextUrl.searchParams.get("region")?.trim().toLowerCase();

	// 空白图短缓存（5 分钟）：首次有数据后 README 能较快翻出真实徽章。
	const blank = () => svg(BLANK_SVG, 300);

	try {
		let country: string;
		let position: number;

		if (region) {
			// 指定地区：实时查 Apple（支持任意商店，不止采集的 7 国）；未上榜 / 未上架 → 空白。
			if (!/^[a-z]{2}$/.test(region)) return blank();
			const parsed = await fetchCountryRankCached(region);
			if (!parsed || parsed.position == null) return blank();
			country = region;
			position = parsed.position;
		} else {
			// 无参：全地区「最好的」名次，取自定时采集库表（标注区域）。
			if (!env.IAP_DB) return blank();
			const row = await bestFreshRank(env.IAP_DB, FRESH_DAYS);
			if (!row) return blank();
			country = row.country;
			position = row.position;
		}

		const value = `${country.toUpperCase()} #${position}`;
		return svg(renderRankBadge({ label: "App Store", value }), 3600);
	} catch {
		// 实时请求失败 / 表尚未迁移 / 偶发查询错误：返回空白图，避免 README camo 缓存到裂图。
		return blank();
	}
}
