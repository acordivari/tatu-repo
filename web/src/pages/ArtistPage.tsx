import { useQuery } from "@tanstack/react-query";
import { Link, useParams } from "react-router-dom";
import { api } from "../api/client";
import type { PostCard } from "../types";
import BookingNote from "../components/BookingNote";

function Tile({ post }: { post: PostCard }) {
  return (
    <a className="tile" href={post.source_url} target="_blank" rel="noreferrer">
      {post.image_url ? (
        <img src={post.image_url} alt={post.caption ?? ""} loading="lazy" />
      ) : null}
    </a>
  );
}

export default function ArtistPage() {
  const { handle } = useParams();
  const { data, isLoading, isError } = useQuery({
    queryKey: ["artist", handle],
    queryFn: () => api.artist(handle!),
    enabled: !!handle,
  });

  if (isLoading) return <div className="page notice">Loading…</div>;
  if (isError || !data)
    return (
      <div className="page notice">
        Artist not found. <Link to="/">Back to directory</Link>
      </div>
    );

  const place = [data.city, data.region, data.country].filter(Boolean).join(", ");
  const shops = data.shops ?? [];
  const primaryShop = shops[0];

  return (
    <div className="page">
      <div className="artist-head">
        <Link to="/" style={{ fontSize: "0.8rem", color: "var(--muted)" }}>
          ← Directory
        </Link>
        <h1>@{data.handle}</h1>
        {data.name && <div className="sub">{data.name}</div>}
        {(place || data.location_raw) && (
          <div className="sub">{place || data.location_raw}</div>
        )}
        {data.bio && <p className="sub">{data.bio}</p>}

        {shops.length > 0 && (
          <div className="artist-shops">
            <span className="section-label">Studio{shops.length > 1 ? "s" : ""}</span>
            {shops.map((s) => (
              <Link key={s.handle} to={`/shops/${s.handle}`} className="shop-chip">
                {s.name}
                {s.role && s.role !== "unknown" && (
                  <span className="shop-chip-role"> · {s.role}</span>
                )}
                {s.business_status?.startsWith("CLOSED") && (
                  <span className="status-badge closed small">closed</span>
                )}
              </Link>
            ))}
          </div>
        )}

        <a className="ig-link" href={data.instagram_url} target="_blank" rel="noreferrer">
          View on Instagram ↗
        </a>
      </div>

      <BookingNote
        context="artist"
        shop={primaryShop ? { handle: primaryShop.handle, name: primaryShop.name } : null}
      />

      {data.posts.length === 0 ? (
        <div className="notice">No featured pieces yet.</div>
      ) : (
        <div className="grid">
          {data.posts.map((p) => (
            <Tile key={p.id} post={p} />
          ))}
        </div>
      )}
    </div>
  );
}
