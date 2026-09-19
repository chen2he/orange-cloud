import { Suspense } from "react";
import Image from "next/image";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { getCloudflareContext } from "@opennextjs/cloudflare";
import { Filters } from "@/components/dashboard/Filters";
import {
	ChartsSection,
	ExpiringSection,
	NotificationsSection,
	OverviewSection,
	RanksSection,
	TransactionsSection,
} from "@/components/dashboard/panels/sections";
import {
	ChartsSkeleton,
	KpiSkeleton,
	RanksSkeleton,
	TableCardSkeleton,
} from "@/components/dashboard/panels/skeletons";
import { CodesSection } from "@/components/dashboard/panels/CodesSection";
import { RefundReviewsSection } from "@/components/dashboard/panels/RefundReviewsSection";
import { TimezoneToggle, UpdatedAt } from "@/components/dashboard/prefs";
import { SESSION_COOKIE, verifySessionToken } from "@/lib/admin/auth";
import { parseFilters, parsePage } from "@/lib/dashboard/types";

// 无 force-dynamic：读取会话 cookie（next/headers）即令本路由动态渲染，
// 每次请求实时读 D1，构建期不会预渲染（D1 / cookie 在构建期不可用）。

type SearchParams = Record<string, string | string[] | undefined>;

export default async function AdminDashboardPage({
	searchParams,
}: {
	searchParams: Promise<SearchParams>;
}) {
	// 鉴权沿用既有口令 / 签名会话逻辑（仅把读 cookie 的方式换成 next/headers，
	// 验签仍走 lib/admin/auth 的 verifySessionToken）。未登录 -> /admin/login。
	const { env } = await getCloudflareContext({ async: true });
	const token = (await cookies()).get(SESSION_COOKIE)?.value;
	if (!token || !(await verifySessionToken(token, env.ADMIN_PASSWORD ?? ""))) {
		redirect("/admin/login");
	}

	const sp = await searchParams;
	const filters = parseFilters(sp);
	const notifPage = parsePage(sp, "notif_page");
	const txPage = parsePage(sp, "tx_page");

	// Current single-valued params, used to build pagination links that
	// preserve the active filters and the other list's page cursor.
	const linkParams = new URLSearchParams();
	for (const [k, v] of Object.entries(sp)) {
		if (typeof v === "string") linkParams.set(k, v);
	}
	const query = linkParams.toString();

	// Suspense keys: sections keyed on the filter signature re-suspend (show a
	// skeleton) when filters change; the table sections also include their page
	// cursor, so paginating shows a skeleton for just that table.
	const filterKey = `${filters.productId ?? "all"}|${filters.days ?? "all"}`;

	return (
		<div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
			<header className="mb-6">
				<div className="flex flex-wrap items-center justify-between gap-3">
					<div className="flex items-center gap-2.5">
						<Image
							src="/icons/icon-64.png"
							alt=""
							width={20}
							height={20}
							className="h-5 w-5 rounded-[5px] shadow-sm"
						/>
						<h1 className="text-lg font-semibold tracking-tight">Orange Cloud · IAP 数据看板</h1>
					</div>
					<div className="flex items-center gap-3">
						<TimezoneToggle />
						<UpdatedAt ms={Date.now()} />
						<a
							href="/admin/logout"
							className="text-xs whitespace-nowrap text-muted transition-colors hover:text-foreground"
						>
							退出
						</a>
					</div>
				</div>
				<div className="mt-5">
					<Suspense fallback={<div className="h-14" />}>
						<Filters />
					</Suspense>
				</div>
			</header>

			<div className="flex flex-col gap-4">
				<Suspense key={`kpi-${filterKey}`} fallback={<KpiSkeleton />}>
					<OverviewSection filters={filters} />
				</Suspense>

				{/* Apple 退款申请（12h 内表态）—— 与筛选无关，静态 key。 */}
				<Suspense key="refund-reviews" fallback={<TableCardSkeleton title="Apple 退款申请" rows={3} />}>
					<RefundReviewsSection />
				</Suspense>

				{/* 激活码（安卓渠道）—— 与 Apple IAP 看板并列；与产品/天数筛选无关，静态 key。 */}
				<Suspense key="codes" fallback={<div className="h-40 rounded-xl border border-border bg-surface" />}>
					<CodesSection />
				</Suspense>

				<Suspense key={`charts-${filterKey}`} fallback={<ChartsSkeleton />}>
					<ChartsSection filters={filters} />
				</Suspense>

				{/* App Store 排名与产品/天数筛选无关，用静态 key（不随筛选重新挂起）。 */}
				<Suspense key="ranks" fallback={<RanksSkeleton />}>
					<RanksSection />
				</Suspense>

				<Suspense
					key={`tx-${filterKey}-${txPage}`}
					fallback={<TableCardSkeleton title="交易" rows={10} />}
				>
					<TransactionsSection filters={filters} page={txPage} query={query} />
				</Suspense>

				<Suspense
					key={`notif-${filterKey}-${notifPage}`}
					fallback={<TableCardSkeleton title="通知" rows={10} />}
				>
					<NotificationsSection filters={filters} page={notifPage} query={query} />
				</Suspense>

				<Suspense key={`exp-${filterKey}`} fallback={<TableCardSkeleton title="即将到期订阅" rows={5} />}>
					<ExpiringSection filters={filters} />
				</Suspense>
			</div>
		</div>
	);
}
