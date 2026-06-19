Geocoder.configure(
  # Nominatim (OpenStreetMap) is free and needs no API key — fine for a
  # batch-geocoded directory. Swap to :google/:mapbox for higher volume.
  lookup: :nominatim,
  timeout: 10,
  units: :km,
  # Nominatim's usage policy requires a descriptive User-Agent / referer.
  http_headers: { "User-Agent" => "BlackworkersDirectory/1.0 (contact: admin@blackworkers.example)" },
  cache: Rails.cache,
  # Don't raise on lookup errors/timeouts — a failed geocode just leaves the
  # artist unlocated rather than breaking the save or the batch.
  always_raise: []
)
