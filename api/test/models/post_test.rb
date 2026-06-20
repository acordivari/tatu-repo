require "test_helper"

# The attribution regex is the heart of the @blackworkers ingestion: it turns a
# caption into the artist it credits. These lock down the credit words it must
# accept and the generic verbs it must NOT mistake for attribution.
class PostTest < ActiveSupport::TestCase
  test "extracts handle after a tattoo credit, with or without @" do
    assert_equal "coolartist", Post.handle_from_caption("Tattoo by @coolartist")
    assert_equal "coolartist", Post.handle_from_caption("tattoo by coolartist")
  end

  test "normalizes the extracted handle (downcase, keep dots/underscores)" do
    assert_equal "cool.artist_1", Post.handle_from_caption("Tattoo by @Cool.Artist_1")
  end

  test "accepts the various credit words the feed uses" do
    {
      "Cover-up by @a"        => "a",
      "coverup by @b"         => "b",
      "Bodysuit by @c"        => "c",
      "Collaboration by @d"   => "d",
      "Piece by @e"           => "e",
      "Freehand by @f"        => "f",
      "Healed tattoo by @g"   => "g",
      "Tattoo (filler) by @h" => "h",
      "Tattoos by @i"         => "i"
    }.each do |caption, handle|
      assert_equal handle, Post.handle_from_caption(caption), "for caption #{caption.inspect}"
    end
  end

  test "does not attribute generic verbs like inspired/commissioned" do
    assert_nil Post.handle_from_caption("Inspired by @someone")
    assert_nil Post.handle_from_caption("Commissioned by @someone")
  end

  test "returns nil when there is no attribution" do
    assert_nil Post.handle_from_caption("Just a nice piece of art today")
    assert_nil Post.handle_from_caption("")
    assert_nil Post.handle_from_caption(nil)
  end
end
