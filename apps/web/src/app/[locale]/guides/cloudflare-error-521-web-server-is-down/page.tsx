import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { setRequestLocale } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import GuideShell, { type RelatedLink } from "@/components/guides/GuideShell";
import Error521Refusal from "@/components/guides/Error521Refusal";
import { guideBySlug, GUIDE_LOCALE } from "@/lib/guides/guides";

const SITE_URL = "https://o-c.do";
const guide = guideBySlug("cloudflare-error-521-web-server-is-down");
const PATH = `/guides/${guide.slug}`;

const DOCS_521 =
	"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-521/";
const DOCS_522 =
	"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-522/";
const DOCS_523 =
	"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-523/";
const DOCS_5XX = "https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/";
const DOCS_IPS = "https://www.cloudflare.com/ips/";
const DOCS_SSL_MODES = "https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/";
const DOCS_ORIGIN_CA = "https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/";

/** FAQ 一处定义：可见文本与 FAQPage JSON-LD 同源，保证逐字一致 */
const FAQ: Array<{ q: string; a: string }> = [
	{
		q: "What does Cloudflare error 521 mean?",
		a: "It means the origin web server refused the connection Cloudflare tried to open. Cloudflare reached your server's address and got an immediate rejection rather than a response, so it returned error 521, web server is down, to the visitor.",
	},
	{
		q: "What is the difference between error 521 and error 522?",
		a: "Both describe the same hop between Cloudflare and your origin, but not the same behaviour. A 521 error means the origin actively refused the connection, so Cloudflare knew straight away. A 522 means the origin said nothing at all and Cloudflare gave up after 19 seconds. A firewall that rejects packets produces 521; the same firewall set to drop them produces 522.",
	},
	{
		q: "Can I fix a 521 error from the Cloudflare dashboard?",
		a: "Usually not, because the fault is at your origin rather than at Cloudflare. The one exception worth checking first is the SSL/TLS encryption mode, which decides whether Cloudflare connects to port 80 or port 443 at your origin. If the mode was changed to Full or Full (strict) and your server only listens on port 80, error 521 starts immediately and changing that setting back stops it.",
	},
	{
		q: "Why do I get a 521 error only after switching to Full (strict)?",
		a: "Because the encryption mode changes which port Cloudflare connects to. Cloudflare connects to port 80 in Flexible mode, and to port 443 in Full and Full (strict). A server configured for plain HTTP only is not listening on 443, so it refuses the connection and every request returns error 521 until HTTPS is enabled at the origin.",
	},
	{
		q: "I am a visitor, not the site owner. Can I do anything about a 521?",
		a: "No. Error 521 is generated at Cloudflare's edge because the website's own server refused the connection, and nothing on your device or network causes it. Cloudflare's support policy is that site visitors should report the problem to the site owner; reloading later is the only useful action.",
	},
];

