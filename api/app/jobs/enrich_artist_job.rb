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
    extract_location(artist)
    artist.reload.resolve_location! if artist.latitude.blank? && artist.location_raw.present?
  rescue ApifyClient::NotConfigured
    Rails.logger.info("[EnrichArtistJob] APIFY_TOKEN not set; skipping #{artist&.handle}")
  end

  private

  def extract_location(artist)
    return unless LocationExtractor.configured?
    return if artist.bio.blank? || artist.location_extracted_at.present?

    loc = LocationExtractor.new.extract([artist.bio]).first
    if loc&.present?
      artist.update_columns(
        city: loc.city, region: loc.region, country: loc.country,
        location_raw: loc.to_query, location_extracted_at: Time.current, updated_at: Time.current
      )
    else
      artist.update_columns(location_extracted_at: Time.current, updated_at: Time.current)
    end
  rescue LocationExtractor::NotConfigured
    nil
  end
end
