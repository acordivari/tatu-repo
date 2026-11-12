# Abuse protection for a public, unauthenticated API. Counters live in a
# per-process memory store, so the effective ceiling is limit × workers —
# fine as a backstop; legitimate browsing stays far below these numbers.
Rack::Attack.enabled = !Rails.env.test?
Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

class Rack::Attack::Request
  # The address of the visitor, for per-client throttles.
  #
  # Not `ip`: on Render every request arrives through Cloudflare and then
  # Render's own proxy, as `X-Forwarded-For: <client>, <Cloudflare edge>` from a
  # private REMOTE_ADDR. Rack skips the private hop and takes the last public
  # address — the Cloudflare edge. Throttles keyed on that were per edge, not
  # per visitor: 27 back-to-back requests passed a 5-per-minute limit, and
  # unrelated visitors behind one edge shared a counter.
  #
  # Cloudflare sets CF-Connecting-IP itself and refuses requests that try to
  # supply one, so it is preferred. Failing that, the entry just left of the
  # edge in X-Forwarded-For is the address Cloudflare saw; anything further
  # left was sent by the client and is never trusted. With neither (local
  # development, tests) this is plain `ip`.
  def client_ip
    @client_ip ||= begin
      hops = get_header("HTTP_X_FORWARDED_FOR").to_s.split(",").map(&:strip)
      normalize_ip(get_header("HTTP_CF_CONNECTING_IP")) ||
        (normalize_ip(hops[-2]) if hops.size >= 2) ||
        ip
    end
  end

  # Wrong or missing moderation token on a candidates endpoint.
  def failed_admin_attempt?
    path.start_with?("/api/v1/candidates") && !AdminToken.valid?(get_header("HTTP_AUTHORIZATION"))
  end

  private

  # A parseable address, or nil. IPv6 is cut to its /64: one subscriber holds
  # the whole /64, so counting single addresses would let them rotate freely.
  def normalize_ip(value)
    addr = IPAddr.new(value.to_s.strip)
    (addr.ipv6? ? addr.mask(64) : addr).to_s
  rescue IPAddr::Error
    nil
  end
end

# Overall per-client ceiling on API traffic (images are served from storage
# directly, so normal page loads are only a handful of JSON requests).
Rack::Attack.throttle("api/ip", limit: 300, period: 5.minutes) do |req|
  req.client_ip if req.path.start_with?("/api/")
end

# Search runs unindexed ILIKE scans — cap it tighter than plain reads.
Rack::Attack.throttle("search/ip", limit: 30, period: 1.minute) do |req|
  req.client_ip if req.path.start_with?("/api/") && req.params["q"].present?
end

# The sitemap walks every artist/shop row per request; crawlers only need it
# occasionally.
Rack::Attack.throttle("sitemap/ip", limit: 5, period: 1.minute) do |req|
  req.client_ip if req.path == "/sitemap.xml"
end

# Guessing the moderation token. Only failed attempts count, so a moderator
# working through the review queue with the right token is never slowed; a
# mistyped token leaves room to try again. Two windows: a burst limit, and an
# hourly one so a patient guesser gains nothing by pacing.
Rack::Attack.throttle("admin/failed/minute", limit: 5, period: 1.minute) do |req|
  req.client_ip if req.failed_admin_attempt?
end
Rack::Attack.throttle("admin/failed/hour", limit: 20, period: 1.hour) do |req|
  req.client_ip if req.failed_admin_attempt?
end

Rack::Attack.throttled_responder = lambda do |_request|
  [ 429,
    { "content-type" => "application/json" },
    [ { error: "Rate limit exceeded — try again in a minute." }.to_json ] ]
end
