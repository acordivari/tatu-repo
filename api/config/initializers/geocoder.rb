Geocoder.configure(
  # Nominatim (OpenStreetMap) is free and needs no API key — fine for a
  # batch-geocoded directory. Swap to :google/:mapbox for higher volume.
  lookup: :nominatim,
  timeout: 10,
  units: :km,
  # Nominatim's usage policy requires a descriptive User-Agent / referer.
  http_headers: { "User-Agent" => "BlackworkersDirectory/1.0 (contact: admin@blackworkers.example)" },
  cache: Rails.cache,
  always_raise: :all
)
