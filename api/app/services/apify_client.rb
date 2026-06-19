# Wrapper over the Apify API for scraping Instagram in a low-risk,
# non-disruptive way. Apify operates the proxies and rate-limiting; we only
# start a run and pull the resulting dataset.
#
# Uses the ASYNC run API (start run -> poll status -> fetch dataset) rather
# than the synchronous endpoint, because a 1k-3k post backfill can exceed the
# sync endpoint's 5-minute / response-size limits.
#
# Configure with APIFY_TOKEN (api/.env via dotenv, ENV, or Rails credentials).
# Without it, the client raises NotConfigured so callers degrade gracefully.
#
# Cost (official apify/instagram-scraper, mid-2026): ~$1.50 per 1,000 posts.
class ApifyClient
  class NotConfigured < StandardError; end
  class RequestError < StandardError; end
  class RunFailed < StandardError; end

  BASE = "https://api.apify.com/v2".freeze
  DEFAULT_ACTOR = "apify~instagram-scraper".freeze
  POLL_INTERVAL = 5         # seconds between status checks
  DEFAULT_TIMEOUT = 2400    # max seconds to wait for a run (40 min — covers a 3k backfill)
  PAGE_SIZE = 1000          # dataset items per request

  def initialize(token: self.class.token, actor: self.class.actor)
    raise NotConfigured, "APIFY_TOKEN is not set" if token.blank?

    @token = token
    @actor = actor
  end

  # Scrape recent posts from a profile (e.g. "blackworkers").
  def posts(username:, limit: 1000, timeout: DEFAULT_TIMEOUT)
    run(
      {
        directUrls:    ["https://www.instagram.com/#{username}/"],
        resultsType:   "posts",
        resultsLimit:  limit,
        addParentData: false
      },
      timeout: timeout
    )
  end

  # Scrape MANY artist profiles in a single run (the efficient path for bulk
  # enrichment). Returns normalized profile hashes keyed by handle.
  def profiles(handles, timeout: DEFAULT_TIMEOUT)
    handles = Array(handles).map { |h| Artist.normalize_handle(h) }.compact.uniq
    return [] if handles.empty?

    items = run(
      {
        directUrls:   handles.map { |h| "https://www.instagram.com/#{h}/" },
        resultsType:  "details",
        resultsLimit: handles.size
      },
      timeout: timeout
    )
    items.filter_map { |raw| normalize_profile(raw) }
  end

  # Convenience: scrape a single profile (delegates to the batch path).
  def profile(handle)
    profiles([handle], timeout: 180).first
  end

  def self.token
    ENV["APIFY_TOKEN"].presence ||
      Rails.application.credentials.dig(:apify, :token)
  end

  def self.actor
    ENV["APIFY_INSTAGRAM_ACTOR"].presence || DEFAULT_ACTOR
  end

  private

  # Map an Apify profile-detail item onto our canonical keys.
  def normalize_profile(raw)
    d = raw.with_indifferent_access
    handle = Artist.normalize_handle(d[:username] || d[:ownerUsername] || d[:inputUrl].to_s[%r{instagram\.com/([^/?]+)}, 1])
    return nil if handle.blank?

    {
      handle:    handle,
      full_name: d[:fullName].presence,
      biography: d[:biography].presence,
      website:   (d[:externalUrl] || d[:website]).presence,
      # Business accounts expose a structured city; otherwise we parse the bio.
      location:  (d.dig(:businessAddress, :city_name) || d[:locationName] || d[:city_name]).presence
    }
  end

  # Start a run, wait for it to finish, then return all dataset items.
  def run(input, timeout:)
    started = start_run(input)
    Rails.logger.info("[ApifyClient] run #{started['id']} started")
    wait_for(started["id"], timeout)
    fetch_all_items(started["defaultDatasetId"])
  end

  def start_run(input)
    res = post("/acts/#{@actor}/runs", input)
    raise RequestError, "start run failed (#{res.code})" unless res.code == 201

    JSON.parse(res.body).fetch("data")
  end

  # Poll the run until it reaches a terminal state or we time out.
  def wait_for(run_id, timeout)
    deadline = monotonic + timeout
    loop do
      data = get("/actor-runs/#{run_id}").fetch("data")
      case data["status"]
      when "SUCCEEDED"
        return data
      when "FAILED", "ABORTED", "TIMED-OUT"
        raise RunFailed, "run #{run_id} ended as #{data['status']}"
      end
      raise RunFailed, "run #{run_id} timed out after #{timeout}s" if monotonic > deadline

      sleep POLL_INTERVAL
    end
  end

  # Page through the dataset and collect every item.
  def fetch_all_items(dataset_id)
    items = []
    offset = 0
    loop do
      page = get("/datasets/#{dataset_id}/items", limit: PAGE_SIZE, offset: offset)
      break if page.blank?

      items.concat(page)
      break if page.size < PAGE_SIZE

      offset += PAGE_SIZE
    end
    items
  end

  # --- HTTP helpers ---

  def post(path, body)
    HTTParty.post(
      "#{BASE}#{path}?token=#{@token}",
      headers: { "Content-Type" => "application/json" },
      body: body.to_json,
      timeout: 60
    )
  end

  def get(path, **query)
    res = HTTParty.get("#{BASE}#{path}", query: query.merge(token: @token), timeout: 60)
    raise RequestError, "GET #{path} failed (#{res.code})" unless res.success?

    JSON.parse(res.body)
  rescue JSON::ParserError => e
    raise RequestError, "invalid JSON from #{path}: #{e.message}"
  end

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
