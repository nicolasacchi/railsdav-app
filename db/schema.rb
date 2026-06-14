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

ActiveRecord::Schema[8.1].define(version: 2026_05_10_000001) do
  create_table "addressbook_shares", force: :cascade do |t|
    t.integer "addressbook_id", null: false
    t.datetime "created_at", null: false
    t.datetime "invitation_expires_at"
    t.datetime "invitation_sent_at"
    t.string "invitation_token"
    t.string "invited_email"
    t.string "permission", default: "read", null: false
    t.string "status", default: "accepted", null: false
    t.string "token"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["addressbook_id", "user_id"], name: "idx_shares_addressbook_user", unique: true
    t.index ["addressbook_id"], name: "index_addressbook_shares_on_addressbook_id"
    t.index ["invitation_token"], name: "index_addressbook_shares_on_invitation_token", unique: true
    t.index ["invited_email"], name: "index_addressbook_shares_on_invited_email"
    t.index ["token"], name: "index_addressbook_shares_on_token", unique: true
    t.index ["user_id"], name: "index_addressbook_shares_on_user_id"
  end

  create_table "addressbooks", force: :cascade do |t|
    t.string "call_screening_policy", default: "screen", null: false
    t.datetime "created_at", null: false
    t.integer "ctag", default: 0, null: false
    t.string "dav_password_digest"
    t.text "description"
    t.string "displayname", default: "Contacts", null: false
    t.boolean "encryption_enabled", default: false, null: false
    t.string "encryption_version"
    t.integer "sync_token", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "uri", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "uri"], name: "index_addressbooks_on_user_id_and_uri", unique: true
    t.index ["user_id"], name: "index_addressbooks_on_user_id"
  end

  create_table "contact_group_memberships", force: :cascade do |t|
    t.integer "contact_group_id", null: false
    t.integer "contact_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["contact_group_id"], name: "index_contact_group_memberships_on_contact_group_id"
    t.index ["contact_id", "contact_group_id"], name: "idx_on_contact_id_contact_group_id_ed265d6f3a", unique: true
    t.index ["contact_id"], name: "index_contact_group_memberships_on_contact_id"
  end

  create_table "contact_groups", force: :cascade do |t|
    t.integer "addressbook_id", null: false
    t.datetime "created_at", null: false
    t.integer "group_contact_id"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["addressbook_id", "name"], name: "index_contact_groups_on_addressbook_id_and_name", unique: true
    t.index ["addressbook_id"], name: "index_contact_groups_on_addressbook_id"
    t.index ["group_contact_id"], name: "index_contact_groups_on_group_contact_id"
  end

  create_table "contact_phone_numbers", force: :cascade do |t|
    t.integer "contact_id", null: false
    t.datetime "created_at", null: false
    t.string "e164", null: false
    t.string "phone_type"
    t.string "raw"
    t.datetime "updated_at", null: false
    t.index ["contact_id", "e164"], name: "index_contact_phone_numbers_on_contact_id_and_e164", unique: true
    t.index ["contact_id"], name: "index_contact_phone_numbers_on_contact_id"
    t.index ["e164"], name: "index_contact_phone_numbers_on_e164"
  end

  create_table "contacts", force: :cascade do |t|
    t.integer "addressbook_id", null: false
    t.string "cached_display_name", default: ""
    t.string "call_screening_policy"
    t.datetime "created_at", null: false
    t.boolean "encrypted", default: false, null: false
    t.string "encryption_version"
    t.string "etag", null: false
    t.string "kind", default: "individual", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.string "uri", null: false
    t.text "vcard_data", null: false
    t.index ["addressbook_id", "cached_display_name"], name: "index_contacts_on_addressbook_id_and_cached_display_name"
    t.index ["addressbook_id", "encrypted"], name: "index_contacts_on_addressbook_id_and_encrypted"
    t.index ["addressbook_id", "uid"], name: "index_contacts_on_addressbook_id_and_uid", unique: true
    t.index ["addressbook_id", "uri"], name: "index_contacts_on_addressbook_id_and_uri", unique: true
    t.index ["addressbook_id"], name: "index_contacts_on_addressbook_id"
  end

  create_table "spam_numbers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "first_reported_at", null: false
    t.datetime "last_seen_at", null: false
    t.text "notes"
    t.string "phone", null: false
    t.integer "report_count", default: 1, null: false
    t.string "source", null: false
    t.string "submitted_by_username"
    t.datetime "updated_at", null: false
    t.index ["last_seen_at"], name: "index_spam_numbers_on_last_seen_at"
    t.index ["phone"], name: "index_spam_numbers_on_phone", unique: true
  end

  create_table "sync_changes", force: :cascade do |t|
    t.integer "addressbook_id", null: false
    t.string "change_type", null: false
    t.datetime "created_at", null: false
    t.integer "sync_token", null: false
    t.datetime "updated_at", null: false
    t.string "uri", null: false
    t.index ["addressbook_id", "sync_token"], name: "index_sync_changes_on_addressbook_id_and_sync_token"
    t.index ["addressbook_id"], name: "index_sync_changes_on_addressbook_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "addressbook_shares", "addressbooks"
  add_foreign_key "addressbook_shares", "users"
  add_foreign_key "addressbooks", "users"
  add_foreign_key "contact_group_memberships", "contact_groups"
  add_foreign_key "contact_group_memberships", "contacts"
  add_foreign_key "contact_groups", "addressbooks"
  add_foreign_key "contact_groups", "contacts", column: "group_contact_id"
  add_foreign_key "contact_phone_numbers", "contacts", on_delete: :cascade
  add_foreign_key "contacts", "addressbooks"
  add_foreign_key "sync_changes", "addressbooks"
end
