require "test_helper"

# The directory thumbnail is the most visible image on the site — the homepage
# grid, shop rosters, and link unfurls all use it — so it must favour posts
# known to be work over whatever the artist posted most recently.
class ArtistSerializerTest < ActiveSupport::TestCase
  def setup
    @artist = Artist.create!(handle: "thumbartist")
  end

  # Posts get a stored image unless stored: false, matching a completed
  # download; stored: false is a post whose download never finished.
  def post(code, days_ago:, stored: true, **attrs)
    Post.create!(ig_shortcode: code, artist: @artist, posted_at: days_ago.days.ago, **attrs).tap do |p|
      p.image.attach(io: StringIO.new("img"), filename: "#{code}.jpg", content_type: "image/jpeg") if stored
    end
  end

  test "skips a post whose image was never stored, even a tattoo" do
    post("pv_unstored_tattoo", days_ago: 1, content_kind: "tattoo", stored: false,
         image_url: "https://instagram.example.fbcdn.net/expired.jpg")
    design = post("pv_stored_design", days_ago: 30, content_kind: "design")

    assert_equal design, ArtistSerializer.new(@artist).pick_preview(@artist.posts.to_a)
  end

  test "has no preview when no post has a stored image" do
    post("pv_unstored_only", days_ago: 1, content_kind: "tattoo", stored: false,
         image_url: "https://instagram.example.fbcdn.net/expired.jpg")

    assert_nil ArtistSerializer.new(@artist).as_card[:preview_image_url]
  end

  test "a post whose image was never stored serializes with no image URL, not the Instagram one" do
    unstored = post("pv_unstored_card", days_ago: 1, stored: false,
                    image_url: "https://instagram.example.fbcdn.net/expired.jpg")

    assert_nil PostSerializer.new(unstored).as_card[:image_url]
  end

  test "prefers an older curated credit over a newer unjudged post" do
    curated = post("pv_curated", days_ago: 400, caption: "Tattoo by @thumbartist #blackworkers")
    post("pv_selfie", days_ago: 1, caption: "Back from a weekend in the woods!")

    assert_equal curated, ArtistSerializer.new(@artist).pick_preview(@artist.posts.to_a)
  end

  test "prefers a vision-confirmed work post, newest first" do
    post("pv_old_work", days_ago: 30, content_kind: "work")
    newer = post("pv_new_work", days_ago: 5, content_kind: "work")
    post("pv_unjudged", days_ago: 1)

    assert_equal newer, ArtistSerializer.new(@artist).pick_preview(@artist.posts.to_a)
  end

  test "falls back to the newest unjudged post, never a hidden one" do
    unjudged = post("pv_unjudged2", days_ago: 10)
    post("pv_person", days_ago: 1, content_kind: "person")

    assert_equal unjudged, ArtistSerializer.new(@artist).pick_preview(@artist.posts.to_a)
  end

  test "a process shot never fronts the artist, even when it is the newest post" do
    tattoo = post("pv_finished", days_ago: 40, content_kind: "tattoo")
    post("pv_stencil", days_ago: 1, content_kind: "process")

    assert_equal tattoo, ArtistSerializer.new(@artist).pick_preview(@artist.posts.to_a)
  end

  test "has no preview when every post is hidden" do
    post("pv_promo", days_ago: 2, content_kind: "promo")

    assert_nil ArtistSerializer.new(@artist).pick_preview(@artist.posts.to_a)
  end

  test "a tattoo outranks a newer design, flash sheet or drawing" do
    tattoo = post("pv_tattoo", days_ago: 60, content_kind: "tattoo")
    post("pv_flash", days_ago: 2, content_kind: "design")
    post("pv_old_work", days_ago: 1, content_kind: "work")

    assert_equal tattoo, ArtistSerializer.new(@artist).pick_preview(@artist.posts.to_a)
  end

  test "a curated credit outranks a newer pre-v5 work verdict, unless v5 called it a design" do
    curated = post("pv_cur", days_ago: 300, caption: "Tattoo by @thumbartist")
    post("pv_cur_design", days_ago: 5, caption: "Design by @thumbartist", content_kind: "design")
    post("pv_work", days_ago: 1, content_kind: "work")

    assert_equal curated, ArtistSerializer.new(@artist).pick_preview(@artist.posts.to_a)
  end

  test "a design outranks an unjudged post, and a painting never shows" do
    design = post("pv_design", days_ago: 20, content_kind: "design")
    post("pv_painting", days_ago: 1, content_kind: "other")
    post("pv_unjudged3", days_ago: 3)

    assert_equal design, ArtistSerializer.new(@artist).pick_preview(@artist.posts.to_a)
  end
end
