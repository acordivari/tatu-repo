# Enriches a single Artist end-to-end: profile (name, bio, website) via Apify,
# location extraction from the bio via Claude, then geocoding. Used for the
# on-demand / web flow; bulk backfills go through the rake tasks
# (instagram:enrich, :extract_locations, :geocode) which batch each stage.
#
# No-ops gracefully when APIFY_TOKEN / ANTHROPIC_API_KEY are unset.
class EnrichArtistJob < ApplicationJob
  queue_as :enrichment

  def perform(artist_id)
    artist = Artist.find_by(id: artist_id)
    return if artist.nil?

    ArtistEnricher.new([artist]).call
    artist.reload
    extract_location(artist)            # bio -> evidence-ledger signals
    LocationResolver.new(artist.reload).call  # ledger -> resolved coords (single source of truth)
  rescue ApifyClient::NotConfigured
    Rails.logger.info("[EnrichArtistJob] APIFY_TOKEN not set; skipping #{artist&.handle}")
  end

  private

  # Mirror the bulk `instagram:extract_locations` path: turn the bio into ledger
  # signals (+ shop membership) via ArtistSignalBuilder rather than writing
  # location columns directly. LocationResolver then picks the best signal.
  def extract_location(artist)
    return unless LocationExtractor.configured?
    return if artist.bio.blank? || artist.location_extracted_at.present?

    loc = LocationExtractor.new.extract([artist.bio]).first
    ArtistSignalBuilder.new(artist, loc).call if loc
    artist.update_columns(location_extracted_at: Time.current, updated_at: Time.current)
  rescue LocationExtractor::NotConfigured
    nil
  end
end
