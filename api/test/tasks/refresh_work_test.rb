require "test_helper"
require "rake"

# The refresh queue decides who gets billed, so it must skip artists fetched
# recently, carry each artist's own date floor, and put the thinnest SHOWN
# galleries first — junk the classifier hid does not count toward a gallery.
class RefreshWorkTest < ActiveSupport::TestCase
  def setup
    # Guard on the helper, not the task: a full `bin/rails test` run has already
    # loaded the rake files (into the CLI's own Rake app), so the helpers exist
    # while no task is registered — and loading again redefines their constants.
    Rails.application.load_tasks unless respond_to?(:artists_to_refresh, true)
  end

  def queue
    send(:artists_to_refresh, 14.days)
  end

  def with_images(artist, n, **attrs)
    n.times do |i|
      post = Post.create!(ig_shortcode: "#{artist.handle}_#{attrs[:content_kind]}_#{i}", artist: artist, **attrs)
      post.image.attach(io: StringIO.new("img"), filename: "#{i}.jpg", content_type: "image/jpeg")
    end
  end

  test "skips artists fetched within the gap and floors the rest at their last fetch" do
    recent = Artist.create!(handle: "rw_recent", work_fetched_at: 3.days.ago)
    stale  = Artist.create!(handle: "rw_stale", work_fetched_at: Time.utc(2026, 8, 24, 18))
    Post.create!(ig_shortcode: "rw_stale_newer", artist: stale, posted_at: Time.utc(2026, 9, 1))
    empty  = Artist.create!(handle: "rw_empty")

    rows = queue.index_by { |r| r[:handle] }
    assert_not rows.key?(recent.handle)
    # The stamp wins when present: a newer held post (a page repost) must not
    # lift the floor past own posts we have not fetched.
    assert_equal Date.new(2026, 8, 24), rows[stale.handle][:since]
    assert_nil rows[empty.handle][:since]
  end

  test "an unstamped artist with held posts is floored at the newest one" do
    unstamped = Artist.create!(handle: "rw_unstamped")
    Post.create!(ig_shortcode: "rw_u1", artist: unstamped, posted_at: Time.utc(2026, 3, 28, 12))
    Post.create!(ig_shortcode: "rw_u2", artist: unstamped, posted_at: Time.utc(2025, 1, 2))

    assert_equal Date.new(2026, 3, 28), queue.find { |r| r[:handle] == "rw_unstamped" }[:since]
  end

  test "orders by shown images, so hidden junk does not fill a gallery" do
    junky = Artist.create!(handle: "rw_junky")
    with_images(junky, 1, content_kind: "work")
    with_images(junky, 4, content_kind: "person")
    full = Artist.create!(handle: "rw_full")
    with_images(full, 3, content_kind: "work")

    handles = queue.map { |r| r[:handle] }
    assert_operator handles.index("rw_junky"), :<, handles.index("rw_full")
    assert_equal 1, queue.find { |r| r[:handle] == "rw_junky" }[:imgs]
  end

  test "delisted artists are never refreshed; missing ones are, so they can come back" do
    Artist.create!(handle: "rw_removed", delisted_at: 1.day.ago, delisted_reason: "deceased")
    Artist.create!(handle: "rw_missing", profile_missing_at: 1.day.ago)

    handles = queue.map { |r| r[:handle] }
    assert_not_includes handles, "rw_removed"
    assert_includes handles, "rw_missing"
  end

  test "record_profile_presence hides not_found profiles and relists ones that post again" do
    gone = Artist.create!(handle: "rw_gone")
    back = Artist.create!(handle: "rw_back", profile_missing_at: 30.days.ago)
    private_one = Artist.create!(handle: "rw_private")
    batch = [ gone, back, private_one ].map { |a| { id: a.id, handle: a.handle } }
    items = [
      { "error" => "not_found", "inputUrl" => "https://www.instagram.com/rw_gone/" },
      { "error" => "no_items", "inputUrl" => "https://www.instagram.com/rw_private/" },
      { "shortCode" => "x1", "ownerUsername" => "rw_back" }
    ]

    assert_equal [ 1, 1 ], send(:record_profile_presence, items, batch)
    assert gone.reload.profile_missing_at
    assert_nil back.reload.profile_missing_at
    assert_nil private_one.reload.profile_missing_at
  end
end
