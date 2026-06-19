# A handle discovered from a follow list (or other source) that may or may not
# be a tattoo artist. Staging area + audit trail before anything joins the real
# Artist directory. Flow: pending -> classified -> approved (becomes an Artist)
# | review (borderline, awaits a human) | rejected.
class ArtistCandidate < ApplicationRecord
  belongs_to :artist, optional: true

  STATUSES = %w[pending review approved rejected].freeze
  CLASSIFICATIONS = %w[tattoo_artist maybe not_artist].freeze

  validates :handle, presence: true, uniqueness: true
  before_validation { self.handle = Artist.normalize_handle(handle) }
  before_validation { self.status ||= "pending" }

  scope :pending,  -> { where(status: "pending") }
  scope :review,   -> { where(status: "review") }
  scope :approved, -> { where(status: "approved") }
  scope :scraped,  -> { where.not(scraped_at: nil) }

  def instagram_url
    "https://www.instagram.com/#{handle}/"
  end

  # Promote this candidate into the real directory, merging by handle and
  # recording the discovery source (corroboration if already present).
  def approve!
    artist = Artist.find_or_initialize_by(handle: handle)
    artist.name = full_name if artist.name.blank? && full_name.present?
    artist.bio  = bio        if artist.bio.blank?  && bio.present?
    artist.sources = (Array(artist.sources) | [source]).compact
    artist.save!
    update!(artist: artist, status: "approved")
    artist
  end
end
