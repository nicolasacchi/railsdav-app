class CreateContactGroupMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :contact_group_memberships do |t|
      t.references :contact, null: false, foreign_key: true
      t.references :contact_group, null: false, foreign_key: true
      t.timestamps
    end

    add_index :contact_group_memberships, [:contact_id, :contact_group_id], unique: true
  end
end
