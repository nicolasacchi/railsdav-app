class CreateContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :contacts do |t|
      t.references :addressbook, null: false, foreign_key: true
      t.string :uid, null: false
      t.string :uri, null: false
      t.string :etag, null: false
      t.text :vcard_data, null: false

      t.timestamps
    end
    add_index :contacts, [:addressbook_id, :uri], unique: true
  end
end
