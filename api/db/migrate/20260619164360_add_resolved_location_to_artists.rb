class AddResolvedLocationToArtists < ActiveRecord::Migration[8.0]
  def change
    add_column :artists, :location_source, :string
    add_column :artists, :location_confidence, :float
    add_column :artists, :location_confirmed_at, :datetime
    # Nullable: only set once a shop becomes the artist's resolved location.
    add_reference :artists, :primary_shop, null: true, foreign_key: { to_table: :shops }
  end
end
