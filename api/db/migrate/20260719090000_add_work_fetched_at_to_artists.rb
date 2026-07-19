class AddWorkFetchedAtToArtists < ActiveRecord::Migration[8.0]
  def change
    # When we last scraped this artist's own gallery for work images —
    # stamped even when the account yields nothing (dead/private/renamed
    # handles), so backfill runs don't re-query the same duds forever.
    add_column :artists, :work_fetched_at, :datetime
  end
end
