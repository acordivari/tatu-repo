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
  # Geometry, not amount, is what separates a burned-in overlay from lettering
  # tattooed on skin. These cases are measured from real production images.
  test "text_overlay flags wide thin caption lines" do
    p = Post.create!(ig_shortcode: "ovl1", ocr_at: Time.current,
                     ocr_text: "YOU RECEIVED 1.3M LIKES IN 2020!",
                     ocr_text_area: 0.043, ocr_lines: 4,
                     ocr_mean_height: 0.023, ocr_elongation: 12.2)

    assert_includes Post.text_overlay, p
  end

  test "text_overlay spares a lettering tattoo despite more text area" do
    # Higher area than the screenshot above, but tall chunky letters.
    p = Post.create!(ig_shortcode: "ltr1", ocr_at: Time.current,
                     ocr_text: "THERE BETTER BE DOGS",
                     ocr_text_area: 0.093, ocr_lines: 4,
                     ocr_mean_height: 0.122, ocr_elongation: 1.5)

    assert_not_includes Post.text_overlay, p
  end

  test "text_overlay ignores short OCR noise on linework" do
    p = Post.create!(ig_shortcode: "noise1", ocr_at: Time.current,
                     ocr_text: "**", ocr_text_area: 0.165, ocr_lines: 1,
                     ocr_mean_height: 0.369, ocr_elongation: 1.2)

    assert_not_includes Post.text_overlay, p
  end

  test "text_overlay only considers scanned posts" do
    p = Post.create!(ig_shortcode: "unscanned1", ocr_text: "YOU RECEIVED 1.3M LIKES",
                     ocr_mean_height: 0.023, ocr_elongation: 12.2)

    assert_not_includes Post.text_overlay, p
  end

  test "needs_ocr skips posts already scanned" do
    Post.create!(ig_shortcode: "scanned1", ocr_at: Time.current)

    assert_not_includes Post.needs_ocr.map(&:ig_shortcode), "scanned1"
  end
end
