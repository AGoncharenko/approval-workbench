class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.uuid :uuid, null: false, default: -> { "uuidv7()" }, index: { unique: true }
      t.references :company, null: false, foreign_key: true
      t.string :name, null: false
      t.string :role, null: false
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.check_constraint "char_length(name) BETWEEN 1 AND 100", name: "users_name_length"
      t.check_constraint "role IN ('requester', 'approver', 'admin')", name: "users_role_allowed"

      t.timestamps
    end
    add_index :users, :email_address, unique: true
  end
end
