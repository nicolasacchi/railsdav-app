require "rails_helper"

RSpec.describe "Contacts call_screening_policy authorization", type: :request do
  let(:owner) { create(:user, username: "alice", password: "password123") }
  let(:guest) { create(:user, username: "bob", password: "password123") }
  let!(:owner_addressbook) do
    create(:addressbook,
      user: owner,
      uri: "alice-shared",
      displayname: "Alice Shared Book",
      call_screening_policy: "screen"
    )
  end
  let!(:guest_share) do
    create(:addressbook_share, addressbook: owner_addressbook, user: guest, permission: "write")
  end

  let(:vcard) do
    "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:c-1\r\nFN:Spammer\r\nN:Spammer;;;;\r\nTEL:+393331234567\r\nEND:VCARD\r\n"
  end

  let!(:contact) do
    create(:contact,
      addressbook: owner_addressbook,
      uri: "spammer.vcf",
      uid: "c-1",
      vcard_data: vcard,
      call_screening_policy: nil
    )
  end

  def login_as(user)
    post login_path, params: { email: user.email, password: "password123" }
  end

  context "when an owner submits a screening policy" do
    it "saves the policy on the contact" do
      login_as(owner)
      patch addressbook_contact_path(owner_addressbook.uri, contact.uri), params: {
        first_name: "Spammer",
        call_screening_policy: "block"
      }
      expect(response).to be_redirect
      expect(contact.reload.call_screening_policy).to eq("block")
    end
  end

  context "when a write-shared guest submits a screening policy on the owner's addressbook" do
    it "ignores the policy param (does not change the contact)" do
      login_as(guest)
      patch addressbook_contact_path(owner_addressbook.uri, contact.uri), params: {
        first_name: "Spammer",
        call_screening_policy: "allow"
      }
      expect(response).to be_redirect
      expect(contact.reload.call_screening_policy).to be_nil
    end

    it "preserves the existing policy if owner had previously set one" do
      contact.update!(call_screening_policy: "block")
      login_as(guest)
      patch addressbook_contact_path(owner_addressbook.uri, contact.uri), params: {
        first_name: "Spammer",
        call_screening_policy: "allow"
      }
      expect(response).to be_redirect
      expect(contact.reload.call_screening_policy).to eq("block")
    end
  end
end
