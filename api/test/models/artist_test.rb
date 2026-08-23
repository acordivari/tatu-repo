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

  test "search for an exact place name returns only artists located there" do
    Artist.create!(handle: "atx1", city: "Austin", region: "Texas", country: "United States")
    # Named Austin, lives in Dover — must NOT match a city search for Austin.
    Artist.create!(handle: "austincpratttattoo", name: "Austin C Pratt-Fusari",
                   city: "Dover", region: "Pennsylvania", country: "United States")

    assert_equal ["atx1"], Artist.search("Austin").pluck(:handle)
    assert_equal ["atx1"], Artist.search("  austin ").pluck(:handle)
  end

  test "search place match works on canonical region and country" do
    Artist.create!(handle: "c1", region: "CA", region_canonical: "California", country: "United States")
    assert_equal ["c1"], Artist.search("California").pluck(:handle)
    assert_equal ["c1"], Artist.search("United States").pluck(:handle)
  end

  test "search falls back to name/handle matching when the query is not a place" do
    Artist.create!(handle: "austincpratttattoo", name: "Austin C Pratt-Fusari",
                   city: "Dover", region: "Pennsylvania", country: "United States")

    # No artist lives in a place called "Austin", so the broad match applies
    # and he is findable by name, partial name, or handle.
    assert_equal ["austincpratttattoo"], Artist.search("Austin C Pratt").pluck(:handle)
    assert_equal ["austincpratttattoo"], Artist.search("austincpratt").pluck(:handle)
    assert_equal ["austincpratttattoo"], Artist.search("Austin").pluck(:handle)
  end

  test "search place precedence respects chained scopes" do
    Artist.create!(handle: "atx1", city: "Austin", region: "Texas", country: "United States")
    Artist.create!(handle: "aus1", city: "Austin", region: nil, country: "Australia")

    handles = Artist.in_country("United States").search("Austin").pluck(:handle)
    assert_equal ["atx1"], handles
  end

  test "needs_location_extraction skips artists without a bio" do
    Artist.create!(handle: "nobio", bio: nil)
    Artist.create!(handle: "blankbio", bio: "")

    assert_empty Artist.needs_location_extraction.pluck(:handle)
  end

  test "needs_location_extraction includes a bio that was never extracted" do
    Artist.create!(handle: "fresh", bio: "Berlin", location_extracted_at: nil)

    assert_equal ["fresh"], Artist.needs_location_extraction.pluck(:handle)
  end

  test "needs_location_extraction re-includes a bio refreshed after its last extraction" do
    # Re-enriching replaces the bio but leaves the older extraction stamp, so
    # the new bio would otherwise never be looked at again.
    Artist.create!(handle: "stale", bio: "Now in Lisbon",
                   location_extracted_at: 2.days.ago, enriched_at: 1.hour.ago)

    assert_equal ["stale"], Artist.needs_location_extraction.pluck(:handle)
  end

  test "needs_location_extraction excludes a bio already extracted after enrichment" do
    Artist.create!(handle: "done", bio: "Lisbon",
                   location_extracted_at: 1.hour.ago, enriched_at: 2.days.ago)

    assert_empty Artist.needs_location_extraction.pluck(:handle)
  end

  test "needs_location_extraction excludes an extracted artist that was never enriched" do
    # enriched_at NULL makes the comparison NULL, so the stamp alone decides.
    Artist.create!(handle: "candidate", bio: "Oslo",
                   location_extracted_at: 1.hour.ago, enriched_at: nil)

    assert_empty Artist.needs_location_extraction.pluck(:handle)
  end
end
