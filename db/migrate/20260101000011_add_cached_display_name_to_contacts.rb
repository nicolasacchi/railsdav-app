class AddCachedDisplayNameToContacts < ActiveRecord::Migration[8.0]
  def up
    add_column :contacts, :cached_display_name, :string, default: ""
    add_index :contacts, [:addressbook_id, :cached_display_name]

    Contact.reset_column_information
    Contact.find_each do |contact|
      parsed = Vcard::Parser.parse(contact.vcard_data)
      name = parsed&.full_name.presence || ""
      contact.update_column(:cached_display_name, name)
    end
  end

  def down
    remove_column :contacts, :cached_display_name
  end
end
