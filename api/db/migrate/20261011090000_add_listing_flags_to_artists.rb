class AddListingFlagsToArtists < ActiveRecord::Migration[8.0]
  def change
    # Set by the pipeline when Instagram reports the profile no longer exists
    # (renamed or deleted), and cleared when a later fetch finds it again.
    add_column :artists, :profile_missing_at, :datetime
    # Taken off the site by hand (the artist has died, or asked to be removed).
    # Never cleared automatically. The row stays as a tombstone so a later page
    # scrape or import cannot quietly re-create the artist.
    add_column :artists, :delisted_at,     :datetime
    add_column :artists, :delisted_reason, :string
  end
end
