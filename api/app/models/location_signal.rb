# One piece of evidence about where an artist is located. The resolver
# (LocationResolver) reads all of an artist's signals and picks the winner,
# so adding a new source (a shop's Google Places record, another aggregator
# that corroborates) is just inserting rows — the precedence handles the rest.
class LocationSignal < ApplicationRecord
  belongs_to :artist
  belongs_to :shop, optional: true

  # Source types ordered by trustworthiness. Google Places sits at the top: a
  # verified physical business with exact coordinates and a business status.
  SOURCE_CONFIDENCE = {
    "shop_google_places"           => 0.97, # shop matched to a verified Google business
    "shop_business_address_mutual" => 0.92, # IG business address + bidirectional bio confirmation
    "shop_business_address"        => 0.85, # IG business address, one-way mention
    "shop_bio_mutual"              => 0.80, # shop's bio location + mutual confirmation
    "shop_bio"                     => 0.70, # shop's bio location, one-way
    "artist_business_address"      => 0.60, # artist's own IG business address
    "artist_bio"                   => 0.50, # artist's bio (weakest — artists travel/guest)
    "post_caption"                 => 0.30  # mentioned alongside a post
  }.freeze

  validates :source_type, presence: true, inclusion: { in: SOURCE_CONFIDENCE.keys }

  before_validation { self.confidence ||= SOURCE_CONFIDENCE[source_type] }
  before_validation { self.observed_at ||= Time.current }

  scope :for_artist, ->(a) { where(artist_id: a.id) }
  # Best evidence first: highest confidence, then most recently observed.
  scope :ranked, -> { order(confidence: :desc, observed_at: :desc) }

  def query
    [city, region, country].compact_blank.join(", ").presence
  end
end
