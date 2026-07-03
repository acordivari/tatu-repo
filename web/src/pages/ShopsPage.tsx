import { useQuery, keepPreviousData } from "@tanstack/react-query";
import { useSearchParams } from "react-router-dom";
import { api } from "../api/client";
import BookingNote from "../components/BookingNote";
import ShopCard from "../components/ShopCard";

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
              <ShopCard key={s.id} s={s} />
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
