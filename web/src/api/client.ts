import type {
  ArtistCard,
  ArtistDetail,
  ArtistMarker,
  Candidate,
  PostCard,
  Paged,
  RegionFacets,
  ShopCard,
  ShopDetail,
} from "../types";

const BASE = import.meta.env.VITE_API_URL ?? "http://localhost:3000/api/v1";

export class ApiError extends Error {
  status: number;
  constructor(status: number, path: string) {
    super(`API ${status} for ${path}`);
    this.status = status;
  }
}

// Admin token for the /review moderation endpoints. Held per-tab; the Review
// page prompts for it and the API rejects candidate calls without it.
const TOKEN_KEY = "tatu_admin_token";

export function getAdminToken(): string | null {
  return sessionStorage.getItem(TOKEN_KEY);
}

export function setAdminToken(token: string | null) {
  if (token) sessionStorage.setItem(TOKEN_KEY, token);
  else sessionStorage.removeItem(TOKEN_KEY);
}

function adminHeaders(): HeadersInit {
  const token = getAdminToken();
  return token ? { Authorization: `Bearer ${token}` } : {};
}

async function getJson<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE}${path}`, init);
  if (!res.ok) throw new ApiError(res.status, path);
  return res.json() as Promise<T>;
}

async function postJson<T>(path: string): Promise<T> {
  const res = await fetch(`${BASE}${path}`, { method: "POST", headers: adminHeaders() });
  if (!res.ok) throw new ApiError(res.status, path);
  return res.json() as Promise<T>;
}

// GET a list endpoint, reading pagination metadata from response headers.
async function getPaged<T>(path: string): Promise<Paged<T>> {
  const res = await fetch(`${BASE}${path}`);
  if (!res.ok) throw new ApiError(res.status, path);
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

  shops: (query: { q?: string; country?: string; page?: number } = {}) =>
    getPaged<ShopCard>(`/shops${toParams(query)}`),

  shop: (handleOrId: string) =>
    getJson<ShopDetail>(`/shops/${encodeURIComponent(handleOrId)}`),

  candidates: () =>
    getJson<{ count: number; candidates: Candidate[] }>(`/candidates`, {
      headers: adminHeaders(),
    }),
  approveCandidate: (handle: string) =>
    postJson<{ status: string; handle: string }>(
      `/candidates/${encodeURIComponent(handle)}/approve`
    ),
  rejectCandidate: (handle: string) =>
    postJson<{ status: string; handle: string }>(
      `/candidates/${encodeURIComponent(handle)}/reject`
    ),
};
