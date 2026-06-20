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

// A studio the artist works at, as shown on the artist profile.
export interface ArtistShop {
  handle: string;
  name: string;
  city: string | null;
  region: string | null;
  country: string | null;
  instagram_url: string;
  business_status: string | null;
  located: boolean;
  role: string | null;
  current: boolean | null;
  primary: boolean;
}

export interface ArtistDetail extends ArtistCard {
  bio: string | null;
  website: string | null;
  location_raw: string | null;
  shops: ArtistShop[];
  posts: PostCard[];
}

export interface ShopCard {
  id: number;
  handle: string;
  name: string;
  city: string | null;
  region: string | null;
  country: string | null;
  instagram_url: string;
  business_status: string | null;
  members_count: number;
  located: boolean;
}

// A roster member on a shop page (an artist card + their role at the shop).
export interface ShopArtist extends ArtistCard {
  role: string | null;
  current: boolean | null;
}

export interface ShopDetail extends ShopCard {
  address: string | null;
  latitude: number | null;
  longitude: number | null;
  maps_url: string | null;
  artists: ShopArtist[];
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
