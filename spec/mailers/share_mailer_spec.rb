require "rails_helper"

RSpec.describe ShareMailer, type: :mailer do
  let(:owner) { create(:user, username: "owner") }
  let(:addressbook) { create(:addressbook, user: owner) }

  describe "#invitation_existing_user" do
    let(:share) do
      create(:addressbook_share, :pending, addressbook: addressbook,
             user: create(:user), invited_email: "friend@example.com")
    end

    it "addresses the invited email and includes the accept link" do
      mail = described_class.invitation_existing_user(share)
      expect(mail.to).to eq(["friend@example.com"])
      expect(mail.subject).to include(owner.username)
      expect(mail.body.encoded).to include(share.invitation_token)
    end
  end

  describe "#invitation_new_user" do
    let(:share) do
      create(:addressbook_share, :pending_new_user, addressbook: addressbook,
             invited_email: "newbie@example.com")
    end

    it "addresses the invited email and includes the register link" do
      mail = described_class.invitation_new_user(share)
      expect(mail.to).to eq(["newbie@example.com"])
      expect(mail.body.encoded).to include(share.invitation_token)
    end
  end
end
