class AddEmailLoginAndSharingInvitations < ActiveRecord::Migration[8.1]
  def change
    # AddressbookShares: invitation support
    add_column :addressbook_shares, :status, :string, null: false, default: "accepted"
    add_column :addressbook_shares, :invited_email, :string
    add_column :addressbook_shares, :invitation_token, :string
    add_column :addressbook_shares, :invitation_sent_at, :datetime

    add_index :addressbook_shares, :invitation_token, unique: true
    add_index :addressbook_shares, :invited_email
  end
end
