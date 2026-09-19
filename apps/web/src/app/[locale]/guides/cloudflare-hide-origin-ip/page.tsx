import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { setRequestLocale } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import GuideShell, { type RelatedLink } from "@/components/guides/GuideShell";
import OriginExposurePaths from "@/components/guides/OriginExposurePaths";
import { guideBySlug, GUIDE_LOCALE } from "@/lib/guides/guides";

const SITE_URL = "https://o-c.do";
const guide = guideBySlug("cloudflare-hide-origin-ip");
const PATH = `/guides/${guide.slug}`;

const DOCS_PROTECT_ORIGIN =
  "https://developers.cloudflare.com/fundamentals/security/protect-your-origin-server/";
const DOCS_PROXY_STATUS =
  "https://developers.cloudflare.com/dns/proxy-status/";
const DOCS_CF_IPS =
  "https://developers.cloudflare.com/fundamentals/concepts/cloudflare-ip-addresses/";
const DOCS_TUNNEL =
  "https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/";
const DOCS_AOP =
  "https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/";
const DOCS_TRANSFORM =
  "https://developers.cloudflare.com/rules/transform/request-header-modification/";
const DOCS_FULL_STRICT =
  "https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/";
const DOCS_ROUND_ROBIN =
  "https://developers.cloudflare.com/dns/manage-dns-records/how-to/round-robin-dns/";
const DOCS_FULL_SETUP =
  "https://developers.cloudflare.com/dns/zone-setups/full-setup/setup/";

/** FAQ 一处定义：可见文本与 FAQPage JSON-LD 同源，保证逐字一致 */
const FAQ: Array<{ q: string; a: string }> = [
  {
    q: "Does Cloudflare hide my origin IP address?",
    a: "It hides it from DNS. A proxied record answers with a Cloudflare address instead of yours, so the ordinary way of looking up a server no longer returns it. That is concealment, not protection: if the address becomes known by some other route, nothing stops a connection straight to it.",
  },
  {
    q: "How do I stop people bypassing Cloudflare and hitting my origin directly?",
    a: "Make the origin refuse anything that did not come from Cloudflare. The options Cloudflare documents are Cloudflare Tunnel, which removes the public IP entirely, Authenticated Origin Pulls at the transport layer, a secret header added by a transform rule, and allowlisting Cloudflare IP ranges at your firewall.",
  },
  {
    q: "Can changing my server IP fix an origin IP leak?",
    a: "It helps, and Cloudflare recommends rotating origin IPs after onboarding because historical DNS records are public and keep the old address alive. But rotation only buys time. If the route that exposed the address is still open, the new one leaks the same way.",
  },
  {
    q: "Do DNS-only records expose my origin server?",
    a: "They can. Any record left grey-clouded answers with the real address, and Cloudflare specifically advises auditing DNS-only records such as SPF and TXT entries to make sure they do not contain origin IP information.",
  },
  {
    q: "Is allowlisting Cloudflare IP addresses enough on its own?",
    a: "Cloudflare rates it as moderately secure rather than very secure, and notes it is vulnerable to IP spoofing. It is also a list that changes, so it needs maintaining. Treat it as a solid floor to combine with Authenticated Origin Pulls or a secret header, not as the finished job.",
  },
];

