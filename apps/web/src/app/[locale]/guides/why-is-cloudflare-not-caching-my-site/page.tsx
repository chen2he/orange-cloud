import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { setRequestLocale } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import GuideShell, { type RelatedLink } from "@/components/guides/GuideShell";
import CacheDecision from "@/components/guides/CacheDecision";
import { guideBySlug, GUIDE_LOCALE } from "@/lib/guides/guides";

const SITE_URL = "https://o-c.do";
const guide = guideBySlug("why-is-cloudflare-not-caching-my-site");
const PATH = `/guides/${guide.slug}`;

const DOCS_STATUSES = "https://developers.cloudflare.com/cache/concepts/cache-responses/";
const DOCS_UNCACHED = "https://developers.cloudflare.com/cache/troubleshooting/investigating-uncached-responses/";
const DOCS_DEFAULTS = "https://developers.cloudflare.com/cache/concepts/default-cache-behavior/";
const DOCS_RULES = "https://developers.cloudflare.com/cache/how-to/cache-rules/";
const DOCS_KEYS = "https://developers.cloudflare.com/cache/how-to/cache-keys/";
const DOCS_ORIGIN_CC = "https://developers.cloudflare.com/cache/concepts/cache-control/";
const DOCS_CDNCC = "https://developers.cloudflare.com/cache/concepts/cdn-cache-control/";
const DOCS_DEV_MODE = "https://developers.cloudflare.com/cache/reference/development-mode/";
const DOCS_TRACE = "https://developers.cloudflare.com/rules/trace-request/";
const DOCS_TIERED = "https://developers.cloudflare.com/cache/how-to/tiered-cache/";
const DOCS_BYPASS_CHANGE =
	"https://developers.cloudflare.com/changelog/post/2026-05-26-bypass-status-for-uncacheable-responses/";

/** FAQ 一处定义：可见文本与 FAQPage JSON-LD 同源，保证逐字一致 */
const FAQ: Array<{ q: string; a: string }> = [
	{
		q: "What does cf-cache-status: DYNAMIC mean?",
		a: "It means Cloudflare decided the request was not eligible for caching before it ever looked in the cache, so the request went straight to your origin. The usual reason is that the file extension is not one Cloudflare caches by default \u2014 HTML and JSON are not \u2014 and no Cache Rule says otherwise.",
	},
	{
		q: "What is the difference between DYNAMIC and BYPASS?",
		a: "Timing. DYNAMIC is decided at request time, from the URL and your rules, before the cache is consulted at all. BYPASS is decided at response time: the request was eligible, but something your origin returned \u2014 a Set-Cookie header, a no-store directive, an oversized body \u2014 made the response unstorable. DYNAMIC is usually fixed in Cloudflare, BYPASS on your server.",
	},
	{
		q: "What is the difference between BYPASS and MISS in Cloudflare?",
		a: "BYPASS means Cloudflare refused to store the response. MISS means the response was cacheable and simply was not in that data center's cache yet, so the next request to the same location should be a HIT. A MISS that never becomes a HIT is a third problem, and it is almost always the cache key.",
	},
	{
		q: "Why is Cloudflare not caching my site?",
		a: "Most likely because nothing is broken. Cloudflare judges eligibility by file extension, and HTML is deliberately excluded from the default list, so pages are served from your origin and report DYNAMIC until you add a Cache Rule that marks them eligible for cache and gives them an edge TTL.",
	},
	{
		q: "Why does Cloudflare keep returning MISS on every request?",
		a: "Almost always because each request produces a different cache key. Query strings count toward the key by default, so tracking parameters, session IDs, or timestamps split one asset into thousands of entries that are never requested twice. Low-traffic assets can also be evicted between requests.",
	},
];

