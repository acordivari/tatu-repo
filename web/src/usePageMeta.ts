import { useEffect } from "react";

const DEFAULT_TITLE = "Tatu — Artists Around the World";

// Per-page document titles for people browsing the SPA. Crawlers and link
// unfurlers never run this — they get the static tags in index.html, or the
// per-artist tags injected by netlify/edge-functions/og.ts.
export function usePageMeta(title?: string | null) {
  useEffect(() => {
    document.title = title ? `${title} · Tatu` : DEFAULT_TITLE;
    return () => {
      document.title = DEFAULT_TITLE;
    };
  }, [title]);
}
