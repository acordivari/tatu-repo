require "test_helper"

# End-to-end checks on the directory endpoints: filtering, pagination headers,
# and the country-scoped region facet (whose counts must match what the filter
# actually returns).
class ArtistsApiTest < ActionDispatch::IntegrationTest
  def setup
    # Two US artists in California — one raw "California", one raw "CA" — both
    # canonicalized to "California". One Canadian artist for cross-country scope.
    Artist.create!(handle: "us_ca_1", country: "United States", region: "California",
                   region_canonical: "California", latitude: 34.0, longitude: -118.0)
    Artist.create!(handle: "us_ca_2", country: "United States", region: "CA",
                   region_canonical: "California", latitude: 34.1, longitude: -118.1)
    Artist.create!(handle: "ca_qc_1", country: "Canada", region: "Quebec",
                   region_canonical: "Quebec", latitude: 45.5, longitude: -73.5)
  end

  test "filters by country" do
    get "/api/v1/artists", params: { country: "United States" }
    assert_response :success
    assert_equal "2", response.headers["X-Total-Count"]
    handles = JSON.parse(response.body).map { |a| a["handle"] }
    assert_equal %w[us_ca_1 us_ca_2].sort, handles.sort
  end

  test "filters by canonical region, merging raw variants" do
    get "/api/v1/artists", params: { country: "United States", region: "California" }
    assert_response :success
    # Both the "California" and the "CA" artist come back under the canonical label.
    assert_equal "2", response.headers["X-Total-Count"]
  end

  test "emits pagination headers" do
    get "/api/v1/artists"
    assert_response :success
    assert_equal "3", response.headers["X-Total-Count"]
    assert_equal "1", response.headers["X-Page"]
    assert response.headers["X-Total-Pages"].present?
    assert response.headers["X-Per-Page"].present?
  end

  test "regions facet returns only countries without a country param" do
    get "/api/v1/artists/regions"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal({ "United States" => 2, "Canada" => 1 }, body["countries"])
    assert_nil body["regions"], "regions should be omitted until a country is chosen"
  end

  test "regions facet is country-scoped, deduped, and agrees with the filter" do
    get "/api/v1/artists/regions", params: { country: "United States" }
    assert_response :success
    facet = JSON.parse(response.body)["regions"]
    assert_equal({ "California" => 2 }, facet)

    # The facet count must equal what filtering by that label actually returns.
    get "/api/v1/artists", params: { country: "United States", region: "California" }
    assert_equal facet["California"].to_s, response.headers["X-Total-Count"]
  end
end
