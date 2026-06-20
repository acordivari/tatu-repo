# A tattoo studio. First-class so we scrape/resolve each shop once even though
# many artists share it, and so a shop can carry its own location (IG business
# address, bio, or — best — a Google Places record).
class Shop < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :artists, through: :memberships

  validates :handle, presence: true, uniqueness: { case_sensitive: false }
  before_validation { self.handle = Artist.normalize_handle(handle) }

  scope :unresolved, -> { where(profile_scraped_at: nil) }
  scope :located,    -> { where.not(latitude: nil, longitude: nil) }
  scope :search, ->(q) {
    t = "%#{sanitize_sql_like(q.to_s.strip)}%"
    where("name ILIKE :t OR handle ILIKE :t OR city ILIKE :t", t: t)
  }

  def instagram_url
    "https://www.instagram.com/#{handle}/"
  end

  def location_query
    [name, address_raw.presence, city, region, country].compact_blank.join(", ").presence
  end
end
