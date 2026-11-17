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

ActiveRecord::Schema[8.1].define(version: 2026_11_17_091001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "approval_events", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "invoice_id", null: false
    t.bigint "actor_id", null: false
    t.string "actor_role", null: false
    t.string "action", null: false
    t.string "from_status", null: false
    t.string "to_status", null: false
    t.text "reason"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.index ["actor_id"], name: "index_approval_events_on_actor_id"
    t.index ["company_id", "invoice_id", "created_at"], name: "index_approval_events_on_invoice_history"
    t.check_constraint "action::text = ANY (ARRAY['submit'::character varying, 'approve'::character varying, 'reject'::character varying]::text[])", name: "approval_events_action_allowed"
    t.check_constraint "actor_role::text = ANY (ARRAY['requester'::character varying, 'approver'::character varying, 'admin'::character varying]::text[])", name: "approval_events_actor_role_allowed"
    t.check_constraint "from_status::text = ANY (ARRAY['DRAFT'::character varying, 'PENDING'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying]::text[])", name: "approval_events_from_status_allowed"
    t.check_constraint "reason IS NULL OR char_length(reason) >= 1 AND char_length(reason) <= 1000", name: "approval_events_reason_length"
    t.check_constraint "to_status::text = ANY (ARRAY['DRAFT'::character varying, 'PENDING'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying]::text[])", name: "approval_events_to_status_allowed"
  end

  create_table "companies", force: :cascade do |t|
    t.uuid "uuid", default: -> { "uuidv7()" }, null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_companies_on_name", unique: true
    t.index ["uuid"], name: "index_companies_on_uuid", unique: true
    t.check_constraint "char_length(name::text) >= 1 AND char_length(name::text) <= 100", name: "companies_name_length"
  end

  create_table "idempotency_keys", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "user_id", null: false
    t.string "key", null: false
    t.string "fingerprint", null: false
    t.bigint "approval_event_id"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.index ["company_id", "user_id", "key"], name: "index_idempotency_keys_on_company_id_and_user_id_and_key", unique: true
    t.check_constraint "char_length(key::text) >= 1 AND char_length(key::text) <= 255", name: "idempotency_keys_key_length"
    t.check_constraint "fingerprint::text ~ '^[0-9a-f]{64}$'::text", name: "idempotency_keys_fingerprint_format"
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
    t.check_constraint "status::text = ANY (ARRAY['DRAFT'::character varying::text, 'PENDING'::character varying::text, 'APPROVED'::character varying::text, 'REJECTED'::character varying::text])", name: "invoices_status_allowed"
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
    t.check_constraint "role::text = ANY (ARRAY['requester'::character varying::text, 'approver'::character varying::text, 'admin'::character varying::text])", name: "users_role_allowed"
  end

  add_foreign_key "approval_events", "companies"
  add_foreign_key "approval_events", "invoices", column: ["company_id", "invoice_id"], primary_key: ["company_id", "id"], name: "approval_events_invoice_same_company"
  add_foreign_key "approval_events", "users", column: "actor_id", on_delete: :restrict
  add_foreign_key "idempotency_keys", "approval_events"
  add_foreign_key "idempotency_keys", "companies"
  add_foreign_key "idempotency_keys", "users"
  add_foreign_key "invoices", "companies"
  add_foreign_key "invoices", "users", column: "submitted_by_id"
  add_foreign_key "sessions", "users", on_delete: :cascade
  add_foreign_key "users", "companies"
end
