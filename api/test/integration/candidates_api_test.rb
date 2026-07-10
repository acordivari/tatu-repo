require "test_helper"

# The candidates endpoints mutate the live directory (approve! publishes an
# artist), so they must reject any request without the shared admin token.
class CandidatesApiTest < ActionDispatch::IntegrationTest
  def setup
    @candidate = ArtistCandidate.create!(handle: "pending_artist", status: "review")
  end

  def with_admin_token(value)
    original = ENV["ADMIN_TOKEN"]
    ENV["ADMIN_TOKEN"] = value
    yield
  ensure
    ENV["ADMIN_TOKEN"] = original
  end

  test "rejects requests without a token" do
    with_admin_token("secret") do
      get "/api/v1/candidates"
      assert_response :unauthorized

      post "/api/v1/candidates/pending_artist/approve"
      assert_response :unauthorized
      assert_equal "review", @candidate.reload.status
      assert_nil Artist.find_by(handle: "pending_artist")

      post "/api/v1/candidates/pending_artist/reject"
      assert_response :unauthorized
      assert_equal "review", @candidate.reload.status
    end
  end

  test "rejects requests with a wrong token" do
    with_admin_token("secret") do
      post "/api/v1/candidates/pending_artist/approve",
           headers: { "Authorization" => "Bearer wrong" }
      assert_response :unauthorized
      assert_equal "review", @candidate.reload.status
    end
  end

  test "rejects everything when no ADMIN_TOKEN is configured" do
    with_admin_token(nil) do
      get "/api/v1/candidates", headers: { "Authorization" => "Bearer anything" }
      assert_response :unauthorized
    end
  end

  test "accepts the correct token" do
    with_admin_token("secret") do
      get "/api/v1/candidates", headers: { "Authorization" => "Bearer secret" }
      assert_response :success
      assert_equal 1, JSON.parse(response.body)["count"]

      post "/api/v1/candidates/pending_artist/approve",
           headers: { "Authorization" => "Bearer secret" }
      assert_response :success
      assert_equal "approved", @candidate.reload.status
      assert Artist.exists?(handle: "pending_artist")
    end
  end
end
