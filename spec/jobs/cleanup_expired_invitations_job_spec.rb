require "rails_helper"

RSpec.describe CleanupExpiredInvitationsJob, type: :job do
  let(:addressbook) { create(:addressbook) }

  it "destroys expired pending invitations" do
    expired = create(:addressbook_share, :pending_new_user, addressbook: addressbook,
                     invitation_expires_at: 1.day.ago)

    expect { described_class.new.perform }.to change(AddressbookShare, :count).by(-1)
    expect(AddressbookShare.exists?(expired.id)).to be(false)
  end

  it "keeps unexpired pending invitations" do
    fresh = create(:addressbook_share, :pending_new_user, addressbook: addressbook,
                   invitation_expires_at: 3.days.from_now)

    expect { described_class.new.perform }.not_to change(AddressbookShare, :count)
    expect(AddressbookShare.exists?(fresh.id)).to be(true)
  end

  it "keeps accepted shares even if the expiry is in the past" do
    accepted = create(:addressbook_share, addressbook: addressbook, user: create(:user),
                      status: "accepted", invitation_expires_at: 1.day.ago)

    expect { described_class.new.perform }.not_to change(AddressbookShare, :count)
    expect(AddressbookShare.exists?(accepted.id)).to be(true)
  end
end
