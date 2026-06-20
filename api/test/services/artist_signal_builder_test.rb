require "test_helper"

# Regression guard for the "name-as-city" bug: @caspermugridge was pinned to
# Casper, Wyoming because the LLM read "Casper" out of the person's own
# name/email. The builder must reject a city that is only a fragment of the
# artist's handle/name, while keeping genuinely-stated cities.
class ArtistSignalBuilderTest < ActiveSupport::TestCase
  def extraction(city:, region: nil, country: nil)
    LocationExtractor::Extraction.new(city: city, region: region, country: country, shop: nil, role: nil)
  end

  test "rejects a city that is a fragment of the artist's own name" do
    artist = Artist.create!(
      handle: "caspermugridge",
      name: "Edmonton Tattoo YEG",
      bio: "tattoo artist @SHOWDOWN TATTOO ( 10727 124st ) Caspermugridge@hotmail.com"
    )
    ArtistSignalBuilder.new(artist, extraction(city: "Casper")).call

    assert_empty artist.location_signals.where(source_type: "artist_bio"),
                 "name-derived city should not create a bio location signal"
  end

  test "keeps a genuinely-stated city" do
    artist = Artist.create!(handle: "joeblow", name: "Joe | Berlin Tattoo", bio: "Berlin based blackwork")
    ArtistSignalBuilder.new(artist, extraction(city: "Berlin", country: "Germany")).call

    sig = artist.location_signals.find_by(source_type: "artist_bio")
    assert_not_nil sig
    assert_equal "Berlin", sig.city
  end

  test "keeps a city that also appears standalone in the name (not name-derived)" do
    # "casper" is in the handle, but "Casper" is also a standalone word in the
    # name, so it's a legitimately-stated place, not a name fragment.
    artist = Artist.create!(handle: "caspershop", name: "Casper Wyoming Tattoo", bio: "")
    ArtistSignalBuilder.new(artist, extraction(city: "Casper", region: "Wyoming")).call

    assert_not_nil artist.location_signals.find_by(source_type: "artist_bio")
  end

  test "still records region/country even if the city is rejected" do
    # "florence" is glued inside the handle and stated nowhere as a standalone
    # word, so the city is dropped but the country survives.
    artist = Artist.create!(handle: "florenceink", name: "Ink Lab", bio: "custom work")
    ArtistSignalBuilder.new(artist, extraction(city: "Florence", country: "Italy")).call

    sig = artist.location_signals.find_by(source_type: "artist_bio")
    assert_not_nil sig
    assert_nil sig.city, "name-derived city dropped"
    assert_equal "Italy", sig.country
  end
end
