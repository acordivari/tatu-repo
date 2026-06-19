# Guards against Google Places false matches before we trust a shop's location.
# Text Search returns *a* business even when it's the wrong one (a same-named
# studio on another continent, or a supplier brand the artist merely tagged).
# Two checks catch the failure modes seen in calibration:
#   1. name overlap   — the Google business name must share a token with the
#      shop handle (kills "killerinktattoo" -> "NERO tattoo atelier").
#   2. distance        — if a located member artist gives us a hint, the match
#      must be within MAX_KM of them (kills "strangelove.la" -> Houston).
class ShopPlaceVerifier
  MAX_KM = 150
  EARTH_KM = 6371.0
  # Generic words that shouldn't count as a meaningful name match on their own.
  GENERIC = %w[tattoo tattoos tattooing tattoos ink inked studio studios shop
               parlour parlor atelier art the and].freeze

  def initialize(shop, place, hint_artist)
    @shop = shop
    @place = place
    @hint = hint_artist
  end

  def accept?
    return false if @place.nil? || @place.latitude.nil?

    name_match? && location_consistent?
  end

  # True when we could positively corroborate the match against a known member
  # location (highest trust). Accepted-but-unverified still stores, hint-less.
  def verified?
    accept? && @hint&.latitude.present?
  end

  private

  def name_match?
    handle_tokens = tokens(@shop.handle.tr("._", " "))
    return true if handle_tokens.empty?

    name_tokens = tokens(@place.name.to_s)
    overlap = handle_tokens.any? { |h| name_tokens.any? { |n| n.include?(h) || h.include?(n) } }
    overlap || squash(@place.name).include?(handle_tokens.join) || handle_tokens.join.include?(squash(@place.name))
  end

  def location_consistent?
    return true if @hint&.latitude.blank? # no hint -> can't check, accept

    distance_km(@hint.latitude, @hint.longitude, @place.latitude, @place.longitude) <= MAX_KM
  end

  def tokens(str)
    normalize(str).split.reject { |t| t.length < 3 || GENERIC.include?(t) }
  end

  def squash(str)
    normalize(str).delete(" ")
  end

  # Lowercase, strip accents, drop non-alphanumerics.
  def normalize(str)
    str.to_s.downcase.unicode_normalize(:nfkd).gsub(/[^\x00-\x7F]/, "").gsub(/[^a-z0-9 ]/, " ").squish
  end

  def distance_km(lat1, lon1, lat2, lon2)
    dlat = (lat2 - lat1) * Math::PI / 180
    dlon = (lon2 - lon1) * Math::PI / 180
    a = Math.sin(dlat / 2)**2 +
        Math.cos(lat1 * Math::PI / 180) * Math.cos(lat2 * Math::PI / 180) * Math.sin(dlon / 2)**2
    EARTH_KM * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  end
end
