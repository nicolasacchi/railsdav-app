class AddUniqueIndexOnContactsUid < ActiveRecord::Migration[8.1]
  def up
    execute <<-SQL
      DELETE FROM contacts WHERE id NOT IN (
        SELECT MAX(id) FROM contacts GROUP BY addressbook_id, uid
      )
    SQL
    add_index :contacts, [ :addressbook_id, :uid ], unique: true, name: "index_contacts_on_addressbook_id_and_uid"
  end

  def down
    remove_index :contacts, name: "index_contacts_on_addressbook_id_and_uid"
  end
end
