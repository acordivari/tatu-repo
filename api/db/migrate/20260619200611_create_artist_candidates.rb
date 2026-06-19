class CreateArtistCandidates < ActiveRecord::Migration[8.0]
  def change
    create_table :artist_candidates do |t|
      t.string :handle, null: false
      t.string :source
      t.string :full_name
      t.text :bio
      t.string :category
      t.integer :followers_count
      t.integer :posts_count
      t.string :classification
      t.float :confidence
      t.text :reason
      t.string :status
      # Set only once the candidate is approved and becomes an Artist.
      t.references :artist, null: true, foreign_key: true
      t.datetime :scraped_at
      t.datetime :classified_at

      t.timestamps
    end
    add_index :artist_candidates, :handle, unique: true
    add_index :artist_candidates, :status
  end
end
