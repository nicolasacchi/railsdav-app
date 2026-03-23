class CreateSyncChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_changes do |t|
      t.references :addressbook, null: false, foreign_key: true
      t.string :uri, null: false
      t.integer :sync_token, null: false
      t.string :change_type, null: false

      t.timestamps
    end
    add_index :sync_changes, [:addressbook_id, :sync_token]
  end
end
