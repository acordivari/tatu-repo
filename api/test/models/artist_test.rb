require "test_helper"

class ArtistTest < ActiveSupport::TestCase
  test "normalize_handle strips @, trims, downcases; blank -> nil" do
    assert_equal "foo",     Artist.normalize_handle("@Foo")
    assert_equal "foo.bar", Artist.normalize_handle("  @Foo.Bar ")
    assert_nil Artist.normalize_handle("   ")
    assert_nil Artist.normalize_handle(nil)
  end

  test "handle is normalized on validation" do
    a = Artist.create!(handle: "@MixedCase")
    assert_equal "mixedcase", a.handle
  end

  test "in_region matches on the canonical label, merging raw variants" do
    # Two artists in California, one tagged "California", one the raw "CA" —
    # both canonicalized to "California".
    Artist.create!(handle: "a1", country: "United States", region: "California", region_canonical: "California")
    Artist.create!(handle: "a2", country: "United States", region: "CA",         region_canonical: "California")

    assert_equal %w[a1 a2].sort, Artist.in_region("California").pluck(:handle).sort
    # The raw variant no longer matches on its own — canonical wins.
    assert_empty Artist.in_region("CA")
  end

  test "in_region falls back to raw region when no canonical is set" do
    Artist.create!(handle: "b1", country: "Poland", region: "Mazowieckie", region_canonical: nil)
    assert_equal ["b1"], Artist.in_region("Mazowieckie").pluck(:handle)
  end
end
