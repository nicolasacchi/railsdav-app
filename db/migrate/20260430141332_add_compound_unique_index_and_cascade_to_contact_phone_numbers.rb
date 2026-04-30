class AddCompoundUniqueIndexAndCascadeToContactPhoneNumbers < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DELETE FROM contact_phone_numbers
      WHERE id NOT IN (
        SELECT MIN(id) FROM contact_phone_numbers GROUP BY contact_id, e164
      )
    SQL

    add_index :contact_phone_numbers, [:contact_id, :e164], unique: true,
              name: "index_contact_phone_numbers_on_contact_id_and_e164"

    remove_foreign_key :contact_phone_numbers, :contacts
    add_foreign_key :contact_phone_numbers, :contacts, on_delete: :cascade
  end

  def down
    remove_foreign_key :contact_phone_numbers, :contacts
    add_foreign_key :contact_phone_numbers, :contacts
    remove_index :contact_phone_numbers, name: "index_contact_phone_numbers_on_contact_id_and_e164"
  end
end
