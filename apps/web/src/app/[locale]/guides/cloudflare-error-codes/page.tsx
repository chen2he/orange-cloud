import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { setRequestLocale } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import GuideShell, { type RelatedLink } from "@/components/guides/GuideShell";
import ErrorCodeBands from "@/components/guides/ErrorCodeBands";
import { guideBySlug, GUIDE_LOCALE } from "@/lib/guides/guides";

const SITE_URL = "https://o-c.do";
const guide = guideBySlug("cloudflare-error-codes");
const PATH = `/guides/${guide.slug}`;

const DOCS_5XX =
  "https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/";
const DOCS_1XXX =
  "https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-1xxx-errors/";
const DOCS_502_504 = `${DOCS_5XX}error-502-504/`;
const DOCS_503 = `${DOCS_5XX}error-503/`;
const DOCS_520 = `${DOCS_5XX}error-520/`;
const DOCS_523 = `${DOCS_5XX}error-523/`;
const DOCS_530 = `${DOCS_5XX}error-530/`;
const DOCS_1015 = `${DOCS_1XXX}error-1015/`;
const DOCS_1033 = `${DOCS_1XXX}error-1033/`;
const DOCS_RAY_ID =
  "https://developers.cloudflare.com/fundamentals/reference/cloudflare-ray-id/";
const DOCS_CUSTOM_ERRORS =
  "https://developers.cloudflare.com/rules/custom-errors/";
const DOCS_LOG_EXPLORER = "https://developers.cloudflare.com/log-explorer/";

/** FAQ 一处定义：可见文本与 FAQPage JSON-LD 同源，保证逐字一致 */
const FAQ: Array<{ q: string; a: string }> = [
  {
    q: "What do Cloudflare error codes mean?",
    a: "They name which part of the request failed. Codes in the 520 to 527 range describe the hop from Cloudflare to your origin server, so the origin is involved. Codes in the 1xxx range are Cloudflare's own decision, made before or instead of contacting your origin — it either could not work out where to send the request, or deliberately refused the visitor.",
  },
  {
    q: "What is the difference between Cloudflare 5xx and 1xxx errors?",
    a: "A 5xx code is a real HTTP status code, sent in the status line of the response. A 1xxx code is not a status code at all: Cloudflare documents that 1xxx errors appear in the HTML body of the response, while the status line carries an ordinary code such as 403, 409, 429 or 530. That is why monitoring tools that only record status codes never report a 1xxx number.",
  },
  {
    q: "Is a Cloudflare error my fault or Cloudflare's?",
    a: "Usually neither — it is most often the origin server. Cloudflare's guidance for 5xx errors is to contact your hosting provider first, because the 520 to 527 codes describe your origin's behaviour. The genuinely ambiguous codes are 500, 502, 503 and 504, which can come from either side, and Cloudflare documents how to tell them apart by reading the response body.",
  },
  {
    q: "How do I find out which Cloudflare rule caused an error?",
    a: "Use the Ray ID printed on the error page. It identifies that single request, and Cloudflare's Log Explorer lets you build a query filtered to a specific Ray ID. For a block, searching the Security Events log for the Ray ID or client IP address from the visitor's error message names the rule that matched.",
  },
  {
    q: "Why does the same Cloudflare error number mean two different things?",
    a: "A few numbers are genuinely overloaded. Error 1002 has two separate documented meanings, DNS points to a prohibited IP and Restricted. Error 1015 normally means a visitor has been rate limited, but Cloudflare notes that Unable to purge is a second, unrelated 1015 raised by cache purge. Read the message text alongside the number, not the number alone.",
  },
];

