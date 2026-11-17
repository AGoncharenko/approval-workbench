class CreateIdempotencyKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :idempotency_keys do |t|
      t.references :company, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true, index: false
      t.string :key, null: false
      t.string :fingerprint, null: false
      t.references :approval_event, foreign_key: true, index: false
      t.datetime :created_at, null: false, default: -> { "now()" }
      t.check_constraint "char_length(key) BETWEEN 1 AND 255", name: "idempotency_keys_key_length"
      t.check_constraint "fingerprint ~ '^[0-9a-f]{64}$'", name: "idempotency_keys_fingerprint_format"
    end
    # The claim target: a concurrent duplicate blocks on this entry until the first request commits or aborts.
    add_index :idempotency_keys, [ :company_id, :user_id, :key ], unique: true
  end
end
