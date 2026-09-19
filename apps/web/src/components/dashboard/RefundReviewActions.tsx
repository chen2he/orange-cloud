"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

type Decision = "GRANT_FULL" | "GRANT_PRORATED" | "DECLINE" | "NONE";

const OPTIONS: { value: Decision; label: string; tone: string }[] = [
	{ value: "GRANT_FULL", label: "全额退", tone: "bg-positive/12 text-positive" },
	{ value: "GRANT_PRORATED", label: "按比例", tone: "bg-accent/12 text-accent" },
	{ value: "DECLINE", label: "拒绝", tone: "bg-negative/12 text-negative" },
	{ value: "NONE", label: "不表态", tone: "bg-foreground/[0.06] text-muted" },
];

// Apple 退款申请的表态按钮：点一下即发给 Apple（只能回应一次），故先 confirm。
export default function RefundReviewActions({ uuid, suggested }: { uuid: string; suggested: Decision }) {
	const router = useRouter();
	const [busy, setBusy] = useState<Decision | "">("");
	const [err, setErr] = useState("");

	async function act(decision: Decision) {
		const label = OPTIONS.find((o) => o.value === decision)?.label;
		if (!confirm(`向 Apple 发送「${label}」？发出后不可更改。`)) return;
		setBusy(decision);
		setErr("");
		try {
			const r = await fetch("/api/admin/refund-reviews", {
				method: "POST",
				headers: { "content-type": "application/json" },
				body: JSON.stringify({ uuid, decision }),
			});
			if (!r.ok) {
				const j = (await r.json().catch(() => ({}))) as { error?: string };
				throw new Error(j.error === "closed" ? "已截止" : "发送失败");
			}
			router.refresh();
		} catch (e) {
			setErr(e instanceof Error ? e.message : "发送失败");
			setBusy("");
		}
	}

	return (
		<div className="flex flex-wrap items-center gap-1.5 whitespace-nowrap">
			{OPTIONS.map((o) => (
				<button
					key={o.value}
					type="button"
					onClick={() => act(o.value)}
					disabled={!!busy}
					className={`rounded-md px-2 py-1 text-[11px] font-medium transition-opacity hover:opacity-80 disabled:opacity-50 ${o.tone} ${
						o.value === suggested ? "ring-1 ring-current" : ""
					}`}
				>
					{busy === o.value ? "…" : o.label}
				</button>
			))}
			{err ? <span className="text-[11px] text-negative">{err}</span> : null}
		</div>
	);
}