const RELATED: RelatedLink[] = [
	{
		href: "/guides/cloudflare-error-522-connection-timed-out",
		label: "Cloudflare error 522: connection timed out",
		note: "The silent twin of this error — same hop, same firewall, but packets dropped instead of refused.",
	},
	{
		href: "/guides/cloudflare-ssl-tls-encryption-modes",
		label: "Which Cloudflare SSL/TLS encryption mode should you use?",
		note: "The setting that decides whether Cloudflare knocks on port 80 or port 443 — and so whether your origin refuses it.",
	},
	{
		href: "/guides/cloudflare-error-526-invalid-ssl-certificate",
		label: "Cloudflare error 526: invalid SSL certificate",
		note: "One step further along the same hop: the origin answered on 443, and the certificate it presented was rejected.",
	},
	{
		href: "/guides/cloudflare-error-1000-dns-points-to-prohibited-ip",
		label: "Cloudflare error 1000: DNS points to prohibited IP",
		note: "The four-digit family: what happens when the address Cloudflare resolved is Cloudflare's own.",
	},
	{
		href: "/guides/what-is-the-orange-cloud-in-cloudflare",
		label: "What does the orange cloud mean in Cloudflare?",
		note: "A 521 can only happen on a proxied record — here is what proxying puts in front of your origin.",
	},
	{
		href: DOCS_521,
		label: "Cloudflare docs: Error 521",
		note: "The official reference, including the full resolution checklist to hand your hosting provider.",
		external: true,
	},
	{
		href: "/guides/cloudflare-error-codes",
		label: "Cloudflare error codes: 5xx vs 1xxx",
		note: "Where 521 sits among the rest, and why a 1xxx code never reaches your monitoring.",
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

const PORT_CHECK = `# On the origin, list what is actually listening
ss -lntp | grep -E ':(80|443)\\s'

# From anywhere, knock on the origin address directly
curl -sv --connect-timeout 5 https://203.0.113.10/ --resolve example.com:443:203.0.113.10`;

export default async function Error521Guide({ params }: { params: Promise<{ locale: string }> }) {
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
				lede="The error page blames your web server, and it is right — but “down” covers four different situations, and one of them is a Cloudflare setting you changed yourself."
				updated={guide.updated}
				readingTime={guide.readingTime}
				related={RELATED}
			>
				<div className="glass r-island note p-6 sm:p-7">
					<p>
						<strong>
							Cloudflare error 521 means your origin server refused the connection Cloudflare tried to open.
						</strong>{" "}
						Something answered, and the answer was no. Either the web server is not running, or it is not
						listening on the port your encryption mode requires.
					</p>
				</div>

				<p>
					Error 521 is generated at Cloudflare&rsquo;s edge, not by your application, so none of your own error
					handling runs and none of your logs necessarily record it. That is already useful information: the
					visitor reached Cloudflare perfectly well, so whatever is broken sits on the second hop, between
					Cloudflare and your server. Your browser records the response as HTTP status 521, which is not a
					standard status code at all — it is one Cloudflare defines for itself, so &ldquo;Cloudflare 521&rdquo;
					and &ldquo;error code 521&rdquo; describe the same single thing. A 521 error also only happens on a{" "}
					<Link href="/guides/what-is-the-orange-cloud-in-cloudflare">proxied record</Link> — on a DNS-only
					record there is no proxy in the path to be refused, and the visitor would simply see your server&rsquo;s
					own failure instead.
				</p>

				<h2 id="refused">Refused, not unreachable</h2>
				<Error521Refusal />
				<p>
					Cloudflare defines error 521 as the origin web server{" "}
					<a href={DOCS_521} target="_blank" rel="noopener noreferrer">
						refusing connections
					</a>
					, and that word does most of the diagnostic work. A refusal is a reply. Your server, or something in
					front of it, received Cloudflare&rsquo;s packet and sent back a TCP reset — the same thing that produces{" "}
					<code>connection refused</code> when you run <code>curl</code> against a port with nothing behind it.
					Because it is a reply rather than a wait, a 521 error appears almost instantly.
				</p>
				<p>
					This is the cleanest way to tell it apart from its neighbours. If Cloudflare had been ignored rather
					than refused it would have kept retrying and reported{" "}
					<Link href="/guides/cloudflare-error-522-connection-timed-out">522 after 19 seconds</Link>. If there
					had been no network route to your address at all, it would have reported 523. One misconfigured
					firewall can produce either 521 or 522 depending on a single word in the rule: <code>REJECT</code>{" "}
					sends the reset and gets you a 521, <code>DROP</code> stays quiet and gets you a 522.
				</p>

				<h2 id="ports">The cause people miss: which port Cloudflare knocks on</h2>
				<p>
					Before touching the firewall, check this, because it is the one cause of error 521 that originates in
					the Cloudflare dashboard rather than at your origin. Your{" "}
					<Link href="/guides/cloudflare-ssl-tls-encryption-modes">SSL/TLS encryption mode</Link> decides which
					port Cloudflare opens a connection to at your server, and Cloudflare&rsquo;s own 521 documentation
					states the mapping plainly:
				</p>
				<div className="table-wrap">
					<table>
						<thead>
							<tr>
								<th scope="col">Encryption mode</th>
								<th scope="col">Origin port Cloudflare connects to</th>
								<th scope="col">What the origin must have</th>
							</tr>
						</thead>
						<tbody>
							<tr>
								<th scope="row">Flexible</th>
								<td>
									Port <code>80</code>
								</td>
								<td>A plain HTTP listener. No certificate needed on this hop.</td>
							</tr>
							<tr>
								<th scope="row">Full</th>
								<td>
									Port <code>443</code>
								</td>
								<td>HTTPS enabled. Any certificate, including a self-signed one.</td>
							</tr>
							<tr>
								<th scope="row">Full (strict)</th>
								<td>
									Port <code>443</code>
								</td>
								<td>
									HTTPS enabled with a certificate that validates — a public CA, or a{" "}
									<a href={DOCS_ORIGIN_CA} target="_blank" rel="noopener noreferrer">
										Cloudflare Origin CA
									</a>{" "}
									certificate.
								</td>
							</tr>
						</tbody>
					</table>
				</div>
				<p>
					So a server that only ever spoke plain HTTP is refusing connections on port 443 the moment the mode
					moves to Full or Full (strict) — nothing is bound there, so the kernel resets every incoming
					connection, and every request returns error 521 from then on. This is why 521 errors so often start
					right after somebody &ldquo;improved the SSL settings&rdquo;, and why the fix is either to enable HTTPS
					at the origin or to move the mode back. Note that this is a different failure from a bad certificate:
					if your origin does answer on 443 but presents a certificate Cloudflare will not accept, you get 526
					rather than 521.
				</p>

				<h2 id="causes">The four causes, in the order worth checking</h2>
				<ol>
					<li>
						<strong>The web server process is not running.</strong> Cloudflare lists an offlined origin
						application as one of the two most common causes. A crashed <code>nginx</code>, an{" "}
						<code>httpd</code> that failed to restart after a config reload, or a container that exited will
						all refuse connections while the host itself stays perfectly reachable. Check the service status
						and the origin error log for the crash.
					</li>
					<li>
						<strong>The server is running but not on the port your mode needs.</strong> The case above: bound
						to <code>80</code> while Cloudflare is knocking on <code>443</code>, or the reverse.
					</li>
					<li>
						<strong>A firewall is rejecting Cloudflare&rsquo;s addresses.</strong> The other most common cause.
						Security software at the origin may block legitimate connections from particular Cloudflare IPs,
						so Cloudflare&rsquo;s advice is to allow{" "}
						<a href={DOCS_IPS} target="_blank" rel="noopener noreferrer">
							all Cloudflare IP ranges
						</a>{" "}
						at the origin rather than a subset. Rate limiting counts here too: a rule that trips after a burst
						will produce intermittent 521 errors that look like a flapping server.
					</li>
					<li>
						<strong>The origin does not support HTTPS at all.</strong> Distinct from being bound to the wrong
						port — the service is there, but TLS was never configured. The remedy is the same as case two,
						with more work: install a certificate, or drop back to a mode that uses port 80 while you do.
					</li>
				</ol>

				<h2 id="confirm">Confirming it yourself</h2>
				<p>
					Both of the checks that matter can be run in a minute. The first asks your origin what it is actually
					listening on; the second bypasses Cloudflare entirely and knocks on the origin address directly, so a{" "}
					<code>connection refused</code> here reproduces the 521 error outside the proxy and proves the fault is
					not Cloudflare&rsquo;s.
				</p>
				<pre>
					<code>{PORT_CHECK}</code>
				</pre>
				<p>
					If the direct request succeeds while the proxied one still returns a 521 error, the difference is
					almost always which addresses are allowed: your own IP is permitted and Cloudflare&rsquo;s ranges are
					not. If the direct request is refused too, the origin is at fault regardless of Cloudflare, and the
					first two causes above are where to look.
				</p>

				<h2 id="neighbours">Where 521 sits among the origin errors</h2>
				<p>
					The whole 52x family describes the Cloudflare-to-origin hop, and they are distinguished only by how
					the origin failed:
				</p>
				<div className="table-wrap">
					<table>
						<thead>
							<tr>
								<th scope="col">Error</th>
								<th scope="col">What the origin did</th>
								<th scope="col">Typical first move</th>
							</tr>
						</thead>
						<tbody>
							<tr>
								<th scope="row">
									<a href={DOCS_521} target="_blank" rel="noopener noreferrer">
										521
									</a>
								</th>
								<td>Refused immediately — sent a reset</td>
								<td>Confirm the service runs and listens on the port your encryption mode needs</td>
							</tr>
							<tr>
								<th scope="row">
									<a href={DOCS_522} target="_blank" rel="noopener noreferrer">
										522
									</a>
								</th>
								<td>Said nothing until the clock ran out</td>
								<td>Allow Cloudflare&rsquo;s IP ranges; check whether the origin is overloaded</td>
							</tr>
							<tr>
								<th scope="row">
									<a href={DOCS_523} target="_blank" rel="noopener noreferrer">
										523
									</a>
								</th>
								<td>Could not be reached — no route to the address</td>
								<td>Verify the A record, and the route tables between your network and Cloudflare</td>
							</tr>
						</tbody>
					</table>
				</div>
				<p>
					A short rule for the three: 521 is a refusal, 522 is silence, 523 is no route. When you do escalate,
					Cloudflare asks you to give your hosting provider the specific error code, the time and timezone it
					happened, and the exact URL — and to check the logs of any load balancer, cache, proxy or firewall
					sitting between Cloudflare and the web server, because the cause is not always in the origin&rsquo;s own
					log. The{" "}
					<a href={DOCS_5XX} target="_blank" rel="noopener noreferrer">
						5xx index
					</a>{" "}
					covers the rest of the family, and the{" "}
					<a href={DOCS_SSL_MODES} target="_blank" rel="noopener noreferrer">
						encryption modes reference
					</a>{" "}
					covers the setting behind the port trap above.
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
