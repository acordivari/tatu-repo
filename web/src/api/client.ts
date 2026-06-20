import type {
  ArtistCard,
  ArtistDetail,
  ArtistMarker,
  Candidate,
  PostCard,
  Paged,
  RegionFacets,
} from "../types";

const BASE = import.meta.env.VITE_API_URL ?? "http://localhost:3000/api/v1";

async function getJson<T>(path: string): Promise<T> {
  const res = await fetch(`${BASE}${path}`);
  if (!res.ok) throw new Error(`API ${res.status} for ${path}`);
  return res.json() as Promise<T>;
}

async function postJson<T>(path: string): Promise<T> {
  const res = await fetch(`${BASE}${path}`, { method: "POST" });
  if (!res.ok) throw new Error(`API ${res.status} for ${path}`);
  return res.json() as Promise<T>;
}

// GET a list endpoint, reading pagination metadata from response headers.
async function getPaged<T>(path: string): Promise<Paged<T>> {
  const res = await fetch(`${BASE}${path}`);
  if (!res.ok) throw new Error(`API ${res.status} for ${path}`);
  const items = (await res.json()) as T[];
  return {
    items,
    page: Number(res.headers.get("X-Page") ?? 1),
    totalPages: Number(res.headers.get("X-Total-Pages") ?? 1),
    totalCount: Number(res.headers.get("X-Total-Count") ?? items.length),
  };
}

export interface ArtistQuery {
  q?: string;
  country?: string;
  region?: string;
  located?: boolean;
  sort?: "name" | "recent" | "featured";
  page?: number;
}

function toParams(obj: object): string {
  const p = new URLSearchParams();
  Object.entries(obj).forEach(([k, v]) => {
    if (v !== undefined && v !== null && v !== "") p.set(k, String(v));
  });
  const s = p.toString();
  return s ? `?${s}` : "";
}

export const api = {
  artists: (query: ArtistQuery = {}) =>
    getPaged<ArtistCard>(`/artists${toParams(query)}`),

  artist: (handleOrId: string) => getJson<ArtistDetail>(`/artists/${handleOrId}`),

  posts: (query: { artist?: string; attributed?: boolean; page?: number } = {}) =>
    getPaged<PostCard>(`/posts${toParams(query)}`),

  mapArtists: (bounds?: {
    sw_lat: number;
    sw_lng: number;
    ne_lat: number;
    ne_lng: number;
  }) => getJson<ArtistMarker[]>(`/artists/map${bounds ? toParams(bounds) : ""}`),

  // Pass a country to also get that country's region facet (scoped + deduped).
  regions: (country?: string) =>
    getJson<RegionFacets>(`/artists/regions${toParams({ country })}`),

  candidates: () =>
    getJson<{ count: number; candidates: Candidate[] }>(`/candidates`),
  approveCandidate: (handle: string) =>
    postJson<{ status: string; handle: string }>(
      `/candidates/${encodeURIComponent(handle)}/approve`
    ),
  rejectCandidate: (handle: string) =>
    postJson<{ status: string; handle: string }>(
      `/candidates/${encodeURIComponent(handle)}/reject`
    ),
};
