# Enriches an Artist with profile data (name, bio, shop, location) scraped
# from their Instagram profile, then lets the model geocode the location.
#
# Profile lookups go through ApifyClient when APIFY_TOKEN is configured. When
# it is not, the job no-ops gracefully so post ingestion still works end-to-end
# in development. Location text is parsed from the bio and the model's
# after_validation geocode hook turns it into lat/lng for the map.
class EnrichArtistJob < ApplicationJob
  queue_as :enrichment

  def perform(artist_id)
    artist = Artist.find_by(id: artist_id)
    return if artist.nil?

    profile = ApifyClient.new.profile(artist.handle)
    return if profile.blank?

    artist.assign_attributes(
      name:         profile[:full_name].presence || artist.name,
      bio:          profile[:biography].presence  || artist.bio,
      website:      profile[:website].presence    || artist.website,
      location_raw: profile[:location].presence   || artist.location_raw,
      enriched_at:  Time.current
    )
    LocationParser.new(artist.location_raw || artist.bio).apply_to(artist)
    artist.save!
  rescue ApifyClient::NotConfigured
    Rails.logger.info("[EnrichArtistJob] APIFY_TOKEN not set; skipping enrichment for #{artist&.handle}")
  end
end
