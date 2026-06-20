class AddMembershipsCountToShops < ActiveRecord::Migration[8.0]
  def change
    add_column :shops, :memberships_count, :integer, default: 0, null: false

    # Backfill existing shops, then keep it current via Membership's counter_cache.
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE shops SET memberships_count =
            (SELECT COUNT(*) FROM memberships WHERE memberships.shop_id = shops.id)
        SQL
      end
    end
  end
end
