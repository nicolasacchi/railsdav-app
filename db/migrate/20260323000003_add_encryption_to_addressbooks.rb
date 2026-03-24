class AddEncryptionToAddressbooks < ActiveRecord::Migration[8.0]
  def change
    add_column :addressbooks, :encryption_enabled, :boolean, default: false, null: false
    add_column :addressbooks, :encryption_version, :string
  end
end
