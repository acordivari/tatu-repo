class AddLocationExtractedAtToArtists < ActiveRecord::Migration[8.0]
  def change
    add_column :artists, :location_extracted_at, :datetime
  end
end
