require "test_helper"

# Guards Google Places false matches (a same-named studio on another continent,
# or a supplier brand). Real failures from calibration: strangelove.la -> Houston
# (distance), killerinktattoo -> NERO (name).
class ShopPlaceVerifierTest < ActiveSupport::TestCase
  # Minimal stand-in for GooglePlacesResolver::Place (verifier only reads these).
  Place = Struct.new(:name, :latitude, :longitude, keyword_init: true)

  def setup
    @shop = Shop.create!(handle: "blackveiltattoo")
    # A located member near the real shop (London) to anchor the distance check.
    @hint = Artist.create!(handle: "member", latitude: 51.5074, longitude: -0.1278)
  end

  test "accepts a name-matching business near the hint" do
    place = Place.new(name: "Black Veil Tattoo Studio", latitude: 51.51, longitude: -0.12)
    assert ShopPlaceVerifier.new(@shop, place, @hint).accept?
  end

  test "rejects a business whose name shares nothing with the handle" do
    place = Place.new(name: "NERO Tattoo Atelier", latitude: 51.51, longitude: -0.12)
    assert_not ShopPlaceVerifier.new(@shop, place, @hint).accept?
  end

  test "rejects a name match that is implausibly far from the hint" do
    # Same name, but in Houston (~7,800 km from the London member).
    place = Place.new(name: "Black Veil Tattoo", latitude: 29.7604, longitude: -95.3698)
    assert_not ShopPlaceVerifier.new(@shop, place, @hint).accept?
  end

  test "accepts a name match when there is no location hint to contradict it" do
    unlocated = Artist.create!(handle: "nolocation")
    place = Place.new(name: "Black Veil Tattoo", latitude: 1.0, longitude: 1.0)
    assert ShopPlaceVerifier.new(@shop, place, unlocated).accept?
  end

  test "rejects a nil place" do
    assert_not ShopPlaceVerifier.new(@shop, nil, @hint).accept?
  end
end
