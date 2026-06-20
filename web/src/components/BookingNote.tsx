import { Link } from "react-router-dom";

type Context = "home" | "artist" | "shop";

/**
 * Booking etiquette, surfaced throughout the app. The directory exists to help
 * people find artists — not to encourage cold DMs. Most artists route booking
 * through their studio or a posted process, so we steer visitors there.
 */
export default function BookingNote({
  context = "home",
  shop,
}: {
  context?: Context;
  shop?: { handle: string; name: string } | null;
}) {
  return (
    <aside className="booking-note" role="note">
      <span className="booking-note-label">Before you book</span>
      <p>{body(context, shop)}</p>
    </aside>
  );
}

function body(context: Context, shop?: { handle: string; name: string } | null) {
  const dms = "Most artists don't take booking requests through Instagram DMs.";

  if (context === "shop") {
    return `${dms} Use this studio's website or posted booking process — and check each artist's own profile for how they prefer to be booked.`;
  }

  if (context === "artist") {
    return (
      <>
        {dms}{" "}
        {shop ? (
          <>
            This artist works at{" "}
            <Link to={`/shops/${shop.handle}`} className="inline-link">
              {shop.name}
            </Link>{" "}
            — consult the shop page and its booking process first.
          </>
        ) : (
          "Check this artist's Instagram profile for their booking process before reaching out."
        )}
      </>
    );
  }

  return `${dms} Open an artist's profile and their shop page to find the right way to book.`;
}
