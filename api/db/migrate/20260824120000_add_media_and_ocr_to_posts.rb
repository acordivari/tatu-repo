class AddMediaAndOcrToPosts < ActiveRecord::Migration[8.0]
  def change
    # Provenance straight from the Apify item, stored verbatim rather than
    # collapsed into a derived flag: "Video" + productType "clips" is a Reel,
    # but plenty of Reels are genuine tattoo work, so the classifier needs the
    # raw fields as features rather than a lossy is_reel boolean.
    add_column :posts, :media_type,   :string   # Image | Video | Sidecar
    add_column :posts, :product_type, :string   # clips | feed | igtv

    # OCR evidence. text_area is the fraction of the frame covered by detected
    # text: burned-in Reel/promo overlays run ~0.05-0.15, while incidental
    # captions in real work photos sit near 0.006. Storing the measurement
    # rather than a verdict keeps the threshold tunable without re-running OCR.
    add_column :posts, :ocr_text,      :text
    add_column :posts, :ocr_text_area, :float
    add_column :posts, :ocr_at,        :datetime

    # Geometry of the detected text. Area alone cannot tell a burned-in caption
    # from lettering tattooed on skin — both are "text". What separates them is
    # shape: rendered UI and caption text is many short, WIDE lines (high
    # elongation, small mean height), while tattooed script is a few TALL,
    # chunky ones. Measured on production images, overlays sit at elongation
    # 10-12 / height 0.02-0.04 and lettering tattoos at elongation 1.1-1.7 /
    # height 0.10-0.28.
    add_column :posts, :ocr_lines,       :integer
    add_column :posts, :ocr_mean_height, :float
    add_column :posts, :ocr_elongation,  :float

    add_index :posts, :ocr_at
    add_index :posts, :media_type
  end
end