const RELATED: RelatedLink[] = [
  {
    href: "/guides/cloudflare-real-visitor-ip-cf-connecting-ip",
    label: "Why do my server logs show Cloudflare\u2019s IP, not the visitor\u2019s?",
    note: "The mirror image of this problem — and the header you must stop trusting once your origin only accepts Cloudflare.",
  },
  {
    href: "/guides/what-is-the-orange-cloud-in-cloudflare",
    label: "What does the orange cloud mean in Cloudflare?",
    note: "Which records can be proxied at all, and why the grey-clouded ones are the first place an address escapes.",
  },
  {
    href: "/guides/cloudflare-ssl-tls-encryption-modes",
    label: "Which Cloudflare SSL/TLS encryption mode should you use?",
    note: "Authenticated Origin Pulls needs Full or Full (strict), so the two settings have to be planned together.",
  },
  {
    href: DOCS_PROTECT_ORIGIN,
    label: "Cloudflare docs: Protect your origin server",
    note: "The reference this guide was checked against, with Cloudflare's own security rating for each option.",
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

export default async function HideOriginIpGuide({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
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
      publisher: {
        "@type": "Organization",
        name: "Orange Cloud",
        url: SITE_URL,
      },
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
        {
          "@type": "ListItem",
          position: 1,
          name: "Guides",
          item: `${SITE_URL}/guides`,
        },
        {
          "@type": "ListItem",
          position: 2,
          name: guide.h1,
          item: `${SITE_URL}${PATH}`,
        },
      ],
    },
  ];

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
      <GuideShell
        title={guide.h1}
        lede="Turning a record orange changes what DNS answers. It does not change what your server will answer — and that gap is the whole subject."
        updated={guide.updated}
        readingTime={guide.readingTime}
        related={RELATED}
      >
        <div className="glass r-island note p-6 sm:p-7">
          <p>
            <strong>
              Yes. Proxying hides your origin IP address from DNS, but it does
              not stop anything from connecting to that address directly.
            </strong>{" "}
            Concealment buys you time; only a rule at the origin closes the
            door.
          </p>
        </div>

        <p>
          This is the most consequential misunderstanding in Cloudflare
          onboarding. A{" "}
          <Link href="/guides/what-is-the-orange-cloud-in-cloudflare">
            proxied record
          </Link>{" "}
          answers queries with a Cloudflare address, so the obvious lookup no
          longer returns your server. It is easy to read that as a shield.
          Cloudflare&rsquo;s own{" "}
          <a
            href={DOCS_PROXY_STATUS}
            target="_blank"
            rel="noopener noreferrer"
          >
            proxy status documentation
          </a>{" "}
          is careful about the wording: proxying <em>hides</em> origin IP
          addresses. Hiding and defending are different jobs.
        </p>
        <OriginExposurePaths />

        <h2 id="how-it-gets-out">The routes an address escapes by</h2>
        <p>
          Cloudflare&rsquo;s{" "}
          <a
            href={DOCS_PROTECT_ORIGIN}
            target="_blank"
            rel="noopener noreferrer"
          >
            guidance on protecting your origin
          </a>{" "}
          names most of these directly, and the striking thing about the list is
          how little of it involves anyone attacking you. Addresses mostly leak
          through ordinary configuration:
        </p>
        <ul>
          <li>
            <strong>Records you left grey-clouded.</strong> A DNS-only record
            answers with the real address by definition. Cloudflare advises
            auditing existing DNS-only records — it calls out <code>SPF</code>{" "}
            and <code>TXT</code> entries — to make sure they do not carry origin
            IP information.
          </li>
          <li>
            <strong>Mail on the same machine.</strong> Cloudflare recommends not
            hosting a mail service on the same server as the web resource you
            want to protect, for a specific reason: mail sent to non-existent
            addresses bounces back to the sender and reveals the mail
            server&rsquo;s IP. Nobody has to break anything — the server
            volunteers it.
          </li>
          <li>
            <strong>History.</strong> DNS records are public and historical
            copies are retained, so the address you used before you onboarded
            remains discoverable afterwards. This is why Cloudflare&rsquo;s{" "}
            <a
              href={DOCS_FULL_SETUP}
              target="_blank"
              rel="noopener noreferrer"
            >
              setup guidance
            </a>{" "}
            recommends rotating your origin IPs once you are onboarded rather
            than keeping the address that was public for years.
          </li>
          <li>
            <strong>Your own application.</strong> Anything that emits an
            absolute URL or connects outward — webhook callers, password reset
            emails, error pages, SSRF-prone endpoints — can carry the address
            out with it.
          </li>
        </ul>
        <p>
          None of these are exotic. They are the reason &ldquo;we are behind
          Cloudflare&rdquo; and &ldquo;our origin is unreachable&rdquo; are
          rarely the same statement.
        </p>

        <h2 id="closing-the-door">Making the origin refuse strangers</h2>
        <p>
          The fix is not better hiding. It is arranging for your origin to
          reject any request that did not arrive through Cloudflare. Cloudflare
          documents several ways to do that, at different layers and with
          different costs, and rates each one:
        </p>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th scope="col">Approach</th>
                <th scope="col">Layer</th>
                <th scope="col">Rated</th>
                <th scope="col">Main cost</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <th scope="row">
                  <a
                    href={DOCS_TUNNEL}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    Cloudflare Tunnel
                  </a>
                </th>
                <td>Application</td>
                <td>Very secure</td>
                <td>
                  Run the <code>cloudflared</code> daemon on the origin
                </td>
              </tr>
              <tr>
                <th scope="row">
                  <a href={DOCS_AOP} target="_blank" rel="noopener noreferrer">
                    Authenticated Origin Pulls
                  </a>
                </th>
                <td>Transport</td>
                <td>Very secure</td>
                <td>
                  Needs Full or{" "}
                  <a
                    href={DOCS_FULL_STRICT}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    Full (strict)
                  </a>
                  ; certificate work per origin
                </td>
              </tr>
              <tr>
                <th scope="row">
                  <a
                    href={DOCS_TRANSFORM}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    Secret header validation
                  </a>
                </th>
                <td>Application</td>
                <td>Moderately secure</td>
                <td>Config on both sides; must stay over TLS</td>
              </tr>
              <tr>
                <th scope="row">
                  <a
                    href={DOCS_CF_IPS}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    Allowlist Cloudflare IPs
                  </a>
                </th>
                <td>Network</td>
                <td>Moderately secure</td>
                <td>Vulnerable to spoofing; the list changes</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p>
          Tunnel is the one that changes the shape of the problem rather than
          patching it. Because <code>cloudflared</code> makes outbound-only
          connections to Cloudflare, the origin does not need a publicly
          routable address at all — and an address that does not exist cannot
          leak. Everything else on that list is a filter in front of a server
          that is still reachable.
        </p>
        <p>
          Two cautions worth reading before you pick. On Authenticated Origin
          Pulls, Cloudflare notes that the certificate it provides for easy
          configuration only proves a request came from{" "}
          <em>the Cloudflare network</em> — not from your zone specifically — so
          uploading your own certificate is the stricter option. And on IP
          allowlisting, Cloudflare rates it only moderately secure and flags IP
          spoofing explicitly. Use it as a floor under one of the stronger two,
          not instead of them.
        </p>

        <h2 id="order">A sensible order to do this in</h2>
        <p>
          You do not need all of it, and doing it in the wrong order produces an
          outage rather than a hardened server. Working from cheapest to most
          disruptive:
        </p>
        <ol>
          <li>
            <strong>Audit DNS first.</strong> Every grey-clouded record, every
            leftover <code>mail</code>, <code>cpanel</code>, <code>ftp</code> or{" "}
            <code>direct</code> hostname, every TXT record with a literal
            address in it. This is free and closes the widest hole.
          </li>
          <li>
            <strong>Then allowlist Cloudflare at the firewall.</strong> Do this
            before rotating anything, and remember Cloudflare&rsquo;s companion
            advice: allowing Cloudflare addresses at the origin is also what
            keeps proxied traffic from being blocked once the default becomes
            deny.
          </li>
          <li>
            <strong>Add a second factor.</strong> Authenticated Origin Pulls or
            a secret header, so that a spoofed source address alone is not
            enough.
          </li>
          <li>
            <strong>Rotate the address last.</strong> Rotation is what makes the
            historical records worthless — but only after the routes that would
            leak the new one are closed. Rotating first simply publishes a fresh
            address through the same open door.
          </li>
        </ol>
        <p>
          If you have{" "}
          <a
            href={DOCS_ROUND_ROBIN}
            target="_blank"
            rel="noopener noreferrer"
          >
            several origin records
          </a>{" "}
          behind one hostname, do the audit against all of them. It only takes
          one forgotten record to make the other work decorative.
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
