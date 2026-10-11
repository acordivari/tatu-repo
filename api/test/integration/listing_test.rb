require "test_helper"

# An artist off the public site — Instagram profile gone, or delisted by hand
# (e.g. the artist has died) — must vanish from every surface a visitor can
# reach, or the site keeps implying they take bookings.
class ListingTest < ActionDispatch::IntegrationTest
  def setup
    @shop = Shop.create!(handle: "liststudio", name: "List Studio", city: "Denver", country: "United States",
                         latitude: 39.7, longitude: -104.9)
    @live    = Artist.create!(handle: "live_artist", country: "United States", region: "Colorado",
                              latitude: 39.7, longitude: -104.9)
    @gone    = Artist.create!(handle: "gone_artist", country: "United States", region: "Colorado",
                              latitude: 39.7, longitude: -104.9, profile_missing_at: 1.day.ago)
    @removed = Artist.create!(handle: "removed_artist", country: "United States", region: "Colorado",
                              latitude: 39.7, longitude: -104.9, delisted_at: 1.day.ago, delisted_reason: "deceased")
    [ @live, @gone, @removed ].each do |a|
      Membership.create!(artist: a, shop: @shop, role: "resident", current: true, confidence: 0.9)
      Post.create!(ig_shortcode: "post_#{a.handle}", artist: a, posted_at: 1.day.ago)
    end
  end

  def handles(json) = json.map { |a| a["handle"] }

  test "directory, search and map list only listed artists" do
    get "/api/v1/artists"
    assert_equal %w[live_artist], handles(JSON.parse(response.body))
    get "/api/v1/artists", params: { q: "artist" }
    assert_equal %w[live_artist], handles(JSON.parse(response.body))
    get "/api/v1/artists/map"
    assert_equal %w[live_artist], handles(JSON.parse(response.body))
  end

  test "region facets count only listed artists" do
    get "/api/v1/artists/regions", params: { country: "United States" }
    facets = JSON.parse(response.body)
    assert_equal 1, facets["countries"]["United States"]
    assert_equal 1, facets["regions"]["Colorado"]
  end

  test "an unlisted artist's page 404s" do
    get "/api/v1/artists/removed_artist"
    assert_response :not_found
    get "/api/v1/artists/gone_artist"
    assert_response :not_found
    get "/api/v1/artists/live_artist"
    assert_response :success
  end

  test "posts feed and shop roster leave unlisted artists out" do
    get "/api/v1/posts"
    assert_equal %w[post_live_artist], JSON.parse(response.body).map { |p| p["shortcode"] }
    get "/api/v1/shops/liststudio"
    assert_equal %w[live_artist], JSON.parse(response.body)["artists"].map { |a| a["handle"] }
  end

  test "sitemap omits unlisted artists" do
    get "/sitemap.xml"
    assert_includes response.body, "/artists/live_artist"
    assert_not_includes response.body, "removed_artist"
    assert_not_includes response.body, "gone_artist"
  end
end
