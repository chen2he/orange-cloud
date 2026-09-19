import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { setRequestLocale } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import GuideShell, { type RelatedLink } from "@/components/guides/GuideShell";
import Error1000Loop from "@/components/guides/Error1000Loop";
import { guideBySlug, GUIDE_LOCALE } from "@/lib/guides/guides";

const SITE_URL = "https://o-c.do";
const guide = guideBySlug("cloudflare-error-1000-dns-points-to-prohibited-ip");
const PATH = `/guides/${guide.slug}`;

const DOCS_1000 =
	"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-1xxx-errors/error-1000/";
const DOCS_1002 =
	"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-1xxx-errors/error-1002/";
const DOCS_1003 =
	"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-1xxx-errors/error-1003/";
const DOCS_1014 =
	"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-1xxx-errors/error-1014/";
const DOCS_1XXX = "https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-1xxx-errors/";
const DOCS_HEADERS = "https://developers.cloudflare.com/fundamentals/reference/http-headers/";
const DOCS_SAAS = "https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/";
const DOCS_BYOIP = "https://developers.cloudflare.com/byoip/";
const CF_IPS = "https://www.cloudflare.com/ips/";

/** FAQ 一处定义：可见文本与 FAQPage JSON-LD 同源，保证逐字一致 */
const FAQ: Array<{ q: string; a: string }> = [
	{
		q: "What does Cloudflare error 1000 mean?",
		a: "It means Cloudflare was asked to forward a request to an address that belongs to Cloudflare. The proxy will not send traffic back into itself, so it stops the request and shows error 1000 instead of looping.",
	},
	{
		q: "How do I fix DNS points to prohibited IP?",
		a: "Find the address your proxied record hands to the proxy and replace it with your real origin. In most cases that is an A record holding a Cloudflare anycast address; ask your hosting provider for the server's actual IP address and put that in the record instead.",
	},
	{
		q: "What is the difference between Cloudflare error 1000 and error 1002?",
		a: "Both are described as DNS pointing to a prohibited IP, but 1002 is the narrower resolution-time case: a record whose value is a Cloudflare address or a wrong CNAME target. Error 1000 also covers request-time causes such as a reverse proxy at the origin, malformed proxy headers, and SaaS platforms running on Cloudflare's own IP ranges.",
	},
	{
		q: "Can Cloudflare error 1000 be caused by something other than my DNS records?",
		a: "Yes. A reverse proxy at your origin that forwards to the public hostname, an X-Forwarded-For header longer than 100 characters, two X-Forwarded-For headers, a client-supplied CF-Connecting-IP header, or an SNI mismatch at the origin will each produce it with the DNS record untouched.",
	},
	{
		q: "Why do I get error 1000 when my domain points to a SaaS platform?",
		a: "If that platform runs on Cloudflare and advertises its own IP ranges through Cloudflare's network, your record resolves into Cloudflare infrastructure. Until the platform creates a custom hostname for your domain on their side, Cloudflare treats it as a loop. The fix belongs to the provider, not to you.",
	},
];

