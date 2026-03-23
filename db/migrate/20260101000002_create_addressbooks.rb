class CreateAddressbooks < ActiveRecord::Migration[8.1]
  def change
    create_table :addressbooks do |t|
      t.references :user, null: false, foreign_key: true
      t.string :uri, null: false
      t.string :displayname, null: false, default: "Contacts"
      t.text :description
      t.integer :ctag, null: false, default: 0
      t.integer :sync_token, null: false, default: 0

      t.timestamps
    end
    add_index :addressbooks, [:user_id, :uri], unique: true
  end
end
