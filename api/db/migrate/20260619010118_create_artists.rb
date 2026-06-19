class CreateArtists < ActiveRecord::Migration[8.0]
  def change
    create_table :artists do |t|
      t.string :handle, null: false
      t.string :name
      t.text :bio
      t.string :shop_name
      t.string :website
      t.string :location_raw
      t.string :city
      t.string :region
      t.string :country
      t.float :latitude
      t.float :longitude
      t.integer :posts_count, null: false, default: 0
      t.datetime :enriched_at

      t.timestamps
    end
    add_index :artists, :handle, unique: true
    add_index :artists, :country
    add_index :artists, :region
    # Geo lookups for the map (radius / bounding-box queries)
    add_index :artists, [:latitude, :longitude]
  end
end
