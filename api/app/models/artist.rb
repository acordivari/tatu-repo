class Artist < ApplicationRecord
  has_many :posts, dependent: :nullify
  has_many :memberships, dependent: :destroy
  has_many :shops, through: :memberships
  has_many :location_signals, dependent: :destroy
  belongs_to :primary_shop, class_name: "Shop", optional: true

  validates :handle, presence: true, uniqueness: { case_sensitive: false }

  before_validation { self.handle = self.class.normalize_handle(handle) }

  scope :located,    -> { where.not(latitude: nil, longitude: nil) }
  scope :unenriched, -> { where(enriched_at: nil) }
  # Has a bio but hasn't had its location extracted by the LLM yet.
  scope :needs_location_extraction, -> { where.not(bio: [nil, ""]).where(location_extracted_at: nil) }
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
end
