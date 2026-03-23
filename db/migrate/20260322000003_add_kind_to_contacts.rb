class AddKindToContacts < ActiveRecord::Migration[8.0]
  def change
    add_column :contacts, :kind, :string, default: "individual", null: false
  end
end
