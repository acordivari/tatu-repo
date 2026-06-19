class Artist < ApplicationRecord
  has_many :posts, dependent: :nullify

  validates :handle, presence: true, uniqueness: { case_sensitive: false }

  before_validation { self.handle = self.class.normalize_handle(handle) }

  scope :located,    -> { where.not(latitude: nil, longitude: nil) }
  scope :unenriched, -> { where(enriched_at: nil) }
  # Has a bio but hasn't had its location extracted by the LLM yet.
  scope :needs_location_extraction, -> { where.not(bio: [nil, ""]).where(location_extracted_at: nil) }
  # Has a location string but hasn't been geocoded to coordinates yet.
  scope :awaiting_geocode, -> { where.not(location_raw: [nil, ""]).where(latitude: nil) }
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

  # Resolve location_raw into coordinates + normalized city/region/country.
  # Returns true if it landed on a real place. Uses update_columns so it can
  # run in a throttled pass without re-triggering validations/callbacks.
  def resolve_location!
    result = NominatimGeocoder.lookup(geocode_query)
    return false if result.nil?

    update_columns(
      latitude:  result.latitude,
      longitude: result.longitude,
      city:      city.presence    || result.city,
      region:    region.presence  || result.region,
      country:   country.presence || result.country,
      updated_at: Time.current
    )
    true
  end
end
