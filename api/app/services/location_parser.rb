# Extracts a likely location phrase from freeform Instagram bio text so the
# geocoder has something clean to resolve. Bios are messy ("📍 Berlin |
# bookings ⬇️"), so this is heuristic: pull the text near a pin emoji or a
# "City, Country" pattern, falling back to the first comma-separated phrase.
#
# It sets artist.location_raw only; the model's geocode hook turns that into
# normalized city/region/country + coordinates.
class LocationParser
  PIN = /[📍🌍🌎🌏🏠🇺🇸]/.freeze
  # "City, ST" or "City, Country" — letters/spaces, comma, letters.
  CITY_COUNTRY = /([A-Z][a-zA-Z.\-]+(?:\s[A-Z][a-zA-Z.\-]+)*,\s*[A-Z][a-zA-Z.\-]+)/.freeze

  def initialize(text)
    @text = text.to_s
  end

  def location
    return if @text.blank?

    near_pin || city_country_phrase
  end

  def apply_to(artist)
    found = location
    artist.location_raw = found if found.present?
    artist
  end

  private

  # Text immediately following a pin emoji, up to a line break or separator.
  def near_pin
    return unless @text =~ PIN

    @text.split(PIN, 2).last.to_s[/\A[^\n|•·\-—]+/].to_s.strip.presence
  end

  def city_country_phrase
    @text[CITY_COUNTRY, 1]&.strip
  end
end
