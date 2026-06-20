export interface ArtistCard {
  id: number;
  handle: string;
  name: string | null;
  shop_name: string | null;
  city: string | null;
  region: string | null;
  country: string | null;
  latitude: number | null;
  longitude: number | null;
  posts_count: number;
  instagram_url: string;
  preview_image_url: string | null;
}

export interface PostCard {
  id: number;
  shortcode: string;
  image_url: string | null;
  source_url: string;
  caption: string | null;
  posted_at: string | null;
  artist_id: number | null;
  artist_handle: string | null;
}

export interface ArtistDetail extends ArtistCard {
  bio: string | null;
  website: string | null;
  location_raw: string | null;
  posts: PostCard[];
}

export interface ArtistMarker {
  id: number;
  handle: string;
  name: string | null;
  city: string | null;
  region: string | null;
  country: string | null;
  latitude: number;
  longitude: number;
}

export interface RegionFacets {
  countries: Record<string, number>;
  // Only present (and scoped to the selected country) when a country is given.
  regions?: Record<string, number>;
}

export interface Candidate {
  handle: string;
  name: string | null;
  bio: string | null;
  category: string | null;
  followers_count: number | null;
  posts_count: number | null;
  confidence: number | null;
  reason: string | null;
  instagram_url: string;
}

export interface Paged<T> {
  items: T[];
  page: number;
  totalPages: number;
  totalCount: number;
}
