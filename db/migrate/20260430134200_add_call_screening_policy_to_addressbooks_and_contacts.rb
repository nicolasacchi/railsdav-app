class AddCallScreeningPolicyToAddressbooksAndContacts < ActiveRecord::Migration[8.1]
  def change
    add_column :addressbooks, :call_screening_policy, :string, default: "screen", null: false
    add_column :contacts, :call_screening_policy, :string
  end
end
