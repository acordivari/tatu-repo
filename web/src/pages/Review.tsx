import { useQuery } from "@tanstack/react-query";
import { useCallback, useEffect, useState } from "react";
import { api } from "../api/client";
import type { Candidate } from "../types";

export default function Review() {
  const { data, isLoading, isError, refetch, isFetching } = useQuery({
    queryKey: ["candidates"],
    queryFn: api.candidates,
    staleTime: Infinity,
  });

  const [queue, setQueue] = useState<Candidate[]>([]);
  const [i, setI] = useState(0);
  const [acted, setActed] = useState({ approved: 0, rejected: 0, skipped: 0 });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Seed the local queue when data arrives (or is refetched for more).
  useEffect(() => {
    if (data?.candidates) {
      setQueue(data.candidates);
      setI(0);
    }
  }, [data]);

  const current = queue[i];

  const decide = useCallback(
    async (action: "approve" | "reject" | "skip") => {
      if (!current || busy) return;
      setBusy(true);
      setError(null);
      try {
        if (action === "approve") await api.approveCandidate(current.handle);
        if (action === "reject") await api.rejectCandidate(current.handle);
        const key = { approve: "approved", reject: "rejected", skip: "skipped" } as const;
        setActed((a) => ({ ...a, [key[action]]: a[key[action]] + 1 }));
        setI((n) => n + 1);
      } catch {
        setError(`Couldn't ${action} @${current.handle}. It stayed in the queue — try again.`);
      } finally {
        setBusy(false);
      }
    },
    [current, busy]
  );

  // Keyboard shortcuts: A approve · R reject · S skip · O open Instagram.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey) return;
      const k = e.key.toLowerCase();
      if (k === "a") decide("approve");
      else if (k === "r" || k === "x") decide("reject");
      else if (k === "s") decide("skip");
      else if (k === "o" && current) window.open(current.instagram_url, "_blank");
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [decide, current]);

  if (isLoading) return <div className="page notice">Loading review queue…</div>;
  if (isError) return <div className="page notice">Could not load candidates. Is the API running?</div>;

  const total = queue.length;
  const done = acted.approved + acted.rejected + acted.skipped;

  if (!current) {
    return (
      <div className="page review">
        <div className="notice">
          <h2>Queue clear 🖤</h2>
          <p>
            {acted.approved} approved · {acted.rejected} rejected · {acted.skipped} skipped
          </p>
          <p style={{ marginTop: "1rem" }}>
            More may still be classifying in the background.
            <br />
            <button
              className="chip"
              style={{ marginTop: "0.75rem" }}
              disabled={isFetching}
              onClick={() => refetch()}
            >
              {isFetching ? "Checking…" : "Check for more candidates"}
            </button>
          </p>
        </div>
      </div>
    );
  }

  const place = [current.category].filter(Boolean).join("");

  return (
    <div className="page review">
      <div className="review-progress">
        {done} / {total} reviewed · <strong>{total - done}</strong> left
        <span className="review-tally">
          ✓ {acted.approved} approved · ✕ {acted.rejected} rejected
        </span>
      </div>

      <div className="review-card">
        <div className="review-handle">@{current.handle}</div>
        {current.name && <div className="review-name">{current.name}</div>}
        <div className="review-meta">
          {place && <span>{place}</span>}
          {current.posts_count != null && <span>{current.posts_count} posts</span>}
          {current.followers_count != null && (
            <span>{current.followers_count.toLocaleString()} followers</span>
          )}
          {current.confidence != null && <span>conf {current.confidence.toFixed(2)}</span>}
        </div>
        <p className="review-bio">{current.bio || <em>(no bio)</em>}</p>

        {error && (
          <p style={{ color: "#b00020", fontSize: "0.85rem" }}>{error}</p>
        )}

        <a className="ig-link" href={current.instagram_url} target="_blank" rel="noreferrer">
          Open on Instagram ↗ (O)
        </a>

        <div className="review-actions">
          <button className="btn-reject" disabled={busy} onClick={() => decide("reject")}>
            ✕ Reject <kbd>R</kbd>
          </button>
          <button className="btn-skip" disabled={busy} onClick={() => decide("skip")}>
            Skip <kbd>S</kbd>
          </button>
          <button className="btn-approve" disabled={busy} onClick={() => decide("approve")}>
            ✓ Approve <kbd>A</kbd>
          </button>
        </div>
      </div>

      <p className="review-hint">
        Tip: use your keyboard — <kbd>A</kbd> approve · <kbd>R</kbd> reject · <kbd>S</kbd> skip ·{" "}
        <kbd>O</kbd> open Instagram
      </p>
    </div>
  );
}
