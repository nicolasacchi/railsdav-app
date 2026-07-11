class CreateSpamNumbers < ActiveRecord::Migration[8.1]
  def change
    create_table :spam_numbers do |t|
      t.string   :phone, null: false                 # E.164, normalized via Phonelib at write time
      t.string   :source, null: false                # 'ntfy_report' | 'manual' | 'feed:<id>'
      t.string   :submitted_by_username              # nullable; first reporter for audit
      t.integer  :report_count, null: false, default: 1
      t.datetime :first_reported_at, null: false
      t.datetime :last_seen_at,      null: false
      t.text     :notes
      t.timestamps
    end
    add_index :spam_numbers, :phone, unique: true
    add_index :spam_numbers, :last_seen_at
  end
end
