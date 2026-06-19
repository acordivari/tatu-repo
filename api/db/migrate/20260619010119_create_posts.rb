class CreatePosts < ActiveRecord::Migration[8.0]
  def change
    create_table :posts do |t|
      t.string :ig_shortcode
      t.text :caption
      t.string :source_url
      t.string :image_url
      t.datetime :posted_at
      # Nullable: a post is ingested even if its caption has no parseable
      # "tattoo by @handle" attribution; it can be linked later.
      t.references :artist, null: true, foreign_key: true

      t.timestamps
    end
    add_index :posts, :ig_shortcode, unique: true
    add_index :posts, :posted_at
  end
end
