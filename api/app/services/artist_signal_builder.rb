# Turns one LocationExtractor::Extraction into ledger rows for an artist:
# an `artist_bio` location signal, and a Membership linking the artist to the
# shop they named (the relationship graph). Idempotent — re-running upserts
# rather than duplicating, and refreshes `last_confirmed_at` (the bio is live).
class ArtistSignalBuilder
  def initialize(artist, extraction, source_account: "blackworkers")
    @artist = artist
    @ext = extraction
    @source_account = source_account
  end

  def call
    record_bio_signal if location?
    record_membership if @ext.shop?
  end

  private

  # A trustworthy location needs at least one component the guard didn't reject.
  def location?
    trusted_city.present? || @ext.region.present? || @ext.country.present?
  end

  def record_bio_signal
    signal = @artist.location_signals.find_or_initialize_by(source_type: "artist_bio", shop_id: nil)
    signal.assign_attributes(
      city: trusted_city, region: @ext.region, country: @ext.country,
      source_account: @source_account, observed_at: Time.current,
      raw: @artist.bio.to_s.gsub(/\s+/, " ").strip[0, 255]
    )
    signal.save!
  end

  # The extracted city, unless it's actually a piece of the artist's own name.
  def trusted_city
    @trusted_city ||= name_derived_city?(@ext.city) ? nil : @ext.city
  end

  # True when `city` is glued INSIDE a handle/name token (a personal name like
  # "casper" within "caspermugridge") and never appears as a standalone word in
  # the name or bio — i.e. the LLM mistook part of a name/email for a place.
  def name_derived_city?(city)
    c = letters(city)
    return false if c.length < 4
    return false if standalone_word?(c, @artist.name) || standalone_word?(c, @artist.bio)

    (word_tokens(@artist.handle) + word_tokens(@artist.name)).any? { |t| t != c && t.include?(c) }
  end

  def letters(str) = str.to_s.downcase.gsub(/[^a-z]/, "")
  def word_tokens(str) = str.to_s.downcase.split(/[^a-z]+/).reject(&:empty?)
  def standalone_word?(city, text) = word_tokens(text).include?(city)

  def record_membership
    return if @ext.shop == @artist.handle # never link an artist to themselves

    shop = Shop.find_or_create_by!(handle: @ext.shop)
    membership = Membership.find_or_initialize_by(artist: @artist, shop: shop)
    membership.assign_attributes(
      role: @ext.role || "unknown",
      source: "bio",
      current: true, # found in the live bio
      first_seen_at: membership.first_seen_at || Time.current,
      last_confirmed_at: Time.current
    )
    membership.confidence ||= 0.5
    membership.save!
  end
end
