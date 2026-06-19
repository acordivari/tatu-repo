# An artist's association with a shop, with provenance. `mutual` (both bios
# reference each other) and `current` (seen in the live bio) are the recency
# signals that let us trust a shop as the artist's present location.
class Membership < ApplicationRecord
  belongs_to :artist
  belongs_to :shop

  ROLES = %w[owner resident working guest unknown].freeze

  validates :artist_id, uniqueness: { scope: :shop_id }

  scope :current, -> { where(current: true) }
  scope :mutual,  -> { where(mutual: true) }
end
