import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { setRequestLocale } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import GuideShell, { type RelatedLink } from "@/components/guides/GuideShell";
import Error525Handshake from "@/components/guides/Error525Handshake";
import { guideBySlug, GUIDE_LOCALE } from "@/lib/guides/guides";

const SITE_URL = "https://o-c.do";
const guide = guideBySlug("cloudflare-error-525-ssl-handshake-failed");
const PATH = `/guides/${guide.slug}`;

const DOCS_525 =
	"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-525/";
const DOCS_5XX = "https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/";
const DOCS_FULL = "https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full/";
const DOCS_FULL_STRICT = "https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/";
const DOCS_SSL_MODES = "https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/";
const DOCS_ORIGIN_CIPHERS = "https://developers.cloudflare.com/ssl/origin-configuration/cipher-suites/";
const DOCS_ORIGIN_CA = "https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/";
const DOCS_PORTS = "https://developers.cloudflare.com/fundamentals/reference/network-ports/";
const DOCS_MIN_TLS = "https://developers.cloudflare.com/ssl/edge-certificates/additional-options/minimum-tls/";
const DOCS_CURL =
	"https://developers.cloudflare.com/support/troubleshooting/general-troubleshooting/gathering-information-for-troubleshooting-sites/#troubleshoot-requests-with-curl";
const DOCS_ORIGIN_ANALYTICS = "https://developers.cloudflare.com/speed/origin-analytics/";
const DOCS_DDNS = "https://developers.cloudflare.com/dns/manage-dns-records/how-to/managing-dynamic-ip-addresses/";

/** FAQ 一处定义：可见文本与 FAQPage JSON-LD 同源，保证逐字一致 */
const FAQ: Array<{ q: string; a: string }> = [
	{
		q: "What does Cloudflare error 525 mean?",
		a: "Error 525, SSL handshake failed, means Cloudflare opened a connection to your origin server but the TLS handshake between the two never completed. Cloudflare documents it as occurring when that handshake fails and the encryption mode is set to Full or Full (strict). Because the connection itself succeeded, a 525 tells you the origin is reachable and the port is open.",
	},
	{
		q: "How do I fix Cloudflare error 525?",
		a: "Work through the four causes Cloudflare lists for the origin: no valid SSL certificate installed, port 443 or your custom secure port not open, no SNI support, and cipher suites that Cloudflare and the origin do not share. A free Cloudflare Origin CA certificate resolves the first case on any plan. If the errors are intermittent rather than constant, the answer is in the origin's own SSL error log rather than in any Cloudflare setting.",
	},
	{
		q: "What is the difference between error 525 and error 526?",
		a: "A 525 is a handshake that never finished, so no usable certificate was ever exchanged. A 526 is a handshake that finished, produced a certificate, and then failed validation. The modes differ too: error 525 can occur in both Full and Full (strict), while Cloudflare documents 526 as requiring Full (strict).",
	},
	{
		q: "Does raising the Minimum TLS Version fix a 525?",
		a: "No. Minimum TLS Version governs which TLS versions visitors may use when connecting to Cloudflare, not which versions Cloudflare offers your origin. It is documented as only allowing HTTPS connections from visitors that support the selected version or newer, so changing it cannot affect the Cloudflare-to-origin handshake that a 525 describes.",
	},
	{
		q: "I am a visitor, not the site owner. Can I fix a 525?",
		a: "No. Error code 525 is generated at Cloudflare's edge because the website's own server would not complete a TLS handshake, and nothing on your device, browser or network causes it. Clearing cookies, switching DNS resolver or using a VPN will not help. Reporting it to the site owner and trying again later are the only useful actions.",
	},
];

