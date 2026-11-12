require "test_helper"

# Throttles must count the VISITOR. On Render a request arrives as
# `X-Forwarded-For: <client>, <Cloudflare edge>` from a private address, and
# the stock Rack answer is the edge — which made every limit per-edge.
class RateLimitTest < ActionDispatch::IntegrationTest
  CLIENT = "198.51.100.7".freeze

  def setup
    Rack::Attack.enabled = true
    Rack::Attack.reset!
  end

  def teardown
    Rack::Attack.reset!
    Rack::Attack.enabled = false
  end

  # Headers as Render delivers them: the client, then whichever Cloudflare edge
  # carried this request, optionally with Cloudflare's own client-IP header.
  def via_render(client:, edge:, cf_header: true, forged: nil)
    chain = [ forged, client, edge ].compact.join(", ")
    { "X-Forwarded-For" => chain }.merge(cf_header ? { "CF-Connecting-IP" => client } : {})
  end

  def with_admin_token(value)
    original = ENV["ADMIN_TOKEN"]
    ENV["ADMIN_TOKEN"] = value
    yield
  ensure
    ENV["ADMIN_TOKEN"] = original
  end

  test "one visitor is throttled even when each request comes through a different edge" do
    5.times do |i|
      get "/sitemap.xml", headers: via_render(client: CLIENT, edge: "104.22.17.#{i + 1}")
      assert_response :success
    end

    get "/sitemap.xml", headers: via_render(client: CLIENT, edge: "104.22.17.99")
    assert_response :too_many_requests
  end

  test "visitors sharing an edge do not share a counter" do
    5.times { get "/sitemap.xml", headers: via_render(client: CLIENT, edge: "104.22.17.40") }

    get "/sitemap.xml", headers: via_render(client: "198.51.100.8", edge: "104.22.17.40")
    assert_response :success
  end

  test "without Cloudflare's header, the address next to the edge is used" do
    5.times do |i|
      get "/sitemap.xml", headers: via_render(client: CLIENT, edge: "104.22.17.#{i + 1}", cf_header: false)
    end

    get "/sitemap.xml", headers: via_render(client: CLIENT, edge: "104.22.17.99", cf_header: false)
    assert_response :too_many_requests
  end

  test "a forged leading X-Forwarded-For entry does not dodge the limit" do
    6.times do |i|
      get "/sitemap.xml", headers: via_render(client: CLIENT, edge: "104.22.17.40",
                                              cf_header: false, forged: "203.0.113.#{i + 1}")
    end

    assert_response :too_many_requests
  end

  test "addresses in one IPv6 /64 count as one visitor" do
    6.times do |i|
      get "/sitemap.xml", headers: via_render(client: "2001:db8:1:2::#{i + 1}", edge: "104.22.17.40")
    end

    assert_response :too_many_requests
  end

  test "repeated wrong admin tokens are cut off" do
    with_admin_token("secret") do
      5.times do |i|
        get "/api/v1/candidates", headers: via_render(client: CLIENT, edge: "104.22.17.40")
          .merge("Authorization" => "Bearer guess#{i}")
        assert_response :unauthorized
      end

      get "/api/v1/candidates", headers: via_render(client: CLIENT, edge: "104.22.17.40")
        .merge("Authorization" => "Bearer guess-again")
      assert_response :too_many_requests
    end
  end

  test "the right admin token is never counted as an attempt" do
    with_admin_token("secret") do
      headers = via_render(client: CLIENT, edge: "104.22.17.40").merge("Authorization" => "Bearer secret")
      8.times do
        get "/api/v1/candidates", headers: headers
        assert_response :success
      end
    end
  end

  test "a mistyped token does not lock the moderator out of their own queue" do
    with_admin_token("secret") do
      base = via_render(client: CLIENT, edge: "104.22.17.40")
      6.times { |i| get "/api/v1/candidates", headers: base.merge("Authorization" => "Bearer guess#{i}") }
      assert_response :too_many_requests

      # The right token is not a failed attempt, so it is not throttled.
      get "/api/v1/candidates", headers: base.merge("Authorization" => "Bearer secret")
      assert_response :success
    end
  end
end
