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

ActiveRecord::Schema[8.1].define(version: 2026_11_17_090000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "companies", force: :cascade do |t|
    t.uuid "uuid", default: -> { "uuidv7()" }, null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_companies_on_name", unique: true
    t.index ["uuid"], name: "index_companies_on_uuid", unique: true
    t.check_constraint "char_length(name::text) >= 1 AND char_length(name::text) <= 100", name: "companies_name_length"
  end

  create_table "invoices", force: :cascade do |t|
    t.uuid "uuid", default: -> { "uuidv7()" }, null: false
    t.bigint "company_id", null: false
    t.bigint "submitted_by_id", null: false
    t.string "vendor_name", null: false
    t.bigint "total_minor_units", null: false
    t.string "currency", limit: 3, null: false
    t.date "due_date", null: false
    t.string "status", default: "DRAFT", null: false
    t.integer "version", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "id"], name: "index_invoices_on_company_id_and_id", unique: true
    t.index ["company_id", "status", "due_date"], name: "index_invoices_on_company_id_and_status_and_due_date"
    t.index ["submitted_by_id"], name: "index_invoices_on_submitted_by_id"
    t.index ["uuid"], name: "index_invoices_on_uuid", unique: true
    t.check_constraint "char_length(vendor_name::text) >= 1 AND char_length(vendor_name::text) <= 200", name: "invoices_vendor_name_length"
    t.check_constraint "currency::text ~ '^[A-Z]{3}$'::text", name: "invoices_currency_format"
    t.check_constraint "status::text = ANY (ARRAY['DRAFT'::character varying, 'PENDING'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying]::text[])", name: "invoices_status_allowed"
    t.check_constraint "total_minor_units >= 0 AND total_minor_units <= '99999999999999'::bigint", name: "invoices_total_range"
    t.check_constraint "version >= 1", name: "invoices_version_positive"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.uuid "uuid", default: -> { "uuidv7()" }, null: false
    t.bigint "company_id", null: false
    t.string "name", null: false
    t.string "role", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_users_on_company_id"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["uuid"], name: "index_users_on_uuid", unique: true
    t.check_constraint "char_length(name::text) >= 1 AND char_length(name::text) <= 100", name: "users_name_length"
    t.check_constraint "role::text = ANY (ARRAY['requester'::character varying, 'approver'::character varying, 'admin'::character varying]::text[])", name: "users_role_allowed"
  end

  add_foreign_key "invoices", "companies"
  add_foreign_key "invoices", "users", column: "submitted_by_id"
  add_foreign_key "sessions", "users", on_delete: :cascade
  add_foreign_key "users", "companies"
end
