import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { setRequestLocale } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import GuideShell, { type RelatedLink } from "@/components/guides/GuideShell";
import Error526Validation from "@/components/guides/Error526Validation";
import { guideBySlug, GUIDE_LOCALE } from "@/lib/guides/guides";

const SITE_URL = "https://o-c.do";
const guide = guideBySlug("cloudflare-error-526-invalid-ssl-certificate");
const PATH = `/guides/${guide.slug}`;

const DOCS_526 =
	"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-526/";
const DOCS_525 =
	"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-525/";
const DOCS_5XX = "https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/";
const DOCS_SSL_MODES = "https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/";
const DOCS_FULL = "https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full/";
const DOCS_FULL_STRICT = "https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/";
const DOCS_ORIGIN_CA = "https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/";
const DOCS_COTS = "https://developers.cloudflare.com/ssl/origin-configuration/custom-origin-trust-store/";
const DOCS_ACM = "https://developers.cloudflare.com/ssl/edge-certificates/advanced-certificate-manager/";
const DOCS_PAUSE = "https://developers.cloudflare.com/fundamentals/manage-domains/pause-cloudflare/";
const DOCS_COMPAT_FLAGS = "https://developers.cloudflare.com/workers/configuration/compatibility-flags/";
const DOCS_CIPHERS = "https://developers.cloudflare.com/ssl/origin-configuration/cipher-suites/";

/** FAQ 一处定义：可见文本与 FAQPage JSON-LD 同源，保证逐字一致 */
const FAQ: Array<{ q: string; a: string }> = [
	{
		q: "What does Cloudflare error 526 mean?",
		a: "It means Cloudflare could not validate the SSL certificate your origin server presented, while your encryption mode was set to Full (strict). The TLS handshake itself worked and your server did send a certificate; Cloudflare then refused to trust it and returned error 526, invalid SSL certificate, to the visitor.",
	},
	{
		q: "How do I fix Cloudflare error 526?",
		a: "Fix the certificate rather than the symptom: install one issued by a public certificate authority or a free Cloudflare Origin CA certificate, make sure it has not expired, make sure the hostname appears in its Common Name or Subject Alternative Name, and make sure your server sends the intermediate certificates alongside the leaf. Switching the encryption mode from Full (strict) to Full also clears the error, but only because it stops Cloudflare checking at all.",
	},
	{
		q: "What is the difference between Cloudflare error 525 and 526?",
		a: "A 525 means the TLS handshake between Cloudflare and your origin failed outright, so no usable certificate was ever exchanged; common causes are no certificate installed, port 443 closed, no SNI support, or mismatched cipher suites. A 526 means the handshake got far enough for your origin to present a certificate and Cloudflare rejected it as invalid. Error 525 can occur in both Full and Full (strict), while 526 requires Full (strict).",
	},
	{
		q: "Can error 526 happen in Full mode?",
		a: "No. In Full mode Cloudflare connects to your origin over HTTPS without validating the origin certificate, so there is no validation step to fail. Cloudflare documents error 526 as occurring only when Full (strict) is set. If you are seeing 526 and believe you are not in Full (strict), check whether Automatic SSL/TLS upgraded the zone for you, or whether the request came from a Worker or from Cloudflare Gateway, both of which apply Full (strict) regardless of the zone setting.",
	},
	{
		q: "I am a visitor, not the site owner. Can I fix a 526?",
		a: "No. Error code 526 is produced at Cloudflare's edge because the website's own server presented a certificate Cloudflare would not accept, and nothing on your device or network causes it or can work around it. Reporting the problem to the site owner, and trying again later, are the only useful actions.",
	},
];

