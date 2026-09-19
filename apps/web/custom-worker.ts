// OpenNext 生成的 .open-next/worker.js 只导出 fetch（+ 缓存层的 Durable Object 类），
// 没有 scheduled 处理器，故直接给 wrangler.jsonc 加 cron 触发后无处理器可调。
// 按 OpenNext 官方 custom-worker 方案（https://opennext.js.org/cloudflare/howtos/custom-worker）：
// 包一层入口 worker —— 复用生成的 fetch，补一个 scheduled() 跑每日榜单抓取，
// 并把 wrangler 的 main 指向本文件。沿用同一个 worker / 同一个 IAP_DB 绑定。

// @ts-ignore .open-next/worker.js 在 `opennextjs-cloudflare build` 时生成
import { default as handler } from "./.open-next/worker.js";
import { captureRanks } from "./src/lib/ranks/capture";
import { syncIndexNow } from "./src/lib/indexnow/sync";
import { sweepRefundReviews } from "./src/lib/appstore/refund-review";
import { serverApiConfig } from "./src/lib/appstore/server-api";

// wrangler.jsonc triggers.crons 里的两条：每日任务 + 半小时一次的退款申请兜底。
const DAILY_CRON = "0 8 * * *";

export default {
	fetch: handler.fetch,

	// 每天 UTC 08:00：
	//   ① 抓 App Store 各地区榜单名次入 D1；
	//   ② 把有变更的页面推给 IndexNow（Bing 等），只推与台账版本不一致的 URL。
	// 每 30 分钟：
	//   ③ Apple 退款申请兜底 —— 收到满 10h 仍未表态的按规则默认发给 Apple，失败的在 12h 截止前重试。
	async scheduled(controller, env, ctx) {
		if (controller.cron === DAILY_CRON) {
			ctx.waitUntil(captureRanks(env.IAP_DB));
			ctx.waitUntil(syncIndexNow(env.IAP_DB).catch((err) => console.error("[indexnow] sync failed:", err)));
			return;
		}
		ctx.waitUntil(
			sweepRefundReviews(env.IAP_DB, serverApiConfig(env))
				.then((r) => {
					if (r.sent || r.failed || r.expired) console.log("[refund-review] sweep", r);
				})
				.catch((err) => console.error("[refund-review] sweep failed:", err)),
		);
	},
} satisfies ExportedHandler<CloudflareEnv>;

// 再导出生成 worker 的 Durable Object 类（OpenNext 缓存层用；全量再导出以兼容后续启用缓存）。
// @ts-ignore .open-next/worker.js 在 build 时生成
export { DOQueueHandler, DOShardedTagCache, BucketCachePurge } from "./.open-next/worker.js";
