class CreateContactPhoneNumbers < ActiveRecord::Migration[8.1]
  def change
    create_table :contact_phone_numbers do |t|
      t.references :contact, null: false, foreign_key: true
      t.string :e164, null: false
      t.string :raw
      t.string :phone_type
      t.timestamps
    end
    add_index :contact_phone_numbers, :e164
  end
end
