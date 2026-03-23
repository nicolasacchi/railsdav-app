class CreateAddressbookShares < ActiveRecord::Migration[8.1]
  def change
    create_table :addressbook_shares do |t|
      t.references :addressbook, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string :permission, null: false, default: "read"
      t.string :token
      t.timestamps
    end
    add_index :addressbook_shares, [ :addressbook_id, :user_id ], unique: true, name: "idx_shares_addressbook_user"
    add_index :addressbook_shares, :token, unique: true
  end
end
