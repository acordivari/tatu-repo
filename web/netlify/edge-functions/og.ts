// Injects page-specific <title> + Open Graph / Twitter tags into the SPA
// shell for artist and shop pages, so shared links unfurl with the artist's
// name and work (crawlers and chat apps don't run the SPA's JavaScript).
// Fails open: any error or API miss returns the untouched shell.
import type { Context } from "@netlify/edge-functions";

const API_BASE =
  Netlify.env.get("VITE_API_URL") ?? "https://tatu-api-tbm6.onrender.com/api/v1";

// Only crawlers/unfurlers need server-rendered tags — humans run the SPA,
// and skipping them avoids adding an API round-trip to every page view.
const CRAWLER_UA =
  /bot|crawler|spider|crawling|facebookexternalhit|twitterbot|slackbot|discordbot|whatsapp|telegrambot|linkedinbot|pinterest|embedly|quora link preview|vkshare|redditbot|applebot|snapchat|skypeuripreview|preview/i;

const ESCAPES: Record<string, string> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
};
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ESCAPES[c]);

const truncate = (s: string, max = 200) =>
  s.length > max ? `${s.slice(0, max - 1).trimEnd()}…` : s;

interface Meta {
  title: string;
  description: string;
  image?: string | null;
  type: string;
}

function artistMeta(data: Record<string, unknown>): Meta {
  const place = [data.city, data.region, data.country].filter(Boolean).join(", ");
  const title = `@${data.handle} — tattoo artist${place ? ` in ${place}` : ""} · Tatu`;
  const bio = typeof data.bio === "string" ? data.bio.replace(/\s+/g, " ").trim() : "";
  const description = truncate(
    bio || `${data.posts_count || "See"} featured pieces by @${data.handle} on Tatu.`
  );
  return { title, description, image: data.preview_image_url as string | null, type: "profile" };
}

function shopMeta(data: Record<string, unknown>): Meta {
  const place = [data.city, data.region, data.country].filter(Boolean).join(", ");
  const title = `${data.name}${place ? ` — ${place}` : ""} · Tatu`;
  const count = (data.members_count as number) ?? 0;
  const description = `Tattoo studio${place ? ` in ${place}` : ""} — ${count} ${
    count === 1 ? "artist" : "artists"
  } on Tatu.`;
  const artists = (data.artists as Array<Record<string, unknown>>) ?? [];
  const image = artists.find((a) => a.preview_image_url)?.preview_image_url as
    | string
    | undefined;
  return { title, description, image, type: "website" };
}

export default async (request: Request, context: Context) => {
  const response = await context.next();
  if (!CRAWLER_UA.test(request.headers.get("user-agent") ?? "")) return response;
  const match = new URL(request.url).pathname.match(/^\/(artists|shops)\/([^/]+)\/?$/);
  const contentType = response.headers.get("content-type") ?? "";
  if (!match || !contentType.includes("text/html")) return response;

  try {
    const [, kind, handle] = match;
    const api = await fetch(`${API_BASE}/${kind}/${encodeURIComponent(handle)}`, {
      signal: AbortSignal.timeout(4000),
    });
    if (!api.ok) return response;
    const data = await api.json();
    const meta = kind === "artists" ? artistMeta(data) : shopMeta(data);

    const tags = [
      `<meta name="description" content="${esc(meta.description)}" />`,
      `<meta property="og:site_name" content="Tatu" />`,
      `<meta property="og:type" content="${meta.type}" />`,
      `<meta property="og:title" content="${esc(meta.title)}" />`,
      `<meta property="og:description" content="${esc(meta.description)}" />`,
      `<meta property="og:url" content="${esc(request.url)}" />`,
      ...(meta.image
        ? [
            `<meta property="og:image" content="${esc(meta.image)}" />`,
            `<meta name="twitter:card" content="summary_large_image" />`,
          ]
        : [`<meta name="twitter:card" content="summary" />`]),
    ].join("\n    ");

    const html = (await response.text())
      // Drop the shell's generic tags so parsers only see the specific ones.
      .replace(/<meta (?:property="og:|name="twitter:|name="description")[^>]*\/?>\s*/g, "")
      .replace(/<title>[\s\S]*?<\/title>/, `<title>${esc(meta.title)}</title>`)
      .replace("</head>", `    ${tags}\n  </head>`);

    const headers = new Headers(response.headers);
    headers.delete("content-length");
    return new Response(html, { status: response.status, headers });
  } catch {
    return response;
  }
};

export const config = { path: ["/artists/*", "/shops/*"], onError: "bypass" };
