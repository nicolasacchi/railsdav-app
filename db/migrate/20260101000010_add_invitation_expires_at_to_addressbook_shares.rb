class AddInvitationExpiresAtToAddressbookShares < ActiveRecord::Migration[8.1]
  def change
    add_column :addressbook_shares, :invitation_expires_at, :datetime
  end
end
