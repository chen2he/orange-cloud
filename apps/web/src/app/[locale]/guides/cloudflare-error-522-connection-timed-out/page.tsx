import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { setRequestLocale } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import GuideShell, { type RelatedLink } from "@/components/guides/GuideShell";
import Error522Path from "@/components/guides/Error522Path";
import { guideBySlug, GUIDE_LOCALE } from "@/lib/guides/guides";

const SITE_URL = "https://o-c.do";
const guide = guideBySlug("cloudflare-error-522-connection-timed-out");
const PATH = `/guides/${guide.slug}`;

const DOCS_5XX = "https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/";
const DOCS_520 = `${DOCS_5XX}error-520/`;
const DOCS_521 = `${DOCS_5XX}error-521/`;
const DOCS_522 = `${DOCS_5XX}error-522/`;
const DOCS_523 = `${DOCS_5XX}error-523/`;
const DOCS_524 = `${DOCS_5XX}error-524/`;
const DOCS_LIMITS = "https://developers.cloudflare.com/fundamentals/reference/connection-limits/";
const DOCS_RAY = "https://developers.cloudflare.com/fundamentals/reference/cloudflare-ray-id/";
const DOCS_ORIGIN_ANALYTICS = "https://developers.cloudflare.com/speed/origin-analytics/";
const DOCS_DNS_ONLY = "https://developers.cloudflare.com/dns/proxy-status/";
const DOCS_WORKERS_DOMAIN = "https://developers.cloudflare.com/workers/configuration/routing/custom-domains/";
const DOCS_FLAG =
	"https://developers.cloudflare.com/workers/configuration/compatibility-flags/#global-fetch-strictly-public";
const DOCS_ORIGIN_RULES = "https://developers.cloudflare.com/rules/origin-rules/";
const DOCS_PAGES_DOMAIN = "https://developers.cloudflare.com/pages/configuration/custom-domains/";
const CF_IPS = "https://www.cloudflare.com/ips/";

/** FAQ 一处定义：可见文本与 FAQPage JSON-LD 同源，保证逐字一致 */
const FAQ: Array<{ q: string; a: string }> = [
	{
		q: "What does Cloudflare error 522 mean?",
		a: "It means Cloudflare tried to reach your origin server over TCP and got no usable answer in time. Either the connection did not complete within 19 seconds, or an established connection produced no acknowledgement of the request within 90 seconds.",
	},
	{
		q: "How do I fix a 522 connection timed out error?",
		a: "Start at the origin firewall. Confirm that every address in Cloudflare's published IP ranges is allowed through, then confirm the origin is running and that the address in your DNS record is still the one your hosting provider has assigned to the server.",
	},
	{
		q: "What is the difference between Cloudflare error 521 and error 522?",
		a: "521 is a refusal and 522 is a silence. Cloudflare documents 521 as the origin refusing its connections, and 522 as Cloudflare timing out while contacting the origin, so a firewall that rejects packets tends to produce 521 while one that drops them produces 522.",
	},
	{
		q: "Is error 522 the same as a 502 bad gateway?",
		a: "No. A 502 is a standard HTTP status that any server or proxy can return, while error code 522 is specific to Cloudflare and always describes the Cloudflare-to-origin hop. A 502 on a proxied site usually came from your own stack rather than from Cloudflare.",
	},
	{
		q: "Can I get a 522 error on Cloudflare Workers or Pages?",
		a: "Yes. A Worker on a Custom Domain that fetches its own hostname returns 522, and a Pages project reached through a CNAME that does not point at a configured custom Pages domain can produce one too. In both cases the origin firewall is irrelevant.",
	},
];

