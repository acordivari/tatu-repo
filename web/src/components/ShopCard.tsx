import { Link } from "react-router-dom";
import type { ShopCard as ShopCardData } from "../types";

// Compact studio card used by the directory grid and the shop page's
// "More studios in {city}" strip.
export default function ShopCard({ s }: { s: ShopCardData }) {
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