const RELATED: RelatedLink[] = [
	{
		href: "/guides/cloudflare-error-1020-access-denied",
		label: "Cloudflare error 1020: access denied",
		note: "The other Access Denied page — deliberate rather than misconfigured, which is what separates the two.",
	},
	{
		href: "/guides/what-is-the-orange-cloud-in-cloudflare",
		label: "What does the orange cloud mean in Cloudflare?",
		note: "The prerequisite: proxied vs DNS only, and why a proxied record needs a real origin address behind it.",
	},
	{
		href: "/guides/cloudflare-orange-to-orange",
		label: "Cloudflare Orange-to-Orange (O2O), explained",
		note: "The supported way for a proxied hostname to route into another Cloudflare zone — and why it is not error 1000.",
	},
	{
		href: "/guides/cloudflare-cname-flattening",
		label: "What is CNAME flattening in Cloudflare?",
		note: "What your root record actually resolves to, which is where a prohibited address most often hides.",
	},
	{
		href: "/guides/cloudflare-error-522-connection-timed-out",
		label: "Cloudflare error 522: connection timed out",
		note: "The neighbouring failure: the origin address is fine, but nothing answers on it before Cloudflare gives up.",
	},
	{
		href: DOCS_1000,
		label: "Cloudflare docs: Error 1000",
		note: "The official cause and resolution list this guide reorganises. Check it before changing anything.",
		external: true,
	},
	{
		href: "/guides/cloudflare-error-codes",
		label: "Cloudflare error codes: 5xx vs 1xxx",
		note: "Why a 1xxx number lives in the response body, and what the status line carries instead.",
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

export default async function Error1000Guide({ params }: { params: Promise<{ locale: string }> }) {
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
				lede="A short error page with a Ray ID and almost no detail. Here is what the proxy actually refused to do, the five situations that cause it, and which of them are yours to fix."
				updated={guide.updated}
				readingTime={guide.readingTime}
				related={RELATED}
			>
				<div className="glass r-island note p-6 sm:p-7">
					<p>
						<strong>Cloudflare error 1000 means the origin address for your hostname is Cloudflare
						itself.</strong> The proxy will not forward a request back into its own network, so it halts
						and returns <em>DNS points to prohibited IP</em> rather than looping.
					</p>
				</div>

				<p>
					The error page carries a Ray ID and one line of text, which makes the Cloudflare 1000 error look
					more mysterious than it is. Everything behind it comes down to a single rule: when Cloudflare
					proxies a hostname, it needs somewhere outside Cloudflare to send the request. If the address it
					ends up with is one of its own, or if the request looks like it has already been round-tripped
					through the proxy, it stops.
				</p>

				<h2 id="what-happens">What the proxy is refusing to do</h2>
				<Error1000Loop />
				<p>
					A proxied record — the orange cloud — answers DNS queries with Cloudflare anycast addresses, so
					visitors connect to Cloudflare first. Cloudflare then looks up where to forward the request: the
					value stored in your A, AAAA, or CNAME record. If that value is also a Cloudflare address, the
					request would arrive back at the same proxy it just left, and do so again on the next hop. Rather
					than let that run, Cloudflare treats the address as prohibited and answers the visitor directly.
					If proxied versus DNS only is new to you, start with{" "}
					<Link href="/guides/what-is-the-orange-cloud-in-cloudflare">
						what the orange cloud means in Cloudflare
					</Link>
					.
				</p>
				<p>
					The same reasoning covers cases where the DNS record is fine but the request itself carries
					evidence of a previous trip through the proxy. That is why the fix is not always in the DNS tab.
				</p>

				<h2 id="causes">The five ways to get there</h2>
				<p>
					Cloudflare lists the causes flat. Sorting them by <em>where the loop is</em> is more useful,
					because it also tells you who can fix it.
				</p>
				<div className="table-wrap">
					<table>
						<thead>
							<tr>
								<th scope="col">Where the loop is</th>
								<th scope="col">What it looks like</th>
								<th scope="col">Who fixes it</th>
							</tr>
						</thead>
						<tbody>
							<tr>
								<th scope="row">In the record</th>
								<td>An A record holds a Cloudflare address, or a load balancer origin points at a proxied record</td>
								<td>You, in DNS</td>
							</tr>
							<tr>
								<th scope="row">At the origin server</th>
								<td>A reverse proxy there forwards to your public hostname, which resolves to Cloudflare again</td>
								<td>You or your host, in the server config</td>
							</tr>
							<tr>
								<th scope="row">In the request headers</th>
								<td>An over-long or duplicated <code>X-Forwarded-For</code>, or a client-supplied <code>CF-Connecting-IP</code></td>
								<td>Whoever sits in front of Cloudflare</td>
							</tr>
							<tr>
								<th scope="row">In the TLS handshake</th>
								<td>The SNI the origin is offered does not match what it expects</td>
								<td>You or your host, at the origin</td>
							</tr>
							<tr>
								<th scope="row">On a SaaS platform</th>
								<td>Your domain points at a provider whose addresses are announced through Cloudflare</td>
								<td>The provider</td>
							</tr>
						</tbody>
					</table>
				</div>

				<h3>1. The record points into Cloudflare</h3>
				<p>
					By far the most common cause, and the one people arrive at this page with. An A record for the
					hostname contains an address from{" "}
					<a href={CF_IPS} target="_blank" rel="noopener noreferrer">
						Cloudflare&rsquo;s published IP ranges
					</a>{" "}
					instead of the server&rsquo;s. It usually happens when someone copies the address a lookup
					returned for the live site — which, on a proxied hostname, is Cloudflare&rsquo;s — and pastes it
					back into the record. In Cloudflare&rsquo;s wording that is a prohibited IP address: correct for a
					visitor to reach, wrong for the proxy to forward to. Ask your hosting provider for the
					origin&rsquo;s real address and replace the value.
				</p>
				<p>
					The load balancing variant is the same mistake one level up: an origin inside a load balancer pool
					is set to a hostname that is itself proxied, so resolving the pool member lands on Cloudflare.
					Point pool origins at addresses or at DNS-only hostnames.
				</p>

				<h3>2. A reverse proxy at the origin sends it back</h3>
				<p>
					Your record is correct, the request reaches your server, and then nginx — or any similar reverse
					proxy — forwards it onward to the public hostname with something like{" "}
					<code>proxy_pass https://www.example.com</code>. That hostname resolves to Cloudflare, so the
					request re-enters the proxy from the origin side. Cloudflare&rsquo;s guidance here is to stop
					proxying and use an HTTP redirect at the origin instead, or to have the proxy talk to an internal
					address that does not resolve through Cloudflare.
				</p>

				<h3>3. The request arrives with proxy headers already set</h3>
				<p>
					Three header conditions produce error 1000 on their own:
				</p>
				<ul>
					<li>
						An <code>X-Forwarded-For</code> header longer than 100 characters.
					</li>
					<li>
						Two <code>X-Forwarded-For</code> headers in one request.
					</li>
					<li>
						A <code>CF-Connecting-IP</code> header present on the inbound request. Cloudflare sets that
						header itself on the way to your origin; seeing it arrive means something upstream is
						impersonating the proxy.
					</li>
				</ul>
				<p>
					The first two are usually a chain, not a single mistake. Every proxy in front of Cloudflare
					appends its address to <code>X-Forwarded-For</code>, so a request that has passed through several
					CDNs or corporate proxies can exceed the limit without anyone having configured anything unusual.
					The{" "}
					<a href={DOCS_HEADERS} target="_blank" rel="noopener noreferrer">
						HTTP headers reference
					</a>{" "}
					documents exactly how the value is built up.
				</p>

				<h3>4. An SNI mismatch at the origin</h3>
				<p>
					When Cloudflare opens the TLS connection to your origin it sends the hostname in the Server Name
					Indication field. If the origin is configured for a different name, or is fronted by something
					that rewrites it, the mismatch can surface as error 1000 rather than a certificate error. Check
					which name the origin&rsquo;s virtual host and certificate actually expect.
				</p>

				<h3>5. A SaaS provider running on Cloudflare</h3>
				<p>
					This is the one that is not your fault. Some platforms use{" "}
					<a href={DOCS_SAAS} target="_blank" rel="noopener noreferrer">
						Cloudflare for SaaS
					</a>{" "}
					together with{" "}
					<a href={DOCS_BYOIP} target="_blank" rel="noopener noreferrer">
						BYOIP
					</a>
					, so their own IP ranges are announced through Cloudflare&rsquo;s network. Your record points at
					the provider, the address resolves into Cloudflare infrastructure, and if the provider has not
					created a custom hostname for your domain, the request is refused. The error is generated in
					their Cloudflare account, so no amount of editing on your side will clear it — the provider has
					to onboard the hostname.
				</p>
				<p>
					When that onboarding is done properly, the same setup becomes an ordinary two-zone route rather
					than an error. That is the subject of{" "}
					<Link href="/guides/cloudflare-orange-to-orange">Cloudflare orange-to-orange</Link>.
				</p>

				<h2 id="diagnose">Narrowing it down</h2>
				<ol>
					<li>
						<strong>Read the record, not the site.</strong> In the dashboard, open the DNS records for the
						zone and look at the stored value of the failing hostname. A lookup against the live site will
						only show you Cloudflare&rsquo;s addresses, which tells you nothing.
					</li>
					<li>
						<strong>Check the value against Cloudflare&rsquo;s ranges.</strong> If the stored address falls
						inside{" "}
						<a href={CF_IPS} target="_blank" rel="noopener noreferrer">
							the published list
						</a>
						, you have cause 1 and you are done.
					</li>
					<li>
						<strong>Follow CNAMEs to the end.</strong> A record can be correct and still land on Cloudflare
						two hops later. Root domains are the usual hiding place, because the value you see is not the
						value that gets served — see{" "}
						<Link href="/guides/cloudflare-cname-flattening">CNAME flattening</Link>.
					</li>
					<li>
						<strong>Grey-cloud the record briefly.</strong> Set it to DNS only. If the site then loads at
						the origin, the record value is fine and the loop is at the origin or in the headers; if it
						still fails, the address is wrong. Remember the record is exposed while it is grey.
					</li>
					<li>
						<strong>Request the origin directly.</strong> From a shell, send a request to the origin
						address with the correct <code>Host</code> header. A clean response points at causes 3 or 4; a
						Cloudflare error page coming back means the origin is bouncing you into the proxy.
					</li>
				</ol>

				<h2 id="not-1000">Errors that look like 1000 but are not</h2>
				<p>
					Cloudflare&rsquo;s 1xxx family reuses very similar wording, and picking the wrong page costs an
					afternoon. The distinctions that matter:
				</p>
				<div className="table-wrap">
					<table>
						<thead>
							<tr>
								<th scope="col">Error</th>
								<th scope="col">Trigger</th>
								<th scope="col">First move</th>
							</tr>
						</thead>
						<tbody>
							<tr>
								<th scope="row">
									<a href={DOCS_1000} target="_blank" rel="noopener noreferrer">
										1000
									</a>
								</th>
								<td>The origin address, the origin server, or the request headers send traffic back into Cloudflare</td>
								<td>Read the stored record value, then the origin config</td>
							</tr>
							<tr>
								<th scope="row">
									<a href={DOCS_1002} target="_blank" rel="noopener noreferrer">
										1002
									</a>
								</th>
								<td>A record value is a Cloudflare address, a CNAME target is wrong, or an off-Cloudflare domain CNAMEs into one</td>
								<td>Confirm the target with your host and correct the record</td>
							</tr>
							<tr>
								<th scope="row">
									<a href={DOCS_1003} target="_blank" rel="noopener noreferrer">
										1003
									</a>
								</th>
								<td>A client browsed to a Cloudflare IP address directly instead of the domain name</td>
								<td>Use the hostname in the URL</td>
							</tr>
							<tr>
								<th scope="row">
									<a href={DOCS_1014} target="_blank" rel="noopener noreferrer">
										1014
									</a>
								</th>
								<td>A CNAME crosses into a different Cloudflare account that has not onboarded the hostname</td>
								<td>The target&rsquo;s owner enables Cloudflare for SaaS, or you release a zone hold</td>
							</tr>
						</tbody>
					</table>
				</div>
				<p>
					A rough rule: 1002 is a wrong value, 1003 is a wrong URL, 1014 is a missing permission, and error
					code 1000 is a loop. The{" "}
					<a href={DOCS_1XXX} target="_blank" rel="noopener noreferrer">
						full 1xxx index
					</a>{" "}
					is worth a bookmark if you administer more than one zone.
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
