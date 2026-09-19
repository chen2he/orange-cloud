import type { Metadata } from "next";
import { getTranslations, setRequestLocale } from "next-intl/server";
import SiteHeader from "@/components/SiteHeader";
import SiteFooter from "@/components/SiteFooter";

const EMAIL = "support@zhe.ltd";

export async function generateMetadata({
	params,
}: {
	params: Promise<{ locale: string }>;
}): Promise<Metadata> {
	const { locale } = await params;
	const t = await getTranslations({ locale, namespace: "contact" });
	return { title: `${t("title")} — Orange Cloud` };
}

export default async function ContactPage({ params }: { params: Promise<{ locale: string }> }) {
	const { locale } = await params;
	setRequestLocale(locale);
	const t = await getTranslations("contact");
	const cards = t.raw("cards") as Array<{ h: string; p: string }>;

	return (
		<div className="theme-light sky-band band-dawn dawn-glow flex min-h-screen flex-col overflow-x-clip">
			<SiteHeader />
			<main className="relative mx-auto w-full max-w-[760px] flex-1 px-6 pb-20 pt-32">
				<h1 className="f-display text-[34px] font-bold t-primary">{t("title")}</h1>
				<p className="mt-3 max-w-[52ch] text-[16px] leading-relaxed t-secondary">{t("intro")}</p>

				{/* 邮箱主卡：整卡点击直接拉起邮件 */}
				<a
					href={`mailto:${EMAIL}`}
					className="glass r-island mt-8 flex items-center gap-4 p-5 no-underline transition-transform duration-150 ease-out hover:scale-[1.01] active:scale-[0.99] sm:gap-5 sm:p-6"
				>
					<span
						className="flex h-12 w-12 flex-none items-center justify-center rounded-full text-white sm:h-14 sm:w-14"
						style={{ background: "var(--oc-orange)", boxShadow: "0 6px 18px rgba(244,129,32,0.32)" }}
					>
						<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
							<rect x="3" y="5" width="18" height="14" rx="2.5" />
							<path d="m3.5 7 7.3 5.1a2 2 0 0 0 2.4 0L20.5 7" />
						</svg>
					</span>
					<span className="min-w-0 flex-1">
						<span className="block text-[13px] t-secondary">{t("emailLabel")}</span>
						<span className="f-display block break-all text-[17px] font-semibold t-primary sm:text-[23px]">
							{EMAIL}
						</span>
					</span>
					<svg className="flex-none t-tertiary" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
						<path d="m9 6 6 6-6 6" />
					</svg>
				</a>
				<p className="mt-4 text-[13px] t-tertiary">{t("emailHint")}</p>

				{/* 引导卡：写什么 */}
				<div className="mt-12 grid gap-4 sm:grid-cols-3">
					{cards.map((card) => (
						<div key={card.h} className="glass r-island h-full p-5">
							<h2 className="text-[16px] font-semibold t-primary">{card.h}</h2>
							<p className="mt-2 text-[13.5px] leading-relaxed t-secondary">{card.p}</p>
						</div>
					))}
				</div>
			</main>
			<SiteFooter />
		</div>
	);
}
