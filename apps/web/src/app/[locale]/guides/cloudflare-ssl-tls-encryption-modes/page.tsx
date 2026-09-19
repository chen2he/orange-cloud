import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { setRequestLocale } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import GuideShell, { type RelatedLink } from "@/components/guides/GuideShell";
import TlsHops from "@/components/guides/TlsHops";
import { guideBySlug, GUIDE_LOCALE } from "@/lib/guides/guides";

const SITE_URL = "https://o-c.do";
const guide = guideBySlug("cloudflare-ssl-tls-encryption-modes");
const PATH = `/guides/${guide.slug}`;

const DOCS_MODES = "https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/";
const DOCS_REDIRECTS = "https://developers.cloudflare.com/ssl/troubleshooting/too-many-redirects/";
const DOCS_ORIGIN_CA = "https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/";

/** FAQ 一处定义：可见文本与 FAQPage JSON-LD 同源，保证逐字一致 */
const FAQ: Array<{ q: string; a: string }> = [
	{
		q: "What is the difference between Flexible and Full in Cloudflare?",
		a: "Flexible sends requests to your origin over plain HTTP, so the second half of the journey is unencrypted and no origin certificate is needed. Full connects to the origin using the same scheme the visitor used, so an HTTPS request stays encrypted end to end — but the origin’s certificate is not checked.",
	},
	{
		q: "Is Cloudflare Flexible SSL secure?",
		a: "Only partially. Visitors see a valid padlock because the visitor-to-Cloudflare connection is encrypted, but traffic between Cloudflare and your origin travels in cleartext and can be read or modified in transit. Cloudflare advises against it for anything carrying logins or personal data.",
	},
	{
		q: "Why does Cloudflare say ERR_TOO_MANY_REDIRECTS?",
		a: "Usually because your encryption mode and your origin disagree about which scheme to use. On Flexible, Cloudflare requests HTTP and an origin that redirects all HTTP to HTTPS sends the request straight back, and the loop repeats until the browser gives up.",
	},
	{
		q: "What is the difference between Full and Full (strict)?",
		a: "Both encrypt the connection to your origin. Full accepts any certificate the origin presents, including expired, self-signed, or wrong-hostname ones. Full (strict) requires an unexpired certificate from a publicly trusted CA or Cloudflare Origin CA whose name matches the hostname.",
	},
	{
		q: "Do I still need an SSL certificate on my origin if I use Cloudflare?",
		a: "For every mode except Off and Flexible, yes. Cloudflare issues the certificate visitors see, but the connection from Cloudflare to your server needs its own certificate — a free Cloudflare Origin CA certificate satisfies Full (strict) and never has to be publicly trusted.",
	},
];