const RELATED: RelatedLink[] = [
  {
    href: "/guides/cloudflare-error-522-connection-timed-out",
    label: "Cloudflare error 522: connection timed out",
    note: "The most common 5xx of the set — the origin stayed silent until Cloudflare gave up.",
  },
  {
    href: "/guides/cloudflare-error-1020-access-denied",
    label: "Cloudflare error 1020: access denied",
    note: "The 1xxx you are most likely to meet, and the clearest example of a body-only code.",
  },
  {
    href: "/guides/cloudflare-error-1000-dns-points-to-prohibited-ip",
    label: "Cloudflare error 1000: DNS points to prohibited IP",
    note: "What happens when Cloudflare works out that your origin address is Cloudflare itself.",
  },
  {
    href: DOCS_5XX,
    label: "Cloudflare docs: 5xx errors",
    note: "One of the two references this guide was checked against, alongside the 1xxx index.",
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

export default async function ErrorCodesGuide({
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
        lede="Before you look up any individual number, it is worth knowing what the range it falls in already tells you — and why the number on the page is often not the number your monitoring recorded."
        updated={guide.updated}
        readingTime={guide.readingTime}
        related={RELATED}
      >
        <div className="glass r-island note p-6 sm:p-7">
          <p>
            <strong>
              A 5xx code in the 520&ndash;527 range describes the hop from
              Cloudflare to your origin server. A 1xxx code is
              Cloudflare&rsquo;s own decision, taken before your origin was ever
              involved.
            </strong>{" "}
            The range tells you who has to fix it.
          </p>
        </div>

        <p>
          Searches for a Cloudflare error code list, CF error codes or simply
          &ldquo;cloudflare error codes&rdquo; almost always start the same way:
          a page appeared with a number on it, and the number means nothing yet.
          The useful first move is not to look that number up but to notice
          which family it belongs to, because the two families are produced at
          different points in the request and are addressed to different people.
        </p>

        <h2 id="two-families">Two families, two points of failure</h2>
        <p>
          Cloudflare sits between the visitor and your server, so a request has
          two hops rather than one. Each family of codes covers exactly one of
          them.
        </p>
        <ErrorCodeBands />
        <p>
          The 520 to 527 codes are Cloudflare&rsquo;s report on the second hop.
          Cloudflare could not get a usable response out of your origin, and
          each number narrows down how that failed &mdash; refused, silent,
          unreachable, slow, or answering in a way Cloudflare could not parse.
          Cloudflare&rsquo;s own advice for this whole family is to take the
          error code, the timestamp and the exact URL to{" "}
          <a href={DOCS_5XX} target="_blank" rel="noopener noreferrer">
            your hosting provider
          </a>
          , and to check anything sitting between the two &mdash; load
          balancers, caches, proxies, firewalls &mdash; not just the web server
          itself.
        </p>
        <p>
          The 1xxx codes never get that far. They are the record of a decision
          Cloudflare made on its own: either it could not work out where to send
          the request, or it worked that out perfectly well and refused to send
          it. A block, a ban, a rate limit and a hostname it cannot resolve all
          land in this range.
        </p>

        <h2 id="not-a-status-code">A 1xxx number is not an HTTP status code</h2>
        <p>
          This is the detail that causes the most confusion, and it is stated
          plainly in Cloudflare&rsquo;s{" "}
          <a href={DOCS_1XXX} target="_blank" rel="noopener noreferrer">
            1xxx reference
          </a>
          : those errors appear in the HTML body of the response, while the
          status line of the same response carries an ordinary code &mdash; a
          403, 409, 429 or 530.
        </p>
        <p>
          The consequences are practical. An uptime monitor, a log pipeline or a
          CI job that records status codes will never once report the number
          1020, because that number never travels in the status line. It sees a
          bare 403 and tells you access was denied, which is true and useless.
          If you are debugging from anything other than a browser, fetch the
          response body as well as the status; the number you actually need is
          in the HTML.
        </p>
        <p>
          Error 530 is the clearest case of the pairing, and the one worth
          committing to memory. Cloudflare documents 530 as meaning it could not
          resolve the origin hostname, and says the{" "}
          <a href={DOCS_530} target="_blank" rel="noopener noreferrer">
            body of that response contains a 1xxx code
          </a>{" "}
          naming the specific reason. A 530 on its own is not a diagnosis. It is
          a pointer to the real one, which is sitting in the HTML you probably
          did not read.
        </p>

        <h2 id="reading-the-band">What each range commits to</h2>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th scope="col">What you see</th>
                <th scope="col">Where it was decided</th>
                <th scope="col">Was your origin reached?</th>
                <th scope="col">Who acts on it</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <th scope="row">520&ndash;527</th>
                <td>Cloudflare, about the origin hop</td>
                <td>Attempted, and it went wrong</td>
                <td>You and your host</td>
              </tr>
              <tr>
                <th scope="row">530</th>
                <td>Cloudflare, before the origin hop</td>
                <td>No &mdash; read the 1xxx in the body</td>
                <td>You</td>
              </tr>
              <tr>
                <th scope="row">1xxx in the body</th>
                <td>Cloudflare, as a decision</td>
                <td>Usually not</td>
                <td>The site owner, not the visitor</td>
              </tr>
              <tr>
                <th scope="row">500, 502, 503, 504</th>
                <td>Either side &mdash; genuinely ambiguous</td>
                <td>Usually yes</td>
                <td>Depends on the body</td>
              </tr>
            </tbody>
          </table>
        </div>

        <h2 id="ambiguous">The four codes that could be either side</h2>
        <p>
          The last row is where people lose time. A 502, 504 or 503 is an
          everyday HTTP status that your own stack emits too, so seeing one on a
          proxied site tells you nothing about which machine produced it.
          Cloudflare documents the distinction for both.
        </p>
        <p>
          For{" "}
          <a href={DOCS_502_504} target="_blank" rel="noopener noreferrer">
            502 and 504
          </a>
          , Cloudflare lists two possible sources and calls the origin the more
          common one: when your origin answers with a standard 502 or 504,
          Cloudflare passes it on as a Cloudflare-branded page. So a
          Cloudflare-looking 502 does not mean Cloudflare failed; it frequently
          means your origin said 502 and Cloudflare repeated it. Cloudflare also
          notes that 504s can turn up in logs and analytics for reasons
          unrelated to an outage, including cache misses from Early Hints and
          from a Worker&rsquo;s Cache API.
        </p>
        <p>
          For{" "}
          <a href={DOCS_503} target="_blank" rel="noopener noreferrer">
            503
          </a>{" "}
          there is a concrete test. Cloudflare&rsquo;s guidance is to look for
          the strings <code>cloudflare</code> or <code>cloudflare-nginx</code>{" "}
          in the HTML body: if they are absent, treat it as your origin
          rate-limiting or overloading and talk to your host; if they are
          present, a connectivity problem inside a Cloudflare data centre is in
          play. Once again the answer is in the body rather than the status
          line.
        </p>

        <h2 id="ray-id">Turning one error page into one log line</h2>
        <p>
          Every Cloudflare-generated error page carries a{" "}
          <a href={DOCS_RAY_ID} target="_blank" rel="noopener noreferrer">
            Ray ID
          </a>
          , which identifies that individual request. That is what makes a
          screenshot from a visitor useful rather than anecdotal: Cloudflare
          documents that{" "}
          <a href={DOCS_LOG_EXPLORER} target="_blank" rel="noopener noreferrer">
            Log Explorer
          </a>{" "}
          can build queries filtered to a specific Ray ID, and for a block, the
          Security Events log searched by that Ray ID or the client IP will name
          the rule that matched. Two details make this go wrong in practice: the
          timestamp on the error page is UTC and needs converting before you
          search, and the error analytics in the dashboard are built from a one
          per cent sample of traffic, so a rare error may simply not appear
          there even though it certainly happened.
        </p>
        <p>
          One caveat on identifying anything by sight. Cloudflare&rsquo;s{" "}
          <a
            href={DOCS_CUSTOM_ERRORS}
            target="_blank"
            rel="noopener noreferrer"
          >
            Custom Errors
          </a>{" "}
          feature lets a site owner replace these default pages entirely, so an
          error page that looks nothing like Cloudflare&rsquo;s may still be
          one. The Ray ID is the more reliable tell than the styling.
        </p>

        <h2 id="overloaded">Numbers that mean more than one thing</h2>
        <p>
          A handful of codes are overloaded, which is worth knowing before you
          trust a search result for the bare number. Error 1002 has two separate
          documented meanings, <em>DNS points to prohibited IP</em> and{" "}
          <em>Restricted</em>. Errors 1006, 1007, 1008 and 1106 are four numbers
          for one situation, an IP address that has been banned. And{" "}
          <a href={DOCS_1015} target="_blank" rel="noopener noreferrer">
            error 1015
          </a>{" "}
          normally means a visitor hit a rate limiting rule, but Cloudflare
          notes that <em>Unable to purge</em> is a second and unrelated 1015
          raised by cache purge &mdash; same number, nothing to do with visitors
          at all.
        </p>
        <p>
          Two more are worth recognising because their cause sits somewhere most
          people do not look. A{" "}
          <a href={DOCS_520} target="_blank" rel="noopener noreferrer">
            520
          </a>{" "}
          can come from response headers exceeding 128&nbsp;KB, which in
          practice means an application that has accumulated too many cookies,
          or from an origin that advertises HTTP/2 support and then does not
          honour it. A{" "}
          <a href={DOCS_523} target="_blank" rel="noopener noreferrer">
            523
          </a>{" "}
          in an AWS environment is often a routing table rather than a server:
          Cloudflare uses public addresses in <code>172.64.0.0/13</code>, and a
          broad VPC route such as <code>172.0.0.0/8</code> swallows the return
          traffic. A{" "}
          <a href={DOCS_1033} target="_blank" rel="noopener noreferrer">
            1033
          </a>{" "}
          is a Cloudflare Tunnel with no healthy <code>cloudflared</code>{" "}
          instance to receive the request.
        </p>

        <h2 id="in-depth">The individual codes, in depth</h2>
        <p>
          Once you know which family you are in, the specific number is worth
          reading properly. We have separate write-ups for the ones people
          actually hit:{" "}
          <Link href="/guides/cloudflare-error-521-web-server-is-down">
            521
          </Link>{" "}
          and{" "}
          <Link href="/guides/cloudflare-error-522-connection-timed-out">
            522
          </Link>{" "}
          for a refused versus a silent origin,{" "}
          <Link href="/guides/cloudflare-error-524-a-timeout-occurred">
            524
          </Link>{" "}
          for the one where the connection succeeded,{" "}
          <Link href="/guides/cloudflare-error-525-ssl-handshake-failed">
            525
          </Link>{" "}
          and{" "}
          <Link href="/guides/cloudflare-error-526-invalid-ssl-certificate">
            526
          </Link>{" "}
          for the two TLS failures that are constantly confused with each other,{" "}
          <Link href="/guides/cloudflare-error-1000-dns-points-to-prohibited-ip">
            1000
          </Link>{" "}
          for the proxy pointed at itself, and{" "}
          <Link href="/guides/cloudflare-error-1020-access-denied">1020</Link>{" "}
          for a block you wrote yourself.
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
