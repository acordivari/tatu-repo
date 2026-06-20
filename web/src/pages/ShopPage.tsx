import { useQuery } from "@tanstack/react-query";
import { Link, useParams } from "react-router-dom";
import { api } from "../api/client";
import type { ShopArtist } from "../types";
import BookingNote from "../components/BookingNote";

function statusLabel(status: string | null): { text: string; tone: string } | null {
  switch (status) {
    case "CLOSED_PERMANENTLY":
      return { text: "Permanently closed", tone: "closed" };
    case "CLOSED_TEMPORARILY":
      return { text: "Temporarily closed", tone: "warn" };
    default:
      return null; // operational — no badge needed
  }
}

function RosterCard({ a }: { a: ShopArtist }) {
  return (
    <Link to={`/artists/${a.handle}`} className="artist-card">
      {a.preview_image_url ? (
        <div className="tile" style={{ marginBottom: "0.75rem" }}>
          <img src={a.preview_image_url} alt={`Work by @${a.handle}`} loading="lazy" />
        </div>
      ) : null}
      <div className="handle">@{a.handle}</div>
      {a.name ? <div className="meta">{a.name}</div> : null}
      {a.role && a.role !== "unknown" ? (
        <div className="role-badge">{a.role}</div>
      ) : null}
    </Link>
  );
}

export default function ShopPage() {
  const { handle } = useParams();
  const { data, isLoading, isError } = useQuery({
    queryKey: ["shop", handle],
    queryFn: () => api.shop(handle!),
    enabled: !!handle,
  });

  if (isLoading) return <div className="page notice">Loading…</div>;
  if (isError || !data)
    return (
      <div className="page notice">
        Shop not found. <Link to="/shops">Back to studios</Link>
      </div>
    );

  const place = [data.city, data.region, data.country].filter(Boolean).join(", ");
  const status = statusLabel(data.business_status);

  return (
    <div className="page">
      <div className="shop-head">
        <Link to="/shops" style={{ fontSize: "0.8rem", color: "var(--muted)" }}>
          ← Studios
        </Link>
        <h1>{data.name}</h1>
        {status && <span className={`status-badge ${status.tone}`}>{status.text}</span>}
        {data.address ? <div className="sub">{data.address}</div> : place ? <div className="sub">{place}</div> : null}

        <div className="shop-links">
          <a className="ig-link" href={data.instagram_url} target="_blank" rel="noreferrer">
            @{data.handle} on Instagram ↗
          </a>
          {data.maps_url && (
            <a className="ig-link" href={data.maps_url} target="_blank" rel="noreferrer">
              View on Google Maps ↗
            </a>
          )}
        </div>
      </div>

      <BookingNote context="shop" />

      <h2 className="section-title">
        {data.members_count} {data.members_count === 1 ? "artist" : "artists"}
      </h2>
      {data.artists.length === 0 ? (
        <div className="notice">No artists linked to this studio yet.</div>
      ) : (
        <div className="artist-grid">
          {data.artists.map((a) => (
            <RosterCard key={a.id} a={a} />
          ))}
        </div>
      )}
    </div>
  );
}