const RELATED: RelatedLink[] = [
	{
		href: "/guides/cloudflare-block-ai-crawlers",
		label: "How do you block AI crawlers on Cloudflare?",
		note: "Uncached crawler traffic lands on your origin — which is why cacheability and crawler policy end up on the same bill.",
	},
	{
		href: "/guides/what-is-the-orange-cloud-in-cloudflare",
		label: "What does the orange cloud mean in Cloudflare?",
		note: "The prerequisite: nothing is cached at all on a record that is set to DNS only.",
	},
	{
		href: "/guides/cloudflare-ssl-tls-encryption-modes",
		label: "Which Cloudflare SSL/TLS encryption mode should you use?",
		note: "The mode decides the origin scheme, and the origin scheme is part of every cache key.",
	},
	{
		href: "/guides/cloudflare-purge-cache-not-working",
		label: "Why isn\u2019t my Cloudflare cache purge working?",
		note: "Once caching does work, the next question: why a purge can clear everything and change nothing.",
	},
	{
		href: DOCS_UNCACHED,
		label: "Cloudflare docs: Investigate uncached responses",
		note: "The official step-by-step diagnostic for DYNAMIC, BYPASS, and repeated MISS.",
		external: true,
	},
	{
		href: "/contact",
		label: "Something wrong on this page?",
		note: "Corrections and questions are welcome — we read every message.",
	},
];

export const metadata: Metadata = {
	metadataBase: new URL(SITE_URL),
	title: guide.title,
	description: guide.description,
	alternates: {
		canonical: PATH,
		languages: { en: PATH, "x-default": PATH },
	},
	openGraph: {
		title: guide.title,
		description: guide.description,
		url: PATH,
		siteName: "Orange Cloud",
		type: "article",
		locale: "en_US",
		images: [{ url: "/og/en.jpg", width: 1280, height: 640, alt: guide.h1 }],
	},
	twitter: {
		card: "summary_large_image",
		title: guide.title,
		description: guide.description,
		images: ["/og/en.jpg"],
	},
};

