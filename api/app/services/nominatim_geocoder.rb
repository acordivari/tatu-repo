# Geocodes a free-text location into coordinates + normalized city/region/
# country using OpenStreetMap's Nominatim. Uses HTTParty directly (the
# geocoder gem's Net::HTTP adapter hits SSL/CRL verification issues in some
# environments). Free; respect the usage policy (<=1 req/sec, descriptive UA).
class NominatimGeocoder
  ENDPOINT = "https://nominatim.openstreetmap.org/search".freeze
  USER_AGENT = "BlackworkersDirectory/1.0 (tattoo artist directory; admin@blackworkers.example)".freeze

  Result = Struct.new(:latitude, :longitude, :city, :region, :country, keyword_init: true)

  def self.lookup(query)
    new(query).lookup
  end

  def initialize(query)
    @query = query.to_s.strip
  end

  def lookup
    return nil if @query.blank?

    res = HTTParty.get(
      ENDPOINT,
      query: { q: @query, format: "jsonv2", addressdetails: 1, limit: 1 },
      headers: { "User-Agent" => USER_AGENT },
      timeout: 15
    )
    return nil unless res.success?

    data = JSON.parse(res.body).first
    return nil if data.nil?

    addr = data["address"] || {}
    Result.new(
      latitude:  data["lat"].to_f,
      longitude: data["lon"].to_f,
      city:      addr["city"] || addr["town"] || addr["village"] || addr["municipality"] || addr["county"],
      region:    addr["state"] || addr["region"] || addr["state_district"],
      country:   addr["country"]
    )
  rescue HTTParty::Error, JSON::ParserError, SocketError, Timeout::Error, Net::OpenTimeout => e
    Rails.logger.warn("[NominatimGeocoder] #{@query.inspect}: #{e.class} #{e.message}")
    nil
  end
end
