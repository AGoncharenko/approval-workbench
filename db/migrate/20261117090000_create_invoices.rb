class CreateInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :invoices do |t|
      t.uuid :uuid, null: false, default: -> { "uuidv7()" }, index: { unique: true }
      t.references :company, null: false, foreign_key: true, index: false
      t.references :submitted_by, null: false, foreign_key: { to_table: :users }
      t.string :vendor_name, null: false
      t.bigint :total_minor_units, null: false
      t.string :currency, limit: 3, null: false
      t.date :due_date, null: false
      t.string :status, null: false, default: "DRAFT"
      t.integer :version, null: false, default: 1
      t.check_constraint "char_length(vendor_name) BETWEEN 1 AND 200", name: "invoices_vendor_name_length"
      t.check_constraint "total_minor_units BETWEEN 0 AND 99999999999999", name: "invoices_total_range"
      t.check_constraint "currency ~ '^[A-Z]{3}$'", name: "invoices_currency_format"
      t.check_constraint "status IN ('DRAFT', 'PENDING', 'APPROVED', 'REJECTED')", name: "invoices_status_allowed"
      t.check_constraint "version >= 1", name: "invoices_version_positive"

      t.timestamps
    end
    # Target for composite FKs from child tables, so they cannot reference another tenant's invoice.
    add_index :invoices, [ :company_id, :id ], unique: true
    add_index :invoices, [ :company_id, :status, :due_date ]
  end
end
