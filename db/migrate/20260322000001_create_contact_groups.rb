class CreateContactGroups < ActiveRecord::Migration[8.0]
  def change
    create_table :contact_groups do |t|
      t.references :addressbook, null: false, foreign_key: true
      t.string :name, null: false
      t.references :group_contact, foreign_key: { to_table: :contacts }
      t.timestamps
    end

    add_index :contact_groups, [:addressbook_id, :name], unique: true
  end
end
