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
    record_bio_signal if @ext.location?
    record_membership if @ext.shop?
  end

  private

  def record_bio_signal
    signal = @artist.location_signals.find_or_initialize_by(source_type: "artist_bio", shop_id: nil)
    signal.assign_attributes(
      city: @ext.city, region: @ext.region, country: @ext.country,
      source_account: @source_account, observed_at: Time.current,
      raw: @artist.bio.to_s.gsub(/\s+/, " ").strip[0, 255]
    )
    signal.save!
  end

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
