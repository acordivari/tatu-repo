# Idempotent dev/demo seed.
#
# 1. Ingests the sample posts fixture (exercises the caption-attribution
#    pipeline that maps "tattoo by @handle" -> Artist).
# 2. Assigns known coordinates to the sample artists so the map and region
#    filters work out-of-the-box WITHOUT external geocoding/Apify calls.
#
# Run with: bin/rails db:seed
# For real data, use: rake instagram:scrape[1000]  (needs APIFY_TOKEN)

fixture = Rails.root.join("db/fixtures/sample_posts.json")
if File.exist?(fixture)
  items = JSON.parse(File.read(fixture))
  result = InstagramIngestor.new(items, attach_images: false).call
  puts "Seeded posts: +#{result.posts_created}, artists: +#{result.artists_created}"
end

# Hand-placed demo locations (lat/lng) so the geographic features are usable
# offline. Real artists get these from EnrichArtistJob -> geocoder.
DEMO_LOCATIONS = {
  "gerfer_tattoo" => { city: "London",  region: "England",  country: "United Kingdom", latitude: 51.5074, longitude: -0.1278 },
  "frankcarrilho" => { city: "Lisbon",  region: "Lisbon",   country: "Portugal",       latitude: 38.7223, longitude: -9.1393 },
  "claudiomanto"  => { city: "Berlin",  region: "Berlin",   country: "Germany",        latitude: 52.5200, longitude: 13.4050 }
}.freeze

DEMO_LOCATIONS.each do |handle, attrs|
  artist = Artist.find_by(handle: handle)
  next unless artist

  # Skip the geocode callback — we're supplying coordinates directly.
  artist.update_columns(attrs.merge(updated_at: Time.current))
end
puts "Placed #{DEMO_LOCATIONS.size} demo artists on the map."
