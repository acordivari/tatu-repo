# Computes an artist's effective location from their evidence ledger: take the
# highest-confidence signal, geocode it (only when it actually changed, to
# avoid redundant Nominatim calls), and write the resolved location +
# provenance back onto the artist. Re-runnable as new evidence (shop Google
# Places records, other aggregators) arrives.
class LocationResolver
  Result = Struct.new(:status, keyword_init: true) # :located, :unchanged, :unlocatable, :cleared

  def initialize(artist)
    @artist = artist
  end

  def call
    signal = @artist.location_signals.ranked.first
    return clear if signal.nil? || (signal.query.blank? && signal.shop&.latitude.blank?)

    # A shop-backed signal already carries exact coordinates (e.g. Google
    # Places) — use them directly instead of re-geocoding.
    return apply_shop_location(signal) if signal.shop&.latitude.present?

    if up_to_date?(signal)
      backfill_provenance(signal)
      return Result.new(status: :unchanged)
    end

    geo = NominatimGeocoder.lookup(signal.query)
    return write_without_coords(signal) if geo.nil?

    region = signal.region.presence || geo.region
    @artist.update_columns(
      city:      signal.city.presence    || geo.city,
      region:    region,
      region_canonical: canonical_for(region),
      country:   signal.country.presence || geo.country,
      latitude:  geo.latitude,
      longitude: geo.longitude,
      location_source:       signal.source_type,
      location_confidence:   signal.confidence,
      location_confirmed_at: signal.observed_at,
      primary_shop_id:       signal.shop_id,
      updated_at: Time.current
    )
    Result.new(status: :located)
  end

  private

  # Keep the canonical region label only while the raw region is unchanged;
  # when the region moves, invalidate it so the next canonicalize pass refills
  # it (and the region facet doesn't show a stale label for the new place).
  def canonical_for(new_region)
    new_region == @artist.region ? @artist.region_canonical : nil
  end

  # Inherit the shop's verified coordinates + address (no geocoding needed).
  def apply_shop_location(signal)
    shop = signal.shop
    region = signal.region.presence || shop.region
    @artist.update_columns(
      city:      signal.city.presence    || shop.city,
      region:    region,
      region_canonical: canonical_for(region),
      country:   signal.country.presence || shop.country,
      latitude:  shop.latitude,
      longitude: shop.longitude,
      location_source:       signal.source_type,
      location_confidence:   signal.confidence,
      location_confirmed_at: signal.observed_at,
      primary_shop_id:       shop.id,
      updated_at: Time.current
    )
    Result.new(status: :located)
  end

  # Already geocoded and the winning signal points at the same place — only the
  # provenance columns (new) may need backfilling; skip the network call.
  def up_to_date?(signal)
    @artist.latitude.present? && signal.query == current_query
  end

  def current_query
    [@artist.city, @artist.region, @artist.country].compact_blank.join(", ").presence
  end

  def backfill_provenance(signal)
    @artist.update_columns(
      location_source:       signal.source_type,
      location_confidence:   signal.confidence,
      location_confirmed_at: signal.observed_at,
      primary_shop_id:       signal.shop_id,
      updated_at: Time.current
    )
  end

  # Best signal exists but didn't geocode — keep provenance, drop stale coords.
  def write_without_coords(signal)
    @artist.update_columns(
      latitude: nil, longitude: nil,
      location_source: signal.source_type, location_confidence: signal.confidence,
      location_confirmed_at: signal.observed_at, primary_shop_id: signal.shop_id,
      updated_at: Time.current
    )
    Result.new(status: :unlocatable)
  end

  # No usable evidence remains — drop the resolved location entirely (coords AND
  # the city/region/country it produced), not just the provenance. Otherwise a
  # pin survives after the signal that justified it is gone.
  def clear
    @artist.update_columns(
      city: nil, region: nil, region_canonical: nil, country: nil,
      latitude: nil, longitude: nil,
      location_source: nil, location_confidence: nil, location_confirmed_at: nil,
      primary_shop_id: nil, updated_at: Time.current
    )
    Result.new(status: :cleared)
  end
end