export default async function NotCachingGuide({ params }: { params: Promise<{ locale: string }> }) {
	const { locale } = await params;
	if (locale !== GUIDE_LOCALE) notFound();
	setRequestLocale(locale);

	const jsonLd = [
		{
			"@context": "https://schema.org",
			"@type": "TechArticle",
			headline: guide.h1,
			description: guide.description,
			url: `${SITE_URL}${PATH}`,
			inLanguage: "en",
			datePublished: guide.updated,
			dateModified: guide.updated,
			image: `${SITE_URL}/og/en.jpg`,
			author: { "@type": "Organization", name: "Orange Cloud", url: SITE_URL },
			publisher: { "@type": "Organization", name: "Orange Cloud", url: SITE_URL },
			mainEntityOfPage: { "@type": "WebPage", "@id": `${SITE_URL}${PATH}` },
		},
		{
			"@context": "https://schema.org",
			"@type": "FAQPage",
			mainEntity: FAQ.map((item) => ({
				"@type": "Question",
				name: item.q,
				acceptedAnswer: { "@type": "Answer", text: item.a },
			})),
		},
		{
			"@context": "https://schema.org",
			"@type": "BreadcrumbList",
			itemListElement: [
				{ "@type": "ListItem", position: 1, name: "Guides", item: `${SITE_URL}/guides` },
				{ "@type": "ListItem", position: 2, name: guide.h1, item: `${SITE_URL}${PATH}` },
			],
		},
	];

	return (
		<>
			<script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }} />
			<GuideShell
				title={guide.h1}
				lede="Putting a site behind a proxy does not make it a cached site. One response header names the decision Cloudflare made, at which moment it was made, and therefore which setting is worth changing."
				updated={guide.updated}
				readingTime={guide.readingTime}
				related={RELATED}
			>
				<div className="glass r-island note p-6 sm:p-7">
					<p>
						<code>cf-cache-status</code> names the cache decision. <code>DYNAMIC</code> means the request
						was never eligible — HTML and JSON are not cached by default. <code>BYPASS</code> means the
						origin response blocked storage. <code>MISS</code> means it was cacheable but not stored yet.
					</p>
				</div>

				<p>
					Ask why Cloudflare is not caching your site and the honest answer is usually that it is working as
					designed. The assumption underneath the question — that traffic routed through Cloudflare is cached
					traffic — is the part that is wrong. Static assets are cached by default, pages are not, and there
					are several distinct ways a response ends up served from your server, each with a different fix.
					Guessing between them is how people stack rules that cancel each other out.
				</p>

				<h2 id="read-the-header">Read the cf-cache-status header before changing any setting</h2>
				<p>
					Every proxied response carries this header, and it names the decision that was made. Tooling spells
					it inconsistently — <code>CF-Cache-Status</code> in Cloudflare&rsquo;s own documentation,{" "}
					<code>cf-cache-status</code> on the wire, plain cache status in most dashboards — but it is one
					header carrying one value per response. Fetch the URL and read it before touching anything:
				</p>
				<pre>
					<code>curl -sSI https://example.com/ | grep -iE &apos;^(cf-cache-status|age):&apos;</code>
				</pre>
				<p>
					The <code>Age</code> header is a useful companion, with one caveat. Cloudflare sets it on{" "}
					<code>HIT</code>, <code>STALE</code>, and <code>UPDATING</code> responses, reporting how many
					seconds the asset has been in cache since it was admitted or last revalidated. It is absent on{" "}
					<code>MISS</code>, <code>DYNAMIC</code>, <code>BYPASS</code>, and <code>NONE/UNKNOWN</code> — but
					if your origin sends its own <code>Age</code> on an uncacheable response, Cloudflare passes that
					value through unchanged. So <code>Age</code> corroborates <code>cf-cache-status</code>; it never
					substitutes for it. If both headers are absent entirely, the hostname is probably not proxied at
					all — see{" "}
					<Link href="/guides/what-is-the-orange-cloud-in-cloudflare">
						proxied vs DNS only
					</Link>{" "}
					for that case, because a DNS-only record never reaches a cache in the first place.
				</p>

				<h2 id="values">What each cf-cache-status value means</h2>
				<div className="table-wrap">
					<table>
						<thead>
							<tr>
								<th scope="col">Value</th>
								<th scope="col">What happened</th>
								<th scope="col">Served from</th>
							</tr>
						</thead>
						<tbody>
							<tr>
								<th scope="row">HIT</th>
								<td>The asset was in cache and still fresh</td>
								<td>Cache</td>
							</tr>
							<tr>
								<th scope="row">MISS</th>
								<td>Cacheable, but not present in this data center yet</td>
								<td>Origin</td>
							</tr>
							<tr>
								<th scope="row">DYNAMIC</th>
								<td>Judged not eligible for cache before any lookup happened</td>
								<td>Origin</td>
							</tr>
							<tr>
								<th scope="row">BYPASS</th>
								<td>Eligible, but the response itself could not be stored</td>
								<td>Origin</td>
							</tr>
							<tr>
								<th scope="row">EXPIRED</th>
								<td>A stale copy existed; fresh content was fetched</td>
								<td>Origin</td>
							</tr>
							<tr>
								<th scope="row">STALE</th>
								<td>Expired copy served because the origin could not be reached</td>
								<td>Cache</td>
							</tr>
							<tr>
								<th scope="row">REVALIDATED</th>
								<td>The origin confirmed the cached copy was unchanged</td>
								<td>Cache</td>
							</tr>
							<tr>
								<th scope="row">UPDATING</th>
								<td>Expired copy served while a refresh runs in the background</td>
								<td>Cache</td>
							</tr>
							<tr>
								<th scope="row">NONE/UNKNOWN</th>
								<td>The response was produced before cache was ever consulted</td>
								<td>Neither</td>
							</tr>
						</tbody>
					</table>
				</div>
				<p>
					That last row catches people out. A Worker that answers without a subrequest, a blocked WAF
					request, and a redirect rule all short-circuit ahead of the cache, so they are labelled{" "}
					<code>NONE/UNKNOWN</code> rather than describing a cache outcome at all. <code>REVALIDATED</code>{" "}
					is also rarer than it used to be: with asynchronous stale-while-revalidate, a refresh that once
					made the visitor wait now usually reports <code>UPDATING</code> or <code>HIT</code> instead. The
					full reference lives in the{" "}
					<a href={DOCS_STATUSES} target="_blank" rel="noopener noreferrer">
						cache responses documentation
					</a>
					.
				</p>

				<h2 id="two-decisions">DYNAMIC vs BYPASS: two decisions, not one</h2>
				<CacheDecision />
				<p>
					<code>DYNAMIC</code> and <code>BYPASS</code> both mean &ldquo;not cached&rdquo;, and they are
					routinely treated as the same problem. They are not. <code>DYNAMIC</code> is decided at{" "}
					<strong>request time</strong>, from the URL and your rules, before the cache is consulted.{" "}
					<code>BYPASS</code> is decided at <strong>response time</strong>, once your origin has answered and
					its headers have been read. One is fixed in your Cloudflare configuration; the other is usually
					fixed on your server.
				</p>

				<h2 id="dynamic">DYNAMIC: the request never reached the cache</h2>
				<p>Four causes account for nearly all of them:</p>
				<ul>
					<li>
						<strong>The extension is not on the default list.</strong> Eligibility is judged by file
						extension, not MIME type, and the{" "}
						<a href={DOCS_DEFAULTS} target="_blank" rel="noopener noreferrer">
							default list
						</a>{" "}
						covers images, fonts, archives, CSS, and JS — but deliberately excludes HTML and JSON, since
						pages and API responses are frequently personalised. A URL with no extension at all, such as{" "}
						<code>/pricing</code>, falls in the same bucket.
					</li>
					<li>
						<strong>A rule says bypass.</strong> A Cache Rule set to bypass, or a legacy configuration or
						page rule with cache level set to bypass, produces <code>DYNAMIC</code> for everything it
						matches. When several rules overlap,{" "}
						<a href={DOCS_TRACE} target="_blank" rel="noopener noreferrer">
							Rule Trace
						</a>{" "}
						shows which one actually applied instead of leaving you to reason about ordering.
					</li>
					<li>
						<strong>The method is not GET or HEAD.</strong> Nothing else is cached, so a page whose content
						arrives via POST cannot be cached no matter how it is configured.
					</li>
					<li>
						<strong>
							<a href={DOCS_DEV_MODE} target="_blank" rel="noopener noreferrer">
								Development Mode
							</a>{" "}
							is on.
						</strong>{" "}
						It suspends caching zone-wide for three hours and returns <code>DYNAMIC</code> for every
						response. It is the first thing to check when caching stopped working &ldquo;for no
						reason&rdquo; earlier today.
					</li>
				</ul>

				<h2 id="bypass">BYPASS: eligible, but the response said no</h2>
				<p>
					Here the request cleared eligibility and the answer from your origin is what prevented storage. The
					usual culprits:
				</p>
				<div className="table-wrap">
					<table>
						<thead>
							<tr>
								<th scope="col">In the response</th>
								<th scope="col">Why it blocks caching</th>
							</tr>
						</thead>
						<tbody>
							<tr>
								<th scope="row">
									<code>Set-Cookie</code>
								</th>
								<td>Treated as per-visitor by default, so the response is not stored</td>
							</tr>
							<tr>
								<th scope="row">
									<code>Cache-Control: no-store</code> or bare <code>private</code>
								</th>
								<td>Blocks storage regardless of plan or origin cache-control mode</td>
							</tr>
							<tr>
								<th scope="row">
									<code>Cache-Control: no-cache</code>, <code>max-age=0</code>
								</th>
								<td>
									On Free, Pro, and Business these produce revalidation rather than a bypass; with
									origin cache-control disabled, the default on Enterprise, they block it
								</td>
							</tr>
							<tr>
								<th scope="row">
									<code>Vary: *</code>
								</th>
								<td>Always bypasses, whatever else is configured</td>
							</tr>
							<tr>
								<th scope="row">
									<code>CDN-Cache-Control: no-store</code>
								</th>
								<td>
									Read ahead of <code>Cache-Control</code>, so it wins even when{" "}
									<code>Cache-Control</code> declares the response public and cacheable
								</td>
							</tr>
							<tr>
								<th scope="row">Body over the size limit</th>
								<td>512 MB on Free, Pro, and Business; 5 GB by default on Enterprise</td>
							</tr>
							<tr>
								<th scope="row">
									Request had <code>Authorization</code>
								</th>
								<td>
									With origin cache-control enabled, cacheable only if the response also carries{" "}
									<code>public</code>, <code>s-maxage</code>, or <code>must-revalidate</code>
								</td>
							</tr>
						</tbody>
					</table>
				</div>
				<p>
					Three of these are worth knowing precisely. First, the header Cloudflare actually obeys is not
					always the one you set: it reads{" "}
					<a href={DOCS_CDNCC} target="_blank" rel="noopener noreferrer">
						<code>Cloudflare-CDN-Cache-Control</code>, then <code>CDN-Cache-Control</code>
					</a>
					, and only then <code>Cache-Control</code> — so an origin returning{" "}
					<code>Cache-Control: public, max-age=3600</code> alongside <code>CDN-Cache-Control: no-store</code>{" "}
					bypasses cache, and the <code>Cache-Control</code> header you keep re-checking is the wrong one to
					look at. Second, whether <code>no-cache</code> blocks caching depends on{" "}
					<a href={DOCS_ORIGIN_CC} target="_blank" rel="noopener noreferrer">
						origin cache-control
					</a>
					, which is enabled by default on Free, Pro, and Business plans and disabled by default on
					Enterprise — so identical origin headers behave differently on different plans. Third, since{" "}
					<a href={DOCS_BYPASS_CHANGE} target="_blank" rel="noopener noreferrer">
						a change in May 2026
					</a>
					, responses Cloudflare refuses to cache report <code>BYPASS</code> consistently. Oversized files
					used to report <code>MISS</code> forever, which was indistinguishable from a broken cache. Older
					write-ups still describe the previous behaviour, and hit-rate figures from before and after the
					change are not comparable.
				</p>

				<h2 id="repeated-miss">Repeated MISS: the cache key keeps changing</h2>
				<p>
					A first <code>MISS</code> in each data center is normal — that request is what populates the cache.
					A URL that misses every time is a different symptom, and the cause is usually that no two requests
					share a{" "}
					<a href={DOCS_KEYS} target="_blank" rel="noopener noreferrer">
						cache key
					</a>
					. The key is built from the origin scheme, host, path, and query string, so:
				</p>
				<ul>
					<li>
						<strong>Query strings fragment the cache.</strong> Every distinct query string is its own
						entry. Campaign tags, session identifiers, and cache-busting timestamps turn one asset into
						thousands of entries that are each requested once. Cache Rules can ignore or allow-list
						specific parameters; sorting them only helps when the same parameters arrive in a different
						order.
					</li>
					<li>
						<strong>Custom keys can shard.</strong> Adding a cookie or header that varies per user to the
						key does exactly what you asked and gives every user a private copy.
					</li>
					<li>
						<strong>Vary multiplies entries.</strong> A high-cardinality header listed in the origin&rsquo;s{" "}
						<code>Vary</code> stores a separate variant per value, and the hit rate collapses.
					</li>
					<li>
						<strong>Low-traffic assets are evicted.</strong> If two consecutive requests to the same data
						center both miss,{" "}
						<a href={DOCS_TIERED} target="_blank" rel="noopener noreferrer">
							Tiered Cache
						</a>{" "}
						is the usual answer for long-tail content.
					</li>
				</ul>
				<p>
					Before concluding the cache is broken, confirm both test requests reached the same location: the
					last three characters of the <code>cf-ray</code> header identify the data center. Note also that
					the scheme in the key is the one used to reach your origin, not the one the visitor used, which is
					why{" "}
					<Link href="/guides/cloudflare-ssl-tls-encryption-modes">changing the encryption mode</Link> forces
					the cache to warm up again.
				</p>

				<h2 id="cache-html">Making pages cacheable on purpose</h2>
				<ol>
					<li>
						Add a{" "}
						<a href={DOCS_RULES} target="_blank" rel="noopener noreferrer">
							Cache Rule
						</a>{" "}
						matching the paths you want cached, with eligibility set to yes and an explicit edge TTL. The
						TTL matters: without one, the response falls back to whatever your origin&rsquo;s headers say.
					</li>
					<li>
						Exclude anything personalised — carts, dashboards, admin paths, anything gated by a session
						cookie — in the same rule expression rather than in a second rule bolted on afterwards.
					</li>
					<li>
						Decide what should happen to <code>Set-Cookie</code>. An edge TTL that ignores origin
						cache-control will strip it and cache the response, which is correct for anonymous pages and
						actively dangerous for personalised ones.
					</li>
					<li>
						Request the URL twice from the same client and confirm you see <code>HIT</code> with an{" "}
						<code>Age</code> that climbs. A single request cannot tell you anything.
					</li>
				</ol>
				<p>
					Cache behaviour is revised more often than most Cloudflare settings — the bypass reporting change
					above landed in 2026 — so before relying on a specific row here, check the{" "}
					<a href={DOCS_UNCACHED} target="_blank" rel="noopener noreferrer">
						current troubleshooting reference
					</a>
					.
				</p>

				<h2 id="faq">FAQ</h2>
				{FAQ.map((item) => (
					<div key={item.q}>
						<h3>{item.q}</h3>
						<p>{item.a}</p>
					</div>
				))}
			</GuideShell>
		</>
	);
}
