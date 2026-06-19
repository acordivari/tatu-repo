class CreateLocationSignals < ActiveRecord::Migration[8.0]
  def change
    create_table :location_signals do |t|
      t.references :artist, null: false, foreign_key: true
      # Nullable: artist_bio / artist_business_address signals have no shop.
      t.references :shop, null: true, foreign_key: true
      t.string :source_type, null: false
      t.string :source_account
      t.string :city
      t.string :region
      t.string :country
      t.float :confidence
      t.datetime :observed_at
      t.string :raw

      t.timestamps
    end
    add_index :location_signals, [:artist_id, :source_type]
  end
end
