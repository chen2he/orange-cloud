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

const DOCS_5XXX =
  "https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/";
const DOCS_525 = `${DOCS_5XXX}error-525/`;
const DOCS_526 = `${DOCS_5XXX}error-526/`;
const DOCS_SSL_MODES =
  "https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/";
const DOCS_FULL =
  "https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full/";
const DOCS_FULL_STRICT =
  "https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/";
const DOCS_ORIGIN_CIPHERS =
  "https://developers.cloudflare.com/ssl/origin-configuration/cipher-suites/";
const DOCS_ORIGIN_CA =
  "https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/";
const DOCS_ORIGIN_ANALYTICS =
  "https://developers.cloudflare.com/speed/origin-analytics/";
const DOCS_CURL =
  "https://developers.cloudflare.com/support/troubleshooting/general-troubleshooting/gathering-information-for-troubleshooting-sites/";
const DOCS_DYNAMIC_IP =
  "https://developers.cloudflare.com/dns/manage-dns-records/how-to/managing-dynamic-ip-addresses/";
const DOCS_TRUST_STORE =
  "https://developers.cloudflare.com/ssl/origin-configuration/custom-origin-trust-store/";

/** FAQ 一处定义：可见文本与 FAQPage JSON-LD 同源，保证逐字一致 */
const FAQ: Array<{ q: string; a: string }> = [
  {
    q: "What does Cloudflare error 525 mean?",
    a: "It means Cloudflare opened a TCP connection to your origin server but the TLS handshake that followed did not complete, so no encrypted channel was ever established. Cloudflare documents two conditions for it: the handshake failed, and your encryption mode is Full or Full (strict).",
  },
  {
    q: "How do I fix Cloudflare error 525?",
    a: "Fix the handshake at the origin rather than in the Cloudflare dashboard. Cloudflare lists four causes to rule out: no valid certificate installed, port 443 not open, no SNI support, and no cipher suite in common with Cloudflare. Installing a free Cloudflare Origin CA certificate and opening port 443 resolves the majority of cases.",
  },
  {
    q: "What is the difference between Cloudflare error 525 and 526?",
    a: "A 525 means the handshake never completed, so Cloudflare never got a usable certificate to look at. A 526 means the handshake did complete, the certificate arrived, and Cloudflare then refused to validate it. That is why 526 needs Full (strict) specifically, while 525 happens under Full as well.",
  },
  {
    q: "Will switching from Full (strict) to Full fix error 525?",
    a: "No. That is the documented quick fix for a 526, and it is the single most common piece of wrong advice about 525. Cloudflare's own page for Full mode warns that visitors may see a 525 if the origin does not allow HTTPS connections on port 443 and present a certificate, so the error survives the change.",
  },
  {
    q: "Is error 525 a problem with Cloudflare or with my server?",
    a: "Almost always your server. Cloudflare's resolution steps are addressed to your hosting provider, and every listed cause is a setting at the origin. The exception worth checking first is a hosting provider that changes your origin IP address, which points Cloudflare at a machine that was never configured to terminate TLS for your hostname.",
  },
];

