class AddRegionCanonicalToArtists < ActiveRecord::Migration[8.0]
  def change
    # Canonical English/Latin region label (e.g. "CA"/"Califórnia" -> "California",
    # "Москва" -> "Moscow") so the region facet and filter dedupe reliably.
    # The raw `region` column is kept for provenance.
    add_column :artists, :region_canonical, :string
    add_index  :artists, [:country, :region_canonical]
  end
end
