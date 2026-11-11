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
  test "text_overlay flags a wordy multi-line caption block" do
    p = Post.create!(ig_shortcode: "ovl1", ocr_at: Time.current,
                     ocr_text: "TOP NINE 2020\nYOU RECEIVED 1.3M LIKES IN 2020!\n20.9k\n20.6k",
                     ocr_text_area: 0.043, ocr_lines: 4,
                     ocr_mean_height: 0.023, ocr_elongation: 12.2)

    assert_includes Post.text_overlay, p
  end

  test "text_overlay spares a watermark on a real work photo" do
    # Overlay-shaped text, but one short line: an artist signature, not junk.
    p = Post.create!(ig_shortcode: "wm1", ocr_at: Time.current,
                     ocr_text: "@familyinktattoo", ocr_text_area: 0.010,
                     ocr_lines: 1, ocr_mean_height: 0.028, ocr_elongation: 7.4)

    assert_not_includes Post.text_overlay, p
  end

  test "text_overlay spares a short caption on a healed-tattoo photo" do
    p = Post.create!(ig_shortcode: "cap1", ocr_at: Time.current,
                     ocr_text: "Over 3yrs healed", ocr_text_area: 0.012,
                     ocr_lines: 2, ocr_mean_height: 0.030, ocr_elongation: 8.1)

    assert_not_includes Post.text_overlay, p
  end

  test "overlay_shape? matches the scope for unpersisted OCR output" do
    assert Post.overlay_shape?(elongation: 12.2, mean_height: 0.023, lines: 4,
                               text: "TOP NINE 2020 YOU RECEIVED 1.3M LIKES IN 2020!")
    assert_not Post.overlay_shape?(elongation: 7.4, mean_height: 0.028, lines: 1,
                                   text: "@familyinktattoo")
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
  test "classifier_stale catches both unclassified and older-classifier rows" do
    fresh = Post.create!(ig_shortcode: "cls_fresh", classified_at: Time.current,
                         content_kind: "work", classifier_version: "v2")
    old   = Post.create!(ig_shortcode: "cls_old", classified_at: Time.current,
                         content_kind: "work", classifier_version: "v1")
    never = Post.create!(ig_shortcode: "cls_never")

    stale = Post.classifier_stale("v2")
    assert_not_includes stale, fresh
    assert_includes stale, old
    assert_includes stale, never
  end

  test "not_work covers OCR overlays and non-work verdicts, and spares work" do
    overlay = Post.create!(ig_shortcode: "nw_overlay", ocr_at: Time.current,
                           ocr_text: "BOOKING OPEN APRIL - JUNE email me to book",
                           ocr_lines: 4, ocr_mean_height: 0.03, ocr_elongation: 12.0)
    person  = Post.create!(ig_shortcode: "nw_person", classified_at: Time.current,
                           content_kind: "person")
    work    = Post.create!(ig_shortcode: "nw_work", classified_at: Time.current,
                           content_kind: "work")
    lettering = Post.create!(ig_shortcode: "nw_lettering", ocr_at: Time.current,
                             ocr_text: "THERE BETTER BE DOGS", ocr_lines: 4,
                             ocr_mean_height: 0.122, ocr_elongation: 1.5)

    hidden = Post.not_work
    assert_includes hidden, overlay
    assert_includes hidden, person
    assert_not_includes hidden, work
    assert_not_includes hidden, lettering
  end

  test "shown is the complement of not_work, and keeps unjudged posts visible" do
    overlay = Post.create!(ig_shortcode: "sh_overlay", ocr_at: Time.current,
                           ocr_text: "BOOKING OPEN APRIL - JUNE email me to book",
                           ocr_lines: 4, ocr_mean_height: 0.03, ocr_elongation: 12.0)
    promo   = Post.create!(ig_shortcode: "sh_promo", classified_at: Time.current, content_kind: "promo")
    work    = Post.create!(ig_shortcode: "sh_work", classified_at: Time.current, content_kind: "work")
    unjudged = Post.create!(ig_shortcode: "sh_unjudged")

    shown = Post.shown
    assert_not_includes shown, overlay
    assert_not_includes shown, promo
    assert_includes shown, work
    assert_includes shown, unjudged
  end

  test "a process shot is hidden, while the tattoo and the design stay" do
    process = Post.create!(ig_shortcode: "pr_process", classified_at: Time.current, content_kind: "process")
    tattoo  = Post.create!(ig_shortcode: "pr_tattoo", classified_at: Time.current, content_kind: "tattoo")
    design  = Post.create!(ig_shortcode: "pr_design", classified_at: Time.current, content_kind: "design")

    assert_includes Post.not_work, process
    assert_predicate process, :not_work?
    assert_not_includes Post.shown, process
    assert_includes Post.shown, tattoo
    assert_includes Post.shown, design
  end

  test "portfolio_order puts designs after everything else, newest first within each" do
    design_new = Post.create!(ig_shortcode: "po_design_new", content_kind: "design", posted_at: 1.day.ago)
    tattoo_old = Post.create!(ig_shortcode: "po_tattoo_old", content_kind: "tattoo", posted_at: 90.days.ago)
    unjudged   = Post.create!(ig_shortcode: "po_unjudged", posted_at: 5.days.ago)
    legacy     = Post.create!(ig_shortcode: "po_legacy", content_kind: "work", posted_at: 30.days.ago)
    design_old = Post.create!(ig_shortcode: "po_design_old", content_kind: "design", posted_at: 60.days.ago)

    ordered = Post.where(id: [ design_new, tattoo_old, unjudged, legacy, design_old ]).portfolio_order

    assert_equal [ unjudged, legacy, tattoo_old, design_new, design_old ], ordered.to_a
  end

  test "not_work? agrees with the not_work scope row by row" do
    rows = [
      Post.create!(ig_shortcode: "nwq_overlay", ocr_at: Time.current,
                   ocr_text: "TOP NINE 2020\nYOU RECEIVED 1.3M LIKES IN 2020!\n20.9k\n20.6k",
                   ocr_lines: 4, ocr_mean_height: 0.023, ocr_elongation: 12.2),
      Post.create!(ig_shortcode: "nwq_watermark", ocr_at: Time.current, ocr_text: "@familyinktattoo",
                   ocr_lines: 1, ocr_mean_height: 0.028, ocr_elongation: 7.4),
      Post.create!(ig_shortcode: "nwq_unscanned", ocr_text: "YOU RECEIVED 1.3M LIKES IN 2020! 20.9k 20.6k",
                   ocr_lines: 4, ocr_mean_height: 0.023, ocr_elongation: 12.2),
      Post.create!(ig_shortcode: "nwq_person", content_kind: "person"),
      Post.create!(ig_shortcode: "nwq_other", content_kind: "other"),
      Post.create!(ig_shortcode: "nwq_process", content_kind: "process"),
      Post.create!(ig_shortcode: "nwq_tattoo", content_kind: "tattoo"),
      Post.create!(ig_shortcode: "nwq_work", content_kind: "work"),
      Post.create!(ig_shortcode: "nwq_bare")
    ]

    hidden = Post.not_work.pluck(:id)
    rows.each do |post|
      assert_equal hidden.include?(post.id), post.not_work?, "disagreement on #{post.ig_shortcode}"
    end
  end

  test "credited_to? recognises a curated credit, not the artist's own caption" do
    artist = Artist.create!(handle: "credited")
    assert Post.new(caption: "Tattoo by @credited #blackworkers").credited_to?(artist)
    assert_not Post.new(caption: "Books open for November!").credited_to?(artist)
    assert_not Post.new(caption: "Tattoo by @someoneelse").credited_to?(artist)
  end
end
