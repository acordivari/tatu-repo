require "test_helper"

class ShopsApiTest < ActionDispatch::IntegrationTest
  def setup
    @shop = Shop.create!(handle: "inkstudio", name: "Ink Studio", city: "Berlin",
                         region: "Berlin", country: "Germany",
                         latitude: 52.52, longitude: 13.405, business_status: "OPERATIONAL",
                         google_place_id: "PLACE123")
    @resident = Artist.create!(handle: "resident_artist", name: "Rae")
    @guest    = Artist.create!(handle: "guest_artist", name: "Gus")
    Membership.create!(artist: @resident, shop: @shop, role: "resident", current: true, confidence: 0.9)
    Membership.create!(artist: @guest, shop: @shop, role: "guest", current: false, confidence: 0.4)

    # An unlocated shop must not appear in the directory.
    Shop.create!(handle: "ghoststudio", name: "Ghost", country: "Germany")
  end

  test "index lists only located shops with member counts" do
    get "/api/v1/shops"
    assert_response :success
    body = JSON.parse(response.body)
    handles = body.map { |s| s["handle"] }
    assert_includes handles, "inkstudio"
    assert_not_includes handles, "ghoststudio", "unlocated shop should be hidden"
    assert_equal 2, body.find { |s| s["handle"] == "inkstudio" }["members_count"]
  end

  test "index search matches name or city" do
    get "/api/v1/shops", params: { q: "Berlin" }
    assert_response :success
    assert_equal ["inkstudio"], JSON.parse(response.body).map { |s| s["handle"] }
  end

  test "show returns the shop with its roster, residents first" do
    get "/api/v1/shops/inkstudio"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Ink Studio", body["name"]
    assert body["maps_url"].include?("PLACE123"), "links to the verified Google place"
    roster = body["artists"].map { |a| a["handle"] }
    assert_equal %w[resident_artist guest_artist], roster, "current/higher-confidence first"
    assert_equal "resident", body["artists"].first["role"]
  end

  test "show resolves by handle and 404s on unknown" do
    get "/api/v1/shops/nope_nope"
    assert_response :not_found
  end

  test "artist detail includes the artist's studio" do
    get "/api/v1/artists/resident_artist"
    assert_response :success
    shops = JSON.parse(response.body)["shops"]
    assert_equal 1, shops.size
    assert_equal "inkstudio", shops.first["handle"]
    assert_equal "resident", shops.first["role"]
  end
end
