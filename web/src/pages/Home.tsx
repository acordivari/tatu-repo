import { useQuery, keepPreviousData } from "@tanstack/react-query";
import { Link, useSearchParams } from "react-router-dom";
import { api } from "../api/client";
import type { ArtistCard } from "../types";

function Card({ a }: { a: ArtistCard }) {
  const place = [a.city, a.region, a.country].filter(Boolean).join(", ");
  return (
    <Link to={`/artists/${a.handle}`} className="artist-card">
      {a.preview_image_url ? (
        <div className="tile" style={{ marginBottom: "0.75rem" }}>
          <img src={a.preview_image_url} alt={`Work by @${a.handle}`} loading="lazy" />
        </div>
      ) : null}
      <div className="handle">@{a.handle}</div>
      {a.name ? <div className="meta">{a.name}</div> : null}
      {place ? <div className="meta">{place}</div> : null}
      <div className="count">
        {a.posts_count} {a.posts_count === 1 ? "piece" : "pieces"}
      </div>
    </Link>
  );
}

export default function Home() {
  const [params, setParams] = useSearchParams();
  const q = params.get("q") ?? "";
  const country = params.get("country") ?? "";
  const region = params.get("region") ?? "";
  const page = Number(params.get("page") ?? 1);

  const facets = useQuery({ queryKey: ["regions"], queryFn: api.regions });

  const artists = useQuery({
    queryKey: ["artists", { q, country, region, page }],
    queryFn: () => api.artists({ q, country, region, page, sort: "featured" }),
    placeholderData: keepPreviousData,
  });

  const setParam = (key: string, value: string) => {
    const next = new URLSearchParams(params);
    if (value) next.set(key, value);
    else next.delete(key);
    next.delete("page");
    setParams(next);
  };

  const topCountries = Object.entries(facets.data?.countries ?? {}).slice(0, 12);

  return (
    <div className="page">
      {!q && (
        <div className="hero">
          <h1>BLACKWORKERS</h1>
          <p>An encyclopedia of blackwork tattooing — find an artist near you.</p>
        </div>
      )}

      {topCountries.length > 0 && (
        <div className="filters">
          <button
            className={`chip ${!country ? "active" : ""}`}
            onClick={() => setParam("country", "")}
          >
            All
          </button>
          {topCountries.map(([name, count]) => (
            <button
              key={name}
              className={`chip ${country === name ? "active" : ""}`}
              onClick={() => setParam("country", country === name ? "" : name)}
            >
              {name} ({count})
            </button>
          ))}
        </div>
      )}

      {artists.isLoading ? (
        <div className="notice">Loading…</div>
      ) : artists.isError ? (
        <div className="notice">
          Could not reach the API. Is the Rails server running on :3000?
        </div>
      ) : artists.data && artists.data.items.length === 0 ? (
        <div className="notice">No artists found{q ? ` for “${q}”` : ""}.</div>
      ) : (
        <>
          <div className="artist-grid">
            {artists.data!.items.map((a) => (
              <Card key={a.id} a={a} />
            ))}
          </div>
          <Pager
            page={page}
            totalPages={artists.data!.totalPages}
            onPage={(p) => setParam("page", String(p))}
          />
        </>
      )}
    </div>
  );
}

function Pager({
  page,
  totalPages,
  onPage,
}: {
  page: number;
  totalPages: number;
  onPage: (p: number) => void;
}) {
  if (totalPages <= 1) return null;
  return (
    <div className="pager">
      <button disabled={page <= 1} onClick={() => onPage(page - 1)}>
        ← Prev
      </button>
      <span>
        {page} / {totalPages}
      </span>
      <button disabled={page >= totalPages} onClick={() => onPage(page + 1)}>
        Next →
      </button>
    </div>
  );
}
