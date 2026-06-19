class Artist < ApplicationRecord
  has_many :posts, dependent: :nullify

  validates :handle, presence: true, uniqueness: { case_sensitive: false }

  before_validation { self.handle = self.class.normalize_handle(handle) }

  # Geocode the artist's location text into lat/lng AND normalized
  # city/region/country (so the directory can be filtered by geography).
  # Runs only when there's a query and it hasn't already been resolved.
  geocoded_by :geocode_query do |artist, results|
    if (geo = results.first)
      artist.latitude  = geo.latitude
      artist.longitude = geo.longitude
      artist.city    = geo.city            if artist.city.blank?
      artist.region  = geo.state           if artist.region.blank?
      artist.country = geo.country         if artist.country.blank?
    end
  end
  after_validation :geocode, if: :geocodable?

  scope :located,    -> { where.not(latitude: nil, longitude: nil) }
  scope :in_country, ->(c) { where("LOWER(country) = ?", c.to_s.downcase) }
  scope :in_region,  ->(r) { where("LOWER(region) = ?", r.to_s.downcase) }

  # Text search across handle, name, shop, and location.
  scope :search, ->(q) {
    term = "%#{sanitize_sql_like(q.to_s.strip)}%"
    where(
      "handle ILIKE :t OR name ILIKE :t OR shop_name ILIKE :t OR " \
      "city ILIKE :t OR region ILIKE :t OR country ILIKE :t",
      t: term
    )
  }

  # Within a bounding box sent by the map viewport.
  scope :within_bounds, ->(sw_lat, sw_lng, ne_lat, ne_lng) {
    located.where(latitude: sw_lat..ne_lat, longitude: sw_lng..ne_lng)
  }

  def instagram_url
    "https://www.instagram.com/#{handle}/"
  end

  # Strip leading @, whitespace, and downcase — handles are case-insensitive.
  def self.normalize_handle(raw)
    raw.to_s.strip.delete_prefix("@").downcase.presence
  end

  # Prefer the most specific location signal available.
  def geocode_query
    [city, region, country].compact_blank.join(", ").presence || location_raw
  end

  # Only geocode when there's a location to resolve and we haven't already.
  def geocodable?
    geocode_query.present? && latitude.blank?
  end
end
