require "test_helper"

# Attribution is where two past bugs lived: owner-mode orphaning posts, and
# owner-mode auto-creating junk artists from collaborative posts. These pin the
# caption vs owner behavior and the create_missing guard.
class InstagramIngestorTest < ActiveSupport::TestCase
  def item(shortcode:, caption: nil, owner: nil)
    { shortCode: shortcode, caption: caption, ownerUsername: owner,
      url: "https://www.instagram.com/p/#{shortcode}/", timestamp: "2024-01-01T00:00:00Z" }
  end

  test "caption mode creates the credited artist and links the post" do
    res = InstagramIngestor.new([item(shortcode: "AA1", caption: "Tattoo by @newartist")],
                                attach_images: false).call

    assert_equal 1, res.posts_created
    assert_equal 1, res.artists_created
    artist = Artist.find_by(handle: "newartist")
    assert_not_nil artist
    assert_equal artist, Post.find_by(ig_shortcode: "AA1").artist
  end

  test "owner mode with create_missing:false skips posts from untracked owners" do
    res = InstagramIngestor.new([item(shortcode: "BB1", owner: "unknownowner")],
                                attach_images: false, attribute_by: :owner, create_missing: false).call

    assert_equal 0, res.posts_created
    assert_nil Artist.find_by(handle: "unknownowner")
    assert_nil Post.find_by(ig_shortcode: "BB1")
  end

  test "owner mode attributes a post to an already-tracked owner" do
    owner = Artist.create!(handle: "knownowner")
    res = InstagramIngestor.new([item(shortcode: "CC1", owner: "KnownOwner")],
                                attach_images: false, attribute_by: :owner, create_missing: false).call

    assert_equal 1, res.posts_created
    assert_equal owner, Post.find_by(ig_shortcode: "CC1").artist
  end

  test "re-ingesting the same shortcode updates rather than duplicates" do
    first = InstagramIngestor.new([item(shortcode: "DD1", caption: "Tattoo by @x")], attach_images: false).call
    second = InstagramIngestor.new([item(shortcode: "DD1", caption: "Tattoo by @x")], attach_images: false).call

    assert_equal 1, first.posts_created
    assert_equal 0, second.posts_created
    assert_equal 1, second.posts_updated
    assert_equal 1, Post.where(ig_shortcode: "DD1").count
  end
end
