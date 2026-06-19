class AddSourcesToArtists < ActiveRecord::Migration[8.0]
  def up
    # Which discovery sources surfaced this artist (provenance + corroboration).
    add_column :artists, :sources, :string, array: true, null: false, default: []
    add_index :artists, :sources, using: :gin
    # Everything we have so far came from the @blackworkers feed.
    execute "UPDATE artists SET sources = ARRAY['blackworkers']"
  end

  def down
    remove_column :artists, :sources
  end
end
