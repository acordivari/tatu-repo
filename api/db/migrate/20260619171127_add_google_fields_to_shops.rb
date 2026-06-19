class AddGoogleFieldsToShops < ActiveRecord::Migration[8.0]
  def change
    add_column :shops, :google_place_id, :string
    add_column :shops, :business_status, :string
  end
end