const RELATED: RelatedLink[] = [
	{
		href: "/guides/cloudflare-error-525-ssl-handshake-failed",
		label: "Cloudflare error 525: SSL handshake failed",
		note: "What Full and Full (strict) both produce when the origin cannot negotiate TLS at all.",
	},
	{
		href: "/guides/cloudflare-error-526-invalid-ssl-certificate",
		label: "Cloudflare error 526: invalid SSL certificate",
		note: "What Full (strict) does when the origin certificate does not check out \u2014 the error this setting exists to produce.",
	},
	{
		href: "/guides/what-is-the-orange-cloud-in-cloudflare",
		label: "What is the orange cloud in Cloudflare?",
		note: "The prerequisite: encryption modes only apply to records that are proxied in the first place.",
	},
	{
		href: "/guides/cloudflare-orange-to-orange",
		label: "Cloudflare Orange-to-Orange (O2O), explained",
		note: "When your proxied hostname routes into a SaaS provider’s Cloudflare zone, and which zone’s settings win.",
	},
	{
		href: "/guides/why-is-cloudflare-not-caching-my-site",
		label: "cf-cache-status: DYNAMIC vs BYPASS vs MISS",
		note: "The origin scheme this setting picks is part of every cache key — what that means in practice.",
	},
	{
		href: DOCS_MODES,
		label: "Cloudflare docs: Encryption modes",
		note: "The official reference for every mode, the Automatic SSL/TLS rollout, and the API values.",
		external: true,
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

export default async function EncryptionModesGuide({ params }: { params: Promise<{ locale: string }> }) {
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
				lede="One dropdown decides whether the second half of every request is encrypted. Here is what each option does, which errors each one produces, and why the choice may no longer be yours."
				updated={guide.updated}
				readingTime={guide.readingTime}
				related={RELATED}
			>
				<div className="glass r-island note p-6 sm:p-7">
					<p>
						<strong>Use Full (strict).</strong> It encrypts the Cloudflare-to-origin hop and validates your
						origin certificate. <strong>Flexible</strong> sends plaintext to your origin and is the most
						common cause of redirect loops. Most zones now choose the mode automatically.
					</p>
				</div>

				<p>
					The padlock in a visitor’s browser is not a statement about your server. It only says the browser
					reached Cloudflare over HTTPS. What happens on the next leg — from Cloudflare to the machine that
					actually holds your site — is a separate connection with separate rules, and the SSL/TLS encryption
					mode is the setting that governs it.
				</p>

				<h2 id="two-connections">There are two connections, not one</h2>
				<TlsHops />
				<p>
					Every proxied request is two hops. The first is secured by the edge certificate Cloudflare issues
					and renews for you; there is nothing to choose there. The second is the one the encryption mode
					controls: whether Cloudflare speaks HTTP or HTTPS to your origin, and how carefully it inspects the
					certificate your origin presents.
				</p>
				<p>
					This is also why the setting is invisible on some records. It only takes effect where Cloudflare is
					in the path at all — a DNS-only record hands out your server’s real address and the browser
					connects directly, so there is no second hop for the mode to govern. If that distinction is new,
					start with{" "}
					<Link href="/guides/what-is-the-orange-cloud-in-cloudflare">
						what the orange cloud is and what proxying changes
					</Link>
					.
				</p>

				<h2 id="modes">The five modes, side by side</h2>
				<div className="table-wrap">
					<table>
						<thead>
							<tr>
								<th scope="col">Mode</th>
								<th scope="col">Visitor → Cloudflare</th>
								<th scope="col">Cloudflare → origin</th>
								<th scope="col">Origin certificate checked</th>
								<th scope="col">Choose it when</th>
							</tr>
						</thead>
						<tbody>
							<tr>
								<th scope="row">Off</th>
								<td>Cleartext — HTTPS is redirected down to HTTP</td>
								<td>Cleartext</td>
								<td>No</td>
								<td>Never, in practice</td>
							</tr>
							<tr>
								<th scope="row">Flexible</th>
								<td>Encrypted</td>
								<td>Cleartext</td>
								<td>No</td>
								<td>Your origin genuinely cannot serve TLS</td>
							</tr>
							<tr>
								<th scope="row">Full</th>
								<td>Encrypted</td>
								<td>Matches the visitor’s scheme</td>
								<td>No</td>
								<td>The origin has a certificate, but not a valid public one</td>
							</tr>
							<tr>
								<th scope="row">Full (strict)</th>
								<td>Encrypted</td>
								<td>Matches the visitor’s scheme</td>
								<td>Yes</td>
								<td>The default target for almost everyone</td>
							</tr>
							<tr>
								<th scope="row">Strict (SSL-Only Origin Pull)</th>
								<td>Either</td>
								<td>Always encrypted</td>
								<td>Yes</td>
								<td>Enterprise zones wanting the strongest option</td>
							</tr>
						</tbody>
					</table>
				</div>
				<p>
					Two rows deserve a second look. <strong>Full</strong> encrypts, but accepts whatever certificate
					the origin offers — expired, self-signed, issued for a different hostname, all fine. That stops
					passive eavesdropping and nothing else: an attacker positioned between Cloudflare and your origin
					can present their own certificate and be believed. <strong>Full (strict)</strong> is the same
					connection with the certificate actually verified, which is the difference between encryption and
					authenticated encryption.
				</p>
				<p>
					The last row is easy to miss because it is Enterprise-only. Unlike Full and Full (strict), which
					mirror whatever scheme the visitor used, it connects to the origin over HTTPS even when the visitor
					arrived over plain HTTP.
				</p>

				<h2 id="automatic">The choice may already have been made for you</h2>
				<p>
					Cloudflare has been rolling out <strong>Automatic SSL/TLS</strong>, and it is the default for zones
					that have been migrated. Instead of a fixed setting, a crawler using the{" "}
					<code>Cloudflare-SSLDetector</code> user agent fetches your site over both HTTP and HTTPS,
					compares the responses, and picks the most secure mode your origin can actually support. Zones that
					have not been migrated still show only the manual list.
				</p>
				<p>Four properties of that system are worth knowing before you go looking for the dropdown:</p>
				<ul>
					<li>
						<strong>It never moves you to something less secure.</strong> If your origin certificate
						expires, a zone on Full (strict) is not quietly demoted to Full — it stays put and starts
						failing, which is the correct behaviour but means you still have to keep the certificate valid.
					</li>
					<li>
						<strong>Upgrades ramp, they do not flip.</strong> A new mode starts on 1% of traffic and climbs
						in 10% steps. If origin connectivity breaks on the way up, Cloudflare aborts and rolls back.
						Moves from Flexible to Full or stricter go slower still, because changing the origin scheme
						changes cache keys and the cache needs to warm.
					</li>
					<li>
						<strong>Scans are roughly monthly</strong>, and stop once the zone is already on the most
						secure mode available or you have switched to Custom SSL/TLS.
					</li>
					<li>
						<strong>Notifications go to Super Admins only</strong>, as a weekly digest of upgraded zones.
						If your account’s admin address is not one you read, upgrades will look like they came from
						nowhere.
					</li>
				</ul>
				<p>
					To take manual control, switch the zone to Custom SSL/TLS — in the API that is the{" "}
					<code>ssl_automatic_mode</code> zone setting set to <code>custom</code>. The mode itself remains
					the <code>ssl</code> setting, with values <code>off</code>, <code>flexible</code>,{" "}
					<code>full</code>, <code>strict</code>, and <code>origin_pull</code>. Note the naming trap:{" "}
					<code>strict</code> is Full (strict), while the Enterprise SSL-only mode is{" "}
					<code>origin_pull</code>.
				</p>

				<h2 id="flexible">Why Flexible causes so much trouble</h2>
				<p>
					Flexible is popular because it makes a padlock appear without touching the server. The costs show
					up later.
				</p>
				<ul>
					<li>
						<strong>Redirect loops.</strong> Cloudflare requests your origin over HTTP. Most modern stacks
						redirect all HTTP to HTTPS. Cloudflare follows that redirect back to itself, downgrades it to
						HTTP again, and the browser reports{" "}
						<a href={DOCS_REDIRECTS} target="_blank" rel="noopener noreferrer">
							ERR_TOO_MANY_REDIRECTS
						</a>
						. The fix is to remove the origin’s HTTPS redirect or move to Full — not to add another rule.
					</li>
					<li>
						<strong>Port 443 only.</strong> Flexible applies to HTTPS on the default port. HTTPS on any
						other port falls back to Full behaviour, so a site served on a non-standard port can behave
						differently from the rest of the zone for reasons nothing in the dashboard explains.
					</li>
					<li>
						<strong>Authenticated Origin Pulls is unavailable.</strong> It does not work under Flexible or
						Off, which rules out the standard way of proving to your origin that a request really came from
						Cloudflare.
					</li>
					<li>
						<strong>The traffic is readable.</strong> Anything between Cloudflare and your origin —
						hosting network, transit provider, anyone who has got in the middle — sees session cookies and
						form posts in cleartext.
					</li>
				</ul>

				<h2 id="errors">Which error means which mode</h2>
				<p>The failure tells you where to look, and the mapping is tight:</p>
				<div className="table-wrap">
					<table>
						<thead>
							<tr>
								<th scope="col">What you see</th>
								<th scope="col">Mode in play</th>
								<th scope="col">What it actually means</th>
							</tr>
						</thead>
						<tbody>
							<tr>
								<th scope="row">Error 525</th>
								<td>Full or Full (strict)</td>
								<td>
									The TLS handshake with your origin failed: no certificate, port 443 closed, missing
									SNI support, or no shared cipher suite
								</td>
							</tr>
							<tr>
								<th scope="row">Error 526</th>
								<td>Full (strict)</td>
								<td>
									A certificate was presented but rejected — expired, revoked, self-signed, incomplete
									chain, or the hostname does not match
								</td>
							</tr>
							<tr>
								<th scope="row">ERR_TOO_MANY_REDIRECTS</th>
								<td>Flexible</td>
								<td>Your origin redirects HTTP to HTTPS while Cloudflare insists on HTTP</td>
							</tr>
							<tr>
								<th scope="row">ERR_TOO_MANY_REDIRECTS</th>
								<td>Full or Full (strict)</td>
								<td>The mirror image: your origin redirects HTTPS down to HTTP</td>
							</tr>
						</tbody>
					</table>
				</div>
				<p>
					Treat 526 as a certificate problem, not a reason to downgrade. Dropping to Full does clear the
					error, and it clears it by no longer checking — the misconfiguration is still there, just silent.
					An incomplete chain is a common culprit: your origin must serve the intermediate certificates
					alongside the leaf, or Cloudflare cannot build a path to a trusted root even though the certificate
					itself is fine.
				</p>

				<h2 id="upgrade">Moving to Full (strict) without an outage</h2>
				<ol>
					<li>
						Put a certificate on the origin. A{" "}
						<a href={DOCS_ORIGIN_CA} target="_blank" rel="noopener noreferrer">
							Cloudflare Origin CA certificate
						</a>{" "}
						is free, lasts for years, and is trusted by Cloudflare specifically — it is not publicly
						trusted, which is fine, because only Cloudflare ever validates it.
					</li>
					<li>
						Confirm the origin answers on port 443, presents the full chain, and that the certificate’s
						name covers the hostname being requested.
					</li>
					<li>
						Remove any HTTP-to-HTTPS redirect at the origin. Cloudflare handles the visitor-facing
						redirect; leaving one at the origin is what creates loops after the switch.
					</li>
					<li>
						Switch to Full (strict) and watch for 525 and 526 in your analytics. Both are origin-side
						failures, so the answer is always on the server, not in the dashboard.
					</li>
					<li>
						If only one hostname needs a different mode, use a configuration rule rather than moving the
						whole zone.
					</li>
				</ol>
				<p>
					One caveat when a hostname is served through a SaaS platform on Cloudflare: your zone is not the
					only one applying settings, and the encryption mode you can see may not be the one deciding the
					final hop. That situation has{" "}
					<Link href="/guides/cloudflare-orange-to-orange">its own rules, covered here</Link>.
				</p>
				<p>
					Modes change and their behaviour is occasionally revised; before relying on a specific row above,
					check{" "}
					<a href={DOCS_MODES} target="_blank" rel="noopener noreferrer">
						the official encryption modes reference
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