const RELATED: RelatedLink[] = [
  {
    href: "/guides/cloudflare-error-526-invalid-ssl-certificate",
    label: "Cloudflare error 526: invalid SSL certificate",
    note: "The sibling code, and the one where relaxing the encryption mode genuinely is a documented fix.",
  },
  {
    href: "/guides/cloudflare-ssl-tls-encryption-modes",
    label: "Which Cloudflare SSL/TLS encryption mode should you use?",
    note: "What Off, Flexible, Full and Full (strict) each do to the Cloudflare-to-origin hop.",
  },
  {
    href: "/guides/cloudflare-error-521-web-server-is-down",
    label: "Cloudflare error 521: web server is down",
    note: "One layer earlier — the origin refusing the TCP connection before TLS ever starts.",
  },
  {
    href: DOCS_525,
    label: "Cloudflare docs: Error 525",
    note: "The reference this guide was checked against, including the four documented causes.",
    external: true,
  },
  {
    href: "/guides/cloudflare-error-codes",
    label: "Cloudflare error codes: 5xx vs 1xxx",
    note: "Where the TLS pair sits in the wider set, and which codes are decided before the origin is reached.",
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

export default async function Error525Guide({
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
        lede="The connection reached your server and then died one layer in. Most advice for this code recycles the fix for its neighbour 526 — which is exactly the change that leaves a 525 untouched."
        updated={guide.updated}
        readingTime={guide.readingTime}
        related={RELATED}
      >
        <div className="glass r-island note p-6 sm:p-7">
          <p>
            <strong>
              Cloudflare error 525 means the TLS handshake between Cloudflare
              and your origin server failed.
            </strong>{" "}
            It happens in both Full and Full (strict) encryption modes, so
            loosening the mode — the usual fix for a 526 — will not clear it.
          </p>
        </div>

        <p>
          The full wording on the page is{" "}
          <em>error 525: SSL handshake failed</em>, and &ldquo;Cloudflare
          525&rdquo;, &ldquo;error code 525&rdquo; and &ldquo;CF error
          525&rdquo; all refer to the same thing. It is worth being precise
          about where it sits, because the neighbouring codes have completely
          different fixes: the TCP connection to your origin already succeeded.
          Something answered on the port. What failed is the negotiation that
          happens immediately afterwards, before a single byte of HTTP is
          exchanged.
        </p>

        <h2 id="two-conditions">
          Two conditions, and one of them surprises people
        </h2>
        <p>
          Cloudflare&rsquo;s{" "}
          <a href={DOCS_525} target="_blank" rel="noopener noreferrer">
            reference for this error
          </a>{" "}
          states that it occurs when two things are true at once: the SSL
          handshake between Cloudflare and the origin fails, <em>and</em> the
          encryption mode is{" "}
          <a href={DOCS_SSL_MODES} target="_blank" rel="noopener noreferrer">
            Full or Full (strict)
          </a>
          .
        </p>
        <p>
          That second condition is the one that trips people up, because it is
          an <strong>or</strong>, not an <em>and</em>. A great deal of advice
          about this code assumes 525 is a strictness problem and tells you to
          step down from Full (strict) to Full. That is the documented quick fix
          for a{" "}
          <Link href="/guides/cloudflare-error-526-invalid-ssl-certificate">
            526
          </Link>
          , and it does nothing here. Cloudflare&rsquo;s own page for{" "}
          <a href={DOCS_FULL} target="_blank" rel="noopener noreferrer">
            Full mode
          </a>{" "}
          says the opposite in its prerequisites: make sure the origin allows
          HTTPS connections on port 443 and presents a certificate, otherwise
          visitors may see a 525.
        </p>
        <p>
          There is one genuine subtlety in Full mode worth knowing before you go
          hunting. Cloudflare documents Full as connecting to the origin{" "}
          <em>using the scheme the visitor requested</em> — an HTTP visitor gets
          a plaintext connection to your origin, an HTTPS visitor gets a TLS
          one. So on a Full-mode zone a 525 can only ever appear on HTTPS
          requests, which is why the error sometimes looks intermittent when the
          real pattern is that only some of your traffic is negotiating TLS at
          all.
        </p>

        <h2 id="where-it-dies">Where in the handshake it dies</h2>
        <p>
          Four conditions have to hold for the handshake to finish. Cloudflare
          lists all four as the common causes to exclude at the origin, and any
          single one of them failing produces the same page.
        </p>
        <Error525Handshake />
        <p>
          Reading the diagram left to right through the failure modes gives you
          a working checklist:
        </p>
        <ul>
          <li>
            <strong>No valid certificate is installed.</strong> The most common
            cause by a distance, and it includes the case where a certificate
            exists for a different hostname or was never loaded by the running
            web server process.
          </li>
          <li>
            <strong>Port 443 is not open.</strong> Or the custom secure port you
            configured is not. Note that a firewall which <em>drops</em> the
            packet produces a{" "}
            <Link href="/guides/cloudflare-error-522-connection-timed-out">
              522
            </Link>{" "}
            instead, because that failure happens before TLS begins.
          </li>
          <li>
            <strong>The origin does not support SNI.</strong> Cloudflare sends
            the hostname in the ClientHello and expects the origin to select a
            certificate from it. A server on a shared address with no SNI
            handling cannot answer that.
          </li>
          <li>
            <strong>No cipher suite in common.</strong> The subtle one, covered
            below.
          </li>
        </ul>
        <p>
          Cloudflare also flags a cause that sits outside all four: a hosting
          provider that{" "}
          <a href={DOCS_DYNAMIC_IP} target="_blank" rel="noopener noreferrer">
            changes your origin IP address
          </a>{" "}
          without telling you. Your DNS record then points at a machine that
          never had a certificate for your hostname, and a site nobody touched
          starts failing.
        </p>

        <h2 id="vs-neighbours">525 against its neighbours</h2>
        <p>
          The 52x codes each name a different layer of the same journey, and
          knowing which layer you are on eliminates most of the search space
          before you open a single config file.
        </p>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th scope="col">Code</th>
                <th scope="col">Layer that failed</th>
                <th scope="col">What the origin did</th>
                <th scope="col">Does relaxing to Full help?</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <th scope="row">521</th>
                <td>TCP</td>
                <td>Refused the connection outright</td>
                <td>No</td>
              </tr>
              <tr>
                <th scope="row">522</th>
                <td>TCP</td>
                <td>Stayed silent until the timeout</td>
                <td>No</td>
              </tr>
              <tr>
                <th scope="row">525</th>
                <td>TLS handshake</td>
                <td>Never completed the negotiation</td>
                <td>
                  <strong>No</strong>
                </td>
              </tr>
              <tr>
                <th scope="row">
                  <a href={DOCS_526} target="_blank" rel="noopener noreferrer">
                    526
                  </a>
                </th>
                <td>TLS validation</td>
                <td>Presented a certificate that was rejected</td>
                <td>Yes — Cloudflare documents it as the quick fix</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p>
          The 525/526 boundary is the one worth internalising. A 526 requires
          that a certificate actually arrived, which is why it only exists under{" "}
          <a href={DOCS_FULL_STRICT} target="_blank" rel="noopener noreferrer">
            Full (strict)
          </a>{" "}
          — that is the only mode that validates anything. If you are getting a
          525, Cloudflare never got far enough to have an opinion about your
          certificate.
        </p>

        <h2 id="ciphers">The cipher mismatch nobody expects</h2>
        <p>
          This is the cause that survives every obvious check: a valid
          certificate is installed, port 443 is open, SNI works, and the
          handshake still fails. Cloudflare{" "}
          <a
            href={DOCS_ORIGIN_CIPHERS}
            target="_blank"
            rel="noopener noreferrer"
          >
            publishes the exact cipher suites
          </a>{" "}
          it offers origins, and it is a separate list from the one it presents
          to browsers and other user agents.
        </p>
        <p>
          The trap is that hardening guides for web servers are written with
          browsers in mind. An origin locked down to a modern, TLS
          1.2-and-ChaCha20-only policy can end up with no overlap at all,
          because Cloudflare&rsquo;s origin-facing TLS 1.2 rows are the ECDHE
          and legacy AES suites — ChaCha20 appears only in the TLS 1.3 section.
          Tighten the origin past what Cloudflare offers and the negotiation has
          nothing to agree on. That same page publishes an NGINX{" "}
          <code>ssl_ciphers</code> line for origins that want to match what
          Cloudflare supports, which is the quickest way out of this one.
        </p>

        <h2 id="diagnosing">Confirming it yourself</h2>
        <p>
          Testing through Cloudflare tells you nothing, because you will be
          talking to Cloudflare rather than to your origin. You need to speak
          TLS to the origin address directly, with the hostname supplied as SNI
          — which tests all four conditions in one command:
        </p>
        <pre>
          <code>
            openssl s_client -connect ORIGIN_IP:443 -servername example.com
          </code>
        </pre>
        <p>
          A certificate chain and a negotiated cipher in the output means the
          handshake works and your 525 is coming from somewhere else. A refusal,
          an empty certificate section or a handshake failure reproduces the
          error at the exact layer Cloudflare hit. Cloudflare&rsquo;s own{" "}
          <a href={DOCS_CURL} target="_blank" rel="noopener noreferrer">
            troubleshooting guidance
          </a>{" "}
          points at curl for the same purpose.
        </p>
        <p>
          Two more places carry the answer when the failure is intermittent.
          Your origin&rsquo;s error log is the authoritative one: nginx includes
          SSL errors in its standard error log though it may need the log level
          raised, and Apache has to be configured to log <code>mod_ssl</code>{" "}
          errors before it says anything useful. On the Cloudflare side,{" "}
          <a
            href={DOCS_ORIGIN_ANALYTICS}
            target="_blank"
            rel="noopener noreferrer"
          >
            Origin Analytics
          </a>{" "}
          records an origin response status of <code>0</code> when no HTTP
          response came back at all, which is what a failed TLS negotiation
          looks like from the edge. Cross-referencing those timestamps against
          the origin log is the fastest way to catch a handshake that only fails
          under load.
        </p>

        <h2 id="fixing">Fixing it</h2>
        <p>
          Every documented cause lives at the origin, so this is a list of
          things to change on your server, in the order that resolves the most
          cases:
        </p>
        <ol>
          <li>
            <strong>Install a certificate.</strong> If the origin has none, a
            free{" "}
            <a href={DOCS_ORIGIN_CA} target="_blank" rel="noopener noreferrer">
              Cloudflare Origin CA certificate
            </a>{" "}
            is the path Cloudflare recommends. It is trusted for
            Cloudflare-to-origin traffic specifically, which is all this hop
            needs.
          </li>
          <li>
            <strong>Open port 443</strong> to Cloudflare, and confirm the web
            server is actually listening on it rather than only on port 80.
          </li>
          <li>
            <strong>Widen the cipher and protocol list</strong> until it
            overlaps what Cloudflare offers origins, using the published list as
            the reference rather than guessing.
          </li>
          <li>
            <strong>Check SNI handling</strong> if the origin serves several
            hostnames from one address.
          </li>
        </ol>
        <p>
          One thing not to do: switching to Flexible. It will make the error
          disappear, because Cloudflare stops speaking TLS to your origin
          entirely — which means that hop travels in plaintext across the public
          internet, and it commonly produces redirect loops as a parting gift.
          If you are weighing that trade, the{" "}
          <Link href="/guides/cloudflare-ssl-tls-encryption-modes">
            encryption modes
          </Link>{" "}
          are worth understanding before you change one. A certificate that
          fails validation but still encrypts is a far better position than no
          encryption at all, and if that is where you are, Full or the{" "}
          <a href={DOCS_TRUST_STORE} target="_blank" rel="noopener noreferrer">
            Custom Origin Trust Store
          </a>{" "}
          both beat Flexible.
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
