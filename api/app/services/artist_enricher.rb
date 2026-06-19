# Enriches a batch of artists from their Instagram profiles in a SINGLE Apify
# run (efficient bulk path), setting name/bio/website and a raw location
# string parsed from the profile. Geocoding is deliberately deferred (see
# Artist#skip_geocoding) to a separate throttled pass so we respect the
# geocoder's rate policy and can validate location parsing for free first.
class ArtistEnricher
  Result = Struct.new(:fetched, :updated, :with_location, keyword_init: true)

  def initialize(artists, client: ApifyClient.new)
    @artists = Array(artists)
    @by_handle = @artists.index_by(&:handle)
    @client = client
  end

  def call
    profiles = @client.profiles(@by_handle.keys)
    result = Result.new(fetched: profiles.size, updated: 0, with_location: 0)

    profiles.each do |p|
      artist = @by_handle[p[:handle]]
      next if artist.nil?

      # If Apify surfaced a structured business-address city, keep it as a hint;
      # otherwise location comes from the LLM extraction step (extract_locations).
      artist.update!(
        name:         p[:full_name] || artist.name,
        bio:          p[:biography] || artist.bio,
        website:      p[:website] || artist.website,
        location_raw: p[:location].presence || artist.location_raw,
        enriched_at:  Time.current
      )
      result.updated += 1
      result.with_location += 1 if artist.location_raw.present?
    end

    # Mark artists Apify returned nothing for as enriched, so we don't re-bill
    # to retry them on every run.
    missing = @by_handle.values.reject { |a| a.enriched_at.present? }
    Artist.where(id: missing.map(&:id)).update_all(enriched_at: Time.current) if missing.any?

    result
  end
end
