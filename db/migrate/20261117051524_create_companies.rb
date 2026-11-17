class CreateCompanies < ActiveRecord::Migration[8.1]
  def change
    create_table :companies do |t|
      t.uuid :uuid, null: false, default: -> { "uuidv7()" }, index: { unique: true }
      t.string :name, null: false, index: { unique: true }
      t.check_constraint "char_length(name) BETWEEN 1 AND 100", name: "companies_name_length"

      t.timestamps
    end
  end
end
