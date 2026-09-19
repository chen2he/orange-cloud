import { Badge, Card, CardHead, EmptyState, EnvBadge } from "@/components/dashboard/ui";
import RefundReviewActions from "@/components/dashboard/RefundReviewActions";
import { getDb } from "@/lib/dashboard/db";
import { formatMoney, formatRelativeFuture, formatTimestamp } from "@/lib/dashboard/format";
import { listRefundReviews, PREFERENCE_LABEL, type RefundReviewRow } from "@/lib/appstore/refund-review";

// 后台「Apple 退款申请」：CONSUMPTION_REQUEST 入库后，在 12h 内对 Apple 表态。
// 未决定的在收到 10h 后由 cron 按「默认」列发送；这里可提前改。

const REASON_LABEL: Record<string, string> = {
	UNINTENDED_PURCHASE: "非本意购买",
	FULFILLMENT_ISSUE: "未收到 / 无法使用",
	UNSATISFIED_WITH_PURCHASE: "不满意",
	LEGAL: "法律原因",
	OTHER: "其他",
};

const PRODUCT_LABEL: Record<string, string> = {
	"jiamin.chen.orange_cloud.pro.monthly": "Pro 月度",
	"jiamin.chen.orange_cloud.pro.yearly": "Pro 年度",
	"jiamin.chen.orange_cloud.pro.lifetime": "Pro 买断",
};

function StatusCell({ row, now }: { row: RefundReviewRow; now: number }) {
	if (row.status === "sent") {
		const sent = row.decision ?? row.suggested;
		return (
			<div className="flex flex-col gap-1">
				<Badge tone="positive">已发送 · {PREFERENCE_LABEL[sent]}</Badge>
				<span className="text-[11px] text-muted">{row.decided_by === "admin" ? "手动" : "自动"} · {formatTimestamp(row.sent_at)}</span>
			</div>
		);
	}
	if (row.status === "expired") return <Badge tone="negative">已过期未发送</Badge>;
	return (
		<div className="flex flex-col gap-1">
			<Badge tone="accent">待发送 · {formatRelativeFuture(row.deadline_at, now)}截止</Badge>
			{row.last_error ? <span className="max-w-[28ch] text-[11px] text-negative">{row.last_error}</span> : null}
		</div>
	);
}

function OutcomeCell({ outcome }: { outcome: string | null }) {
	if (outcome === "REFUND") return <Badge tone="negative">已退款</Badge>;
	if (outcome === "REFUND_DECLINED") return <Badge tone="positive">已拒绝</Badge>;
	return <span className="text-muted">—</span>;
}

export async function RefundReviewsSection() {
	const db = await getDb();
	// 迁移 0011 未应用时容错显示空
	const rows = await listRefundReviews(db, 30).catch(() => [] as RefundReviewRow[]);
	const now = Date.now();
	const pending = rows.filter((r) => r.status === "pending").length;

	return (
		<Card>
			<div id="refund-reviews" />
			<CardHead
				title={pending > 0 ? `Apple 退款申请 · ${pending} 条待处理` : "Apple 退款申请"}
				hint="12 小时内向 Apple 表态；未处理的在 10 小时后按「默认」自动发送"
			/>
			{rows.length === 0 ? (
				<EmptyState label="暂无退款申请" />
			) : (
				<div className="scroll-area overflow-x-auto px-5 pt-3 pb-5">
					<table className="w-full text-sm">
						<thead>
							<tr className="border-b border-border text-left text-xs text-muted">
								<th className="py-2 pr-3 font-medium whitespace-nowrap">申请时间</th>
								<th className="py-2 pr-3 font-medium">商品</th>
								<th className="py-2 pr-3 font-medium">金额</th>
								<th className="py-2 pr-3 font-medium">原因</th>
								<th className="py-2 pr-3 font-medium">默认</th>
								<th className="py-2 pr-3 font-medium">状态</th>
								<th className="py-2 pr-3 font-medium">结果</th>
								<th className="py-2 font-medium">表态</th>
							</tr>
						</thead>
						<tbody>
							{rows.map((r) => (
								<tr key={r.notification_uuid} className="border-b border-border/60 align-top">
									<td className="py-2.5 pr-3 text-xs whitespace-nowrap text-muted">
										{formatTimestamp(r.requested_at)}
										<div className="mt-1">
											<EnvBadge env={r.environment} />
										</div>
									</td>
									<td className="py-2.5 pr-3 whitespace-nowrap">
										{PRODUCT_LABEL[r.product_id ?? ""] ?? r.product_id ?? "—"}
										<div className="font-mono text-[11px] text-muted">{r.transaction_id}</div>
									</td>
									<td className="py-2.5 pr-3 tabular-nums whitespace-nowrap">
										{r.currency ? formatMoney(r.price_millis, r.currency) : "—"}
										{r.storefront ? <div className="text-[11px] text-muted">{r.storefront}</div> : null}
									</td>
									<td className="py-2.5 pr-3 text-muted whitespace-nowrap">{REASON_LABEL[r.reason ?? ""] ?? r.reason ?? "—"}</td>
									<td className="max-w-[24ch] py-2.5 pr-3">
										<div className="font-medium">{PREFERENCE_LABEL[r.suggested]}</div>
										{r.suggested_reason ? <div className="text-[11px] text-muted">{r.suggested_reason}</div> : null}
									</td>
									<td className="py-2.5 pr-3">
										<StatusCell row={r} now={now} />
									</td>
									<td className="py-2.5 pr-3">
										<OutcomeCell outcome={r.outcome} />
									</td>
									<td className="py-2.5">
										{r.status === "pending" && r.deadline_at > now ? (
											<RefundReviewActions uuid={r.notification_uuid} suggested={r.suggested} />
										) : (
											<span className="text-muted">—</span>
										)}
									</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
		</Card>
	);
}
