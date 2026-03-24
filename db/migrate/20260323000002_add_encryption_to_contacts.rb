class AddEncryptionToContacts < ActiveRecord::Migration[8.0]
  def change
    add_column :contacts, :encrypted, :boolean, default: false, null: false
    add_column :contacts, :encryption_version, :string
    add_index :contacts, [:addressbook_id, :encrypted]
  end
end
