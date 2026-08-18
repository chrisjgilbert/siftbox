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

ActiveRecord::Schema[8.1].define(version: 2026_08_15_134702) do
  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "message_checksum", null: false
    t.string "message_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "edition_citations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "edition_story_id", null: false
    t.integer "newsletter_id", null: false
    t.datetime "updated_at", null: false
    t.index ["edition_story_id", "newsletter_id"], name: "index_edition_citations_on_edition_story_id_and_newsletter_id", unique: true
    t.index ["newsletter_id"], name: "index_edition_citations_on_newsletter_id"
  end

  create_table "edition_stories", force: :cascade do |t|
    t.text "body", default: "", null: false
    t.datetime "created_at", null: false
    t.integer "edition_id", null: false
    t.string "headline", default: "", null: false
    t.integer "position", null: false
    t.string "section", null: false
    t.datetime "updated_at", null: false
    t.index ["edition_id", "position"], name: "index_edition_stories_on_edition_id_and_position", unique: true
  end

  create_table "editions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "editor_model", default: "", null: false
    t.integer "input_tokens", default: 0, null: false
    t.integer "number", null: false
    t.integer "output_tokens", default: 0, null: false
    t.string "prompt_version", default: "", null: false
    t.datetime "published_at", null: false
    t.date "published_on", null: false
    t.text "raw_response", default: "", null: false
    t.datetime "updated_at", null: false
    t.datetime "window_ended_at", null: false
    t.datetime "window_started_at", null: false
    t.index ["number"], name: "index_editions_on_number", unique: true
    t.index ["published_on"], name: "index_editions_on_published_on", unique: true
    t.index ["window_ended_at"], name: "index_editions_on_window_ended_at"
  end

  create_table "newsletters", force: :cascade do |t|
    t.text "body_html", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "dismissed_at"
    t.datetime "held_at"
    t.string "lead_image_url", default: "", null: false
    t.string "message_id", default: "", null: false
    t.datetime "received_at", null: false
    t.datetime "released_at"
    t.string "sender_email", default: "", null: false
    t.string "sender_name", default: "", null: false
    t.string "snippet", default: "", null: false
    t.string "subject", default: "", null: false
    t.datetime "updated_at", null: false
    t.index ["held_at"], name: "index_newsletters_on_held_at", where: "held_at IS NOT NULL"
    t.index ["message_id"], name: "index_newsletters_on_present_message_id", unique: true, where: "message_id <> ''"
    t.index ["received_at"], name: "index_newsletters_on_received_at"
    t.index ["released_at"], name: "index_newsletters_on_released_at", where: "released_at IS NOT NULL"
    t.index ["sender_email"], name: "index_newsletters_on_sender_email"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "waitlist_signups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_waitlist_signups_on_email", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "edition_citations", "edition_stories", on_delete: :cascade
  add_foreign_key "edition_citations", "newsletters", on_delete: :cascade
  add_foreign_key "edition_stories", "editions", on_delete: :cascade
  add_foreign_key "sessions", "users", on_delete: :cascade
end
