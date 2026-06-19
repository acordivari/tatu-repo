class CreateShops < ActiveRecord::Migration[8.0]
  def change
    create_table :shops do |t|
      t.string :handle, null: false
      t.string :name
      t.boolean :is_business
      t.text :bio
      t.string :address_raw
      t.string :city
      t.string :region
      t.string :country
      t.float :latitude
      t.float :longitude
      t.datetime :profile_scraped_at

      t.timestamps
    end
    add_index :shops, :handle, unique: true
  end
end
