# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_06_20_211246) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "artist_candidates", force: :cascade do |t|
    t.string "handle", null: false
    t.string "source"
    t.string "full_name"
    t.text "bio"
    t.string "category"
    t.integer "followers_count"
    t.integer "posts_count"
    t.string "classification"
    t.float "confidence"
    t.text "reason"
    t.string "status"
    t.bigint "artist_id"
    t.datetime "scraped_at"
    t.datetime "classified_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["artist_id"], name: "index_artist_candidates_on_artist_id"
    t.index ["handle"], name: "index_artist_candidates_on_handle", unique: true
    t.index ["status"], name: "index_artist_candidates_on_status"
  end

  create_table "artists", force: :cascade do |t|
    t.string "handle", null: false
    t.string "name"
    t.text "bio"
    t.string "shop_name"
    t.string "website"
    t.string "location_raw"
    t.string "city"
    t.string "region"
    t.string "country"
    t.float "latitude"
    t.float "longitude"
    t.integer "posts_count", default: 0, null: false
    t.datetime "enriched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "location_extracted_at"
    t.string "location_source"
    t.float "location_confidence"
    t.datetime "location_confirmed_at"
    t.bigint "primary_shop_id"
    t.string "sources", default: [], null: false, array: true
    t.string "region_canonical"
    t.index ["country", "region_canonical"], name: "index_artists_on_country_and_region_canonical"
    t.index ["country"], name: "index_artists_on_country"
    t.index ["handle"], name: "index_artists_on_handle", unique: true
    t.index ["latitude", "longitude"], name: "index_artists_on_latitude_and_longitude"
    t.index ["primary_shop_id"], name: "index_artists_on_primary_shop_id"
    t.index ["region"], name: "index_artists_on_region"
    t.index ["sources"], name: "index_artists_on_sources", using: :gin
  end

  create_table "location_signals", force: :cascade do |t|
    t.bigint "artist_id", null: false
    t.bigint "shop_id"
    t.string "source_type", null: false
    t.string "source_account"
    t.string "city"
    t.string "region"
    t.string "country"
    t.float "confidence"
    t.datetime "observed_at"
    t.string "raw"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["artist_id", "source_type"], name: "index_location_signals_on_artist_id_and_source_type"
    t.index ["artist_id"], name: "index_location_signals_on_artist_id"
    t.index ["shop_id"], name: "index_location_signals_on_shop_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.bigint "artist_id", null: false
    t.bigint "shop_id", null: false
    t.string "role"
    t.string "source"
    t.boolean "mutual"
    t.float "confidence"
    t.boolean "current"
    t.datetime "first_seen_at"
    t.datetime "last_confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["artist_id", "shop_id"], name: "index_memberships_on_artist_id_and_shop_id", unique: true
    t.index ["artist_id"], name: "index_memberships_on_artist_id"
    t.index ["current"], name: "index_memberships_on_current"
    t.index ["shop_id"], name: "index_memberships_on_shop_id"
  end

  create_table "posts", force: :cascade do |t|
    t.string "ig_shortcode"
    t.text "caption"
    t.string "source_url"
    t.string "image_url"
    t.datetime "posted_at"
    t.bigint "artist_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["artist_id"], name: "index_posts_on_artist_id"
    t.index ["ig_shortcode"], name: "index_posts_on_ig_shortcode", unique: true
    t.index ["posted_at"], name: "index_posts_on_posted_at"
  end

  create_table "shops", force: :cascade do |t|
    t.string "handle", null: false
    t.string "name"
    t.boolean "is_business"
    t.text "bio"
    t.string "address_raw"
    t.string "city"
    t.string "region"
    t.string "country"
    t.float "latitude"
    t.float "longitude"
    t.datetime "profile_scraped_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "google_place_id"
    t.string "business_status"
    t.index ["handle"], name: "index_shops_on_handle", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "artist_candidates", "artists"
  add_foreign_key "artists", "shops", column: "primary_shop_id"
  add_foreign_key "location_signals", "artists"
  add_foreign_key "location_signals", "shops"
  add_foreign_key "memberships", "artists"
  add_foreign_key "memberships", "shops"
  add_foreign_key "posts", "artists"
end
