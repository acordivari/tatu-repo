# Abuse protection for a public, unauthenticated API. Counters live in a
# per-process memory store, so the effective ceiling is limit × workers —
# fine as a backstop; legitimate browsing stays far below these numbers.
Rack::Attack.enabled = !Rails.env.test?
Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

# Overall per-IP ceiling on API traffic (images are served from storage
# directly, so normal page loads are only a handful of JSON requests).
Rack::Attack.throttle("api/ip", limit: 300, period: 5.minutes) do |req|
  req.ip if req.path.start_with?("/api/")
end

# Search runs unindexed ILIKE scans — cap it tighter than plain reads.
Rack::Attack.throttle("search/ip", limit: 30, period: 1.minute) do |req|
  req.ip if req.path.start_with?("/api/") && req.params["q"].present?
end

# The sitemap walks every artist/shop row per request; crawlers only need it
# occasionally.
Rack::Attack.throttle("sitemap/ip", limit: 5, period: 1.minute) do |req|
  req.ip if req.path == "/sitemap.xml"
end

Rack::Attack.throttled_responder = lambda do |_request|
  [ 429,
    { "content-type" => "application/json" },
    [ { error: "Rate limit exceeded — try again in a minute." }.to_json ] ]
end
