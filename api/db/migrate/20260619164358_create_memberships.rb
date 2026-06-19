class CreateMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :memberships do |t|
      t.references :artist, null: false, foreign_key: true
      t.references :shop, null: false, foreign_key: true
      t.string :role
      t.string :source
      t.boolean :mutual
      t.float :confidence
      t.boolean :current
      t.datetime :first_seen_at
      t.datetime :last_confirmed_at

      t.timestamps
    end
    # One membership row per artist↔shop pair (updated, not duplicated).
    add_index :memberships, [:artist_id, :shop_id], unique: true
    add_index :memberships, :current
  end
end
