# Thin wrapper over the Apify API for scraping Instagram in a low-risk,
# non-disruptive way. Apify operates the proxies and rate-limiting; we only
# pull the resulting dataset.
#
# Configure with APIFY_TOKEN (Rails credentials or ENV). Without it, the
# client raises NotConfigured so callers can degrade gracefully.
#
# Actor: apify/instagram-scraper
#   posts(username:, limit:) -> [{shortCode, caption, url, displayUrl, timestamp}, ...]
#   profile(handle)          -> {full_name, biography, website, location}
class ApifyClient
  class NotConfigured < StandardError; end
  class RequestError < StandardError; end

  BASE = "https://api.apify.com/v2".freeze
  ACTOR = "apify~instagram-scraper".freeze

  def initialize(token: self.class.token)
    raise NotConfigured, "APIFY_TOKEN is not set" if token.blank?

    @token = token
  end

  # Scrape recent posts from a profile (e.g. "blackworkers").
  def posts(username:, limit: 1000)
    run_sync(
      directUrls:    ["https://www.instagram.com/#{username}/"],
      resultsType:   "posts",
      resultsLimit:  limit,
      addParentData: false
    )
  end

  # Scrape a single artist profile's details for enrichment.
  def profile(handle)
    items = run_sync(
      directUrls:   ["https://www.instagram.com/#{handle}/"],
      resultsType:  "details",
      resultsLimit: 1
    )
    detail = items.first
    return nil if detail.blank?

    d = detail.with_indifferent_access
    {
      full_name: d[:fullName],
      biography: d[:biography],
      website:   d[:externalUrl] || d[:website],
      location:  d.dig(:businessAddress, :city_name) || d[:locationName]
    }
  end

  def self.token
    ENV["APIFY_TOKEN"].presence ||
      Rails.application.credentials.dig(:apify, :token)
  end

  private

  # Run the actor and block until it returns the dataset items.
  def run_sync(input)
    response = HTTParty.post(
      "#{BASE}/acts/#{ACTOR}/run-sync-get-dataset-items?token=#{@token}",
      headers: { "Content-Type" => "application/json" },
      body: input.to_json,
      timeout: 300
    )
    raise RequestError, "Apify returned #{response.code}" unless response.success?

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    raise RequestError, "Invalid Apify response: #{e.message}"
  end
end
