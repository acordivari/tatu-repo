class Artist < ApplicationRecord
  has_many :posts, dependent: :nullify
  has_many :memberships, dependent: :destroy
  has_many :shops, through: :memberships
  has_many :location_signals, dependent: :destroy
  belongs_to :primary_shop, class_name: "Shop", optional: true

  validates :handle, presence: true, uniqueness: { case_sensitive: false }

  before_validation { self.handle = self.class.normalize_handle(handle) }

  # Effective region for faceting/filtering: the canonical label when present,
  # else the raw scraped region. The facet and the filter MUST use this same
  # expression so they always agree (see ArtistsController#regions / in_region).
  REGION_KEY = Arel.sql("COALESCE(NULLIF(region_canonical, ''), region)")

  scope :located,    -> { where.not(latitude: nil, longitude: nil) }
  scope :unenriched, -> { where(enriched_at: nil) }
  # Has a bio whose location hasn't been extracted yet — either never, or not
  # since the bio itself was last refreshed. Re-enriching an artist replaces the
  # bio but leaves the older extraction stamp behind, so comparing the two
  # stamps is what stops a fresh bio from being silently skipped.
  scope :needs_location_extraction, lambda {
    where.not(bio: [ nil, "" ])
      .where("location_extracted_at IS NULL OR location_extracted_at < enriched_at")
  }
  scope :in_country, ->(c) { where("LOWER(country) = ?", c.to_s.downcase) }
  scope :in_region,  ->(r) { where("LOWER(#{REGION_KEY.to_s}) = ?", r.to_s.strip.downcase) }

  # Text search. A query that exactly names a place with artists in it (city,
  # region, or country) is treated as a location search and returns only the
  # artists there — otherwise an artist merely *named* "Austin" would ride
  # along with every Austin, TX result. Anything else falls back to a broad
  # substring match across handle, name, shop, and location fields, so a
  # person is still findable by name or handle.
  scope :search, ->(q) {
    term = q.to_s.strip
    place = where(
      "LOWER(city) = :q OR LOWER(#{REGION_KEY.to_s}) = :q OR LOWER(country) = :q",
      q: term.downcase
    )
    return place if place.exists?

    t = "%#{sanitize_sql_like(term)}%"
    where(
      "handle ILIKE :t OR name ILIKE :t OR shop_name ILIKE :t OR " \
      "city ILIKE :t OR region ILIKE :t OR region_canonical ILIKE :t OR country ILIKE :t",
      t: t
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
end
