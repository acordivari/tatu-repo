class AddContentKindToPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :posts, :content_kind,       :string
    add_column :posts, :content_confidence, :float
    add_column :posts, :classified_at,      :datetime
    # The stamp alone is not enough to decide what still needs classifying: a
    # changed prompt or model makes every prior verdict stale, and scoping on
    # "classified_at IS NULL" would silently skip them all. Recording which
    # classifier produced a verdict lets a re-run target exactly what is out of
    # date. (Three bugs of this shape have already been fixed in this pipeline.)
    add_column :posts, :classifier_version, :string

    add_index :posts, :content_kind
    add_index :posts, :classifier_version
  end
end
