import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { hasLocale, NextIntlClientProvider } from "next-intl";
import { getTranslations, setRequestLocale } from "next-intl/server";
import { routing } from "@/i18n/routing";
import "../globals.css";
import Script from "next/script";

const SITE_URL = "https://o-c.do";

const OG_LOCALES: Record<string, string> = {
	en: "en_US",
	"zh-Hans": "zh_CN",
	"zh-Hant": "zh_TW",
	"zh-HK": "zh_HK",
	ja: "ja_JP",
	"es-MX": "es_MX",
	ko: "ko_KR",
	"pt-BR": "pt_BR",
	"pt-PT": "pt_PT",
	de: "de_DE",
	fr: "fr_FR",
	ar: "ar_AR",
	tr: "tr_TR",
};

/** RTL 语言（ar）→ <html dir="rtl">，靠 CSS 逻辑属性自动镜像。 */
const RTL_LOCALES = new Set(["ar"]);

// 各语言社交分享图（晨昏横幅，1280×640）。生成：orange-cloud/appstore/render/og.mjs
const OG_IMAGES: Record<string, string> = {
	en: "/og/en.jpg",
	"zh-Hans": "/og/zh-Hans.jpg",
	"zh-Hant": "/og/zh-Hant.jpg",
	"zh-HK": "/og/zh-HK.jpg",
	ja: "/og/ja.jpg",
};

export function generateStaticParams() {
	return routing.locales.map((locale) => ({ locale }));
}

export async function generateMetadata({
	params,
}: {
	params: Promise<{ locale: string }>;
}): Promise<Metadata> {
	const { locale } = await params;
	if (!hasLocale(routing.locales, locale)) notFound();
	const t = await getTranslations({ locale, namespace: "meta" });
	const path = locale === routing.defaultLocale ? "/" : `/${locale}`;
	const ogImage = OG_IMAGES[locale] ?? OG_IMAGES.en;

	return {
		metadataBase: new URL(SITE_URL),
		title: t("title"),
		description: t("description"),
		alternates: {
			canonical: path,
			languages: {
				en: "/",
				"zh-Hans": "/zh-Hans",
				"zh-Hant": "/zh-Hant",
				"zh-HK": "/zh-HK",
				ja: "/ja",
				"es-MX": "/es-MX",
				ko: "/ko",
				"pt-BR": "/pt-BR",
				"pt-PT": "/pt-PT",
				de: "/de",
				fr: "/fr",
				ar: "/ar",
				tr: "/tr",
				"x-default": "/",
			},
		},
		// Bing Webmaster 站点验证。App Router 里 next/head 不渲染，必须走 metadata。
		verification: { other: { "msvalidate.01": "D37E43E607B99CBD72EB0FAFBB58FF89" } },
		icons: {
			icon: [
				{ url: "/icons/icon-32.png", sizes: "32x32", type: "image/png" },
				{ url: "/icons/icon-64.png", sizes: "64x64", type: "image/png" },
			],
			apple: "/icons/icon-180.png",
		},
		openGraph: {
			title: t("title"),
			description: t("description"),
			url: path,
			siteName: "Orange Cloud",
			type: "website",
			locale: OG_LOCALES[locale],
			images: [{ url: ogImage, width: 1280, height: 640, alt: t("title") }],
		},
		twitter: {
			card: "summary_large_image",
			title: t("title"),
			description: t("description"),
			images: [ogImage],
		},
		itunes: {
			appId: "6779323783",
		},
		keywords: t("keywords").split(",").map((keyword: string) => keyword.trim()),
	};
}

export default async function LocaleLayout({
	children,
	params,
}: {
	children: React.ReactNode;
	params: Promise<{ locale: string }>;
}) {
	const { locale } = await params;
	if (!hasLocale(routing.locales, locale)) {
		notFound();
	}
	setRequestLocale(locale);
	const t = await getTranslations({ locale, namespace: "meta" });

	// SoftwareApplication 结构化数据：仅 Bing/Copilot 走索引富化路径确认有效，
	// LLM 检索本身不解析 JSON-LD，保持单处、最小字段即可。
	const jsonLd = {
		"@context": "https://schema.org",
		"@type": "SoftwareApplication",
		name: "Orange Cloud",
		operatingSystem: "iOS 17.0+ / Android 9+",
		applicationCategory: "DeveloperApplication",
		description: t("description"),
		url: SITE_URL,
		downloadUrl: "https://apps.apple.com/app/id6779323783",
		offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
		author: {
			"@type": "Person",
			name: "chen2he",
			url: "https://github.com/chen2he",
		},
		sameAs: ["https://github.com/chen2he/orange-cloud"],
	};

	return (
		<html lang={locale} dir={RTL_LOCALES.has(locale) ? "rtl" : "ltr"}>
			<body className="antialiased">
				{/* Cloudflare Web Analytics 信标。以前包在 next/head 里，App Router 会整块丢弃、页面上从没出现过。 */}
				<Script
					strategy="afterInteractive"
					src="https://static.cloudflareinsights.com/beacon.min.js"
					data-cf-beacon='{"token": "dfe9d89898c447bea839ca39f7769bae"}'
				/>
				<script
					type="application/ld+json"
					dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
				/>
				<NextIntlClientProvider>{children}</NextIntlClientProvider>
			</body>
		</html>
	);
}
