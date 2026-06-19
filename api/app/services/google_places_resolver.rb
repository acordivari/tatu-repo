# Resolves a tattoo shop to its verified Google Places business — exact
# coordinates, a clean name + address, and a business status (OPERATIONAL /
# CLOSED_PERMANENTLY), which doubles as "is this shop still real?" confirmation.
#
# Uses the Places API (New) Text Search. Configure with GOOGLE_MAPS_API_KEY.
# A field mask is REQUIRED by the API (omitting it errors). Queries pair the
# shop's handle/name with a city hint (from a located member artist) so we get
# the right business, not a same-named shop on another continent.
class GooglePlacesResolver
  class NotConfigured < StandardError; end

  ENDPOINT = "https://places.googleapis.com/v1/places:searchText".freeze
  FIELD_MASK = "places.id,places.displayName,places.formattedAddress,places.location,places.businessStatus,places.addressComponents".freeze

  Place = Struct.new(
    :place_id, :name, :formatted_address, :latitude, :longitude,
    :business_status, :city, :region, :country, keyword_init: true
  )

  def initialize(api_key: self.class.api_key)
    raise NotConfigured, "GOOGLE_MAPS_API_KEY is not set" if api_key.blank?

    @api_key = api_key
  end

  def self.api_key
    ENV["GOOGLE_MAPS_API_KEY"].presence || Rails.application.credentials.dig(:google_maps, :api_key)
  end

  def self.configured?
    api_key.present?
  end

  # query: a text query like "Black Veil Tattoo Salem MA". Returns a Place or nil.
  def lookup(query)
    return nil if query.blank?

    res = HTTParty.post(
      ENDPOINT,
      headers: {
        "Content-Type"     => "application/json",
        "X-Goog-Api-Key"   => @api_key,
        "X-Goog-FieldMask" => FIELD_MASK
      },
      body: { textQuery: query, pageSize: 1 }.to_json,
      timeout: 20
    )
    raise "Places API #{res.code}: #{res.body.to_s[0, 200]}" unless res.success?

    place = JSON.parse(res.body)["places"]&.first
    place && build(place)
  rescue HTTParty::Error, JSON::ParserError, SocketError, Timeout::Error, Net::OpenTimeout => e
    Rails.logger.warn("[GooglePlacesResolver] #{query.inspect}: #{e.class} #{e.message}")
    nil
  end

  private

  def build(place)
    comps = place["addressComponents"] || []
    Place.new(
      place_id:          place["id"],
      name:              place.dig("displayName", "text"),
      formatted_address: place["formattedAddress"],
      latitude:          place.dig("location", "latitude"),
      longitude:         place.dig("location", "longitude"),
      business_status:   place["businessStatus"],
      city:              component(comps, "locality") || component(comps, "postal_town"),
      region:            component(comps, "administrative_area_level_1"),
      country:           component(comps, "country")
    )
  end

  def component(comps, type)
    comps.find { |c| Array(c["types"]).include?(type) }&.dig("longText")
  end
end
