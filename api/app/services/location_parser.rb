# Extracts a clean, geocodable location phrase from a freeform Instagram bio.
#
# Tattoo bios are messy ("🇧🇷 São Paulo / SP", "📍 @studio", "based in Denver co",
# "MILANO", "Books Closed. Calgary, AB"). This pulls the best location candidate
# using several ordered strategies and rejects non-places (@handles, emails,
# URLs). The model's geocode pass then validates it against Nominatim, so a
# slightly loose candidate is fine — a wrong one is filtered out by geocoding.
class LocationParser
  PINS = /[📍🌍🌎🌏🏠⛩️]/.freeze

  # Flag emoji -> country name (regional-indicator pairs decoded to ISO-3166).
  FLAG_COUNTRIES = {
    "US" => "USA", "GB" => "United Kingdom", "CA" => "Canada", "BR" => "Brazil",
    "DE" => "Germany", "FR" => "France", "IT" => "Italy", "ES" => "Spain",
    "PT" => "Portugal", "NL" => "Netherlands", "BE" => "Belgium", "CH" => "Switzerland",
    "AT" => "Austria", "PL" => "Poland", "SE" => "Sweden", "NO" => "Norway",
    "DK" => "Denmark", "FI" => "Finland", "IE" => "Ireland", "RU" => "Russia",
    "UA" => "Ukraine", "JP" => "Japan", "KR" => "South Korea", "CN" => "China",
    "TW" => "Taiwan", "TH" => "Thailand", "ID" => "Indonesia", "PH" => "Philippines",
    "AU" => "Australia", "NZ" => "New Zealand", "MX" => "Mexico", "AR" => "Argentina",
    "CL" => "Chile", "CO" => "Colombia", " ZA" => "South Africa", "GR" => "Greece",
    "CZ" => "Czechia", "RO" => "Romania", "HU" => "Hungary", "TR" => "Turkey",
    "IL" => "Israel", "SG" => "Singapore", "KH" => "Cambodia"
  }.freeze

  # "based in X", Portuguese "em X", Spanish/Italian "en/in X".
  BASED_IN = /\b(?:based\s+in|located\s+in|tatuador[ae]?\s+em|tattoo(?:er|ist)?\s+in|em|en)\s+([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ.'\- ]{2,30})/i.freeze

  # "City, Region/Country" or "City - Country" / "City / Country".
  CITY_SEP = /([A-Z][A-Za-zÀ-ÿ.'\-]+(?:\s+[A-Z][A-Za-zÀ-ÿ.'\-]+){0,2})\s*[,\/\-]\s*([A-Z][A-Za-zÀ-ÿ.'\-]{1,20})/.freeze

  def initialize(text)
    @raw = text.to_s
    @clean = scrub(@raw)
  end

  def location
    return if @clean.blank?

    from_pin || from_city_sep || from_based_in || from_flag
  end

  def apply_to(artist)
    found = location
    artist.location_raw = found if found.present?
    artist
  end

  private

  # Remove emails, URLs, @handles, hashtags — never valid locations.
  def scrub(text)
    text.dup
        .gsub(/\S+@\S+\.\S+/, " ")           # emails
        .gsub(%r{https?://\S+|www\.\S+}i, " ") # urls
        .gsub(/[@#]\w+/, " ")                  # handles / hashtags
        .gsub(/\s+/, " ")
        .strip
  end

  # Text right after a pin emoji, stopped at a separator or sentence break.
  def from_pin
    return unless @raw =~ PINS

    candidate = @raw.split(PINS, 2).last.to_s
                    .gsub(/[@#]\w+/, "")
                    .strip[/\A[^\n|•·✈️✆☎️:;]+/]
                    .to_s.strip
    cleanup(candidate)
  end

  def from_city_sep
    return unless (m = @clean.match(CITY_SEP))

    cleanup("#{m[1]}, #{m[2]}")
  end

  def from_based_in
    return unless (m = @clean.match(BASED_IN))

    cleanup(m[1])
  end

  # A flag emoji gives the country; pair it with nearby capitalized words.
  def from_flag
    country = flag_country(@raw)
    return if country.nil?

    # Words adjacent to the flag, if any look like a place.
    city = @raw.gsub(/[@#]\w+/, "")[/[A-Z][A-Za-zÀ-ÿ.'\- ]{2,30}/]&.strip
    city && city.length > 2 ? cleanup("#{city}, #{country}") : country
  end

  def flag_country(text)
    text.scan(/[\u{1F1E6}-\u{1F1FF}]{2}/).each do |flag|
      code = flag.chars.map { |c| (c.codepoints.first - 0x1F1E6 + 65).chr }.join
      return FLAG_COUNTRIES[code] if FLAG_COUNTRIES[code]
    end
    nil
  end

  # Final tidy: trim trailing punctuation/filler, reject obvious non-places.
  def cleanup(str)
    s = str.to_s.gsub(/\s+/, " ").strip.sub(/[\s,.\-\/]+\z/, "").sub(/\A[\s,.\-\/]+/, "")
    return nil if s.length < 3 || s.length > 40
    # Reject phrases that are clearly not a place.
    return nil if s.match?(/\b(books?|open|closed|email|booking|dm|appointments?|inquiries|guest|spot)\b/i)

    s
  end
end