const RELATED: RelatedLink[] = [
	{
		href: "/guides/cloudflare-ssl-tls-encryption-modes",
		label: "Which Cloudflare SSL/TLS encryption mode should you use?",
		note: "The setting that decides whether Cloudflare validates your origin certificate at all — and so whether a 526 is even possible.",
	},
	{
		href: "/guides/cloudflare-error-525-ssl-handshake-failed",
		label: "Cloudflare error 525: SSL handshake failed",
		note: "The closest neighbour: the handshake failing outright rather than a certificate being rejected \u2014 and the reason relaxing the mode fixes one but not the other.",
	},
	{
		href: "/guides/cloudflare-error-521-web-server-is-down",
		label: "Cloudflare error 521: web server is down",
		note: "One step earlier on the same hop: the origin refused the connection before any certificate was exchanged.",
	},
	{
		href: "/guides/cloudflare-error-522-connection-timed-out",
		label: "Cloudflare error 522: connection timed out",
		note: "The silent failure on that hop — no refusal, no certificate, just nineteen seconds of nothing.",
	},
	{
		href: "/guides/what-is-the-orange-cloud-in-cloudflare",
		label: "What does the orange cloud mean in Cloudflare?",
		note: "A 526 only exists because the record is proxied — here is what proxying puts in front of your origin.",
	},
	{
		href: DOCS_526,
		label: "Cloudflare docs: Error 526",
		note: "The official reference, including the Zero Trust and Workers variants of the same error.",
		external: true,
	},
	{
		href: "/guides/cloudflare-error-codes",
		label: "Cloudflare error codes: 5xx vs 1xxx",
		note: "The wider map of Cloudflare error codes, and what each range already tells you.",
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

const OPENSSL_CHECK = `# Ask the origin directly what chain it serves, bypassing Cloudflare
openssl s_client -connect 203.0.113.10:443 -servername example.com </dev/null

# Look for these three lines in the output:
#   Certificate chain      -> must include the intermediate, not just the leaf
#   Verify return code: 0  -> anything else is what Cloudflare is rejecting
#   notAfter=...           -> the expiry date, in UTC`;

export default async function Error526Guide({ params }: { params: Promise<{ locale: string }> }) {
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
				lede="Unlike the rest of the 52x family, this one needs two things to be true at once — and the second is a setting in your own dashboard."
				updated={guide.updated}
				readingTime={guide.readingTime}
				related={RELATED}
			>
				<div className="glass r-island note p-6 sm:p-7">
					<p>
						<strong>
							Cloudflare error 526 means two things are true at once: your encryption mode is Full (strict),
							and Cloudflare could not validate the certificate your origin presented.
						</strong>{" "}
						Fix the certificate, or change the mode.
					</p>
				</div>

				<p>
					Everything people find confusing about this error follows from that pairing. A certificate can be
					broken for months without anyone noticing, because in every other mode Cloudflare does not look. So
					&ldquo;Cloudflare 526&rdquo; is rarely a report that something just broke at your origin — more often it
					is a report that something started being <em>checked</em>. Like the rest of the family, error code 526
					is generated at Cloudflare&rsquo;s edge rather than by your application, so your own logs may show
					nothing at all, and it can only occur on a{" "}
					<Link href="/guides/what-is-the-orange-cloud-in-cloudflare">proxied record</Link>.
				</p>

				<h2 id="two-conditions">Two conditions, and both have to hold</h2>
				<Error526Validation />
				<p>
					Cloudflare&rsquo;s{" "}
					<a href={DOCS_526} target="_blank" rel="noopener noreferrer">
						documentation for error 526
					</a>{" "}
					states the two conditions explicitly: Cloudflare cannot validate the SSL certificate at your origin
					web server, <em>and</em>{" "}
					<a href={DOCS_FULL_STRICT} target="_blank" rel="noopener noreferrer">
						Full (strict)
					</a>{" "}
					is the encryption mode set for the domain. The second condition is what makes this an invalid SSL
					certificate error rather than a connection error, because{" "}
					<a href={DOCS_FULL} target="_blank" rel="noopener noreferrer">
						Full mode
					</a>{" "}
					connects to the origin over HTTPS <em>without validating the origin&rsquo;s certificate</em> — it is
					documented as the mode for origins with self-signed or otherwise invalid certificates. No validation,
					no 526.
				</p>

				<h2 id="causes">What makes a certificate invalid to Cloudflare</h2>
				<p>
					Cloudflare&rsquo;s edge trusts certificates issued by a certificate authority in its own published
					trust store. The 526 checklist in the docs is really a list of ways to fall outside it:
				</p>
				<div className="table-wrap">
					<table>
						<thead>
							<tr>
								<th scope="col">What is wrong with the certificate</th>
								<th scope="col">How it usually got that way</th>
							</tr>
						</thead>
						<tbody>
							<tr>
								<th scope="row">Expired</th>
								<td>A renewal job that stopped running, or a certificate nobody was tracking</td>
							</tr>
							<tr>
								<th scope="row">Revoked</th>
								<td>Reissued after a key compromise, with the old certificate left installed</td>
							</tr>
							<tr>
								<th scope="row">Self-signed rather than CA-issued</th>
								<td>A default certificate shipped by the web server or control panel</td>
							</tr>
							<tr>
								<th scope="row">Hostname not in the Common Name or Subject Alternative Name</th>
								<td>A certificate issued for the apex only, then used for a subdomain</td>
							</tr>
							<tr>
								<th scope="row">Incomplete chain</th>
								<td>Only the leaf installed, without the intermediate CA certificates</td>
							</tr>
							<tr>
								<th scope="row">Port 443 not accepting connections</th>
								<td>HTTPS never enabled at the origin, or firewalled off</td>
							</tr>
						</tbody>
					</table>
				</div>
				<p>
					The incomplete chain is the one worth singling out, because it is the case where your site looks fine
					in a browser and still returns 526. Cloudflare requires the origin to serve the leaf certificate
					together with any required intermediates, so that a trusted chain up to a root CA can be built. If
					your server only sends the leaf, there is nothing for Cloudflare to build with.
				</p>

				<h2 id="525-vs-526">526 vs 525: rejected, not un-negotiated</h2>
				<p>
					These two are the pair people mix up, and the split is clean: 525 is a handshake that never finished,
					526 is a handshake that finished and produced something Cloudflare would not accept.
				</p>
				<div className="table-wrap">
					<table>
						<thead>
							<tr>
								<th scope="col">&nbsp;</th>
								<th scope="col">Error 525</th>
								<th scope="col">Error 526</th>
							</tr>
						</thead>
						<tbody>
							<tr>
								<th scope="row">Cloudflare&rsquo;s name for it</th>
								<td>SSL handshake failed</td>
								<td>Invalid SSL certificate</td>
							</tr>
							<tr>
								<th scope="row">What failed</th>
								<td>The TLS negotiation itself</td>
								<td>Validation of the certificate that was negotiated</td>
							</tr>
							<tr>
								<th scope="row">Modes it can occur in</th>
								<td>Full and Full (strict)</td>
								<td>Full (strict) only</td>
							</tr>
							<tr>
								<th scope="row">Typical causes</th>
								<td>
									No certificate installed, port 443 closed, no SNI support, or{" "}
									<a href={DOCS_CIPHERS} target="_blank" rel="noopener noreferrer">
										cipher suites
									</a>{" "}
									the origin and Cloudflare do not share
								</td>
								<td>Expired, revoked, self-signed, wrong hostname, or missing intermediates</td>
							</tr>
						</tbody>
					</table>
				</div>

				<h2 id="out-of-nowhere">Why it started on a site nobody touched</h2>
				<p>
					Three mechanisms account for most &ldquo;this was working yesterday&rdquo; reports, and none of them
					involves anyone editing a server.
				</p>
				<ul>
					<li>
						<strong>Automatic SSL/TLS moved you to Full (strict).</strong> Cloudflare&rsquo;s{" "}
						<a href={DOCS_SSL_MODES} target="_blank" rel="noopener noreferrer">
							encryption mode setting
						</a>{" "}
						now defaults to a mode chosen for you by the SSL/TLS Recommender, which upgrades gradually — 1% of
						traffic, then 10% increments — and aborts if origin connectivity fails during the rollout. That is
						the benign path. The trap comes later: Cloudflare states plainly that Automatic SSL/TLS{" "}
						<em>will not</em> move you back to a less secure mode if your origin certificate later expires.
						Once you are on Full (strict), you own that certificate&rsquo;s validity for good.
					</li>
					<li>
						<strong>A Cloudflare Origin CA certificate quietly expired.</strong> These are long-lived, which
						is the point, and Cloudflare documents that it does not currently send expiration notifications
						for them. A certificate issued years ago by someone who has since left is exactly the kind of
						thing that surfaces as a sudden 526.
					</li>
					<li>
						<strong>A renewal reinstalled the leaf without its intermediates.</strong> Automated renewals
						usually get this right; a hand-copied <code>.crt</code> file often does not.
					</li>
				</ul>

				<h2 id="confirm">Confirming it yourself</h2>
				<p>
					Ask the origin directly, with Cloudflare out of the path, so you see the same chain Cloudflare sees:
				</p>
				<pre>
					<code>{OPENSSL_CHECK}</code>
				</pre>
				<p>
					Cloudflare&rsquo;s own suggestion is the browser-based equivalent:{" "}
					<a href={DOCS_PAUSE} target="_blank" rel="noopener noreferrer">
						pause Cloudflare
					</a>{" "}
					and run your hostname through an SSL checker. Either way you are looking for the same three things:
					the chain includes an intermediate, the verification succeeds, and the expiry is in the future.
				</p>

				<h2 id="fixes">Three ways out, cheapest first</h2>
				<ol>
					<li>
						<strong>
							Install a{" "}
							<a href={DOCS_ORIGIN_CA} target="_blank" rel="noopener noreferrer">
								Cloudflare Origin CA certificate
							</a>
							.
						</strong>{" "}
						Free on every plan including Free, issued from the dashboard, and trusted by Cloudflare by design.
						One caveat that catches people: these certificates encrypt only the Cloudflare-to-origin hop and
						are not publicly trusted, so if you later switch that record to DNS only, visitors will see
						certificate warnings.
					</li>
					<li>
						<strong>
							Upload your CA to the{" "}
							<a href={DOCS_COTS} target="_blank" rel="noopener noreferrer">
								Custom Origin Trust Store
							</a>
							.
						</strong>{" "}
						The route for an internal or private CA — but it requires{" "}
						<a href={DOCS_ACM} target="_blank" rel="noopener noreferrer">
							Advanced Certificate Manager
						</a>{" "}
						on the zone, and once a CA is uploaded Cloudflare ignores its default trust store for that zone
						entirely and uses only what you supplied.
					</li>
					<li>
						<strong>Drop to Full.</strong> Cloudflare lists this first as a &ldquo;potential quick fix&rdquo;,
						and it does stop the error immediately — because the check stops happening. Traffic to your origin
						stays encrypted but unauthenticated. Treat it as a way to buy an afternoon, not a resolution.
					</li>
				</ol>

				<h2 id="not-your-setting">Two places where your zone setting does not apply</h2>
				<p>
					Both are documented, and both produce a 526 on a zone that is not in Full (strict) at all — which is
					why they are worth knowing before you spend an hour checking a setting that is already correct.
				</p>
				<p>
					<strong>Workers.</strong> A subrequest from a Worker to a hostname outside your Cloudflare zone that
					is not proxied by Cloudflare always uses Full (strict), regardless of the zone configuration. If you
					need such a fetch to trust a private CA, the Custom Origin Trust Store applies only once the{" "}
					<code>cots_on_external_fetch</code>{" "}
					<a href={DOCS_COMPAT_FLAGS} target="_blank" rel="noopener noreferrer">
						compatibility flag
					</a>{" "}
					is enabled.
				</p>
				<p>
					<strong>Cloudflare Gateway.</strong> In the Zero Trust path a 526 means Gateway distrusted the origin
					— an unknown or revoked issuer, an expired certificate anywhere in the chain, a name mismatch, or a
					name containing characters such as underscores that Chrome tolerates and Gateway does not. Gateway
					also refuses origins that offer only insecure cipher suites, or that redirect every HTTPS request to
					HTTP.
				</p>

				<h2 id="neighbours">Where 526 sits among the origin errors</h2>
				<div className="table-wrap">
					<table>
						<thead>
							<tr>
								<th scope="col">Error</th>
								<th scope="col">How far the connection got</th>
							</tr>
						</thead>
						<tbody>
							<tr>
								<th scope="row">
									<Link href="/guides/cloudflare-error-521-web-server-is-down">521</Link>
								</th>
								<td>Refused at once — no TCP connection</td>
							</tr>
							<tr>
								<th scope="row">
									<Link href="/guides/cloudflare-error-522-connection-timed-out">522</Link>
								</th>
								<td>Silence — no TCP connection within 19 seconds</td>
							</tr>
							<tr>
								<th scope="row">
									<a href={DOCS_525} target="_blank" rel="noopener noreferrer">
										525
									</a>
								</th>
								<td>TCP connected, TLS handshake failed</td>
							</tr>
							<tr>
								<th scope="row">
									<a href={DOCS_526} target="_blank" rel="noopener noreferrer">
										526
									</a>
								</th>
								<td>TLS handshake succeeded, certificate rejected</td>
							</tr>
						</tbody>
					</table>
				</div>
				<p>
					Read down that column and the family becomes a single sequence: each error is the connection getting
					one step further before failing. A 526 is the furthest of the four, which is genuinely good news — the
					network path works, the port is open, TLS negotiates. Only the paperwork is wrong. The{" "}
					<a href={DOCS_5XX} target="_blank" rel="noopener noreferrer">
						5xx index
					</a>{" "}
					covers the rest of the family, and{" "}
					<Link href="/guides/cloudflare-ssl-tls-encryption-modes">the guide to the encryption modes</Link>{" "}
					covers the setting that decides whether the paperwork gets checked.
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
