import { useQuery, keepPreviousData } from "@tanstack/react-query";
import { Link, useSearchParams } from "react-router-dom";
import { api } from "../api/client";
import type { ShopCard } from "../types";
import BookingNote from "../components/BookingNote";

function Card({ s }: { s: ShopCard }) {
  const place = [s.city, s.region, s.country].filter(Boolean).join(", ");
  const closed = s.business_status?.startsWith("CLOSED");
  return (
    <Link to={`/shops/${s.handle}`} className="shop-card">
      <div className="shop-card-name">{s.name}</div>
      {place ? <div className="meta">{place}</div> : null}
      <div className="shop-card-foot">
        <span className="count">
          {s.members_count} {s.members_count === 1 ? "artist" : "artists"}
        </span>
        {closed && <span className="status-badge closed small">closed</span>}
      </div>
    </Link>
  );
}

export default function ShopsPage() {
  const [params, setParams] = useSearchParams();
  const q = params.get("q") ?? "";
  const page = Number(params.get("page") ?? 1);

  const shops = useQuery({
    queryKey: ["shops", { q, page }],
    queryFn: () => api.shops({ q, page }),
    placeholderData: keepPreviousData,
  });

  const setParam = (key: string, value: string) => {
    const next = new URLSearchParams(params);
    if (value) next.set(key, value);
    else next.delete(key);
    if (key !== "page") next.delete("page");
    setParams(next);
  };

  return (
    <div className="page">
      <div className="hero">
        <h1 className="section-title" style={{ fontSize: "1.6rem" }}>
          Studios
        </h1>
        <p>Browse the tattoo studios behind the artists.</p>
      </div>

      <BookingNote context="home" />

      <form className="filters" onSubmit={(e) => e.preventDefault()}>
        <input
          className="shop-search"
          defaultValue={q}
          placeholder="Search studios by name or city…"
          onChange={(e) => setParam("q", e.target.value)}
          aria-label="Search studios"
        />
      </form>

      {shops.isLoading ? (
        <div className="notice">Loading…</div>
      ) : shops.isError ? (
        <div className="notice">Could not reach the API. Is the Rails server running on :3000?</div>
      ) : shops.data && shops.data.items.length === 0 ? (
        <div className="notice">No studios found{q ? ` for “${q}”` : ""}.</div>
      ) : (
        <>
          <div className="shop-grid">
            {shops.data!.items.map((s) => (
              <Card key={s.id} s={s} />
            ))}
          </div>
          {shops.data!.totalPages > 1 && (
            <div className="pager">
              <button disabled={page <= 1} onClick={() => setParam("page", String(page - 1))}>
                ← Prev
              </button>
              <span>
                {page} / {shops.data!.totalPages}
              </span>
              <button
                disabled={page >= shops.data!.totalPages}
                onClick={() => setParam("page", String(page + 1))}
              >
                Next →
              </button>
            </div>
          )}
        </>
      )}
    </div>
  );
}
