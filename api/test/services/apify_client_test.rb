require "test_helper"

# A re-scrape must carry a date floor, or Apify bills every post we already
# hold on the way down to the new ones.
class ApifyClientTest < ActiveSupport::TestCase
  def setup
    @client = ApifyClient.new(token: "test-token", actor: "apify~instagram-scraper")
    stub_request(:get, %r{api\.apify\.com/v2/actor-runs/run1})
      .to_return(status: 200, body: { data: { status: "SUCCEEDED" } }.to_json)
    stub_request(:get, %r{api\.apify\.com/v2/datasets/ds1/items})
      .to_return(status: 200, body: "[]")
  end

  def stub_start
    stub_request(:post, %r{api\.apify\.com/v2/acts/apify~instagram-scraper/runs})
      .to_return(status: 201, body: { data: { id: "run1", defaultDatasetId: "ds1" } }.to_json)
  end

  test "posts_for sends the date floor when given" do
    stub_start
    @client.posts_for(%w[artist_a], per_user: 12, newer_than: Date.new(2026, 8, 24))

    assert_requested(:post, %r{/acts/apify~instagram-scraper/runs}) do |req|
      JSON.parse(req.body)["onlyPostsNewerThan"] == "2026-08-24"
    end
  end

  test "posts_for omits the floor for a first fetch" do
    stub_start
    @client.posts_for(%w[artist_a], per_user: 12)

    assert_requested(:post, %r{/acts/apify~instagram-scraper/runs}) do |req|
      !JSON.parse(req.body).key?("onlyPostsNewerThan")
    end
  end
end