const RELATED: RelatedLink[] = [
	{
		href: "/guides/cloudflare-error-526-invalid-ssl-certificate",
		label: "Cloudflare error 526: invalid SSL certificate",
		note: "One gate further along: the handshake finished, a certificate arrived, and Cloudflare refused to trust it.",
	},
	{
		href: "/guides/cloudflare-ssl-tls-encryption-modes",
		label: "Which Cloudflare SSL/TLS encryption mode should you use?",
		note: "The setting that decides whether Cloudflare attempts an origin handshake at all — and so whether a 525 is possible.",
	},
	{
		href: "/guides/cloudflare-error-521-web-server-is-down",
		label: "Cloudflare error 521: web server is down",
		note: "The gate before this one: the port refused the connection, so TLS never started.",
	},
	{
		href: "/guides/what-is-the-orange-cloud-in-cloudflare",
		label: "What does the orange cloud mean in Cloudflare?",
		note: "A 525 exists only because the record is proxied — here is what proxying puts in front of your origin.",
	},
	{
		href: DOCS_525,
		label: "Cloudflare docs: Error 525",
		note: "The official reference, including the Origin Analytics method for dating intermittent failures.",
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

const OPENSSL_CHECK = `# Talk to the origin the way Cloudflare does, with Cloudflare out of the path.
# -servername is the SNI name; drop it to test gate 3 on its own.
openssl s_client -connect 203.0.113.10:443 -servername example.com </dev/null

# What the failures look like:
#   wrong version number   -> gate 2: that port is not speaking TLS
#   no shared cipher       -> gate 4: the origin's cipher list excludes all of them
#   handshake failure      -> gate 3 or 4; the origin's SSL error log says which
#   a certificate printed  -> the handshake worked, so you are chasing a 526`;

export default async function Error525Guide({ params }: { params: Promise<{ locale: string }> }) {
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
				lede="Of all the origin errors, this is the most specific about where it happened and the least specific about why. Four gates, three of which emit this code."
				updated={guide.updated}
				readingTime={guide.readingTime}
				related={RELATED}
			>
				<div className="glass r-island note p-6 sm:p-7">
					<p>
						<strong>
							Cloudflare error 525 means the TLS handshake between Cloudflare and your origin failed.
						</strong>{" "}
						The connection opened, so the server is reachable and the port is listening. The two sides then
						could not agree on a secure session.
					</p>
				</div>

				<p>
					That distinction is the whole value of the code. HTTP 525 is not a report that your origin is down — it
					is a report that your origin answered and then could not, or would not, speak TLS on the terms
					Cloudflare offered. Like the rest of the family, err 525 is produced at Cloudflare&rsquo;s edge rather
					than by your application, so your access log may contain nothing at all, and it can only happen on a{" "}
					<Link href="/guides/what-is-the-orange-cloud-in-cloudflare">proxied record</Link>.
				</p>

				<h2 id="where">Where in the handshake it fails</h2>
				<Error525Handshake />
				<p>
					Cloudflare&rsquo;s{" "}
					<a href={DOCS_525} target="_blank" rel="noopener noreferrer">
						documentation for error 525
					</a>{" "}
					states two conditions: the SSL handshake fails between Cloudflare and the origin, and the encryption
					mode is{" "}
					<a href={DOCS_FULL} target="_blank" rel="noopener noreferrer">
						Full
					</a>{" "}
					or{" "}
					<a href={DOCS_FULL_STRICT} target="_blank" rel="noopener noreferrer">
						Full (strict)
					</a>
					. Both modes qualify, and that is where 525 parts company with its neighbour: a 526 needs Full
					(strict) specifically, because only Full (strict) validates anything. A 525 happens earlier, before
					there is a certificate to have an opinion about.
				</p>

				<h2 id="causes">The four causes, and which one is yours</h2>
				<p>
					Cloudflare lists four things to exclude at the origin. They map onto the gates above, and each leaves
					a different fingerprint — which is the part worth having, because a Cloudflare 525 on its own never
					tells you which of the four you hit.
				</p>
				<div className="table-wrap">
					<table>
						<thead>
							<tr>
								<th scope="col">Cause</th>
								<th scope="col">What it looks like</th>
								<th scope="col">Fix</th>
							</tr>
						</thead>
						<tbody>
							<tr>
								<th scope="row">No valid SSL certificate installed</th>
								<td>Every HTTPS request fails, immediately and consistently</td>
								<td>
									Install any certificate — a free{" "}
									<a href={DOCS_ORIGIN_CA} target="_blank" rel="noopener noreferrer">
										Cloudflare Origin CA
									</a>{" "}
									certificate is enough
								</td>
							</tr>
							<tr>
								<th scope="row">Port 443, or your custom secure port, is not open</th>
								<td>Same: total and constant, often right after HTTPS was first enabled</td>
								<td>Open the port to Cloudflare and bind the web server to it</td>
							</tr>
							<tr>
								<th scope="row">No SNI support at the origin</th>
								<td>
									Fails for every hostname, or for every hostname except the server&rsquo;s default
									virtual host
								</td>
								<td>Enable SNI, or move the site to a server that supports it</td>
							</tr>
							<tr>
								<th scope="row">No shared cipher suite</th>
								<td>
									Appears the day someone hardens the TLS configuration; often hits one server in a pool
								</td>
								<td>
									Widen the origin&rsquo;s{" "}
									<a href={DOCS_ORIGIN_CIPHERS} target="_blank" rel="noopener noreferrer">
										cipher list
									</a>{" "}
									to include at least one suite Cloudflare offers
								</td>
							</tr>
						</tbody>
					</table>
				</div>
				<p>
					Cloudflare frames all four as things to raise with your hosting provider, which fairly reflects where
					they live: not one of them is a Cloudflare setting. The only Cloudflare-side lever is the encryption
					mode itself, and turning that down stops the bleeding rather than fixing anything.
				</p>

				<h2 id="only-https">Why only some visitors see it</h2>
				<p>
					A 525 that appears for some people and not others is often not intermittent at all. In Full mode,
					Cloudflare connects to the origin <em>using the scheme the visitor requested</em> — an HTTP request in
					means plaintext HTTP out to your origin. No TLS handshake is attempted on that path, so it cannot
					produce a 525. Only visitors arriving over HTTPS reach the handshake, and they are the only ones who
					see the error.
				</p>
				<p>
					That is how a site sits in Full mode for months with a broken origin certificate and only starts
					throwing 525s when something — a new redirect rule, HSTS finally taking hold, a link shared as
					https — pushes real traffic onto the encrypted path.
				</p>

				<h2 id="ciphers">The cipher trap, and the setting that is not it</h2>
				<p>
					The cipher cause deserves its own section, because the instinct is to reach for the wrong dial.
				</p>
				<p>
					Cloudflare publishes the exact list of suites it presents to origins, and that list spans TLS 1.0
					through TLS 1.3; your server picks whichever of them it prefers. So the failure mode is not &ldquo;my
					origin only allows modern TLS&rdquo; — TLS 1.3 suites are in what Cloudflare offers. The failure mode
					is a hand-tuned <code>ssl_ciphers</code> line, or a compliance baseline, that happens to exclude every
					suite on that list. An ECDSA-only configuration paired with an RSA certificate will do it.
				</p>
				<p>
					And the dial people reach for instead:{" "}
					<a href={DOCS_MIN_TLS} target="_blank" rel="noopener noreferrer">
						Minimum TLS Version
					</a>{" "}
					does nothing here. It is documented as controlling which versions <em>visitors</em> may use to reach
					Cloudflare — the first hop, not the second. Raising it locks out old browsers and leaves your 525
					exactly where it was.
				</p>
				<p>
					While you are checking ports, note that HTTPS on a proxied record is not limited to 443. Cloudflare{" "}
					<a href={DOCS_PORTS} target="_blank" rel="noopener noreferrer">
						proxies HTTPS
					</a>{" "}
					on 443, 2053, 2083, 2087, 2096 and 8443, and the handshake has to succeed on whichever one the request
					arrived at.
				</p>

				<h2 id="confirm">Confirming it yourself</h2>
				<p>
					Cloudflare&rsquo;s own suggestion is to{" "}
					<a href={DOCS_CURL} target="_blank" rel="noopener noreferrer">
						test the origin directly with curl
					</a>
					. One level down, <code>openssl s_client</code> names the failing gate for you:
				</p>
				<pre>
					<code>{OPENSSL_CHECK}</code>
				</pre>
				<p>
					Run it from outside your own network, against the origin address, with the real hostname as the SNI
					name. If that command succeeds and Cloudflare still returns a 525, the next thing to suspect is that
					Cloudflare is not talking to the server you just tested — a stale <code>A</code> record after a{" "}
					<a href={DOCS_DDNS} target="_blank" rel="noopener noreferrer">
						dynamic origin IP change
					</a>{" "}
					is a documented cause, and so is a single misconfigured node behind a load balancer.
				</p>

				<h2 id="intermittent">When it really is intermittent</h2>
				<p>
					Constant 525s are configuration. Occasional ones are usually resource pressure or one bad node, and
					Cloudflare is explicit that the answer lives in the origin&rsquo;s logs rather than in the dashboard:
					read the SSL error log at the timestamps when the errors occurred. On nginx, SSL errors go to the
					standard error log, though you may have to raise the log level to see them; on Apache, mod_ssl logging
					has to be switched on first.
				</p>
				<p>
					For dating the failures without origin access,{" "}
					<a href={DOCS_ORIGIN_ANALYTICS} target="_blank" rel="noopener noreferrer">
						Origin Analytics
					</a>{" "}
					records an origin status code of <code>0</code> when Cloudflare received no HTTP response at all,
					which is what a failed TLS negotiation looks like from the edge. Line those timestamps up against
					whatever else happened on the box.
				</p>

				<h2 id="neighbours">525 against its neighbours</h2>
				<div className="table-wrap">
					<table>
						<thead>
							<tr>
								<th scope="col">Error</th>
								<th scope="col">How far it got</th>
								<th scope="col">Modes it needs</th>
							</tr>
						</thead>
						<tbody>
							<tr>
								<th scope="row">
									<Link href="/guides/cloudflare-error-521-web-server-is-down">521</Link>
								</th>
								<td>Connection refused outright</td>
								<td>Any</td>
							</tr>
							<tr>
								<th scope="row">
									<Link href="/guides/cloudflare-error-522-connection-timed-out">522</Link>
								</th>
								<td>No TCP connection within the timeout</td>
								<td>Any</td>
							</tr>
							<tr>
								<th scope="row">525</th>
								<td>TCP connected, TLS handshake failed</td>
								<td>Full or Full (strict)</td>
							</tr>
							<tr>
								<th scope="row">
									<Link href="/guides/cloudflare-error-526-invalid-ssl-certificate">526</Link>
								</th>
								<td>Handshake succeeded, certificate rejected</td>
								<td>Full (strict) only</td>
							</tr>
							<tr>
								<th scope="row">
									<Link href="/guides/cloudflare-error-524-a-timeout-occurred">524</Link>
								</th>
								<td>Handshake succeeded, no HTTP response in time</td>
								<td>Any</td>
							</tr>
						</tbody>
					</table>
				</div>
				<p>
					The third column is what actually narrows things down. A 525 requires that an origin handshake was
					attempted at all, so if you believe the zone is on Flexible, check what the mode really is:{" "}
					<a href={DOCS_SSL_MODES} target="_blank" rel="noopener noreferrer">
						Automatic SSL/TLS
					</a>{" "}
					can select Full or Full (strict) on your behalf. How that rollout behaves is worth knowing, because it
					explains a 525 that touches only a slice of traffic — upgrades start at 1% and climb in 10%
					increments, and Cloudflare aborts and rolls back if origin connectivity fails during the ramp. The{" "}
					<a href={DOCS_5XX} target="_blank" rel="noopener noreferrer">
						5xx index
					</a>{" "}
					covers the rest of the family, and{" "}
					<Link href="/guides/cloudflare-error-526-invalid-ssl-certificate">the 526 guide</Link> picks up exactly
					where this one stops: the moment a certificate finally arrives.
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