const RELATED: RelatedLink[] = [
	{
		href: "/guides/cloudflare-error-524-a-timeout-occurred",
		label: "Cloudflare error 524: a timeout occurred",
		note: "The next timer on the same connection: the origin picked up, then never answered within the read timeout.",
	},
	{
		href: "/guides/cloudflare-error-521-web-server-is-down",
		label: "Cloudflare error 521: web server is down",
		note: "The refusal to this error's silence — same hop, same firewall, one word different in the rule.",
	},
	{
		href: "/guides/cloudflare-error-1000-dns-points-to-prohibited-ip",
		label: "Cloudflare error 1000: DNS points to prohibited IP",
		note: "The other error that comes from the origin address in your DNS record — this one because the address is Cloudflare's own.",
	},
	{
		href: "/guides/cloudflare-ssl-tls-encryption-modes",
		label: "Which Cloudflare SSL/TLS encryption mode should you use?",
		note: "Your encryption mode decides whether the origin needs to be listening on port 80 or port 443 — which decides what the firewall has to allow.",
	},
	{
		href: "/guides/what-is-the-orange-cloud-in-cloudflare",
		label: "What does the orange cloud mean in Cloudflare?",
		note: "Why a proxied record puts Cloudflare on the path at all, and what changes the moment you grey-cloud it for a test.",
	},
	{
		href: "/guides/cloudflare-real-visitor-ip-cf-connecting-ip",
		label: "Why do my server logs show Cloudflare\u2019s IP, not the visitor\u2019s?",
		note: "The same published IP ranges, used at the origin for the other half of the job — deciding which requests may claim a visitor address.",
	},
	{
		href: DOCS_522,
		label: "Cloudflare docs: Error 522",
		note: "The official cause and resolution list this guide reorganises. Check it before changing anything at the origin.",
		external: true,
	},
	{
		href: "/guides/cloudflare-error-codes",
		label: "Cloudflare error codes: 5xx vs 1xxx",
		note: "How to read any Cloudflare error code: which hop the range describes, and who fixes it.",
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

export default async function Error522Guide({ params }: { params: Promise<{ locale: string }> }) {
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
				lede="The page says connection timed out and nothing else. Here is which connection, which deadline it missed, and the order in which the possible causes are worth checking."
				updated={guide.updated}
				readingTime={guide.readingTime}
				related={RELATED}
			>
				<div className="glass r-island note p-6 sm:p-7">
					<p>
						<strong>Cloudflare error 522 means Cloudflare could not complete a connection to your origin
						server in time.</strong> Either no TCP handshake finished within 19 seconds, or an open
						connection produced no acknowledgement within 90. The usual cause is an origin firewall
						dropping Cloudflare&rsquo;s addresses.
					</p>
				</div>

				<p>
					The 522 page is generated at Cloudflare&rsquo;s edge, not by your application, which is why it
					appears with a{" "}
					<a href={DOCS_RAY} target="_blank" rel="noopener noreferrer">
						Ray ID
					</a>{" "}
					and none of your own error handling. That also narrows the problem usefully: the visitor reached
					Cloudflare without trouble, so whatever is broken sits on the second hop — between Cloudflare and
					your server. Nothing in your DNS provider, your CDN settings, or the visitor&rsquo;s network is
					implicated by an HTTP error 522.
				</p>

				<h2 id="where">Where a 522 error happens</h2>
				<Error522Path />
				<p>
					Cloudflare defines error 522 as timing out while contacting the origin web server, and{" "}
					<Link href="/guides/cloudflare-error-521-web-server-is-down">error 521</Link> as the origin{" "}
					<em>refusing</em> its connections. That difference is the most useful thing on this
					page. A firewall rule that rejects a packet sends something back, and Cloudflare reports 521; a
					rule that drops it sends nothing, so Cloudflare keeps retrying until the clock runs out and
					reports 522. Both are usually the same misconfiguration seen through different firewall policies.
				</p>

				<h2 id="deadlines">Two deadlines, one error code</h2>
				<p>
					The 522 errors Cloudflare returns come from two separate timers on the origin connection, and it
					is worth knowing which one you hit before you start changing things.
				</p>
				<div className="table-wrap">
					<table>
						<thead>
							<tr>
								<th scope="col">Stage</th>
								<th scope="col">What Cloudflare is waiting for</th>
								<th scope="col">Limit</th>
								<th scope="col">Error</th>
							</tr>
						</thead>
						<tbody>
							<tr>
								<th scope="row">Opening the connection</th>
								<td>A SYN+ACK in reply to its SYN, retried at 1, 1, 1, 1, 1, 2, 4 and 8 seconds</td>
								<td>19 s</td>
								<td>522</td>
							</tr>
							<tr>
								<th scope="row">Connection established</th>
								<td>An acknowledgement of the resource request it sent</td>
								<td>90 s</td>
								<td>522</td>
							</tr>
							<tr>
								<th scope="row">Request acknowledged</th>
								<td>The HTTP response itself — the Proxy Read Timeout</td>
								<td>125 s</td>
								<td>524</td>
							</tr>
						</tbody>
					</table>
				</div>
				<p>
					Neither of the 522 limits can be changed; only the 125-second read timeout is configurable, and
					only on Enterprise zones. The{" "}
					<a href={DOCS_LIMITS} target="_blank" rel="noopener noreferrer">
						connection limits reference
					</a>{" "}
					lists all of them together. In practice you can tell the two apart with a stopwatch: a page that
					fails after roughly twenty seconds never connected at all, while one that hangs for a minute and a
					half connected and then went quiet — a very different problem, usually load rather than filtering.
				</p>

				<h2 id="causes">The causes, in the order worth checking</h2>
				<p>Cloudflare&rsquo;s own list, ordered by how often it turns out to be the answer:</p>
				<ol>
					<li>
						<strong>Cloudflare IP addresses are blocked or rate limited at the origin</strong> — in{" "}
						<code>.htaccess</code>, <code>iptables</code>, or a firewall. Cloudflare calls this the most
						common cause. Rate limiting deserves its own mention: a rule that permits Cloudflare but
						throttles it will produce 522s that come and go with traffic, which is far harder to spot than
						a flat block.
					</li>
					<li>
						<strong>The origin is overloaded or offline</strong> and drops incoming requests rather than
						answering them.
					</li>
					<li>
						<strong>Keepalives are disabled at the origin.</strong> Cloudflare reuses open TCP connections
						to your server; when the origin refuses to hold them open, connections get reset under load.
					</li>
					<li>
						<strong>The address in your DNS record is stale</strong> — it no longer matches the IP your
						hosting provider has provisioned for the server. Worth checking after any migration.
					</li>
					<li>
						<strong>Packets are being dropped</strong> somewhere between Cloudflare and the origin. This is
						the residual case, and the one where a traceroute from the origin back to a Cloudflare address
						is the evidence your host will want.
					</li>
				</ol>
				<p>
					One nuance on the first item: which port has to be open depends on your encryption mode, because
					that is what decides whether Cloudflare connects to the origin over HTTP or HTTPS. If you are not
					sure which one your zone uses, see{" "}
					<Link href="/guides/cloudflare-ssl-tls-encryption-modes">
						which Cloudflare SSL/TLS encryption mode you should use
					</Link>
					.
				</p>

				<h2 id="platform">The 522s that have nothing to do with your firewall</h2>
				<p>
					Three documented cases produce a Cloudflare 522 with a perfectly healthy origin, and every generic
					checklist misses them:
				</p>
				<ul>
					<li>
						<strong>A Worker on a Custom Domain fetching its own hostname.</strong> Per the docs, a{" "}
						<code>fetch</code> from a Worker on a{" "}
						<a href={DOCS_WORKERS_DOMAIN} target="_blank" rel="noopener noreferrer">
							Custom Domain
						</a>{" "}
						back to that same hostname returns 522. Use a Route, target a different hostname, or enable
						the{" "}
						<a href={DOCS_FLAG} target="_blank" rel="noopener noreferrer">
							<code>global_fetch_strictly_public</code>
						</a>{" "}
						compatibility flag.
					</li>
					<li>
						<strong>A Pages project without a custom domain.</strong> If a CNAME points at a Pages project
						that has no{" "}
						<a href={DOCS_PAGES_DOMAIN} target="_blank" rel="noopener noreferrer">
							custom domain
						</a>{" "}
						configured for it, the request has nowhere valid to land.
					</li>
					<li>
						<strong>An Origin Rule pointing at a hostname that will not resolve.</strong>{" "}
						<a href={DOCS_ORIGIN_RULES} target="_blank" rel="noopener noreferrer">
							Origin Rules
						</a>{" "}
						override where a request is sent, so a rule aimed at a Worker route whose hostname is an A
						record on a reserved address such as <code>192.0.2.0</code> produces 522 no matter what your
						real origin is doing.
					</li>
				</ul>

				<h2 id="diagnose">Narrowing it down</h2>
				<ol>
					<li>
						<strong>Capture the details first.</strong> The error code, the exact URL, and the time with
						timezone are the three things Cloudflare tells you to hand your hosting provider; the Ray ID
						from the page makes the request findable in logs.
					</li>
					<li>
						<strong>Check whether it is everything or some paths.</strong> In the dashboard, open{" "}
						<strong>HTTP Traffic</strong> and add a filter on <em>Edge status code</em> for 522. Error
						analytics run on a 1% traffic sample, so treat the shape as the signal, not the counts.
					</li>
					<li>
						<strong>Allow the ranges rather than checking them.</strong> Cloudflare connects from{" "}
						<a href={CF_IPS} target="_blank" rel="noopener noreferrer">
							its published IP ranges
						</a>
						, and those change over time. An allowlist that was complete two years ago may not be now.
					</li>
					<li>
						<strong>Request the origin directly.</strong> From a shell, connect to the origin address with
						the correct <code>Host</code> header. If it answers for you but not for Cloudflare, you are
						looking at a filter, not an outage — and the fact that it answers <em>you</em> is why an
						overloaded origin is so often misdiagnosed.
					</li>
					<li>
						<strong>Grey-cloud the record briefly.</strong> Setting it to{" "}
						<a href={DOCS_DNS_ONLY} target="_blank" rel="noopener noreferrer">
							DNS only
						</a>{" "}
						takes Cloudflare off the path: if the site is still unreachable, the origin is the problem.
						The record exposes your server&rsquo;s real address while it is grey, so change it back.
					</li>
					<li>
						<strong>Look at TCP failures per endpoint.</strong>{" "}
						<a href={DOCS_ORIGIN_ANALYTICS} target="_blank" rel="noopener noreferrer">
							Origin Analytics
						</a>{" "}
						reports connection failure rates by path, which separates a struggling endpoint from an origin
						that is unreachable outright.
					</li>
				</ol>

				<h2 id="neighbours">522 next to its neighbours</h2>
				<p>
					The 5xx family Cloudflare generates all describes the same hop, and the codes are easy to mix up:
				</p>
				<div className="table-wrap">
					<table>
						<thead>
							<tr>
								<th scope="col">Error</th>
								<th scope="col">What the origin did</th>
								<th scope="col">First move</th>
							</tr>
						</thead>
						<tbody>
							<tr>
								<th scope="row">
									<a href={DOCS_520} target="_blank" rel="noopener noreferrer">
										520
									</a>
								</th>
								<td>Answered, but with an empty, malformed or unexpected response</td>
								<td>Read the origin error log for crashes; check HTTP/2 support at the origin</td>
							</tr>
							<tr>
								<th scope="row">
									<a href={DOCS_521} target="_blank" rel="noopener noreferrer">
										521
									</a>
								</th>
								<td>Refused the connection outright</td>
								<td>Confirm the service is running and listening on the port your SSL mode requires</td>
							</tr>
							<tr>
								<th scope="row">
									<a href={DOCS_522} target="_blank" rel="noopener noreferrer">
										522
									</a>
								</th>
								<td>Said nothing at all, until the clock ran out</td>
								<td>Allow Cloudflare&rsquo;s IP ranges; check origin load</td>
							</tr>
							<tr>
								<th scope="row">
									<a href={DOCS_523} target="_blank" rel="noopener noreferrer">
										523
									</a>
								</th>
								<td>Could not be reached — no route to the address at all</td>
								<td>Verify the A record, and route tables between the network and Cloudflare</td>
							</tr>
							<tr>
								<th scope="row">
									<a href={DOCS_524} target="_blank" rel="noopener noreferrer">
										524
									</a>
								</th>
								<td>Accepted the request, then took too long to answer it</td>
								<td>Profile the slow request; move long jobs off the proxied hostname</td>
							</tr>
						</tbody>
					</table>
				</div>
				<p>
					A rough rule: 520 is a bad answer, 521 is a refusal, 522 is silence, 523 is no route, and 524 is
					slowness. If you administer more than one zone, the{" "}
					<a href={DOCS_5XX} target="_blank" rel="noopener noreferrer">
						5xx index
					</a>{" "}
					is worth a bookmark. And if the error you are actually seeing is a four-digit one, the cause is
					elsewhere entirely — see{" "}
					<Link href="/guides/cloudflare-error-1000-dns-points-to-prohibited-ip">
						error 1000, DNS points to prohibited IP
					</Link>
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
